// systolic_array.v
// Wires up an N x N grid of PEs.
//
// Row i of matrix A comes in on the left side of row i and walks to the right.
// Column j of matrix B comes in on top of column j and walks down.
// So PE(i,j) sees every a[i][k] and every b[k][j] go past, and ends up holding
// C[i][j] = sum over k of a[i][k] * b[k][j]. That's exactly matrix multiply.
//
// Verilog-2001 doesn't let us use 2D ports nicely, so everything is packed
// into long flat buses. How to find things in them:
//   a_left [i*DATA_W +: DATA_W]        -> the A value going into row i
//   b_top  [j*DATA_W +: DATA_W]        -> the B value going into column j
//   c_flat [(i*N+j)*ACC_W +: ACC_W]    -> the result sitting in PE(i,j)
`timescale 1ns/1ps
module systolic_array #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 20
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    en,
    input  wire                    clr,
    input  wire [N*DATA_W-1:0]     a_left,
    input  wire [N*DATA_W-1:0]     b_top,
    output wire [N*N*ACC_W-1:0]    c_flat
);
    // The wires between PEs.
    // a_h: horizontal links. Each row has N+1 of them (left edge, N-1 in
    //      between, and one hanging off the right end that we don't use).
    //      a_h[i*(N+1)+j] is what goes into PE(i,j).
    // b_v: vertical links, same idea. b_v[i*N+j] goes into PE(i,j), and the
    //      extra bottom row is just the unused output of the last PEs.
    wire [N*(N+1)*DATA_W-1:0] a_h;
    wire [(N+1)*N*DATA_W-1:0] b_v;

    genvar i, j;
    generate
        // hook the left edge up to the A inputs
        for (i = 0; i < N; i = i + 1) begin : g_left
            assign a_h[(i*(N+1))*DATA_W +: DATA_W] = a_left[i*DATA_W +: DATA_W];
        end
        // hook the top edge up to the B inputs
        for (j = 0; j < N; j = j + 1) begin : g_top
            assign b_v[j*DATA_W +: DATA_W] = b_top[j*DATA_W +: DATA_W];
        end

        // and now the grid itself. Each PE reads from the link before it and
        // drives the link after it, which chains them all together
        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk  (clk),
                    .rst  (rst),
                    .en   (en),
                    .clr  (clr),
                    .a_in (a_h[(i*(N+1)+j)  *DATA_W +: DATA_W]),
                    .b_in (b_v[(i*N+j)      *DATA_W +: DATA_W]),
                    .a_out(a_h[(i*(N+1)+j+1)*DATA_W +: DATA_W]),
                    .b_out(b_v[((i+1)*N+j)  *DATA_W +: DATA_W]),
                    .acc  (c_flat[(i*N+j)*ACC_W +: ACC_W])
                );
            end
        end
    endgenerate
endmodule
