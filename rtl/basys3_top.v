// basys3_top.v
// Top level for the Digilent Basys-3 board (Artix-7 XC7A35T).
// The PC talks to the accelerator through the board's USB cable (it shows up
// as a serial port), via uart_bridge. Pin assignments are in
// constraints/basys3.xdc.
//
//   btnC    -> reset
//   LED 0   -> accelerator busy
//   LED 1   -> result ready (a multiply finished since the last 'S')
//   LED 15:8 -> last command byte received (handy for debugging)
`timescale 1ns/1ps
module basys3_top (
    input  wire        clk,       // 100 MHz
    input  wire        btnC,
    input  wire        RsRx,
    output wire        RsTx,
    output wire [15:0] led
);
    localparam N = 4, ACC_W = 20, ADDR_W = 4;

    // the button isn't synchronised to the clock, so pass it through 2 flops
    reg rst_s1 = 1'b1, rst = 1'b1;
    always @(posedge clk) begin
        rst_s1 <= btnC;
        rst    <= rst_s1;
    end

    wire              wr_en, wr_sel, start, busy, done, result_ready;
    wire [ADDR_W-1:0] wr_addr, rd_addr;
    wire [7:0]        wr_data, last_cmd;
    wire signed [ACC_W-1:0] rd_data;

    uart_bridge #(.N(N), .ACC_W(ACC_W), .CLKS_PER_BIT(868)) u_bridge (
        .clk(clk), .rst(rst), .rx(RsRx), .tx(RsTx),
        .acc_wr_en(wr_en), .acc_wr_sel(wr_sel), .acc_wr_addr(wr_addr), .acc_wr_data(wr_data),
        .acc_start(start), .acc_done(done), .acc_rd_addr(rd_addr), .acc_rd_data(rd_data),
        .result_ready(result_ready), .last_cmd(last_cmd)
    );

    systolic_top #(.N(N), .ACC_W(ACC_W)) u_acc (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .start(start), .busy(busy), .done(done),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );

    assign led = {last_cmd, 6'b0, result_ready, busy};
endmodule
