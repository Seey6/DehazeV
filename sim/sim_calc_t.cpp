#include <verilated.h>
#include "Vcalc_t.h"
#include <verilated_vcd_c.h>
#include <iostream>
#include <vector>
#include <deque>
#include <cmath>
#include <cstdlib>

// LUT generation helper
uint16_t get_lut_val(uint16_t addr) {
    if (addr == 0) return 4095;
    // Match Python's int(round(4095 / i))
    double val = 4095.0 / addr;
    return (uint16_t)std::round(val);
}

struct TestCase {
    uint16_t S_H;
    uint16_t S_D;
    uint16_t K_Hn125;
    uint16_t expected_inv_t;
};

std::deque<TestCase> expected_q;

uint16_t calc_expected(uint16_t S_H, uint16_t S_D, uint16_t K_Hn125) {
    uint16_t sh_sub_sd = (S_D - S_H) & 0xFFF;
    uint16_t k_mul = (K_Hn125 * sh_sub_sd) >> 12;
    k_mul &= 0xFFF;
    
    uint16_t denom = (S_D - k_mul) & 0xFFF;
    uint16_t inv_denom = get_lut_val(denom);
    
    uint16_t res = (inv_denom * S_D) >> 12;
    return res & 0xFFF;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vcalc_t* top = new Vcalc_t;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("waveform.vcd");

    top->clk = 0;
    top->rst_n = 0;
    top->in_valid = 0;
    top->S_H = 0;
    top->S_D = 0;
    top->K_Hn125 = 0;

    // Reset
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(i);
    }
    top->rst_n = 1;

    std::cout << "Starting calc_t simulation with software verification..." << std::endl;

    int mismatch_count = 0;
    int checked_count = 0;
    bool out_valid_d1 = false;
    int time_step = 10;

    // Run for enough cycles to flush pipeline
    for (int i = 0; i < 200; i++) {
        // Drive inputs
        if (i < 100) { 
            top->in_valid = 1;
            top->S_H = rand() & 0x7FF;
            top->S_D = (top->S_H *(8191 - top->S_H)) >> 12;
            top->K_Hn125 = rand() & 0xFFF;
            
            TestCase tc;
            tc.S_H = top->S_H;
            tc.S_D = top->S_D;
            tc.K_Hn125 = top->K_Hn125;
            tc.expected_inv_t = calc_expected(tc.S_H, tc.S_D, tc.K_Hn125);
            expected_q.push_back(tc);
        } else {
            top->in_valid = 0;
        }

        // Clock low
        top->clk = 0;
        top->eval();
        tfp->dump(time_step++);
        
        // Clock high
        top->clk = 1;
        top->eval();
        tfp->dump(time_step++);
        
        // Check output
        // out_valid is high one cycle before data is valid in inv_t register
        if (out_valid_d1) {
            if (expected_q.empty()) {
                std::cout << "Error: Unexpected output valid at cycle " << i << std::endl;
            } else {
                TestCase tc = expected_q.front();
                expected_q.pop_front();
                
                // Allow small tolerance for rounding differences
                int diff = abs((int)top->inv_t - (int)tc.expected_inv_t);
                if (diff > 1) {
                     std::cout << "Mismatch at cycle " << i << ": "
                               << "S_H=" << tc.S_H << " S_D=" << tc.S_D << " K=" << tc.K_Hn125
                               << " HW=" << top->inv_t << " SW=" << tc.expected_inv_t 
                               << " Diff=" << diff << std::endl;
                     mismatch_count++;
                }
                checked_count++;
            }
        }
        
        out_valid_d1 = top->out_valid;
    }

    std::cout << "Simulation finished. Checked: " << checked_count << ", Mismatches: " << mismatch_count << std::endl;

    top->final();
    tfp->close();
    delete tfp;
    delete top;
    return 0;
}
