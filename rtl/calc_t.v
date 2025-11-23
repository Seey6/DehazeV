module calc_t (
        input wire clk,
        input wire rst_n,

        input wire [11:0] S_H,      // Q0.12
        input wire [11:0] S_D,      // Q0.12
        input wire [11:0] K_Hn125,  // Q4.8
        input wire        in_valid,

        output reg [11:0] inv_t,    // Q4.8
        output reg        out_valid
    );
    // ----------------------------------------------------
    // Valid Signal Pipeline
    // ----------------------------------------------------
    reg [4:0] in_valid_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            in_valid_pipe <= 0;
        else
            in_valid_pipe <= {in_valid_pipe[3:0], in_valid};
    end

    // ----------------------------------------------------
    // Data Pipeline
    // ----------------------------------------------------

    // Stage 1 Regs
    reg [11:0] K_Hn125_d1;
    reg [11:0] S_D_d1;
    reg [11:0] SHsubSD;

    // Stage 2 Regs
    reg [11:0] Khn125mulSHsubSD;
    reg [11:0] S_D_d2;

    // Stage 3 Regs
    reg [11:0] S_D_d3;
    reg [11:0] SDsubKhn125mulSHsubSD; // Denominator

    // Stage 4 Regs (LUT Output Ready)
    reg [11:0] S_D_d4;

    // Stage 5 Regs (Result)
    reg [11:0] inv_t_tmp;

    // ----------------------------------------------------
    // Wires & Instantiation
    // ----------------------------------------------------

    // 【修正1】: 必须定义为 wire
    /* verilator lint_off UNUSEDSIGNAL */
    wire [11:0] inv_SDsub125; //Q8.12
    /* verilator lint_on UNUSEDSIGNAL */
    // LUT Instantiation (Assumes Latency = 1 cycle)
    // Logic: Addr valid @ Pipe 2 -> Data valid @ Pipe 3
    lut_inv12 u_lut_inv12(
                  .clk  (clk),
                  .addr (SDsubKhn125mulSHsubSD),
                  .data (inv_SDsub125)
              );

    // Multipliers
    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] wire_Khn125mulSHsubSD;//Q4.20
    assign wire_Khn125mulSHsubSD = K_Hn125_d1 * SHsubSD;

    wire [23:0] wire_inv_t_tmp;
    assign wire_inv_t_tmp = inv_SDsub125 * S_D_d4;
    /* verilator lint_on UNUSEDSIGNAL */

    // ----------------------------------------------------
    // Pipeline Logic
    // ----------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 建议复位数据寄存器，虽然不是必须，但有助于仿真debug
            SHsubSD <= 0;
            K_Hn125_d1 <= 0;
            S_D_d1 <= 0;
            Khn125mulSHsubSD <= 0;
            S_D_d2 <= 0;
            SDsubKhn125mulSHsubSD <= 0;
            S_D_d3 <= 0;
            S_D_d4 <= 0;
            inv_t_tmp <= 0;
            inv_t <= 0;
            out_valid <= 0;
        end
        else begin
            // --- Pipe 0 Input ---
            if(in_valid) begin
                // 【修正2】: 增加下溢保护
                // if(S_D == 0 || S_H==0) begin
                //     SHsubSD <= 12'd2048;
                //     S_D_d1 <= 12'd2048;
                // end
                // else begin
                S_D_d1 <= S_D;
                if (S_D >= S_H)
                    SHsubSD <= S_D - S_H; //Q0.12
                else
                    SHsubSD <= 12'd0; // 保护：如果不应该发生，设为0
                // end


                K_Hn125_d1 <= K_Hn125; //Q4.8
            end

            // --- Pipe 1 (Stage 5 Part A) ---
            if(in_valid_pipe[0]) begin
                // Calculate: 1.25K * (SD - SH)
                if (|wire_Khn125mulSHsubSD[23:20]) begin
                    // 饱和处理：设为最大值 (或者直接设为 12'hFFF)
                    // 只要比 S_D (最大 1.0) 大，下一级的减法保护就会生效
                    Khn125mulSHsubSD <= 12'hFFF;
                end
                else begin
                    // 没有整数位，安全截取小数部分 [19:8] (对应 Q0.12)
                    Khn125mulSHsubSD <= wire_Khn125mulSHsubSD[19:8];
                end
                S_D_d2           <= S_D_d1;//Q0.12
            end

            // --- Pipe 2 (Stage 5 Part B) ---
            if(in_valid_pipe[1]) begin
                // Calculate Denominator: SD - (Term above)
                // 同样建议增加下溢保护，虽然理论上分母不应为负
                if (S_D_d2 >= Khn125mulSHsubSD)
                    SDsubKhn125mulSHsubSD <= S_D_d2 - Khn125mulSHsubSD;//Q0.12
                else
                    SDsubKhn125mulSHsubSD <= 12'd0; // 防止分母为0或负数，给最小正数

                S_D_d3 <= S_D_d2;
            end

            // --- Pipe 3 (Stage 6 Part A - LUT Wait) ---
            if(in_valid_pipe[2]) begin
                // LUT is reading data during this cycle based on addr from Pipe 2
                S_D_d4 <= S_D_d3;
            end

            // --- Pipe 4 (Stage 6 Part B - Final Mul) ---
            if(in_valid_pipe[3]) begin
                // inv_SDsub125 is valid here (LUT output)
                // Calculate: S_D * (1/Denominator)
                if(|wire_inv_t_tmp[23:16]) begin
                    inv_t_tmp <= 12'hfff;
                end
                if(|wire_inv_t_tmp[15:12]) begin
                    inv_t_tmp <= wire_inv_t_tmp[15:4];
                end
                else begin
                    inv_t_tmp <= 12'h100;
                end
            end

            // --- Output ---
            if(in_valid_pipe[4]) begin
                inv_t     <= inv_t_tmp;
                out_valid <= 1'b1;
            end
            else begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule
