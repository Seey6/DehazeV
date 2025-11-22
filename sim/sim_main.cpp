#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vdehaze_top.h"
#include <iostream>
#include <opencv2/opencv.hpp>

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vdehaze_top* top = new Vdehaze_top;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("waveform.vcd");

    // Read Input Image using OpenCV
    cv::Mat input_img = cv::imread("haze.jpg", cv::IMREAD_COLOR);
    if (input_img.empty()) {
        std::cerr << "Error: Could not read haze.jpg" << std::endl;
        return 1;
    }
    
    // Ensure dimensions match what we expect/configured in RTL
    // Note: RTL parameters WIDTH/HEIGHT are compile-time fixed in Verilator.
    // Ensure you compile RTL with -GWIDTH=600 -GHEIGHT=450 or match the image size.
    int width = input_img.cols;
    int height = input_img.rows;
    std::cout << "Processing image: " << width << "x" << height << std::endl;

    cv::Mat output_img(height, width, CV_8UC3);
    cv::Mat transmission_img(height, width, CV_8UC1);
    cv::Mat saturation_img(height, width, CV_8UC1);

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
    int total_pixels = width * height;
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
                
                // OpenCV uses BGR by default, but we can access as bytes.
                // Vec3b is [B, G, R].
                // Our RTL expects R, G, B.
                cv::Vec3b pixel = input_img.at<cv::Vec3b>(pixel_idx / width, pixel_idx % width);
                top->in_r = pixel[2]; // R
                top->in_g = pixel[1]; // G
                top->in_b = pixel[0]; // B
                
                int x = pixel_idx % width;
                int y = pixel_idx / width;
                top->in_sof = (pixel_idx == 0);
                top->in_eol = (x == width - 1);
                
                pixel_idx++;
            } else {
                // End of Frame
                top->in_valid = 0;
                top->in_sof = 0;
                top->in_eol = 0;
                
                // Inter-frame gap
                static int gap = 0;
                if (gap < 100) {
                    gap++;
                } else {
                    gap = 0;
                    frame_count++;
                    if (frame_count < max_frames) {
                        pixel_idx = 0; 
                        out_pixel_idx = 0; // Reset for next frame capture
                        std::cout << "Starting Frame " << frame_count + 1 << std::endl;
                    }
                }
            }
        }
        
        top->eval();
        
        // Capture Output
        if (top->clk && top->out_valid) {
            if (out_pixel_idx < total_pixels) {
                // Write back to OpenCV Mat
                // RTL outputs R, G, B. OpenCV expects B, G, R.
                cv::Vec3b& out_pixel = output_img.at<cv::Vec3b>(out_pixel_idx / width, out_pixel_idx % width);
                out_pixel[0] = top->out_b; // B
                out_pixel[1] = top->out_g; // G
                out_pixel[2] = top->out_r; // R
                
                // Capture Transmission Map
                // inv_t is Q4.8 (1/t)
                // t = 256.0 / inv_t
                // pixel = t * 255
                unsigned char t_val = 0;
                if (top->out_inv_t > 0) {
                    double t = 256.0 / (double)top->out_inv_t;
                    if (t > 1.0) t = 1.0;
                    t_val = (unsigned char)(t * 255.0);
                }
                transmission_img.at<unsigned char>(out_pixel_idx / width, out_pixel_idx % width) = t_val;

                // Capture Saturation Map
                // out_sat is Q12 (0.0 to 1.0)
                // pixel = S * 255
                unsigned char s_val = 0;
                double s = (double)top->out_sat / 4096.0;
                if (s > 1.0) s = 1.0;
                s_val = (unsigned char)(s * 255.0);
                saturation_img.at<unsigned char>(out_pixel_idx / width, out_pixel_idx % width) = s_val;

                out_pixel_idx++;
            }
        }
        
        tfp->dump(main_time++);
    }

    cv::imwrite("rtl_output.png", output_img);
    cv::imwrite("rtl_transmission.png", transmission_img);
    cv::imwrite("rtl_saturation.png", saturation_img);
    
    top->final();
    tfp->close();
    delete top;
    delete tfp;
    
    std::cout << "Simulation finished. Output written to output.png" << std::endl;
    return 0;
}
