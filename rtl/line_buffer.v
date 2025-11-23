module line_buffer #(
        parameter WIDTH = 160,
        parameter DATA_WIDTH = 8
    )(
        input wire clk,
        input wire ce,                    // Chip Enable / Write Enable
        input wire [$clog2(WIDTH)-1:0] addr,
        input wire [DATA_WIDTH-1:0] din,
        output reg [DATA_WIDTH-1:0] dout
    );

    // 强制 Vivado 使用 Block RAM
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram [0:WIDTH-1];

    always @(posedge clk) begin
        if (ce) begin
            dout      <= ram[addr]; // Read old data (Read-Before-Write)
            ram[addr] <= din;       // Write new data
        end
    end

endmodule
