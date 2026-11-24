// tb_matmul_v2.v
// Tests systolic_top_v2 (the Phase II design) three ways:
//
//   1. single:    load one job (row by row), run it, read it back, check it.
//                 Measures latency and end-to-end time for one job on its own.
//   2. streaming: what you'd actually do in a real system. While job k runs,
//                 we load job k+1 into the other bank AND read job k-1's
//                 results out, all at the same time. Measures how many cycles
//                 each job really costs once everything overlaps.
//   3. acc_mode:  run a job, then run the same job again in acc_mode. The
//                 answer should be exactly 2 x C. (Tiling depends on this.)
//
// Vectors come from model/gen_vectors.py. +SET=_stress picks the big random set:
//   vvp sim.vvp +SET=_stress
`timescale 1ns/1ps
module tb_matmul_v2;
    parameter N         = 4;
    parameter NUM_TESTS = 14;
    parameter PIPE      = 1;
    localparam W = 8, ACC_W = 20, NN = N*N;
    localparam ROW_W  = (N <= 2) ? 1 : $clog2(N);
    localparam ADDR_W = (N*N <= 2) ? 1 : $clog2(N*N);

    reg clk = 0, rst = 1;
    reg wr_en = 0, wr_sel = 0, wr_bank = 0, start = 0, start_bank = 0, acc_mode = 0;
    reg  [ROW_W-1:0]  wr_row = 0, rd_row = 0;
    reg  [N*W-1:0]    wr_data_row = 0;
    reg  [ADDR_W-1:0] rd_addr = 0;
    wire busy, done;
    wire [N*ACC_W-1:0] rd_data_row;
    wire signed [ACC_W-1:0] rd_data;

    systolic_top_v2 #(.N(N), .PIPE(PIPE)) dut (
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_sel(wr_sel), .wr_bank(wr_bank),
        .wr_row(wr_row), .wr_data_row(wr_data_row),
        .start(start), .start_bank(start_bank), .acc_mode(acc_mode), .busy(busy), .done(done),
        .rd_row(rd_row), .rd_data_row(rd_data_row), .rd_addr(rd_addr), .rd_data(rd_data));

    always #5 clk = ~clk;

    reg [W-1:0]     ab_mem [0:NUM_TESTS*2*NN-1];
    reg [ACC_W-1:0] c_mem  [0:NUM_TESTS*NN-1];

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    integer errors = 0, checked = 0;
    integer tst, r, c, t0, t_lat, t_e2e, t_first, t_last;
    reg [8*16-1:0] set;
    reg [8*64-1:0] vecdir;

    // load test 'tn' into bank 'bk': N rows of A, then N rows of B (2N clocks)
    task load_job(input integer tn, input integer bk);
        integer rr, cc;
        begin
            for (rr = 0; rr < 2*N; rr = rr + 1) begin
                wr_en = 1; wr_bank = bk; wr_sel = (rr >= N); wr_row = rr % N;
                for (cc = 0; cc < N; cc = cc + 1)
                    wr_data_row[cc*W +: W] = ab_mem[tn*2*NN + (rr >= N ? NN : 0) + (rr % N)*N + cc];
                @(posedge clk); #1;
            end
            wr_en = 0;
        end
    endtask

    // read all N rows of C (N clocks) and compare with test 'tn' (times 'mult')
    task read_check(input integer tn, input integer mult);
        integer rr, cc;
        reg signed [ACC_W-1:0] got, want;
        begin
            for (rr = 0; rr < N; rr = rr + 1) begin
                rd_row = rr; #1;
                for (cc = 0; cc < N; cc = cc + 1) begin
                    got  = rd_data_row[cc*ACC_W +: ACC_W];
                    want = $signed(c_mem[tn*NN + rr*N + cc]) * mult;
                    checked = checked + 1;
                    if (got !== want) begin
                        errors = errors + 1;
                        $display("  MISMATCH test %0d C[%0d][%0d] = %0d, expected %0d", tn, rr, cc, got, want);
                    end
                end
                @(posedge clk); #1;
            end
        end
    endtask

    task pulse_start(input integer bk, input integer am);
        begin
            start = 1; start_bank = bk; acc_mode = am;
            @(posedge clk); #1;
            start = 0; acc_mode = 0;
        end
    endtask

    task wait_done;
        begin
            while (!done) begin @(posedge clk); #1; end
        end
    endtask

    initial begin
        if (!$value$plusargs("SET=%s", set)) set = "";
        if (!$value$plusargs("VEC=%s", vecdir)) vecdir = "sim/vectors";
        $readmemh($sformatf("%0s/N%0d%0s_ab.hex", vecdir, N, set), ab_mem);
        $readmemh($sformatf("%0s/N%0d%0s_c.hex",  vecdir, N, set), c_mem);
        $dumpfile($sformatf("sim/waves/tb_matmul_v2_N%0d%0s.vcd", N, set));
        $dumpvars(1, tb_matmul_v2);
        $display("=== systolic_top_v2 %0dx%0d, PIPE=%0d, %0d tests %0s ===", N, N, PIPE, NUM_TESTS, set);
        repeat (2) @(posedge clk);
        #1 rst = 0;

        // ---------- 1. one job at a time ----------
        for (tst = 0; tst < NUM_TESTS; tst = tst + 1) begin
            t0 = cyc;
            load_job(tst, tst % 2);
            pulse_start(tst % 2, 0);
            t_lat = cyc;
            wait_done;
            t_lat = cyc - t_lat + 1;      // +1: count the start cycle, same as v1 bench
            read_check(tst, 1);
            t_e2e = cyc - t0;
        end
        $display("  single: start->done latency = %0d cycles, load+run+read = %0d cycles per job", t_lat, t_e2e);

        // ---------- 2. streaming: load next + read previous while running ----------
        load_job(0, 0);
        t_first = cyc;
        for (tst = 0; tst < NUM_TESTS; tst = tst + 1) begin
            pulse_start(tst % 2, 0);
            fork
                if (tst + 1 < NUM_TESTS) load_job(tst + 1, (tst + 1) % 2);
                if (tst > 0)             read_check(tst - 1, 1);
            join
            wait_done;
            @(posedge clk); #1;           // core is back in IDLE
        end
        read_check(NUM_TESTS - 1, 1);
        t_last = cyc;
        $display("  streaming: %0d jobs in %0d cycles = %0d cycles per job (steady state)",
                 NUM_TESTS, t_last - t_first, (t_last - t_first) / NUM_TESTS);

        // ---------- 3. accumulate mode: C + C = 2C ----------
        for (tst = 0; tst < NUM_TESTS; tst = tst + 1) begin
            load_job(tst, 0);
            pulse_start(0, 0); wait_done; @(posedge clk); #1;
            pulse_start(0, 1); wait_done;     // same inputs again, but keep adding
            read_check(tst, 2);
        end
        $display("  acc_mode: every test gave exactly 2 x C");

        $display("SUMMARY v2 N=%0d PIPE=%0d set=%0s checked=%0d errors=%0d latency=%0d e2e=%0d stream=%0d -> %s",
                 N, PIPE, set, checked, errors, t_lat, t_e2e, (t_last - t_first) / NUM_TESTS,
                 errors ? "FAILED" : "ALL PASSED");
        $finish;
    end

    initial begin #50000000; $display("TIMEOUT"); $finish; end
endmodule
