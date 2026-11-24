// tiled_matmul.v
// Multiplies big M x M matrices on our small N x N systolic array by cutting
// them into N x N tiles (blocks). With M = 8 and N = 4 there are 2 x 2 tiles.
//
// The math: split A, B and C into tiles. Then each output tile is
//     C[I][J] = A[I][0]*B[0][J] + A[I][1]*B[1][J] + ... + A[I][T-1]*B[T-1][J]
// where T = M/N. Each term is exactly one N x N multiply, which the array
// already does. The first term runs normally, and every later term runs in
// acc_mode, so the PEs keep adding onto the running total. After the last
// term we copy the finished tile out into the big C memory.
//
// The trick that keeps it fast: double buffering. While the array computes
// one term from bank 0, the loader is already copying the NEXT pair of tiles
// into bank 1. Loading (2N cycles) is shorter than computing (3N+3 cycles),
// so it's completely hidden.
//
// Host side looks like v1 (one element at a time):
//   write A and B (wr_sel 0/1, wr_addr = row*M + col), pulse start,
//   wait for done, read C with rd_addr.
//
// This trades time for area: the 8x8 multiply uses 16 multipliers instead
// of 64, at the cost of more cycles.
`timescale 1ns/1ps
module tiled_matmul #(
    parameter M      = 8,      // big matrix size
    parameter N      = 4,      // array size (M must be a multiple of N)
    parameter DATA_W = 8,
    parameter ACC_W  = 20,
    parameter PIPE   = 1,
    parameter AW     = $clog2(M*M),
    parameter ROW_W  = (N <= 2) ? 1 : $clog2(N)
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     wr_en,
    input  wire                     wr_sel,     // 0 = A, 1 = B
    input  wire [AW-1:0]            wr_addr,    // row*M + col
    input  wire [DATA_W-1:0]        wr_data,
    input  wire                     start,
    output wire                     busy,
    output reg                      done,
    input  wire [AW-1:0]            rd_addr,
    output wire signed [ACC_W-1:0]  rd_data
);
    localparam T = M / N;   // tiles per side

    // the big matrices
    reg [DATA_W-1:0] mem_a [0:M*M-1];
    reg [DATA_W-1:0] mem_b [0:M*M-1];
    reg [ACC_W-1:0]  mem_c [0:M*M-1];

    localparam [2:0] S_IDLE = 3'd0, S_PRELOAD = 3'd1, S_START = 3'd2, S_RUN = 3'd3,
                     S_WAITLD = 3'd4, S_READC = 3'd5, S_DONE = 3'd6;
    reg [2:0] state;
    assign busy = (state != S_IDLE);

    // which output tile (ti, tj) and which term tk we're on, and which bank
    // the array is using right now
    reg [7:0] ti, tj, tk;
    reg       bank;
    reg [7:0] rc;            // row counter while copying C out

    // ---- the loader: copies one A tile and one B tile into a bank ----
    // runs for 2N clocks: rows 0..N-1 of the A tile, then rows 0..N-1 of B
    reg       ld_active, ld_bank;
    reg [7:0] ld_cnt, ld_i, ld_j, ld_k;

    // ---- the core ----
    wire                core_busy, core_done;
    wire [N*ACC_W-1:0]  core_row;
    reg  [N*DATA_W-1:0] ld_row;
    wire [ROW_W-1:0]    ld_r = ld_cnt % N;

    // build the row the loader is writing this clock
    integer c;
    always @(*) begin
        for (c = 0; c < N; c = c + 1) begin
            if (ld_cnt < N)   // A tile (ld_i, ld_k): A[ld_i*N + r][ld_k*N + c]
                ld_row[c*DATA_W +: DATA_W] = mem_a[(ld_i*N + ld_r)*M + ld_k*N + c];
            else              // B tile (ld_k, ld_j): B[ld_k*N + r][ld_j*N + c]
                ld_row[c*DATA_W +: DATA_W] = mem_b[(ld_k*N + ld_r)*M + ld_j*N + c];
        end
    end

    systolic_top_v2 #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .PIPE(PIPE)) u_core (
        .clk(clk), .rst(rst),
        .wr_en(ld_active), .wr_sel(ld_cnt >= N), .wr_bank(ld_bank),
        .wr_row(ld_r), .wr_data_row(ld_row),
        .start(state == S_START), .start_bank(bank), .acc_mode(tk != 0),
        .busy(core_busy), .done(core_done),
        .rd_row(rc[ROW_W-1:0]), .rd_data_row(core_row),
        .rd_addr({(2*ROW_W){1'b0}}), .rd_data()
    );

    // what comes after the current (ti, tj, tk)?
    reg       has_next;
    reg [7:0] ni, nj, nk;
    always @(*) begin
        has_next = 1'b1; ni = ti; nj = tj; nk = 0;
        if (tk < T-1)      nk = tk + 1;                 // next term, same tile
        else if (tj < T-1) nj = tj + 1;                 // next tile in this row
        else if (ti < T-1) begin ni = ti + 1; nj = 0; end  // next row of tiles
        else               has_next = 1'b0;             // that was the last one
    end

    integer k;
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; done <= 1'b0;
            ti <= 0; tj <= 0; tk <= 0; bank <= 0; rc <= 0;
            ld_active <= 0; ld_cnt <= 0; ld_bank <= 0; ld_i <= 0; ld_j <= 0; ld_k <= 0;
        end else begin
            done <= 1'b0;

            // host writes (only while we're idle)
            if (wr_en && state == S_IDLE) begin
                if (wr_sel) mem_b[wr_addr] <= wr_data;
                else        mem_a[wr_addr] <= wr_data;
            end

            // loader runs on its own once kicked off
            if (ld_active) begin
                if (ld_cnt == 2*N-1) ld_active <= 1'b0;
                else                 ld_cnt    <= ld_cnt + 1;
            end

            case (state)
                S_IDLE: if (start) begin
                    ti <= 0; tj <= 0; tk <= 0; bank <= 0;
                    // load the very first tile pair into bank 0
                    ld_active <= 1'b1; ld_cnt <= 0; ld_bank <= 0;
                    ld_i <= 0; ld_j <= 0; ld_k <= 0;
                    state <= S_PRELOAD;
                end
                S_PRELOAD: if (!ld_active) state <= S_START;
                S_START: begin
                    // the core starts this clock; at the same time, start
                    // loading the next tile pair into the other bank
                    if (has_next) begin
                        ld_active <= 1'b1; ld_cnt <= 0; ld_bank <= !bank;
                        ld_i <= ni; ld_j <= nj; ld_k <= nk;
                    end
                    state <= S_RUN;
                end
                S_RUN: if (core_done) begin
                    if (tk == T-1) begin
                        rc <= 0;
                        state <= S_READC;        // tile finished, copy it out
                    end else begin
                        tk <= tk + 1; bank <= !bank;
                        state <= S_WAITLD;       // next term
                    end
                end
                S_WAITLD: if (!ld_active) state <= S_START;
                S_READC: begin
                    // copy row rc of the finished tile into the big C memory
                    for (k = 0; k < N; k = k + 1)
                        mem_c[(ti*N + rc)*M + tj*N + k] <= core_row[k*ACC_W +: ACC_W];
                    if (rc == N-1) begin
                        if (has_next) begin
                            ti <= ni; tj <= nj; tk <= 0; bank <= !bank;
                            state <= S_WAITLD;
                        end else
                            state <= S_DONE;
                    end else
                        rc <= rc + 1;
                end
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    assign rd_data = mem_c[rd_addr];
endmodule
