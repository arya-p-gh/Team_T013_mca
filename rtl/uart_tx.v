// uart_tx.v
// Sends one byte back to the PC, 8N1 (start bit, 8 data bits LSB first,
// stop bit). Pulse start with the byte on data; busy stays high until the
// stop bit has gone out.
`timescale 1ns/1ps
module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output wire       busy
);
    localparam CW = $clog2(CLKS_PER_BIT + 1);
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg [1:0]    state;
    reg [CW-1:0] cnt;
    reg [2:0]    bit_idx;
    reg [7:0]    shreg;

    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; tx <= 1'b1; cnt <= 0; bit_idx <= 0; shreg <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;                       // idle line is high
                    if (start) begin
                        shreg <= data; cnt <= 0; state <= S_START;
                    end
                end
                S_START: begin
                    tx <= 1'b0;                       // start bit
                    if (cnt == CLKS_PER_BIT-1) begin cnt <= 0; bit_idx <= 0; state <= S_DATA; end
                    else cnt <= cnt + 1;
                end
                S_DATA: begin
                    tx <= shreg[bit_idx];             // LSB first
                    if (cnt == CLKS_PER_BIT-1) begin
                        cnt <= 0;
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 1;
                    end else cnt <= cnt + 1;
                end
                S_STOP: begin
                    tx <= 1'b1;                       // stop bit
                    if (cnt == CLKS_PER_BIT-1) begin cnt <= 0; state <= S_IDLE; end
                    else cnt <= cnt + 1;
                end
            endcase
        end
    end
endmodule
