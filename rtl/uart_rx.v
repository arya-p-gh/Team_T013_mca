// uart_rx.v
// Receives bytes from the PC over the USB-UART line (8 data bits, no parity,
// 1 stop bit, "8N1"). The line idles high, a byte starts with a low start bit,
// then 8 data bits LSB first, then a high stop bit.
//
// CLKS_PER_BIT = clock frequency / baud rate.
//   Basys-3: 100 MHz / 115200 baud = 868.
// In simulation we use a tiny number like 16 so tests run fast.
//
// We sample each bit in the middle of its time slot, which is the safest
// point. The input goes through two flip-flops first, because it comes from
// outside the chip and isn't synchronised to our clock.
`timescale 1ns/1ps
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg        valid,     // 1-cycle pulse when a byte has arrived
    output reg  [7:0] data
);
    localparam CW = $clog2(CLKS_PER_BIT + 1);
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg rx_s1 = 1'b1, rx_s2 = 1'b1;          // 2-flop synchroniser
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end

    reg [1:0]    state;
    reg [CW-1:0] cnt;
    reg [2:0]    bit_idx;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; cnt <= 0; bit_idx <= 0; valid <= 1'b0; data <= 8'd0;
        end else begin
            valid <= 1'b0;
            case (state)
                S_IDLE: if (!rx_s2) begin          // line went low: start bit
                    cnt <= 0; state <= S_START;
                end
                S_START: begin                     // wait half a bit, check it's still low
                    if (cnt == CLKS_PER_BIT/2) begin
                        cnt <= 0;
                        if (!rx_s2) begin bit_idx <= 0; state <= S_DATA; end
                        else        state <= S_IDLE;   // just a glitch
                    end else cnt <= cnt + 1;
                end
                S_DATA: begin                      // one full bit later = middle of next bit
                    if (cnt == CLKS_PER_BIT-1) begin
                        cnt <= 0;
                        data[bit_idx] <= rx_s2;
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 1;
                    end else cnt <= cnt + 1;
                end
                S_STOP: begin
                    if (cnt == CLKS_PER_BIT-1) begin
                        cnt <= 0;
                        valid <= rx_s2;            // only accept it if the stop bit is high
                        state <= S_IDLE;
                    end else cnt <= cnt + 1;
                end
            endcase
        end
    end
endmodule
