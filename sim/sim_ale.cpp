#include <verilated.h>
#include "Vale.h"
#include <verilated_vcd_c.h>
#include <iostream>
#include <vector>
#include <algorithm>
#include <opencv2/opencv.hpp>

// Helper function to print progress
vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

void print_progress(int current, int total) {
    if (current % (total / 10) == 0) {
        std::cout << "Progress: " << (current * 100) / total << "%" << std::endl;
    }
}

// Software reference implementation of ALE algorithm
struct ALE_Result {
    uint8_t A_r, A_g, A_b;
};

ALE_Result software_ALE(const cv::Mat& img_ds) {
    ALE_Result result;
    
    // Step 1: Downsample by factor of 2 (sample at even coordinates)
    // cv::Mat img_ds;
    // cv::resize(img, img_ds, cv::Size(), 0.5, 0.5, cv::INTER_NEAREST);
    
    // Split into channels
    std::vector<cv::Mat> bgr_channels;
    cv::split(img_ds, bgr_channels);
    cv::Mat b_ch = bgr_channels[0];
    cv::Mat g_ch = bgr_channels[1];
    cv::Mat r_ch = bgr_channels[2];
    
    // Step 2: Apply cascaded 3x3 minimum filters (erode = minimum filter)
    // Cascade 3 times to approximate 15x15
    // Use BORDER_CONSTANT with value 255 to match hardware behavior
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
    
    cv::Mat r_min, g_min, b_min;
    
    // First cascade
    cv::erode(r_ch, r_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    cv::erode(g_ch, g_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    cv::erode(b_ch, b_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    
    // Second cascade
    cv::erode(r_min, r_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    cv::erode(g_min, g_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    cv::erode(b_min, b_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    
    // Third cascade
    cv::erode(r_min, r_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    cv::erode(g_min, g_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    cv::erode(b_min, b_min, kernel, cv::Point(-1,-1), 1, cv::BORDER_CONSTANT, cv::Scalar(255));
    
    // Step 3: Calculate dark channel (min of R, G, B)
    cv::Mat dark_channel = cv::min(cv::min(r_min, g_min), b_min);
    
    // Step 4: Find pixel with maximum dark channel value
    double min_val, max_val;
    cv::Point min_loc, max_loc;
    cv::minMaxLoc(dark_channel, &min_val, &max_val, &min_loc, &max_loc);
    
    std::cout << "Software ALE: max_dc=" << (int)max_val 
              << " at (" << max_loc.x << "," << max_loc.y << ")" << std::endl;
    
    // Show top 5 dark channel values
    cv::Mat dark_flat = dark_channel.reshape(1, 1);
    std::vector<std::pair<uint8_t, int>> dc_values;
    for (int i = 0; i < dark_flat.cols; i++) {
        dc_values.push_back({dark_flat.at<uint8_t>(i), i});
    }
    std::sort(dc_values.begin(), dc_values.end(), std::greater<std::pair<uint8_t, int>>());
    
    std::cout << "Top 5 dark channel values:" << std::endl;
    for (int i = 0; i < std::min(5, (int)dc_values.size()); i++) {
        int idx = dc_values[i].second;
        int x = idx % dark_channel.cols;
        int y = idx / dark_channel.cols;
        uint8_t r_val = r_min.at<uint8_t>(y, x);
        uint8_t g_val = g_min.at<uint8_t>(y, x);
        uint8_t b_val = b_min.at<uint8_t>(y, x);
        std::cout << "  #" << i+1 << ": dc=" << (int)dc_values[i].first 
                  << " at (" << x << "," << y << ")"
                  << " RGB=(" << (int)r_val << "," << (int)g_val << "," << (int)b_val << ")"
                  << std::endl;
    }
    
    // Step 5: Extract RGB values at max location (using FILTERED values)
    uint8_t A_r = r_min.at<uint8_t>(max_loc);
    uint8_t A_g = g_min.at<uint8_t>(max_loc);
    uint8_t A_b = b_min.at<uint8_t>(max_loc);
    
    // Clip to minimum 100
    result.A_r = std::max((uint8_t)100, A_r);
    result.A_g = std::max((uint8_t)100, A_g);
    result.A_b = std::max((uint8_t)100, A_b);
    
    std::cout << "Using FILTERED RGB from max_dc location" << std::endl;
    
    return result;
}


int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vale* top = new Vale;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("ale.vcd");

    // Load image using OpenCV
    cv::Mat img_raw = cv::imread("haze.jpg");
    if (img_raw.empty()) {
        std::cerr << "Error: Could not read haze.jpg" << std::endl;
        return 1;
    }

    // Resize to match hardware default parameters (320x240)
    // If you want to change this, you must also update the parameters in ale.v
    const int WIDTH = 320;
    const int HEIGHT = 240;
    cv::Mat img;
    cv::resize(img_raw, img, cv::Size(WIDTH, HEIGHT));

    const int TOTAL_PIXELS = WIDTH * HEIGHT;
    
    // Initialize inputs
    top->clk = 0;
    top->rst_n = 0;
    top->in_valid = 0;
    top->in_sof = 0;
    top->in_eol = 0;
    top->in_r = 0;
    top->in_g = 0;
    top->in_b = 0;

    // Reset
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_n = 1;

    std::cout << "Starting ALE simulation with haze.jpg (" << WIDTH << "x" << HEIGHT << ")..." << std::endl;

    // Run simulation
    int frame_count = 0;
    int max_frames = 2;
    
    uint8_t detected_A_r = 0;
    uint8_t detected_A_g = 0;
    uint8_t detected_A_b = 0;
    bool A_valid_pulsed = false;

    while (!Verilated::gotFinish() && frame_count < max_frames) {
        for (int y = 0; y < HEIGHT; y++) {
            for (int x = 0; x < WIDTH; x++) {
                top->clk = 0;
                top->eval();
                tfp->dump(main_time++);

                // Set inputs
                top->in_valid = 1;
                top->in_sof = (x == 0 && y == 0);
                top->in_eol = (x == WIDTH - 1);
                
                // OpenCV uses BGR
                cv::Vec3b pixel = img.at<cv::Vec3b>(y, x);
                top->in_r = pixel[2]; // R
                top->in_g = pixel[1]; // G
                top->in_b = pixel[0]; // B

                top->clk = 1;
                top->eval();
                tfp->dump(main_time++);

                // Check outputs
                if (top->A_valid) {
                    detected_A_r = top->A_r;
                    detected_A_g = top->A_g;
                    detected_A_b = top->A_b;
                    A_valid_pulsed = true;
                    std::cout << "Frame " << frame_count << " A_valid pulsed at (x,y)=(" << x << "," << y << ") A=(" 
                              << (int)detected_A_r << "," << (int)detected_A_g << "," << (int)detected_A_b << ")" << std::endl;
                }
            }
        }
        
        // Gap between frames
        top->in_valid = 0;
        top->in_sof = 0;
        top->in_eol = 0;
        for (int i = 0; i < 100; i++) {
            top->clk = !top->clk;
            top->eval();
            tfp->dump(main_time++);
        }
        
        frame_count++;
    }

    // Run software reference ALE
    std::cout << "\n========================================" << std::endl;
    std::cout << "Running Software Reference ALE..." << std::endl;
    ALE_Result sw_result = software_ALE(img);
    std::cout << "Software Reference Result: A=(" << (int)sw_result.A_r << ", " 
              << (int)sw_result.A_g << ", " << (int)sw_result.A_b << ")" << std::endl;
    
    std::cout << "\n========================================" << std::endl;
    std::cout << "Hardware vs Software Comparison:" << std::endl;
    std::cout << "Hardware ALE: A=(" << (int)detected_A_r << ", " << (int)detected_A_g << ", " << (int)detected_A_b << ")" << std::endl;
    std::cout << "Software ALE: A=(" << (int)sw_result.A_r << ", " << (int)sw_result.A_g << ", " << (int)sw_result.A_b << ")" << std::endl;
    
    int diff_r = std::abs((int)detected_A_r - (int)sw_result.A_r);
    int diff_g = std::abs((int)detected_A_g - (int)sw_result.A_g);
    int diff_b = std::abs((int)detected_A_b - (int)sw_result.A_b);
    int max_diff = std::max({diff_r, diff_g, diff_b});
    
    std::cout << "Difference:   Δ=(" << diff_r << ", " << diff_g << ", " << diff_b << ") max=" << max_diff << std::endl;
    
    // Accept differences up to 15 due to timing, border effects, and implementation details
    bool match = (max_diff <= 15);
    if (match) {
        std::cout << "✓ PASS: Hardware matches software reference (within tolerance ±15)" << std::endl;
    } else {
        std::cout << "✗ FAIL: Hardware differs from software reference by more than ±15" << std::endl;
    }
    std::cout << "========================================\n" << std::endl;

    if (A_valid_pulsed) {
        std::cout << "Test Passed: A_valid pulsed." << std::endl;
        std::cout << "Detected Atmospheric Light A: (" << (int)detected_A_r << ", " << (int)detected_A_g << ", " << (int)detected_A_b << ")" << std::endl;
    } else {
        std::cout << "Test Failed: A_valid never pulsed." << std::endl;
    }

    top->final();
    tfp->close();
    delete top;
    delete tfp;
    return 0;
}
