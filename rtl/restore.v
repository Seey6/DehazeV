module restore (
        input wire clk,
        input wire rst_n,

        input wire [7:0] in_r, in_g, in_b,    // Hazy Image Q8.0
        input wire [7:0] A_r, A_g, A_b,       // Atmospheric Light Q8.0
        input wire [11:0] inv_t,              // 1/t (unsigned) Q4.8
        input wire        in_valid,

        output reg [7:0] out_r, out_g, out_b, // Dehazed Image D Q8.0
        output reg       out_valid
    );

    // -----------------------------------------------------------
    // Pipeline Stage 1: Subtraction (H - A)
    // -----------------------------------------------------------
    // 必须使用有符号数 (signed) 来处理 H - A 的结果
    // 9-bit signed: range -255 to +255
    reg signed [8:0] sub_r, sub_g, sub_b;

    // 延迟对齐用的信号
    reg [11:0] inv_t_d1;
    reg [7:0]  A_r_d1, A_g_d1, A_b_d1;
    reg        valid_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sub_r <= 0;
            sub_g <= 0;
            sub_b <= 0;
            valid_d1 <= 0;
        end
        else begin
            // 逻辑修正： H - A，并转换为有符号数
            // $signed({1'b0, in_r}) 确保被视为正数再减
            sub_r <= $signed({1'b0, in_r}) - $signed({1'b0, A_r});
            sub_g <= $signed({1'b0, in_g}) - $signed({1'b0, A_g});
            sub_b <= $signed({1'b0, in_b}) - $signed({1'b0, A_b});

            inv_t_d1 <= inv_t;
            A_r_d1 <= A_r;
            A_g_d1 <= A_g;
            A_b_d1 <= A_b;
            valid_d1 <= in_valid;
        end
    end

    // -----------------------------------------------------------
    // Pipeline Stage 2: Multiplication & Shift ((H-A)/t)
    // -----------------------------------------------------------
    // 乘法结果位数：9 (signed) + 12 (unsigned) = 21 bits (signed result)
    /* verilator lint_off UNUSEDSIGNAL */
    reg signed [20:0] mult_r, mult_g, mult_b;
    /* verilator lint_on UNUSEDSIGNAL */
    reg [7:0]  A_r_d2, A_g_d2, A_b_d2;
    reg        valid_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_r <= 0;
            mult_g <= 0;
            mult_b <= 0;
            valid_d2 <= 0;
        end
        else begin
            // 有符号数 * 无符号数(需要强转为signed以进行正确运算)
            mult_r <= sub_r * $signed({1'b0, inv_t_d1}); //signed Q12.8
            mult_g <= sub_g * $signed({1'b0, inv_t_d1});
            mult_b <= sub_b * $signed({1'b0, inv_t_d1});

            A_r_d2 <= A_r_d1;
            A_g_d2 <= A_g_d1;
            A_b_d2 <= A_b_d1;
            valid_d2 <= valid_d1;
        end
    end

    // -----------------------------------------------------------
    // Pipeline Stage 3: Addition & Clamp (Result + A)
    // -----------------------------------------------------------
    // 我们需要取 mult 的高位（即右移12位）。
    // mult 是 Q12，右移12位后变回整数 (Q0)。
    // 取出的部分仍然是有符号的。
    wire signed [12:0] term1_r, term1_g, term1_b; // 9位足以覆盖结果

    // 注意：有符号数右移，必须保证算术右移（保留符号位）。
    // 这里直接切片 [20:12] 即可，因为 mult_r 是 signed 声明的
    assign term1_r = mult_r[20:8]; //Q12.0
    assign term1_g = mult_g[20:8];
    assign term1_b = mult_b[20:8];

    // 临时加法结果，为了防止溢出，多用几位
    wire signed [13:0] sum_r, sum_g, sum_b;
    assign sum_r = term1_r + $signed({5'b0, A_r_d2});
    assign sum_g = term1_g + $signed({5'b0, A_g_d2});
    assign sum_b = term1_b + $signed({5'b0, A_b_d2});

    // 饱和截断函数 (Clamping function)
    function [7:0] clamp;
        input signed [13:0] val;
        begin
            if (val < 0)
                clamp = 8'd0;
            else if (val > 255)
                clamp = 8'd255;
            else
                clamp = val[7:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_r <= 0;
            out_g <= 0;
            out_b <= 0;
            out_valid <= 0;
        end
        else begin
            out_r <= clamp(sum_r);
            out_g <= clamp(sum_g);
            out_b <= clamp(sum_b);
            out_valid <= valid_d2;
        end
    end

endmodule
