// tb_pe.v
// Tests a single PE. Two things matter here:
//   - does it pass a and b along with exactly 1 cycle of delay?
//   - does it add up the products correctly?
// If both hold, chaining 16 of them into a grid should just work.
//
// Phase II: also run with -P tb_pe.PIPE=1 for the pipelined PE. tick() adds
// one extra clock with en=0 so the delayed acc catches up; a_out/b_out are
// frozen during that clock, so every check expects the same numbers.
`timescale 1ns/1ps
module tb_pe;
    parameter  PIPE = 0;
    localparam DATA_W = 8, ACC_W = 20;
    reg clk = 0, rst = 1, en = 0, clr = 0;
    reg  signed [DATA_W-1:0] a_in = 0, b_in = 0;
    wire signed [DATA_W-1:0] a_out, b_out;
    wire signed [ACC_W-1:0]  acc;
    integer errors = 0, checks = 0, n;
    reg signed [ACC_W-1:0] model;
    reg en_save;

    pe #(.DATA_W(DATA_W), .ACC_W(ACC_W), .PIPE(PIPE)) dut (
        .clk(clk), .rst(rst), .en(en), .clr(clr),
        .a_in(a_in), .b_in(b_in), .a_out(a_out), .b_out(b_out), .acc(acc));

    always #5 clk = ~clk;

    // one clock step (plus a catch-up clock for the pipelined version)
    task tick;
        begin
            @(posedge clk); #1;
            if (PIPE) begin
                en_save = en; en = 0;
                @(posedge clk); #1;
                en = en_save;
            end
        end
    endtask

    task expect3(input signed [DATA_W-1:0] ea, input signed [DATA_W-1:0] eb,
                 input signed [ACC_W-1:0] ec, input [8*36-1:0] msg);
        begin
            checks = checks + 1;
            if (a_out !== ea || b_out !== eb || acc !== ec) begin
                errors = errors + 1;
                $display("  FAIL %-36s a_out=%0d b_out=%0d acc=%0d (exp %0d %0d %0d)",
                         msg, a_out, b_out, acc, ea, eb, ec);
            end else
                $display("  PASS %-36s a_out=%0d b_out=%0d acc=%0d", msg, a_out, b_out, acc);
        end
    endtask

    initial begin
        $dumpfile(PIPE ? "sim/waves/tb_pe_pipe.vcd" : "sim/waves/tb_pe.vcd");
        $dumpvars(0, tb_pe);
        $display("=== Processing Element directed tests (PIPE=%0d) ===", PIPE);
        @(posedge clk); #1 rst = 0;
        expect3(0, 0, 0, "after reset");

        // 1) whatever goes in should come out one clock later, and get multiplied
        en = 1; a_in = 2; b_in = 3; tick;
        expect3(2, 3, 6, "forward + MAC (2*3)");
        a_in = -4; b_in = 5;        tick;
        expect3(-4, 5, -14, "forward + MAC (-4*5)");

        // 2) with en=0 everything should freeze, even though the inputs change
        en = 0; a_in = 9; b_in = 9; tick;
        expect3(-4, 5, -14, "stall (en=0)");

        // 3) clr should zero everything
        clr = 1;                    tick; clr = 0;
        expect3(0, 0, 0, "clear");

        // 4) feed in a little dot product: 1*5 + 2*6 + 3*7 + 4*8 = 70
        en = 1; model = 0;
        for (n = 1; n <= 4; n = n + 1) begin
            a_in = n; b_in = n + 4; model = model + n*(n+4);
            tick;
        end
        expect3(4, 8, 70, "4-term dot product = 70");

        // 5) the array feeds zeros when there's no data, so make sure they don't change the sum
        a_in = 0; b_in = 0; repeat (3) tick;
        expect3(0, 0, 70, "zero bubbles keep acc");

        $display("PE PIPE=%0d: %0d checks, %0d errors -> %s", PIPE, checks, errors,
                 errors ? "FAILED" : "ALL PASSED");
        $finish;
    end
endmodule
