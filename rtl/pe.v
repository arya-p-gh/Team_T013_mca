// pe.v
// One processing element (PE), the little cell we copy N x N times.
//
//            b_in
//             |
//             v
//   a_in --> [ PE ] --> a_out
//             |
//             v
//            b_out
//
// Each cycle a PE does two things:
//   1. multiplies whatever a and b it's holding right now and adds that to
//      its own running total (acc). That total ends up being one C[i][j].
//   2. passes a to the PE on its right and b to the PE below it, one cycle
//      later. This hand-off is what makes it "systolic": data pulses through
//      the grid like blood through a heart.
//
// The result never moves while it's being built, it just sits in acc. That's
// why this style is called "output stationary".
//
// Phase II: PIPE is passed straight down to the MAC. The a/b forwarding still
// takes exactly 1 cycle either way, only acc finishes 1 cycle later.
`timescale 1ns/1ps
module pe #(
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter PIPE   = 0
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     en,
    input  wire                     clr,
    input  wire signed [DATA_W-1:0] a_in,
    input  wire signed [DATA_W-1:0] b_in,
    output reg  signed [DATA_W-1:0] a_out,
    output reg  signed [DATA_W-1:0] b_out,
    output wire signed [ACC_W-1:0]  acc
);
    // pass a right and b down (registered, so it takes exactly 1 cycle)
    always @(posedge clk) begin
        if (rst || clr) begin
            a_out <= {DATA_W{1'b0}};
            b_out <= {DATA_W{1'b0}};
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end

    // the actual math. load is tied to 0 because a PE always accumulates;
    // we use clr before each new job to start from zero instead
    mac_unit #(.DATA_W(DATA_W), .ACC_W(ACC_W), .PIPE(PIPE)) u_mac (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .clr (clr),
        .load(1'b0),
        .a   (a_in),
        .b   (b_in),
        .acc (acc)
    );
endmodule
