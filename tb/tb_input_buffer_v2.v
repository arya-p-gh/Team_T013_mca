// tb_input_buffer_v2.v
// Checks the Phase II input buffer on its own:
//   - row writes land in the right bank and row
//   - the skewed output pattern is right for both A-style and B-style lanes
//   - writing into one bank while the other bank is being fed doesn't
//     disturb the data coming out
// Every lane output is compared against what it should be at that step.
`timescale 1ns/1ps
module tb_input_buffer_v2;
    localparam N = 4, W = 8, ROW_W = 2, CNT_W = 5;
    reg clk = 0, rst = 1;
    reg we = 0, wbank = 0, rbank = 0, feed_en = 0;
    reg [ROW_W-1:0] wrow = 0;
    reg [N*W-1:0]   wdata = 0;
    reg [CNT_W-1:0] t = 0;
    wire [N*W-1:0]  lanes_a, lanes_b;
    integer errors = 0, checks = 0, r, c, l, k, step, bank;
    reg [W-1:0] expv;

    // same write data goes to both buffers; one is wired as A, one as B
    input_buffer_v2 #(.N(N), .DATA_W(W), .IS_B(0), .ROW_W(ROW_W), .CNT_W(CNT_W)) dut_a (
        .clk(clk), .rst(rst), .we(we), .wbank(wbank), .wrow(wrow), .wdata(wdata),
        .rbank(rbank), .feed_en(feed_en), .t(t), .lanes(lanes_a));
    input_buffer_v2 #(.N(N), .DATA_W(W), .IS_B(1), .ROW_W(ROW_W), .CNT_W(CNT_W)) dut_b (
        .clk(clk), .rst(rst), .we(we), .wbank(wbank), .wrow(wrow), .wdata(wdata),
        .rbank(rbank), .feed_en(feed_en), .t(t), .lanes(lanes_b));

    always #5 clk = ~clk;

    // the value we store at (bank, row r, col c). Different per bank so a
    // bank mix-up shows up straight away
    function [W-1:0] val(input integer bk, input integer rr, input integer cc);
        val = bk*64 + rr*N + cc + 1;
    endfunction

    task write_bank(input integer bk);
        begin
            for (r = 0; r < N; r = r + 1) begin
                we = 1; wbank = bk; wrow = r;
                for (c = 0; c < N; c = c + 1) wdata[c*W +: W] = val(bk, r, c);
                @(posedge clk); #1;
            end
            we = 0;
        end
    endtask

    // feed one whole job from bank bk and check every lane every step.
    // if scribble=1, keep writing junk into the OTHER bank at the same time
    task feed_and_check(input integer bk, input integer scribble);
        begin
            rbank = bk;
            for (step = 0; step <= 3*N-2; step = step + 1) begin
                feed_en = 1; t = step;
                if (scribble) begin
                    we = 1; wbank = !bk; wrow = step % N; wdata = {N*W{1'b1}};
                end
                @(posedge clk); #1;   // lanes are registered: they show step 'step' now
                for (l = 0; l < N; l = l + 1) begin
                    k = step - l;
                    // A lane l -> A[l][k], B lane l -> B[k][l], 0 outside the window
                    checks = checks + 2;
                    expv = (k >= 0 && k < N) ? val(bk, l, k) : 0;
                    if (lanes_a[l*W +: W] !== expv) begin
                        errors = errors + 1;
                        $display("  FAIL A bank%0d step %0d lane %0d: got %0d want %0d", bk, step, l, lanes_a[l*W +: W], expv);
                    end
                    expv = (k >= 0 && k < N) ? val(bk, k, l) : 0;
                    if (lanes_b[l*W +: W] !== expv) begin
                        errors = errors + 1;
                        $display("  FAIL B bank%0d step %0d lane %0d: got %0d want %0d", bk, step, l, lanes_b[l*W +: W], expv);
                    end
                end
            end
            feed_en = 0; we = 0;
        end
    endtask

    initial begin
        $dumpfile("sim/waves/tb_input_buffer_v2.vcd");
        $dumpvars(0, tb_input_buffer_v2);
        $display("=== input_buffer_v2 tests ===");
        @(posedge clk); #1 rst = 0;

        write_bank(0);
        write_bank(1);
        feed_and_check(0, 0);   $display("  bank 0 skew pattern checked");
        feed_and_check(1, 0);   $display("  bank 1 skew pattern checked");
        // feed bank 0 while hammering bank 1 with junk: bank 0 output must be clean
        feed_and_check(0, 1);   $display("  bank 0 fed while bank 1 was being written");

        $display("input_buffer_v2: %0d checks, %0d errors -> %s", checks, errors,
                 errors ? "FAILED" : "ALL PASSED");
        $finish;
    end
endmodule
