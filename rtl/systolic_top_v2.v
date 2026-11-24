// systolic_top_v2.v
// Phase II top level. Computes C = A x B (or C += A x B in acc_mode) for
// N x N matrices, using the same systolic array as v1 but with:
//   - pipelined MACs (PIPE = 1) for a faster clock
//   - row-wide, double-banked input buffers (load a row per clock, and load
//     the next job while this one runs)
//   - a row-wide result read port
//   - acc_mode, used by tiled_matmul to add partial products together
//
// How the host uses it:
//   1. Write rows: wr_en=1, wr_sel (0=A, 1=B), wr_bank, wr_row, wr_data_row
//      (element c of the row at wr_data_row[c*8 +: 8]). 2N clocks per job.
//   2. Pulse start with start_bank = the bank you filled, acc_mode = 0
//      (or 1 to add onto the previous result).
//   3. While busy, you can already fill the OTHER bank for the next job.
//      Writes to the bank currently being computed on are ignored.
//   4. When done pulses, read C a row at a time (rd_row -> rd_data_row), or
//      element-wise with rd_addr -> rd_data.
//
// Inside:
//   systolic_top_v2
//    |- systolic_controller_v2  u_ctrl
//    |- input_buffer_v2         u_buf_a, u_buf_b
//    |- systolic_array          u_array (PIPE passed down to every PE)
//    '- output_buffer_v2        u_obuf
`timescale 1ns/1ps
module systolic_top_v2 #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter PIPE   = 1,
    parameter ROW_W  = (N <= 2) ? 1 : $clog2(N),
    parameter ADDR_W = (N*N <= 2) ? 1 : $clog2(N*N),
    parameter CNT_W  = $clog2(3*N + 1) + 1
)(
    input  wire                     clk,
    input  wire                     rst,
    // row write port
    input  wire                     wr_en,
    input  wire                     wr_sel,       // 0 = A, 1 = B
    input  wire                     wr_bank,
    input  wire [ROW_W-1:0]         wr_row,
    input  wire [N*DATA_W-1:0]      wr_data_row,
    // control
    input  wire                     start,
    input  wire                     start_bank,
    input  wire                     acc_mode,
    output wire                     busy,
    output wire                     done,
    // result read ports
    input  wire [ROW_W-1:0]         rd_row,
    output wire [N*ACC_W-1:0]       rd_data_row,
    input  wire [ADDR_W-1:0]        rd_addr,
    output wire signed [ACC_W-1:0]  rd_data
);
    wire             arr_clr, arr_en, feed_en, capture, rbank;
    wire [CNT_W-1:0] t;
    wire [2:0]       state;
    wire [N*DATA_W-1:0]  a_left, b_top;
    wire [N*N*ACC_W-1:0] c_flat;

    systolic_controller_v2 #(.N(N), .CNT_W(CNT_W), .PIPE(PIPE)) u_ctrl (
        .clk(clk), .rst(rst), .start(start), .start_bank(start_bank), .acc_mode(acc_mode),
        .arr_clr(arr_clr), .arr_en(arr_en), .feed_en(feed_en), .t(t), .rbank(rbank),
        .capture(capture), .busy(busy), .done(done), .state(state)
    );

    // a write is blocked only if it targets the bank the array is reading
    wire wr_ok = wr_en & ~(busy & (wr_bank == rbank));

    input_buffer_v2 #(.N(N), .DATA_W(DATA_W), .IS_B(0), .ROW_W(ROW_W), .CNT_W(CNT_W)) u_buf_a (
        .clk(clk), .rst(rst),
        .we(wr_ok & ~wr_sel), .wbank(wr_bank), .wrow(wr_row), .wdata(wr_data_row),
        .rbank(rbank), .feed_en(feed_en), .t(t), .lanes(a_left)
    );

    input_buffer_v2 #(.N(N), .DATA_W(DATA_W), .IS_B(1), .ROW_W(ROW_W), .CNT_W(CNT_W)) u_buf_b (
        .clk(clk), .rst(rst),
        .we(wr_ok & wr_sel), .wbank(wr_bank), .wrow(wr_row), .wdata(wr_data_row),
        .rbank(rbank), .feed_en(feed_en), .t(t), .lanes(b_top)
    );

    systolic_array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .PIPE(PIPE)) u_array (
        .clk(clk), .rst(rst), .en(arr_en), .clr(arr_clr),
        .a_left(a_left), .b_top(b_top), .c_flat(c_flat)
    );

    output_buffer_v2 #(.N(N), .ACC_W(ACC_W), .ROW_W(ROW_W), .ADDR_W(ADDR_W)) u_obuf (
        .clk(clk), .rst(rst), .capture(capture), .c_flat(c_flat),
        .rd_row(rd_row), .rd_data_row(rd_data_row),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );
endmodule
