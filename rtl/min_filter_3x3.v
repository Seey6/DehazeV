module min_filter_3x3 #(
        parameter WIDTH = 160,
        parameter DATA_WIDTH = 8
    )(
        input wire clk,
        input wire rst_n,

        input wire [DATA_WIDTH-1:0] in_val,
        input wire       in_valid,

        output reg [DATA_WIDTH-1:0] out_val,
        output reg       out_valid
    );
    // reg [DATA_WIDTH-1:0] lb1 [0:WIDTH-1];
    // reg [DATA_WIDTH-1:0] lb2 [0:WIDTH-1];

    reg [$clog2(WIDTH)-1:0] wr_ptr;
    // reg [DATA_WIDTH-1:0] lb2_out;
    reg [DATA_WIDTH-1:0] in_val_d1, in_val_d2;
    reg [DATA_WIDTH-1:0] lb1_out_d1;
    reg [DATA_WIDTH-1:0] r0_0, r0_1, r0_2;
    reg [DATA_WIDTH-1:0] r1_0, r1_1, r1_2;
    reg [DATA_WIDTH-1:0] r2_0, r2_1, r2_2;
    function [DATA_WIDTH-1:0] min3;
        input [DATA_WIDTH-1:0] a, b, c;
        begin
            if (a <= b && a <= c)
                min3 = a;
            else if (b <= a && b <= c)
                min3 = b;
            else
                min3 = c;
        end
    endfunction


    wire [DATA_WIDTH-1:0] lb1_dout;
    wire [DATA_WIDTH-1:0] lb2_dout;
    // =========================================================================
    // 2. Instantiate Line Buffers
    // =========================================================================

    // Line Buffer 1: 缓存第一行
    // 当 in_valid 为高时，写入当前像素，读出上一行的同列像素
    line_buffer #(
                    .WIDTH(WIDTH),
                    .DATA_WIDTH(DATA_WIDTH)
                ) u_lb1 (
                    .clk  (clk),
                    .ce   (in_valid), // Enable on input valid
                    .addr (wr_ptr),   // Shared write pointer
                    .din  (in_val),
                    .dout (lb1_dout)  // Data from LB1 (Row 1)
                );

    // Line Buffer 2: 缓存第二行
    // 当 in_valid_pipeline[0] 为高时（即 in_valid 的下一拍），
    // 写入 LB1 刚刚读出的数据，并读出再上一行的数据
    line_buffer #(
                    .WIDTH(WIDTH),
                    .DATA_WIDTH(DATA_WIDTH)
                ) u_lb2 (
                    .clk  (clk),
                    .ce   (in_valid_pipeline[0]), // Enable delayed by 1 cycle
                    .addr (wr_ptr),               // Uses same pointer address
                    .din  (lb1_dout),             // Input comes from LB1 output
                    .dout (lb2_dout)              // Data from LB2 (Row 2)
                );


    reg [DATA_WIDTH-1:0] min_r0, min_r1, min_r2;

    reg [DATA_WIDTH-1:0] min_final_calc;

    reg [15:0] pixel_cnt;
    reg        warmup_done;
    reg [4:0]  in_valid_pipeline;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr            <= 0;
            pixel_cnt         <= 0;
            warmup_done       <= 0;
            out_valid         <= 0;
            out_val           <= 0;
            in_valid_pipeline <= 0;

            r0_0 <= 0;
            r0_1 <= 0;
            r0_2 <= 0;
            r1_0 <= 0;
            r1_1 <= 0;
            r1_2 <= 0;
            r2_0 <= 0;
            r2_1 <= 0;
            r2_2 <= 0;
        end
        else begin
            in_valid_pipeline <= {in_valid_pipeline[3:0], in_valid};
            if (in_valid) begin
                // lb1_out <= lb1_dout;
                // lb1[wr_ptr] <= in_val;
                in_val_d1  <= in_val;

            end
            if (in_valid_pipeline[0]) begin
                // lb2[wr_ptr] <= lb1_out;
                // lb2_out <= ;
                /* verilator lint_off WIDTHEXPAND */
                if (wr_ptr == WIDTH - 1)
                    /* verilator lint_on WIDTHEXPAND */
                    wr_ptr <= 0;
                else
                    wr_ptr <= wr_ptr + 1;

                in_val_d2  <= in_val_d1;
                lb1_out_d1 <= lb1_dout;
            end
            if (in_valid_pipeline[1]) begin
                r0_0 <= in_val_d2;
                r1_0 <= lb1_out_d1;
                r2_0 <= lb2_dout;
            end
            if (in_valid_pipeline[2]) begin
                r0_1 <= r0_0;
                r1_1 <= r1_0;
                r2_1 <= r2_0;
            end
            if (in_valid_pipeline[3]) begin
                r0_2 <= r0_1;
                r1_2 <= r1_1;
                r2_2 <= r2_1;
            end
            if(in_valid_pipeline[2]) begin
                min_r0 <= min3(r0_0, r0_1, r0_2);
                min_r1 <= min3(r1_0, r1_1, r1_2);
                min_r2 <= min3(r2_0, r2_1, r2_2);
            end
            if(in_valid_pipeline[3]) begin
                min_final_calc <= min3(min_r0, min_r1, min_r2);
                if (!warmup_done) begin
                    pixel_cnt <= pixel_cnt + 1;
                    if (pixel_cnt >= 16'(WIDTH * 2 + 2)) begin
                        warmup_done <= 1;
                    end
                end
            end
            if (in_valid_pipeline[4]) begin
                out_valid <= warmup_done;
                out_val   <= min_final_calc;
            end
            else begin
                out_valid <= 1'b0;
                out_val   <= 0;
            end

        end
    end

endmodule
