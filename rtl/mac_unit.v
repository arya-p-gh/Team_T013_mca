// mac_unit.v
// The basic multiply-accumulate block. Every PE has one of these inside it,
// and the sequential baseline uses just one for the whole job.
//
// What it does each clock:
//   clr           -> acc becomes 0
//   en and load   -> acc = a*b         (throw away old sum, start fresh)
//   en            -> acc = acc + a*b   (normal accumulate)
//   nothing       -> acc stays the same
//
// About the numbers: a and b are 8-bit signed, and we treat them as Q4.4
// (4 integer bits, 4 fraction bits, so 1.5 is stored as 24). Multiplying two
// of them gives a 16-bit Q8.8 result. We keep a 20-bit accumulator so there's
// room to add up a bunch of products without overflowing.
`timescale 1ns/1ps
module mac_unit #(
    parameter DATA_W = 8,
    parameter ACC_W  = 20
)(
    input  wire                     clk,
    input  wire                     rst,    // sync reset, active high
    input  wire                     en,
    input  wire                     clr,
    input  wire                     load,
    input  wire signed [DATA_W-1:0] a,
    input  wire signed [DATA_W-1:0] b,
    output reg  signed [ACC_W-1:0]  acc
);
    // full product, then sign-extend it to the accumulator width
    // (copy the top bit into the extra bits so negative numbers stay negative)
    wire signed [2*DATA_W-1:0] prod     = a * b;
    wire signed [ACC_W-1:0]    prod_ext = {{(ACC_W-2*DATA_W){prod[2*DATA_W-1]}}, prod};

    always @(posedge clk) begin
        if (rst || clr)
            acc <= {ACC_W{1'b0}};
        else if (en)
            acc <= load ? prod_ext : acc + prod_ext;
    end
endmodule
