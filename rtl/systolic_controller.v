// systolic_controller.v
// The state machine that runs one matrix multiply from start to finish.
//
//   IDLE --start--> CLEAR --> COMPUTE --> CAPTURE --> DONE --> back to IDLE
//
//   CLEAR   - wipe every PE's accumulator so we don't add onto old results
//   COMPUTE - count t from 0 up to 3N-2. The input buffers use t to decide
//             what to feed, and the array is enabled the whole time.
//   CAPTURE - copy the finished results into the output buffer
//   DONE    - pulse done for one cycle so the host knows it can read
//
// Why does COMPUTE last 3N-1 cycles? The last pair of numbers has to travel
// to the bottom-right PE. Its lane is skewed by N-1, it travels N-1 hops,
// there are N values per lane, and the input buffer adds 1 cycle. Add it all
// up and the last multiply lands in cycle 3N-2. Counting from 0 that's 3N-1
// cycles. (For N=4 that's 11.)
`timescale 1ns/1ps
module systolic_controller #(
    parameter N     = 4,
    parameter CNT_W = 5
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    output reg              arr_clr,
    output reg              arr_en,
    output reg              feed_en,
    output reg  [CNT_W-1:0] t,
    output reg              capture,
    output wire             busy,
    output reg              done,
    output reg  [2:0]       state
);
    localparam [2:0] S_IDLE    = 3'd0,
                     S_CLEAR   = 3'd1,
                     S_COMPUTE = 3'd2,
                     S_CAPTURE = 3'd3,
                     S_DONE    = 3'd4;

    localparam [CNT_W-1:0] T_LAST = 3*N - 2;   // last value of t before we stop

    // state changes and the step counter
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            t     <= {CNT_W{1'b0}};
        end else begin
            case (state)
                S_IDLE:    if (start) state <= S_CLEAR;
                S_CLEAR:   begin state <= S_COMPUTE; t <= {CNT_W{1'b0}}; end
                S_COMPUTE: if (t == T_LAST) state <= S_CAPTURE;
                           else             t     <= t + 1'b1;
                S_CAPTURE: state <= S_DONE;
                S_DONE:    state <= S_IDLE;
                default:   state <= S_IDLE;
            endcase
        end
    end

    // outputs depend only on the current state (a Moore machine)
    always @(*) begin
        arr_clr = (state == S_CLEAR);
        arr_en  = (state == S_COMPUTE);
        feed_en = (state == S_COMPUTE);
        capture = (state == S_CAPTURE);
        done    = (state == S_DONE);
    end

    // busy = "please don't write new matrices right now"
    assign busy = (state != S_IDLE) && (state != S_DONE);
endmodule
