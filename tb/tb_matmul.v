// tb_matmul.v
// The main testbench: runs full matrix multiplies and checks every answer.
//
// The test matrices and the correct answers come from model/gen_vectors.py,
// which uses NumPy, so we're checking against something independent of our
// own Verilog.
//
// For each test we:
//   1. write A and B in, one element per clock (like a real host would)
//   2. pulse start and count clock cycles until done
//   3. read back all of C and compare each element with the expected value
//
// The same file tests the baseline too: compile with -DSEQ and it swaps in
// seq_matmul instead of systolic_top. Example:
//   iverilog -g2012 -P tb_matmul.N=4 -P tb_matmul.NUM_TESTS=14 ...
`timescale 1ns/1ps
module tb_matmul;
    parameter N         = 4;
    parameter NUM_TESTS = 14;
    parameter DATA_W    = 8;
    parameter ACC_W     = 20;
    parameter VERBOSE   = 1;
    localparam ADDR_W   = (N*N <= 2) ? 1 : $clog2(N*N);
    localparam NN       = N*N;

    reg                     clk = 0, rst = 1;
    reg                     wr_en = 0, wr_sel = 0, start = 0;
    reg  [ADDR_W-1:0]       wr_addr = 0, rd_addr = 0;
    reg  [DATA_W-1:0]       wr_data = 0;
    wire                    busy, done;
    wire signed [ACC_W-1:0] rd_data;

`ifdef SEQ
    seq_matmul   #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
`else
    systolic_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
`endif
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr),
        .wr_data(wr_data), .start(start), .busy(busy), .done(done),
        .rd_addr(rd_addr), .rd_data(rd_data));

    always #5 clk = ~clk;   // 100 MHz simulation clock

    // all the test data, loaded from the hex files.
    // ab_mem layout per test: N*N values of A, then N*N values of B
    reg [DATA_W-1:0] ab_mem [0:NUM_TESTS*2*NN-1];
    reg [ACC_W-1:0]  c_mem  [0:NUM_TESTS*NN-1];

    integer tst, e, r, c, errors, total_err, cycles, load_cycles, read_cycles;
    integer total_cycles;
    reg signed [ACC_W-1:0] expv;
    reg [8*64-1:0] vecdir;

    initial begin
        if (!$value$plusargs("VEC=%s", vecdir)) vecdir = "sim/vectors";
        $readmemh($sformatf("%0s/N%0d_ab.hex", vecdir, N), ab_mem);
        $readmemh($sformatf("%0s/N%0d_c.hex",  vecdir, N), c_mem);
`ifdef SEQ
        $dumpfile($sformatf("sim/waves/tb_seq_N%0d.vcd", N));
`else
        $dumpfile($sformatf("sim/waves/tb_systolic_N%0d.vcd", N));
`endif
        $dumpvars(0, tb_matmul);

`ifdef SEQ
        $display("=== Sequential baseline (1 MAC), N=%0d, %0d tests ===", N, NUM_TESTS);
`else
        $display("=== Systolic array %0dx%0d, %0d tests ===", N, N, NUM_TESTS);
`endif
        total_err = 0; total_cycles = 0;
        repeat (2) @(posedge clk);
        #1 rst = 0;

        for (tst = 0; tst < NUM_TESTS; tst = tst + 1) begin
            // --- step 1: write A then B (first NN writes are A, next NN are B) ---
            load_cycles = 0;
            for (e = 0; e < 2*NN; e = e + 1) begin
                wr_en = 1; wr_sel = (e >= NN); wr_addr = e % NN;
                wr_data = ab_mem[tst*2*NN + e];
                @(posedge clk); #1; load_cycles = load_cycles + 1;
            end
            wr_en = 0;

            // --- step 2: kick it off and count cycles until done ---
            start = 1; @(posedge clk); #1; start = 0;
            cycles = 1;
            while (!done) begin @(posedge clk); #1; cycles = cycles + 1; end
            total_cycles = total_cycles + cycles;

            // --- step 3: read every C element and compare ---
            errors = 0; read_cycles = 0;
            for (e = 0; e < NN; e = e + 1) begin
                rd_addr = e; #1;
                expv = c_mem[tst*NN + e];
                if (rd_data !== expv) begin
                    errors = errors + 1;
                    $display("  MISMATCH test %0d C[%0d][%0d] = %0d, expected %0d",
                             tst, e / N, e % N, rd_data, expv);
                end
                @(posedge clk); #1; read_cycles = read_cycles + 1;
            end
            total_err = total_err + errors;
            $display("  test %2d : start->done = %3d cycles | load %0d | read %0d | %s",
                     tst, cycles, load_cycles, read_cycles, errors ? "FAIL" : "PASS");

            // test 7 is the fixed-point one, so print it as real numbers.
            // results are Q12.8, so divide by 256 to get the actual value
            if (VERBOSE && tst == 7) begin
                $display("  -- result matrix of test %0d (Q4.4 x Q4.4 -> Q12.8) --", tst);
                for (r = 0; r < N; r = r + 1) begin
                    $write("   ");
                    for (c = 0; c < N; c = c + 1) begin
                        rd_addr = r*N + c; #1;
                        $write(" %8.4f", $itor(rd_data) / 256.0);
                    end
                    $write("\n");
                end
            end
        end

        $display("SUMMARY N=%0d tests=%0d errors=%0d compute_cycles_per_matmul=%0d -> %s",
                 N, NUM_TESTS, total_err, total_cycles / NUM_TESTS,
                 total_err ? "FAILED" : "ALL PASSED");
        $finish;
    end

    // safety net: if something hangs (say done never comes), stop anyway
    initial begin
        #2000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
