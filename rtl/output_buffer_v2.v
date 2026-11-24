// output_buffer_v2.v
// Phase II output buffer. Still takes a snapshot of every PE result in one
// clock when capture is high, but now it can also hand back a whole row of C
// per clock (rd_row -> rd_data_row). Reading a 4x4 result drops from 16
// cycles to 4. The single-element port is kept too, it's handy for debugging.
//
// Because it's a snapshot, the array can start the next job right after
// capture, and the host reads these results while that job runs.
`timescale 1ns/1ps
module output_buffer_v2 #(
    parameter N      = 4,
    parameter ACC_W  = 20,
    parameter ROW_W  = 2,
    parameter ADDR_W = 4
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     capture,
    input  wire [N*N*ACC_W-1:0]     c_flat,
    // whole-row read: element c of the row is at [c*ACC_W +: ACC_W]
    input  wire [ROW_W-1:0]         rd_row,
    output wire [N*ACC_W-1:0]       rd_data_row,
    // single element read (row*N + col)
    input  wire [ADDR_W-1:0]        rd_addr,
    output wire signed [ACC_W-1:0]  rd_data
);
    reg [N*N*ACC_W-1:0] c_reg;

    always @(posedge clk) begin
        if (rst)          c_reg <= {N*N*ACC_W{1'b0}};
        else if (capture) c_reg <= c_flat;
    end

    // row r is stored as N neighbouring slices, so it's one wide slice
    assign rd_data_row = c_reg[rd_row*N*ACC_W +: N*ACC_W];
    assign rd_data     = c_reg[rd_addr*ACC_W +: ACC_W];
endmodule
