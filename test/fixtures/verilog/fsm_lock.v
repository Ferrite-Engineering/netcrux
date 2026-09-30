// fsm_lock — planted FSM deadlock (a hung test).
//
// Normal flow: IDLE -(start)-> RUN -> DONE -> IDLE, asserting `done` in DONE.
// BUG: when `mode` is high at the start of a transaction the FSM jumps to TRAP,
// a state with NO outgoing edge — a deadlock. `done` never asserts, so a
// testbench that waits for `done` hangs forever. SimCrux's job scheduler hits
// its per-test timeout and SIGKILLs the process tree (no orphaned vvp).
//
// Caught: SimCrux (one test times out while its sibling passes), WaveCrux (the
// state bus parks at S_TRAP and `done` never rises — FSM state visualization),
// NetCrux (FSM extraction finds an unreachable-exit / dead state; encoding
// classified from the S_* one-hot-vs-binary constants).
module fsm_lock (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire       mode,
    output reg        done,
    output reg  [2:0] state
);

    localparam [2:0] S_IDLE = 3'd0,
                     S_RUN  = 3'd1,
                     S_DONE = 3'd2,
                     S_TRAP = 3'd4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else begin
            case (state)
                S_IDLE: if (start) state <= (mode ? S_TRAP : S_RUN); // BUG path
                S_RUN:  state <= S_DONE;
                S_DONE: state <= S_IDLE;
                S_TRAP: state <= S_TRAP;                             // deadlock
                default: state <= S_IDLE;
            endcase
        end
    end

    always @(*) done = (state == S_DONE);

endmodule
