// tb_tiled.v
// Tests tiled_matmul: big M x M matrices multiplied on the 4x4 array, tile by
// tile. Uses the same test vectors as the plain N=M tests (for M=8 that's
// the N8 files), so the expected answers come from the Python model.
//
//   iverilog ... -P tb_tiled.M=8     (2x2 tiles, 8 small multiplies per job)
//   iverilog ... -P tb_tiled.M=12    (3x3 tiles, 27 small multiplies per job)
`timescale 1ns/1ps
module tb_tiled;
    parameter M         = 8;
    parameter N         = 4;
    parameter NUM_TESTS = 14;
    localparam W = 8, ACC_W = 20, MM = M*M, AW = $clog2(M*M);

    reg clk = 0, rst = 1, wr_en = 0, wr_sel = 0, start = 0;
    reg  [AW-1:0] wr_addr = 0, rd_addr = 0;
    reg  [W-1:0]  wr_data = 0;
    wire busy, done;
    wire signed [ACC_W-1:0] rd_data;

    tiled_matmul #(.M(M), .N(N)) dut (
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr),
        .wr_data(wr_data), .start(start), .busy(busy), .done(done),
        .rd_addr(rd_addr), .rd_data(rd_data));

    always #5 clk = ~clk;

    reg [W-1:0]     ab_mem [0:NUM_TESTS*2*MM-1];
    reg [ACC_W-1:0] c_mem  [0:NUM_TESTS*MM-1];

    integer tst, e, cycles, errors = 0, checked = 0;
    reg signed [ACC_W-1:0] want;

    initial begin
        $readmemh($sformatf("sim/vectors/N%0d_ab.hex", M), ab_mem);
        $readmemh($sformatf("sim/vectors/N%0d_c.hex",  M), c_mem);
        $dumpfile($sformatf("sim/waves/tb_tiled_M%0d.vcd", M));
        $dumpvars(1, tb_tiled);
        $display("=== tiled_matmul: %0dx%0d matrices on a %0dx%0d array (%0d tiles per side) ===",
                 M, M, N, N, M/N);
        repeat (2) @(posedge clk);
        #1 rst = 0;

        for (tst = 0; tst < NUM_TESTS; tst = tst + 1) begin
            // load the big A and B one element at a time
            for (e = 0; e < 2*MM; e = e + 1) begin
                wr_en = 1; wr_sel = (e >= MM); wr_addr = e % MM;
                wr_data = ab_mem[tst*2*MM + e];
                @(posedge clk); #1;
            end
            wr_en = 0;

            start = 1; @(posedge clk); #1; start = 0;
            cycles = 1;
            while (!done) begin @(posedge clk); #1; cycles = cycles + 1; end

            for (e = 0; e < MM; e = e + 1) begin
                rd_addr = e; #1;
                want = c_mem[tst*MM + e];
                checked = checked + 1;
                if (rd_data !== want) begin
                    errors = errors + 1;
                    $display("  MISMATCH test %0d C[%0d][%0d] = %0d, expected %0d",
                             tst, e / M, e % M, rd_data, want);
                end
            end
            $display("  test %2d : start->done = %4d cycles | %s", tst, cycles,
                     errors ? "FAIL" : "PASS");
        end

        $display("SUMMARY tiled M=%0d N=%0d tests=%0d checked=%0d errors=%0d cycles=%0d -> %s",
                 M, N, NUM_TESTS, checked, errors, cycles, errors ? "FAILED" : "ALL PASSED");
        $finish;
    end

    initial begin #50000000; $display("TIMEOUT"); $finish; end
endmodule
