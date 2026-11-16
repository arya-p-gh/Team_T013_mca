// systolic_top.v
// Top level of the accelerator. Computes C = A x B for two N x N matrices.
//
// How to use it from the outside (this is our "matrix data interface"):
//   1. Write A and B one element at a time:
//        wr_en = 1, wr_sel = 0 for A or 1 for B,
//        wr_addr = row*N + col, wr_data = the value
//   2. Pulse start for one cycle. busy stays high while it works.
//   3. When done pulses, read the answers: put row*N + col on rd_addr and
//      the result shows up on rd_data straight away.
//
// What's inside:
//   systolic_top
//    |- input_buffer        u_buf_a  (stores A, feeds the rows with skew)
//    |- input_buffer        u_buf_b  (stores B, feeds the columns with skew)
//    |- systolic_controller u_ctrl   (the FSM running the show)
//    |- systolic_array      u_array  (N*N PEs, each with a MAC)
//    '- output_buffer       u_obuf   (holds the final C for reading)
`timescale 1ns/1ps
module systolic_top #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter ADDR_W = (N*N <= 2) ? 1 : $clog2(N*N),   // enough bits to address N*N elements
    parameter CNT_W  = $clog2(3*N) + 1                 // enough bits to count to about 3N
)(
    input  wire                     clk,
    input  wire                     rst,
    // writing the input matrices
    input  wire                     wr_en,
    input  wire                     wr_sel,     // 0 = A, 1 = B
    input  wire [ADDR_W-1:0]        wr_addr,
    input  wire [DATA_W-1:0]        wr_data,
    // go / status
    input  wire                     start,
    output wire                     busy,
    output wire                     done,
    // reading the result
    input  wire [ADDR_W-1:0]        rd_addr,
    output wire signed [ACC_W-1:0]  rd_data
);
    wire             arr_clr, arr_en, feed_en, capture;
    wire [CNT_W-1:0] t;
    wire [2:0]       state;

    wire [N*DATA_W-1:0]  a_left, b_top;
    wire [N*N*ACC_W-1:0] c_flat;

    systolic_controller #(.N(N), .CNT_W(CNT_W)) u_ctrl (
        .clk(clk), .rst(rst), .start(start),
        .arr_clr(arr_clr), .arr_en(arr_en), .feed_en(feed_en), .t(t),
        .capture(capture), .busy(busy), .done(done), .state(state)
    );

    // writes are ignored while busy, so the host can't change a matrix halfway
    // through a multiply
    input_buffer #(.N(N), .DATA_W(DATA_W), .IS_B(0), .ADDR_W(ADDR_W), .CNT_W(CNT_W)) u_buf_a (
        .clk(clk), .rst(rst),
        .we(wr_en & ~wr_sel & ~busy), .waddr(wr_addr), .wdata(wr_data),
        .feed_en(feed_en), .t(t), .lanes(a_left)
    );

    input_buffer #(.N(N), .DATA_W(DATA_W), .IS_B(1), .ADDR_W(ADDR_W), .CNT_W(CNT_W)) u_buf_b (
        .clk(clk), .rst(rst),
        .we(wr_en & wr_sel & ~busy), .waddr(wr_addr), .wdata(wr_data),
        .feed_en(feed_en), .t(t), .lanes(b_top)
    );

    systolic_array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_array (
        .clk(clk), .rst(rst), .en(arr_en), .clr(arr_clr),
        .a_left(a_left), .b_top(b_top), .c_flat(c_flat)
    );

    output_buffer #(.N(N), .ACC_W(ACC_W), .ADDR_W(ADDR_W)) u_obuf (
        .clk(clk), .rst(rst), .capture(capture), .c_flat(c_flat),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );
endmodule
