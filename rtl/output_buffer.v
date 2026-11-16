// output_buffer.v
// Takes a snapshot of all the PE results once the multiply finishes.
//
// When capture goes high we copy every accumulator in one clock. After that
// the host can read C out at its own pace, one element at a time, while the
// array is free to start on something else.
`timescale 1ns/1ps
module output_buffer #(
    parameter N      = 4,
    parameter ACC_W  = 20,
    parameter ADDR_W = 4
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     capture,
    input  wire [N*N*ACC_W-1:0]     c_flat,
    input  wire [ADDR_W-1:0]        rd_addr,   // row*N + col
    output wire signed [ACC_W-1:0]  rd_data
);
    reg [N*N*ACC_W-1:0] c_reg;

    always @(posedge clk) begin
        if (rst)          c_reg <= {N*N*ACC_W{1'b0}};
        else if (capture) c_reg <= c_flat;
    end

    // plain mux: pick the slice the host asked for (no clock, answer comes back right away)
    assign rd_data = c_reg[rd_addr*ACC_W +: ACC_W];
endmodule
