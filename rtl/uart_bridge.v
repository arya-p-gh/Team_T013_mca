// uart_bridge.v
// Lets a PC drive the accelerator over a serial port, so we can demo it on
// the board without any extra hardware. It turns simple one-letter commands
// into writes/start/reads on systolic_top:
//
//   'P'                    -> replies 'K'        (ping, checks the link works)
//   'A' + N*N bytes        -> writes matrix A    (row by row, Q4.4 bytes)
//   'B' + N*N bytes        -> writes matrix B
//   'S'                    -> runs C = A x B, then sends back N*N results,
//                             3 bytes each, most significant byte first
//                             (the 20-bit result sign-extended to 24 bits)
//
// Anything else is ignored. host/uart_host.py on the PC side speaks this.
`timescale 1ns/1ps
module uart_bridge #(
    parameter N            = 4,
    parameter ACC_W        = 20,
    parameter CLKS_PER_BIT = 868,
    parameter ADDR_W       = $clog2(N*N)
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    rx,
    output wire                    tx,
    // to the accelerator (systolic_top)
    output reg                     acc_wr_en,
    output reg                     acc_wr_sel,
    output reg  [ADDR_W-1:0]       acc_wr_addr,
    output reg  [7:0]              acc_wr_data,
    output reg                     acc_start,
    input  wire                    acc_done,
    output reg  [ADDR_W-1:0]       acc_rd_addr,
    input  wire signed [ACC_W-1:0] acc_rd_data,
    // for LEDs
    output reg                     result_ready,
    output reg  [7:0]              last_cmd
);
    localparam NN = N*N;

    wire       rx_valid;
    wire [7:0] rx_data;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk(clk), .rst(rst), .rx(rx), .valid(rx_valid), .data(rx_data));
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (.clk(clk), .rst(rst), .start(tx_start), .data(tx_data), .tx(tx), .busy(tx_busy));

    localparam [2:0] S_CMD = 3'd0, S_LOAD = 3'd1, S_WAIT = 3'd2,
                     S_SEND = 3'd3, S_SEND_W1 = 3'd4, S_SEND_W2 = 3'd5;
    reg [2:0]        state;
    reg [ADDR_W:0]   cnt;        // element counter (one extra bit so it can reach NN)
    reg [1:0]        byte_idx;   // which of the 3 result bytes we're sending

    // result sign-extended to 24 bits, then pick the byte to send
    wire [23:0] res24 = {{(24-ACC_W){acc_rd_data[ACC_W-1]}}, acc_rd_data};

    always @(posedge clk) begin
        if (rst) begin
            state <= S_CMD; cnt <= 0; byte_idx <= 0;
            acc_wr_en <= 0; acc_wr_sel <= 0; acc_wr_addr <= 0; acc_wr_data <= 0;
            acc_start <= 0; acc_rd_addr <= 0; tx_start <= 0; tx_data <= 0;
            result_ready <= 0; last_cmd <= 0;
        end else begin
            acc_wr_en <= 1'b0;
            acc_start <= 1'b0;
            tx_start  <= 1'b0;
            case (state)
                S_CMD: if (rx_valid) begin
                    last_cmd <= rx_data;
                    case (rx_data)
                        8'h41: begin acc_wr_sel <= 1'b0; cnt <= 0; state <= S_LOAD; end   // 'A'
                        8'h42: begin acc_wr_sel <= 1'b1; cnt <= 0; state <= S_LOAD; end   // 'B'
                        8'h53: begin acc_start <= 1'b1; result_ready <= 1'b0; state <= S_WAIT; end // 'S'
                        8'h50: if (!tx_busy) begin tx_data <= 8'h4B; tx_start <= 1'b1; end // 'P' -> 'K'
                        default: ;
                    endcase
                end
                S_LOAD: if (rx_valid) begin       // each byte is the next matrix element
                    acc_wr_en   <= 1'b1;
                    acc_wr_addr <= cnt[ADDR_W-1:0];
                    acc_wr_data <= rx_data;
                    if (cnt == NN-1) state <= S_CMD;
                    cnt <= cnt + 1;
                end
                S_WAIT: if (acc_done) begin
                    result_ready <= 1'b1;
                    cnt <= 0; byte_idx <= 0; acc_rd_addr <= 0;
                    state <= S_SEND;
                end
                S_SEND: begin                     // send byte 2, 1, 0 of result cnt
                    tx_data  <= (byte_idx == 0) ? res24[23:16] :
                                (byte_idx == 1) ? res24[15:8]  : res24[7:0];
                    tx_start <= 1'b1;
                    state    <= S_SEND_W1;
                end
                S_SEND_W1: state <= S_SEND_W2;    // give the transmitter a clock to go busy
                S_SEND_W2: if (!tx_busy) begin
                    if (byte_idx == 2) begin
                        byte_idx <= 0;
                        if (cnt == NN-1) state <= S_CMD;
                        else begin
                            cnt <= cnt + 1;
                            acc_rd_addr <= cnt[ADDR_W-1:0] + 1'b1;
                            state <= S_SEND;
                        end
                    end else begin
                        byte_idx <= byte_idx + 1;
                        state <= S_SEND;
                    end
                end
                default: state <= S_CMD;
            endcase
        end
    end
endmodule
