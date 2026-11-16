// seq_matmul.v
// The "normal" way to multiply matrices, used as our baseline for comparison.
//
// There's only ONE multiply-accumulate unit here, and it grinds through the
// three nested loops one MAC at a time:
//     for i, for j, for k:  C[i][j] += A[i][k] * B[k][j]
// That's N^3 cycles of work (64 for a 4x4), against about 3N for the systolic
// array.
//
// The ports are exactly the same as systolic_top, so the same testbench and
// the same test vectors work for both designs. That keeps the comparison fair.
//
// Small trick to save cycles: when we start a new C[i][j] (k == 0), the MAC
// loads the product instead of adding, and in that same cycle we save the
// previous answer to memory. So there's no extra "clear" cycle between dot
// products, just one flush cycle at the very end.
`timescale 1ns/1ps
module seq_matmul #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter ADDR_W = (N*N <= 2) ? 1 : $clog2(N*N),
    parameter IDX_W  = (N <= 2) ? 1 : $clog2(N)
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     wr_en,
    input  wire                     wr_sel,
    input  wire [ADDR_W-1:0]        wr_addr,
    input  wire [DATA_W-1:0]        wr_data,
    input  wire                     start,
    output wire                     busy,
    output reg                      done,
    input  wire [ADDR_W-1:0]        rd_addr,
    output wire signed [ACC_W-1:0]  rd_data
);
    reg [DATA_W-1:0] mem_a [0:N*N-1];
    reg [DATA_W-1:0] mem_b [0:N*N-1];
    reg [ACC_W-1:0]  mem_c [0:N*N-1];

    localparam [1:0] S_IDLE = 2'd0, S_RUN = 2'd1, S_FLUSH = 2'd2, S_DONE = 2'd3;
    reg [1:0] state;
    reg [IDX_W-1:0] i, j, k;          // the three loop counters
    reg [ADDR_W-1:0] prev_idx;        // where the last finished C element goes
    reg              have_prev;       // false for the very first dot product

    assign busy = (state == S_RUN) || (state == S_FLUSH);

    // host writes A and B (ignored while we're running)
    always @(posedge clk) begin
        if (wr_en && !busy) begin
            if (wr_sel) mem_b[wr_addr] <= wr_data;
            else        mem_a[wr_addr] <= wr_data;
        end
    end

    // the single MAC, fed with A[i][k] and B[k][j]
    wire signed [ACC_W-1:0] acc;
    mac_unit #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_mac (
        .clk (clk),
        .rst (rst),
        .en  (state == S_RUN),
        .clr (1'b0),
        .load(k == 0),            // start of a new dot product
        .a   (mem_a[i*N + k]),
        .b   (mem_b[k*N + j]),
        .acc (acc)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; i <= 0; j <= 0; k <= 0;
            have_prev <= 1'b0; prev_idx <= 0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    state <= S_RUN; i <= 0; j <= 0; k <= 0; have_prev <= 1'b0;
                end
                S_RUN: begin
                    // acc still holds the last finished sum during this cycle,
                    // so save it now while the MAC starts on the next one
                    if (k == 0 && have_prev) mem_c[prev_idx] <= acc;
                    // step k, then j, then i (like an odometer)
                    if (k == N-1) begin
                        prev_idx  <= i*N + j;
                        have_prev <= 1'b1;
                        k <= 0;
                        if (j == N-1) begin
                            j <= 0;
                            if (i == N-1) state <= S_FLUSH;
                            else          i <= i + 1'b1;
                        end else j <= j + 1'b1;
                    end else k <= k + 1'b1;
                end
                S_FLUSH: begin
                    // save the very last result, nothing comes after it
                    mem_c[prev_idx] <= acc;
                    state <= S_DONE;
                end
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    assign rd_data = mem_c[rd_addr];
endmodule
