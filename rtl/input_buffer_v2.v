// input_buffer_v2.v
// Phase II version of the input buffer. Same skew trick as input_buffer.v,
// but with two upgrades that attack the I/O bottleneck we found in Phase I
// (loading took 32 cycles while the actual multiply took only 14):
//
//   1. Row-wide writes: the host writes a whole row (N values) per clock
//      instead of one number. Loading a 4x4 matrix now takes 4 cycles, not 16.
//
//   2. Two banks (ping-pong / double buffering): there's room for two
//      matrices. While the array is busy reading bank 0, the host can already
//      fill bank 1 with the next matrix, so loading hides behind computing.
//
// Storage is just 2N rows of N values each:
//   rows[bank*N + r] = row r of the matrix in that bank
//
// Feeding works like before. At step t, lane l outputs
//   for A (IS_B = 0):  A[l][t-l]
//   for B (IS_B = 1):  B[t-l][l]
// read from whichever bank the controller picked (rbank), and 0 outside the
// lane's window.
`timescale 1ns/1ps
module input_buffer_v2 #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter IS_B   = 0,   // 0 = A buffer, 1 = B buffer
    parameter ROW_W  = 2,   // enough bits for a row number 0..N-1
    parameter CNT_W  = 5
)(
    input  wire                 clk,
    input  wire                 rst,
    // row write port
    input  wire                 we,
    input  wire                 wbank,      // which bank to write (0 or 1)
    input  wire [ROW_W-1:0]     wrow,       // which row
    input  wire [N*DATA_W-1:0]  wdata,      // the whole row, element c at [c*DATA_W +: DATA_W]
    // feed port
    input  wire                 rbank,      // which bank the array reads
    input  wire                 feed_en,
    input  wire [CNT_W-1:0]     t,
    output reg  [N*DATA_W-1:0]  lanes
);
    reg [N*DATA_W-1:0] rows [0:2*N-1];

    always @(posedge clk)
        if (we) rows[wbank*N + wrow] <= wdata;

    integer l, k;
    always @(posedge clk) begin
        if (rst) begin
            lanes <= {N*DATA_W{1'b0}};
        end else begin
            for (l = 0; l < N; l = l + 1) begin
                k = t - l;   // lane l runs l steps behind
                if (feed_en && (t >= l) && (k < N)) begin
                    if (IS_B)   // B[k][l]: row k, column l
                        lanes[l*DATA_W +: DATA_W] <= rows[rbank*N + k][l*DATA_W +: DATA_W];
                    else        // A[l][k]: row l, column k
                        lanes[l*DATA_W +: DATA_W] <= rows[rbank*N + l][k*DATA_W +: DATA_W];
                end else
                    lanes[l*DATA_W +: DATA_W] <= {DATA_W{1'b0}};
            end
        end
    end
endmodule
