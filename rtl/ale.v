module ale #(
        parameter WIDTH = 320,
        /* verilator lint_off UNUSEDPARAM */
        parameter HEIGHT = 240,
        /* verilator lint_on UNUSEDPARAM */
        parameter DATA_WIDTH = 8
    )(
        input wire clk,
        input wire rst_n,

        input wire [7:0] in_r, in_g, in_b,
        input wire       in_valid,
        input wire       in_sof,
        input wire       in_eol,

        output reg [7:0] A_r, A_g, A_b,
        output reg       A_valid
    );

    localparam DS_WIDTH = WIDTH / 2;

    // ========================================================================
    // Downsampling Logic
    // ========================================================================
    // We want to sample 1 pixel out of every 2x2 block.
    // For example, pixels at (even, even) coordinates.

    reg [10:0] x_cnt;
    reg [10:0] y_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt <= 0;
            y_cnt <= 0;
        end
        else if (in_valid) begin
            if (in_sof) begin
                x_cnt <= 1; // Current pixel is (0,0), next is (1,0)
                y_cnt <= 0;
            end
            else if (in_eol) begin
                x_cnt <= 0;
                y_cnt <= y_cnt + 1;
            end
            else begin
                x_cnt <= x_cnt + 1;
            end
        end
    end

    // Determine if current pixel should be sampled
    // Sample if x is even and y is even.
    // Note: on the cycle in_sof is high, we are at (0,0).
    wire current_x_is_even = in_sof ? 1'b1 : (x_cnt[0] == 0);
    wire current_y_is_even = in_sof ? 1'b1 : (y_cnt[0] == 0);

    wire is_sample = in_valid && current_x_is_even && current_y_is_even;

    // ========================================================================
    // 3x3 Minimum Filter Chains
    // ========================================================================
    // Cascading three 3x3 filters on the downsampled image approximates
    // a 15x15 filter on the original image.
    // Filter 1 output: 3x3 coverage (DS)
    // Filter 2 output: 5x5 coverage (DS)
    // Filter 3 output: 7x7 coverage (DS) -> approx 14x14 (Original)

    // R Channel
    wire [7:0] r1, r2, r3;
    wire v1_r, v2_r, v3_r;
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_r1 (clk, rst_n, in_r, is_sample, r1, v1_r);
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_r2 (clk, rst_n, r1,   v1_r,      r2, v2_r);
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_r3 (clk, rst_n, r2,   v2_r,      r3, v3_r);

    // G Channel
    wire [7:0] g1, g2, g3;
    wire v1_g, v2_g;
    /* verilator lint_off UNUSEDSIGNAL */
    wire v3_g;
    /* verilator lint_on UNUSEDSIGNAL */
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_g1 (clk, rst_n, in_g, is_sample, g1, v1_g);
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_g2 (clk, rst_n, g1,   v1_g,      g2, v2_g);
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_g3 (clk, rst_n, g2,   v2_g,      g3, v3_g);

    // B Channel
    wire [7:0] b1, b2, b3;
    wire v1_b, v2_b;
    /* verilator lint_off UNUSEDSIGNAL */
    wire v3_b;
    /* verilator lint_on UNUSEDSIGNAL */
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_b1 (clk, rst_n, in_b, is_sample, b1, v1_b);
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_b2 (clk, rst_n, b1,   v1_b,      b2, v2_b);
    min_filter_3x3 #(.WIDTH(DS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_min_b3 (clk, rst_n, b2,   v2_b,      b3, v3_b);

    // Valid signal from last stage (all channels are aligned)
    wire valid_out = v3_r;

    // ========================================================================
    // Atmospheric Light Estimation (Max of Dark Channel)
    // ========================================================================

    // Calculate Dark Channel of the filtered output
    // DC = min(R_min, G_min, B_min)
    wire [7:0] min_rg = (r3 < g3) ? r3 : g3;
    wire [7:0] cur_dc = (min_rg < b3) ? min_rg : b3;

    reg [7:0] max_dc;
    reg [7:0] cand_r, cand_g, cand_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_r <= 8'd255;
            A_g <= 8'd255;
            A_b <= 8'd255;
            A_valid <= 0;
            max_dc <= 0;
            cand_r <= 8'd255;
            cand_g <= 8'd255;
            cand_b <= 8'd255;
        end
        else begin
            A_valid <= 0;

            // Update A at start of new frame with the candidate found in previous frame
            if (in_valid && in_sof) begin
                A_r <= cand_r;
                A_g <= cand_g;
                A_b <= cand_b;
                A_valid <= 1;

                // Reset search for new frame
                max_dc <= 0;
                cand_r <= 8'd255;
                cand_g <= 8'd255;
                cand_b <= 8'd255;
            end

            // Search for max dark channel
            if (valid_out) begin
                if (cur_dc > max_dc) begin
                    max_dc <= cur_dc;
                    // We use the filtered values as the estimate for A.
                    // This corresponds to the window minimums at the brightest dark channel location.
                    cand_r <= r3;
                    cand_g <= g3;
                    cand_b <= b3;
                end
            end
        end
    end

endmodule
