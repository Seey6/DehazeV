module dehaze_top #(
        parameter WIDTH = 320,
        parameter HEIGHT = 240
    )(
        input wire clk,
        input wire rst_n,

        // Input Stream
        input wire [7:0] in_r,
        input wire [7:0] in_g,
        input wire [7:0] in_b,
        input wire       in_valid,
        input wire       in_sof,
        input wire       in_eol,

        // Output Stream
        output wire [7:0] out_r,
        output wire [7:0] out_g,
        output wire [7:0] out_b,
        output wire       out_valid,
        output wire       out_sof,
        output wire       out_eol,
        output wire [11:0] out_inv_t,
        output wire [11:0] out_sat
    );

    wire [7:0] A_r, A_g, A_b;
    wire       A_valid;
    ale #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_ale (
            .clk(clk), .rst_n(rst_n),
            .in_r(in_r), .in_g(in_g), .in_b(in_b),
            .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol),
            .A_r(A_r), .A_g(A_g), .A_b(A_b),
            .A_valid(A_valid)
        );

    wire [11:0] S_H;
    wire [11:0] S_D;
    wire [11:0] K_Hn125;
    wire       sat_valid;
    calc_sat u_sat (
                 .clk(clk), .rst_n(rst_n),
                 .in_r(in_r), .in_g(in_g), .in_b(in_b),
                 .in_valid(in_valid),
                 .A_r(A_r), .A_g(A_g), .A_b(A_b),
                 .A_valid(A_valid),
                 .S_H(S_H), .S_D(S_D), .K_Hn125(K_Hn125),
                 .out_valid(sat_valid)
             );

    wire [11:0] inv_t;
    /* verilator lint_off UNUSEDSIGNAL */
    wire       t_valid;
    /* verilator lint_on UNUSEDSIGNAL */
    calc_t u_t (
               .clk(clk), .rst_n(rst_n),
               .S_H(S_H), .S_D(S_D), .K_Hn125(K_Hn125),
               .in_valid(sat_valid),
               .inv_t(inv_t),
               .out_valid(t_valid)
           );
    // -------------------------------------------------------------------------
    // Delay Alignment
    // -------------------------------------------------------------------------
    // Latency Analysis:
    // calc_sat: 8 cycles (after fix)
    // calc_t:   6 cycles
    // Total Path Latency: 14 cycles
    // restore module latency: 3 cycles

    localparam PIPELINE_DLY = 14;
    localparam RESTORE_DLY  = 3;
    localparam TOTAL_DLY    = PIPELINE_DLY + RESTORE_DLY;

    reg [7:0] r_dly [0:PIPELINE_DLY-1];
    reg [7:0] g_dly [0:PIPELINE_DLY-1];
    reg [7:0] b_dly [0:PIPELINE_DLY-1];
    reg       val_dly [0:PIPELINE_DLY-1];
    reg [7:0] Ar_dly [0:PIPELINE_DLY-1];
    reg [7:0] Ag_dly [0:PIPELINE_DLY-1];
    reg [7:0] Ab_dly [0:PIPELINE_DLY-1];

    // SOF and EOL need to be delayed by the full path (Pipeline + Restore)
    reg       sof_dly [0:TOTAL_DLY-1];
    reg       eol_dly [0:TOTAL_DLY-1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<PIPELINE_DLY; i=i+1) begin
                r_dly[i]   <= 0;
                g_dly[i]   <= 0;
                b_dly[i]   <= 0;
                val_dly[i] <= 0;
                Ar_dly[i]  <= 0;
                Ag_dly[i]  <= 0;
                Ab_dly[i]  <= 0;
            end
            for (i=0; i<TOTAL_DLY; i=i+1) begin
                sof_dly[i] <= 0;
                eol_dly[i] <= 0;
            end
        end
        else begin
            // Input to delay line (Index 0)
            r_dly[0]   <= in_r;
            g_dly[0]   <= in_g;
            b_dly[0]   <= in_b;
            val_dly[0] <= in_valid;
            Ar_dly[0]  <= A_r; // for test
            Ag_dly[0]  <= A_g;
            Ab_dly[0]  <= A_b;

            sof_dly[0] <= in_sof;
            eol_dly[0] <= in_eol;

            // Shift
            for (i=1; i<PIPELINE_DLY; i=i+1) begin
                r_dly[i]   <= r_dly[i-1];
                g_dly[i]   <= g_dly[i-1];
                b_dly[i]   <= b_dly[i-1];
                val_dly[i] <= val_dly[i-1];
                Ar_dly[i]  <= Ar_dly[i-1];
                Ag_dly[i]  <= Ag_dly[i-1];
                Ab_dly[i]  <= Ab_dly[i-1];
            end
            for (i=1; i<TOTAL_DLY; i=i+1) begin
                sof_dly[i] <= sof_dly[i-1];
                eol_dly[i] <= eol_dly[i-1];
            end
        end
    end

    restore u_restore (
                .clk(clk), .rst_n(rst_n),
                .in_r(r_dly[PIPELINE_DLY-1]),
                .in_g(g_dly[PIPELINE_DLY-1]),
                .in_b(b_dly[PIPELINE_DLY-1]),
                .A_r(Ar_dly[PIPELINE_DLY-2]),
                .A_g(Ag_dly[PIPELINE_DLY-2]),
                .A_b(Ab_dly[PIPELINE_DLY-2]),
                .in_valid(val_dly[PIPELINE_DLY-1]),
                .inv_t(inv_t),
                .out_valid(out_valid),
                .out_r(out_r),
                .out_g(out_g),
                .out_b(out_b)
            );

    assign out_sof = sof_dly[TOTAL_DLY-1];
    assign out_eol = eol_dly[TOTAL_DLY-1];

    // -------------------------------------------------------------------------
    // inv_t Output Alignment
    // -------------------------------------------------------------------------
    reg [11:0] inv_t_dly [0:RESTORE_DLY-1];
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j=0; j<RESTORE_DLY; j=j+1)
                inv_t_dly[j] <= 0;
        end
        else begin
            inv_t_dly[0] <= inv_t;
            for (j=1; j<RESTORE_DLY; j=j+1)
                inv_t_dly[j] <= inv_t_dly[j-1];
        end
    end
    assign out_inv_t = inv_t_dly[RESTORE_DLY-1];

    // -------------------------------------------------------------------------
    // Saturation Output Alignment
    // -------------------------------------------------------------------------
    // S_H is valid at the input of calc_t.
    // calc_t latency = 6
    // restore latency = 3
    // Total delay = 9
    localparam SAT_DLY = 9;
    reg [11:0] sat_dly [0:SAT_DLY-1];
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k=0; k<SAT_DLY; k=k+1)
                sat_dly[k] <= 0;
        end
        else begin
            sat_dly[0] <= S_H;
            for (k=1; k<SAT_DLY; k=k+1)
                sat_dly[k] <= sat_dly[k-1];
        end
    end
    assign out_sat = sat_dly[SAT_DLY-1];

endmodule
