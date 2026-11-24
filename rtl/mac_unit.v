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
//
// Phase II: PIPE parameter
//   PIPE = 0 -> multiply and add happen in the same clock (original design)
//   PIPE = 1 -> the product goes into a register first, and gets added one
//               clock later. In Phase I the slowest path in the whole chip was
//               "multiplier then adder" in one cycle, so splitting it lets the
//               clock run faster. The catch: every result shows up 1 cycle later.
//   The en and load signals are delayed by one cycle too, so they still line
//   up with the product they belong to.
`timescale 1ns/1ps
module mac_unit #(
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter PIPE   = 0
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
    wire signed [2*DATA_W-1:0] prod = a * b;

    // what the adder actually sees (straight from the multiplier, or from the
    // pipeline register when PIPE = 1)
    wire signed [2*DATA_W-1:0] prod_s;
    wire                       en_s, load_s;

    generate
        if (PIPE) begin : g_pipe
            reg signed [2*DATA_W-1:0] prod_r;
            reg                       en_r, load_r;
            always @(posedge clk) begin
                if (rst || clr) begin
                    prod_r <= 0;
                    en_r   <= 1'b0;
                    load_r <= 1'b0;
                end else begin
                    // only grab a new product when enabled, so a stall
                    // doesn't add the same product twice
                    if (en) prod_r <= prod;
                    en_r   <= en;
                    load_r <= load;
                end
            end
            assign prod_s = prod_r;
            assign en_s   = en_r;
            assign load_s = load_r;
        end else begin : g_comb
            assign prod_s = prod;
            assign en_s   = en;
            assign load_s = load;
        end
    endgenerate

    // sign-extend the product to the accumulator width
    // (copy the top bit into the extra bits so negative numbers stay negative)
    wire signed [ACC_W-1:0] prod_ext = {{(ACC_W-2*DATA_W){prod_s[2*DATA_W-1]}}, prod_s};

    always @(posedge clk) begin
        if (rst || clr)
            acc <= {ACC_W{1'b0}};
        else if (en_s)
            acc <= load_s ? prod_ext : acc + prod_ext;
    end
endmodule
