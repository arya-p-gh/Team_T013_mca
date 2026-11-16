// tb_mac_unit.v
// Tests the MAC unit on its own before we trust it inside the PEs.
// Every step sets the inputs, waits one clock, then checks acc against the
// value we worked out by hand. Any mismatch gets printed as FAIL.
`timescale 1ns/1ps
module tb_mac_unit;
    localparam DATA_W = 8, ACC_W = 20;
    reg clk = 0, rst = 1, en = 0, clr = 0, load = 0;
    reg  signed [DATA_W-1:0] a = 0, b = 0;
    wire signed [ACC_W-1:0]  acc;
    integer errors = 0, checks = 0;

    mac_unit #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst), .en(en), .clr(clr), .load(load), .a(a), .b(b), .acc(acc));

    always #5 clk = ~clk;

    // compare acc with what we expect and print PASS or FAIL
    task check(input signed [ACC_W-1:0] exp, input [8*40-1:0] msg);
        begin
            checks = checks + 1;
            if (acc !== exp) begin
                errors = errors + 1;
                $display("  FAIL %-40s acc=%0d expected=%0d", msg, acc, exp);
            end else
                $display("  PASS %-40s acc=%0d", msg, acc);
        end
    endtask

    // set the inputs, wait one clock edge (+1ns so the outputs settle)
    task step(input e, input c, input l, input signed [DATA_W-1:0] x, input signed [DATA_W-1:0] y);
        begin
            en = e; clr = c; load = l; a = x; b = y;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        $dumpfile("sim/waves/tb_mac_unit.vcd");
        $dumpvars(0, tb_mac_unit);
        $display("=== MAC unit directed tests ===");
        @(posedge clk); #1 rst = 0;
        check(0, "reset value");

        step(1,0,0,  3,  4);  check(12,          "3*4 accumulate from 0");
        step(1,0,0,  5, -2);  check(2,           "+5*-2  -> 12-10");
        step(1,0,0, -7, -7);  check(51,          "-7*-7  -> 2+49");
        step(0,0,0, 99, 99);  check(51,          "en=0 holds value");
        step(1,0,1,  6,  7);  check(42,          "load=1 restarts with 6*7");
        step(1,1,0, 10, 10);  check(0,           "clr has priority");
        step(1,0,0,127,127);  check(16129,       "127*127");
        step(1,0,0,-128,-128);check(16129+16384, "+(-128*-128)");
        step(1,0,0,127,-128); check(32513-16256, "+(127*-128)");
        step(1,0,1,-128,127); check(-16256,      "load most negative product");
        // worst case: add up 16 of the biggest possible products.
        // 16 * 16384 = 262144, still fits in 20 bits signed (max is 524287)
        step(1,1,0,0,0);
        repeat (16) step(1,0,0,-128,-128);
        check(262144, "16 x (-128*-128) no overflow");
        // fixed-point check: 1.5 is 0x18 and -2.25 is 0xDC in Q4.4.
        // 1.5 * -2.25 = -3.375, which is -864 in Q8.8 (-3.375 * 256)
        step(1,0,1, 8'sh18, 8'shDC); check(-864, "Q4.4: 1.5 * -2.25 = -3.375");

        $display("MAC unit: %0d checks, %0d errors -> %s", checks, errors,
                 errors ? "FAILED" : "ALL PASSED");
        $finish;
    end
endmodule
