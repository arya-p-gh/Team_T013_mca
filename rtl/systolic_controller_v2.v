// systolic_controller_v2.v
// Phase II controller. Same idea as systolic_controller.v:
//
//   IDLE --start--> CLEAR --> COMPUTE --> CAPTURE --> DONE --> IDLE
//
// with three additions:
//
//   1. acc_mode: if start comes with acc_mode = 1, we skip CLEAR and the PEs
//      keep adding onto whatever they already hold. This is what makes tiling
//      work: C_tile = A_tile0*B_tile0 + A_tile1*B_tile1 + ... is just several
//      jobs in a row, all but the first in acc_mode.
//
//   2. PIPE: with pipelined MACs every result lands 1 cycle later, so COMPUTE
//      runs one extra cycle (3N-1+PIPE cycles in total).
//
//   3. Bank select: the bank number given with start is latched into rbank and
//      held for the whole job, so the host can keep filling the other bank.
`timescale 1ns/1ps
module systolic_controller_v2 #(
    parameter N     = 4,
    parameter CNT_W = 5,
    parameter PIPE  = 1
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire             start_bank,
    input  wire             acc_mode,
    output reg              arr_clr,
    output reg              arr_en,
    output reg              feed_en,
    output reg  [CNT_W-1:0] t,
    output reg              rbank,
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

    // last value of t: the last operands reach PE(N-1,N-1) at 3N-2, plus one
    // more cycle if the MACs are pipelined
    localparam [CNT_W-1:0] T_LAST = 3*N - 2 + PIPE;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            t     <= {CNT_W{1'b0}};
            rbank <= 1'b0;
        end else begin
            case (state)
                S_IDLE: if (start) begin
                    rbank <= start_bank;
                    t     <= {CNT_W{1'b0}};
                    // accumulate mode: don't wipe the PEs, go straight to work
                    state <= acc_mode ? S_COMPUTE : S_CLEAR;
                end
                S_CLEAR:   state <= S_COMPUTE;
                S_COMPUTE: if (t == T_LAST) state <= S_CAPTURE;
                           else             t     <= t + 1'b1;
                S_CAPTURE: state <= S_DONE;
                S_DONE:    state <= S_IDLE;
                default:   state <= S_IDLE;
            endcase
        end
    end

    // Moore outputs, same as v1
    always @(*) begin
        arr_clr = (state == S_CLEAR);
        arr_en  = (state == S_COMPUTE);
        feed_en = (state == S_COMPUTE);
        capture = (state == S_CAPTURE);
        done    = (state == S_DONE);
    end

    assign busy = (state != S_IDLE) && (state != S_DONE);
endmodule
