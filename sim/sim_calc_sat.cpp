#include <verilated.h>
#include "Vcalc_sat.h"
#include <iostream>
#include <iomanip>
#include <verilated_vcd_c.h>

vluint64_t main_time = 0;

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    
    Vcalc_sat* top = new Vcalc_sat;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("calc_sat.vcd");

    top->clk = 0;
    top->rst_n = 0;
    top->in_valid = 0;
    top->in_r = 0;
    top->in_g = 0;
    top->in_b = 0;
    top->A_r = 200;
    top->A_g = 200;
    top->A_b = 200;

    // Reset
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_n = 1;

    std::cout << "Starting calc_sat simulation..." << std::endl;

    // Test Case 1: H = A. Hn = 1.0. Min=1.0, Mean=1.0. S_H = 1 - 1/1 = 0.
    top->in_r = 200;
    top->in_g = 200;
    top->in_b = 200;
    top->in_valid = 1;

    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time++);
        if (top->clk && top->out_valid) {
            std::cout << "TC1 (H=A): S_H=" << top->S_H << " (Expected 0)" << std::endl;
        }
    }

    // Test Case 2: H = 0.5*A. Hn = 0.5. Min=0.5, Mean=0.5. S_H = 0.
    top->in_r = 100;
    top->in_g = 100;
    top->in_b = 100;
    
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time++);
        if (top->clk && top->out_valid) {
            std::cout << "TC2 (H=0.5A): S_H=" << top->S_H << " (Expected 0)" << std::endl;
        }
    }

    // Test Case 3: Saturation. R=200, G=100, B=100. A=200.
    // Hn_R = 1.0 (4096). Hn_G = 0.5 (2048). Hn_B = 0.5 (2048).
    // Min = 2048.
    // Sum = 4096 + 2048 + 2048 = 8192.
    // Mean = 8192 / 3 = 2730.
    // S_H = 1 - 2048/2730 = 1 - 0.75 = 0.25.
    // 0.25 * 4096 = 1024.
    top->in_r = 200;
    top->in_g = 100;
    top->in_b = 100;

    for (int i = 0; i < 20; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time++);
        if (top->clk && top->out_valid) {
            std::cout << "TC3 (Sat): S_H=" << top->S_H << " (Expected ~1024)" << std::endl;
        }
    }

    top->final();
    tfp->close();
    delete tfp;
    delete top;
    return 0;
}
