#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vdehaze_top.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>

// PPM Helper
struct Image {
    int width;
    int height;
    std::vector<unsigned char> data; // RGBRGB...
};

bool read_ppm(const std::string& filename, Image& img) {
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error opening " << filename << std::endl;
        return false;
    }
    std::string header;
    file >> header;
    if (header != "P6") {
        std::cerr << "Invalid PPM format (must be P6)" << std::endl;
        return false;
    }
    file >> img.width >> img.height;
    int max_val;
    file >> max_val;
    file.ignore(256, '\n'); // Skip whitespace after max_val

    img.data.resize(img.width * img.height * 3);
    file.read(reinterpret_cast<char*>(img.data.data()), img.data.size());
    return true;
}

bool write_ppm(const std::string& filename, const Image& img) {
    std::ofstream file(filename, std::ios::binary);
    if (!file) return false;
    file << "P6\n" << img.width << " " << img.height << "\n255\n";
    file.write(reinterpret_cast<const char*>(img.data.data()), img.data.size());
    return true;
}

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vdehaze_top* top = new Vdehaze_top;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("waveform.vcd");

    Image input_img;
    if (!read_ppm("input.ppm", input_img)) return 1;

    Image output_img;
    output_img.width = input_img.width;
    output_img.height = input_img.height;
    output_img.data.resize(input_img.data.size());

    top->clk = 0;
    top->rst_n = 0;
    top->in_valid = 0;

    // Reset
    for (int i = 0; i < 10; ++i) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_n = 1;

    int pixel_idx = 0;
    int out_pixel_idx = 0;
    int total_pixels = input_img.width * input_img.height;
    int frame_count = 0;
    int max_frames = 2; // Run 2 frames to let ALE settle
    
    // Simulation Loop
    while (frame_count < max_frames && !Verilated::gotFinish()) {
        top->clk = !top->clk;
        if (top->clk) {
            // Rising edge logic
            
            // Input Driver
            if (pixel_idx < total_pixels) {
                top->in_valid = 1;
                top->in_r = input_img.data[pixel_idx * 3 + 0];
                top->in_g = input_img.data[pixel_idx * 3 + 1];
                top->in_b = input_img.data[pixel_idx * 3 + 2];
                
                int x = pixel_idx % input_img.width;
                int y = pixel_idx / input_img.width;
                top->in_sof = (pixel_idx == 0);
                top->in_eol = (x == input_img.width - 1);
                
                pixel_idx++;
            } else {
                // End of Frame
                top->in_valid = 0;
                top->in_sof = 0;
                top->in_eol = 0;
                
                // Wait for a few cycles between frames?
                // Or just start next frame immediately?
                // Let's add a small gap
                static int gap = 0;
                if (gap < 100) {
                    gap++;
                } else {
                    gap = 0;
                    frame_count++;
                    if (frame_count < max_frames) {
                        pixel_idx = 0; // Restart input
                        // Reset output index only if we want to capture the last frame
                        out_pixel_idx = 0; 
                    }
                }
            }
        }
        
        top->eval();
        
        // Capture Output
        if (top->clk && top->out_valid) {
            // Only capture if we are in the second frame (or just overwrite)
            // Since we reset out_pixel_idx, we effectively overwrite.
            if (out_pixel_idx < total_pixels) {
                output_img.data[out_pixel_idx * 3 + 0] = top->out_r;
                output_img.data[out_pixel_idx * 3 + 1] = top->out_g;
                output_img.data[out_pixel_idx * 3 + 2] = top->out_b;
                out_pixel_idx++;
            }
        }
        
        tfp->dump(main_time++);
    }

    write_ppm("output.ppm", output_img);
    
    top->final();
    tfp->close();
    delete top;
    delete tfp;
    
    std::cout << "Simulation finished. Output written to output.ppm" << std::endl;
    return 0;
}
