// Tiny 3-state Moore FSM: IDLE -> BUSY -> DONE -> IDLE. Useful as a
// fixture that exercises sequential logic — yosys infers $dff cells
// for the state register.
module fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       go,
    output wire       done
);
  localparam [1:0] IDLE = 2'b00;
  localparam [1:0] BUSY = 2'b01;
  localparam [1:0] DONE = 2'b10;

  reg  [1:0] state;
  reg  [1:0] next;

  always @(posedge clk or posedge rst) begin
    if (rst) state <= IDLE;
    else state <= next;
  end

  always @* begin
    case (state)
      IDLE: next = go ? BUSY : IDLE;
      BUSY: next = DONE;
      DONE: next = IDLE;
      default: next = IDLE;
    endcase
  end

  assign done = (state == DONE);
endmodule
