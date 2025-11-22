#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vmin_filter_3x3.h"
#include <iostream>
#include <vector>
#include <algorithm>
#include <iomanip>

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

// Software reference that mimics hardware behavior (streaming with circular line buffers)
// This simulates what the hardware actually does with its wrapping line buffers
class MinFilter3x3Sim {
public:
    MinFilter3x3Sim(int width) : WIDTH(width), wr_ptr(0), pixel_cnt(0), warmup_done(false) {
        lb1.resize(WIDTH, 0);
        lb2.resize(WIDTH, 0);
        r0_0 = r0_1 = r0_2 = 0;
        r1_0 = r1_1 = r1_2 = 0;
        r2_0 = r2_1 = r2_2 = 0;
    }
    
    std::pair<bool, uint8_t> process(uint8_t in_val) {
        // Read from line buffers
        uint8_t lb1_read = lb1[wr_ptr];
        uint8_t lb2_read = lb2[wr_ptr];
        
        // Write to line buffers
        lb1[wr_ptr] = in_val;
        lb2[wr_ptr] = lb1_read;
        
        // Shift window
        r0_2 = r0_1; r0_1 = r0_0; r0_0 = in_val;
        r1_2 = r1_1; r1_1 = r1_0; r1_0 = lb1_read;
        r2_2 = r2_1; r2_1 = r2_0; r2_0 = lb2_read;
        
        // Update pointer
        wr_ptr = (wr_ptr + 1) % WIDTH;
        pixel_cnt++;
        
        // Warmup logic (check BEFORE increment to match hardware register timing)
        if (!warmup_done) {
            if (pixel_cnt > WIDTH * 2 + 2) {
                warmup_done = true;
            }else{
                warmup_done  =false;
            }
        }
        
        // Calculate min
        uint8_t min_val = r0_0;
        min_val = std::min(min_val, r0_1);
        min_val = std::min(min_val, r0_2);
        min_val = std::min(min_val, r1_0);
        min_val = std::min(min_val, r1_1);
        min_val = std::min(min_val, r1_2);
        min_val = std::min(min_val, r2_0);
        min_val = std::min(min_val, r2_1);
        min_val = std::min(min_val, r2_2);
        
        return {warmup_done, min_val};
    }

private:
    int WIDTH;
    std::vector<uint8_t> lb1, lb2;
    int wr_ptr;
    uint8_t r0_0, r0_1, r0_2;
    uint8_t r1_0, r1_1, r1_2;
    uint8_t r2_0, r2_1, r2_2;
    int pixel_cnt;
    bool warmup_done;
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vmin_filter_3x3* top = new Vmin_filter_3x3;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("waveform.vcd");

    // Test parameters
    const int WIDTH = 160;
    const int HEIGHT = 120;
    
    // Create test image: simple gradient pattern
    std::vector<std::vector<uint8_t>> test_img(HEIGHT, std::vector<uint8_t>(WIDTH));
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            test_img[y][x] = ((x + y * 2) % 256);
        }
    }

    // Storage for outputs
    std::vector<uint8_t> hw_output, sw_output;

    // Software reference simulator
    MinFilter3x3Sim sw_sim(WIDTH);

    // Initialize DUT
    top->clk = 0;
    top->rst_n = 0;
    top->in_valid = 0;
    top->in_val = 0;

    // Reset
    std::cout << "Resetting DUT..." << std::endl;
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_n = 1;

    // Run simulation
    std::cout << "Running hardware simulation..." <<  std::endl;
    int pixel_idx = 0;
    int total_pixels = WIDTH * HEIGHT;
    
    int first_valid_pixel = -1;
    int max_cycles = total_pixels * 2 + 500;
    
    for (int cycle = 0; cycle < max_cycles && !Verilated::gotFinish(); cycle++) {
        top->clk = !top->clk;
        
        if (top->clk) {  // Rising edge
            // Input Driver
            if (pixel_idx < total_pixels) {
                top->in_valid = 1;
                int x = pixel_idx % WIDTH;
                int y = pixel_idx / WIDTH;
                top->in_val = test_img[y][x];
                
                // Software reference
                auto [sw_valid, sw_val] = sw_sim.process(test_img[y][x]);
                if (sw_valid) {
                    sw_output.push_back(sw_val);
                }
                
                pixel_idx++;
            } else {
                top->in_valid = 0;
            }
            
            // Output Monitor
            if (top->out_valid) {
                if (first_valid_pixel == -1) {
                    first_valid_pixel = pixel_idx - 1;
                    std::cout << "First valid output at input pixel: " << first_valid_pixel << std::endl;
                }
                hw_output.push_back(top->out_val);
            }
        }
        
        top->eval();
        tfp->dump(main_time++);
    }

    std::cout << "HW outputs: " << hw_output.size() << std::endl;
    std::cout << "SW outputs: " << sw_output.size() << std::endl;

    // Compare results
    std::cout << "\nComparing hardware vs software results..." << std::endl;
    int mismatches = 0;
    int max_diff = 0;
    size_t compare_count = std::min(hw_output.size(), sw_output.size());
    
    // Show first few outputs
    std::cout << "\nFirst 20 outputs:" << std::endl;
    std::cout << "Idx | HW Out | SW Out | Match" << std::endl;
    std::cout << "----|--------|--------|------" << std::endl;
    for (size_t i = 0; i < std::min((size_t)20, compare_count); i++) {
        bool match = (hw_output[i] == sw_output[i]);
        std::cout << std::setw(3) << i << " | "
                  << std::setw(6) << (int)hw_output[i] << " | "
                  << std::setw(6) << (int)sw_output[i] << " | "
                  << (match ? "✓" : "✗") << std::endl;
        if (!match) mismatches++;
    }

    // Full comparison
    for (size_t i = 0; i < compare_count; i++) {
        if (hw_output[i] != sw_output[i]) {
            mismatches++;
            int diff = abs((int)hw_output[i] - (int)sw_output[i]);
            max_diff = std::max(max_diff, diff);
            
            if (mismatches <= 10) {
                std::cout << "Mismatch at output[" << i << "]: "
                          << "HW=" << (int)hw_output[i] 
                          << " SW=" << (int)sw_output[i] << std::endl;
            }
        }
    }

    std::cout << "\n=== TEST RESULTS ===" << std::endl;
    std::cout << "Total compared: " << compare_count << std::endl;
    std::cout << "Total mismatches: " << mismatches << " / " << compare_count;
    std::cout << " (" << (100.0 * mismatches / compare_count) << "%)" << std::endl;
    if (mismatches > 0) {
        std::cout << "Maximum difference: " << max_diff << std::endl;
    }
    
    if (mismatches == 0) {
        std::cout << "✓ TEST PASSED!" << std::endl;
    } else {
        std::cout << "✗ TEST FAILED!" << std::endl;
    }

    // Cleanup
    top->final();
    tfp->close();
    delete top;
    delete tfp;
    
    std::cout << "\nWaveform saved to waveform.vcd" << std::endl;
    
    return (mismatches == 0) ? 0 : 1;
}
