// tb_uart.v
// Tests the whole board path in simulation: a fake PC sends bytes over the
// serial line into uart_bridge, the accelerator runs, and the results come
// back over the serial line. This is exactly what happens on the Basys-3,
// just with a much faster baud rate so the simulation doesn't take forever.
//
// It runs every N=4 test case from the Python model through the UART and
// compares all 16 results of each.
`timescale 1ns/1ps
module tb_uart;
    parameter  NUM_TESTS = 14;
    localparam N = 4, NN = 16, ACC_W = 20, CPB = 16;   // 16 clocks per bit in sim
    localparam BIT_NS = CPB * 10;

    reg  clk = 0, rst = 1;
    reg  pc_tx = 1'b1;          // PC -> FPGA line (idle high)
    wire fpga_tx;               // FPGA -> PC line

    wire              wr_en, wr_sel, start, busy, done, result_ready;
    wire [3:0]        wr_addr, rd_addr;
    wire [7:0]        wr_data, last_cmd;
    wire signed [ACC_W-1:0] rd_data;

    uart_bridge #(.N(N), .ACC_W(ACC_W), .CLKS_PER_BIT(CPB)) u_bridge (
        .clk(clk), .rst(rst), .rx(pc_tx), .tx(fpga_tx),
        .acc_wr_en(wr_en), .acc_wr_sel(wr_sel), .acc_wr_addr(wr_addr), .acc_wr_data(wr_data),
        .acc_start(start), .acc_done(done), .acc_rd_addr(rd_addr), .acc_rd_data(rd_data),
        .result_ready(result_ready), .last_cmd(last_cmd));

    systolic_top #(.N(N), .ACC_W(ACC_W)) u_acc (
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr),
        .wr_data(wr_data), .start(start), .busy(busy), .done(done),
        .rd_addr(rd_addr), .rd_data(rd_data));

    always #5 clk = ~clk;

    reg [7:0]       ab_mem [0:NUM_TESTS*2*NN-1];
    reg [ACC_W-1:0] c_mem  [0:NUM_TESTS*NN-1];

    // PC side: send one byte (start bit, 8 bits LSB first, stop bit)
    task send_byte(input [7:0] b);
        integer i;
        begin
            pc_tx = 1'b0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin pc_tx = b[i]; #(BIT_NS); end
            pc_tx = 1'b1; #(BIT_NS);
        end
    endtask

    // PC side: receive one byte, sampling each bit in the middle
    task recv_byte(output [7:0] b);
        integer i;
        begin
            @(negedge fpga_tx);           // start bit begins
            #(BIT_NS + BIT_NS/2);         // skip start bit, land mid first data bit
            for (i = 0; i < 8; i = i + 1) begin b[i] = fpga_tx; #(BIT_NS); end
        end
    endtask

    integer tst, e, errors = 0, total = 0;
    reg [7:0] b0, b1, b2, pong;
    reg signed [23:0] got;
    reg signed [ACC_W-1:0] expv;

    initial begin
        $readmemh("sim/vectors/N4_ab.hex", ab_mem);
        $readmemh("sim/vectors/N4_c.hex",  c_mem);
        $dumpfile("sim/waves/tb_uart.vcd");
        $dumpvars(1, tb_uart);
        $display("=== UART bridge end-to-end test (%0d tests) ===", NUM_TESTS);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        // ping first: send 'P', expect 'K'
        fork
            send_byte(8'h50);
            recv_byte(pong);
        join
        $display("  ping -> got 0x%02h (%s)", pong, pong == 8'h4B ? "ok" : "WRONG");
        if (pong != 8'h4B) errors = errors + 1;

        for (tst = 0; tst < NUM_TESTS; tst = tst + 1) begin
            send_byte(8'h41);                                   // 'A'
            for (e = 0; e < NN; e = e + 1) send_byte(ab_mem[tst*2*NN + e]);
            send_byte(8'h42);                                   // 'B'
            for (e = 0; e < NN; e = e + 1) send_byte(ab_mem[tst*2*NN + NN + e]);
            send_byte(8'h53);                                   // 'S'
            for (e = 0; e < NN; e = e + 1) begin
                recv_byte(b0); recv_byte(b1); recv_byte(b2);
                got  = {b0, b1, b2};
                expv = c_mem[tst*NN + e];
                total = total + 1;
                if (got !== {{(24-ACC_W){expv[ACC_W-1]}}, expv}) begin
                    errors = errors + 1;
                    $display("  MISMATCH test %0d element %0d: got %0d want %0d", tst, e, got, expv);
                end
            end
            $display("  test %2d sent and received over UART", tst);
        end

        $display("UART: %0d results checked, %0d errors -> %s", total, errors,
                 errors ? "FAILED" : "ALL PASSED");
        $finish;
    end

    initial begin #200000000; $display("TIMEOUT"); $finish; end
endmodule
