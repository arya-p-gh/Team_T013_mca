// input_buffer.v
// Holds one input matrix and feeds it into the array with the right timing.
// We use two copies: one for A (feeds the rows) and one for B (feeds the
// columns).
//
// Why the timing matters: if we pushed a whole column of A in at once, the
// numbers would reach the PEs at the wrong moments and get multiplied with
// the wrong b values. The fix is the classic systolic "skew": lane 0 starts
// right away, lane 1 starts 1 cycle later, lane 2 starts 2 cycles later, and
// so on. Drawn out, the data enters as a diagonal staircase.
//
// At step t, lane l outputs:
//   for A (IS_B = 0):  A[l][t-l]
//   for B (IS_B = 1):  B[t-l][l]
// and outputs 0 when it has nothing to send (before its turn or after it has
// sent all N values). 0 times anything is 0, so the PEs can just keep
// multiplying and the zeros don't mess up the sums. Handy trick.
//
// The output is registered (1 cycle delay) so the path from memory to the
// PEs stays short and the clock can run faster.
`timescale 1ns/1ps
module input_buffer #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter IS_B   = 0,   // 0 = this is the A buffer, 1 = the B buffer
    parameter ADDR_W = 4,   // needs to fit N*N addresses
    parameter CNT_W  = 5    // needs to fit a count up to about 3N
)(
    input  wire                 clk,
    input  wire                 rst,
    // host writes matrix elements in here, one per cycle
    input  wire                 we,
    input  wire [ADDR_W-1:0]    waddr,      // row*N + col
    input  wire [DATA_W-1:0]    wdata,
    // controller tells us when to feed and which step we're on
    input  wire                 feed_en,
    input  wire [CNT_W-1:0]     t,
    output reg  [N*DATA_W-1:0]  lanes
);
    // the matrix itself, stored row by row
    reg [DATA_W-1:0] mem [0:N*N-1];

    always @(posedge clk)
        if (we) mem[waddr] <= wdata;

    // work out what each lane should output this cycle
    integer l;
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            lanes <= {N*DATA_W{1'b0}};
        end else begin
            for (l = 0; l < N; l = l + 1) begin
                k = t - l;   // which element this lane is on (lane l runs l steps behind)
                if (feed_en && (t >= l) && (k < N))
                    lanes[l*DATA_W +: DATA_W] <= IS_B ? mem[k*N + l] : mem[l*N + k];
                else
                    lanes[l*DATA_W +: DATA_W] <= {DATA_W{1'b0}};  // not this lane's turn, send 0
            end
        end
    end
endmodule
