module calc_sat (
        input wire clk,
        input wire rst_n,

        input wire [7:0] in_r, in_g, in_b,
        input wire       in_valid,

        input wire [7:0] A_r, A_g, A_b,
        /* verilator lint_off UNUSEDSIGNAL */
        input wire A_valid,
        /* verilator lint_on UNUSEDSIGNAL */

        output reg [11:0] S_H,   // Q0.12
        output reg [11:0] S_D,   // Q0.12
        output reg [11:0] K_Hn125,  // Q4.8 (Mean of Hn)
        output         out_valid
    );

    reg [7:0] in_valid_pipe;
    assign out_valid = in_valid_pipe[7];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_valid_pipe <= 0;
        end
        else begin
            in_valid_pipe <= {in_valid_pipe[6:0], in_valid};
        end
    end
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] inv_A_r, inv_A_g, inv_A_b;
    /* verilator lint_on UNUSEDSIGNAL */
    lut_inv_A lut_inv_r (clk, A_r, inv_A_r);
    lut_inv_A lut_inv_g (clk, A_g, inv_A_g);
    lut_inv_A lut_inv_b (clk, A_b, inv_A_b);

    wire [11:0] inv_Khn;
    wire [10:0] wire_khn;
    assign wire_khn = sum_rg + {1'b0,b_div_A_d};
    lut_khn llut_khn (clk,K_Hn[10:0],inv_Khn);

    reg [7:0] in_r_d, in_g_d, in_b_d;
    reg [9:0] r_div_A, g_div_A, b_div_A;
    /* verilator lint_off UNUSEDSIGNAL */
    /* verilator lint_off UNDRIVEN */
    reg [9:0] r_div_A_d, g_div_A_d, b_div_A_d;
    /* verilator lint_on UNDRIVEN */
    /* verilator lint_on UNUSEDSIGNAL */
    reg [9:0] min_rgb_div_A;
    reg [10:0] sum_rg;
    reg [11:0] minTri;
    reg [11:0] khn_sub_min3;
    reg [11:0] K_Hn,K_Hn_d1,K_Hn_d2,K_Hn_d3;
    reg [11:0] S_H_d1,S_H_d2;
    reg [11:0] S_D_d1;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] sh_mult_res;
    assign sh_mult_res = khn_sub_min3 * inv_Khn; //Q4.8 * Q4.8 = Q8.16
    wire [23:0] wire_S_D;
    wire [24:0] wire_two_sub_S_H;
    assign wire_two_sub_S_H = 24'd8191 - {12'b0,S_H_d1};
    /* verilator lint_on UNUSEDSIGNAL */
    assign wire_S_D = wire_two_sub_S_H[12:0] * S_H_d1;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] wire_r_div_A;
    wire [23:0] wire_g_div_A;
    wire [23:0] wire_b_div_A;
    /* verilator lint_on UNUSEDSIGNAL */
    assign wire_r_div_A = in_r_d * inv_A_r[5:0];
    assign wire_g_div_A = in_g_d * inv_A_g[5:0];
    assign wire_b_div_A = in_b_d * inv_A_b[5:0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_r_d <= 8'b0;
            in_g_d <= 8'b0;
            in_b_d <= 8'b0;
        end
        else begin
            if(in_valid) begin
                in_r_d <= in_r;
                in_g_d <= in_g;
                in_b_d <= in_b;
            end
            if(in_valid_pipe[0]) begin
                // inv_A is ready
                r_div_A <= wire_r_div_A[13:4];
                g_div_A <= wire_g_div_A[13:4];
                b_div_A <= wire_b_div_A[13:4];
            end
            if(in_valid_pipe[1]) begin

                b_div_A_d <= b_div_A;
                if(r_div_A <= g_div_A && r_div_A <= b_div_A) begin
                    min_rgb_div_A <= r_div_A;
                end
                else if(g_div_A <= r_div_A && g_div_A <= b_div_A) begin
                    min_rgb_div_A <= g_div_A;
                end
                else begin
                    min_rgb_div_A <= b_div_A;
                end
                sum_rg <= r_div_A + g_div_A;

            end
            if(in_valid_pipe[2]) begin
                if(wire_khn == 0) begin
                    K_Hn <= 12'b1;
                end
                else begin
                    K_Hn <= {1'b0,wire_khn};
                end
                minTri <= min_rgb_div_A * 2'd3;
            end
            if(in_valid_pipe[3]) begin
                // inv_khn should <= inv(khn)
                khn_sub_min3 <= K_Hn - minTri;
                K_Hn_d1 <= K_Hn + (K_Hn >> 2);
            end
            if(in_valid_pipe[4]) begin
                K_Hn_d2 <= K_Hn_d1 / 3;
                if (|sh_mult_res[23:12])
                    S_H_d1 <= 12'hFFF;
                else
                    // 提取 [15:4] 作为 Q0.12 的结果
                    S_H_d1 <= sh_mult_res[11:0];
            end
            if(in_valid_pipe[5]) begin
                S_D_d1 <= wire_S_D[23:12];
                K_Hn_d3 <= K_Hn_d2;
                S_H_d2 <= S_H_d1;
            end
            if(in_valid_pipe[6]) begin
                S_D <= S_D_d1;
                K_Hn125 <= K_Hn_d3;
                S_H <= S_H_d2;
            end
        end

    end
endmodule
