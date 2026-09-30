// cdc_capture — planted clock-domain-crossing (CDC) bug.
//
// A sample index produced in the clk_a domain is captured into the clk_b
// domain. Each new sample is announced by a one-cycle `req_a` pulse. The
// request crosses into clk_b through only a SINGLE flop (an insufficient
// synchronizer — no 2-FF chain, no pulse-stretch, no toggle/ack handshake),
// and the multi-bit `sample_a` bus is captured directly with no coherent
// hold. When clk_b is slow relative to the request pulse, whole pulses fall
// between clk_b sampling edges and samples are silently DROPPED. Because
// whether a pulse is caught depends on the (asynchronous) clock phase, the
// failure is phase/seed dependent — i.e. flaky.
//
// Meant to be caught four ways by the crux suite:
//   * SimCrux  — the self-checking testbench fails on some phases/seeds
//   * WaveCrux — a req_a pulse with no following captured_valid_b is a visibly
//                dropped sample; captured_b skips a value
//   * NetCrux  — CDC analysis flags req_a/sample_a -> clk_b as unsynchronized
//   * LintCrux — Verilator/Verible flag the width truncation + unused net below
module cdc_capture #(
    parameter WIDTH  = 8,
    parameter STRIDE = 4          // clk_a cycles between samples
) (
    input  wire             clk_a,
    input  wire             rst_a_n,
    input  wire             clk_b,
    input  wire             rst_b_n,
    output reg  [WIDTH-1:0] captured_b,
    output reg              captured_valid_b
);

    // ---------------------------------------------------------------
    // Domain A: issue a sample + one-cycle request every STRIDE cycles.
    // sample_a holds its value between pulses (stable for the crossing).
    // ---------------------------------------------------------------
    reg [WIDTH-1:0] sample_a;
    reg [7:0]       div;
    reg             req_a;

    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) begin
            sample_a <= {WIDTH{1'b0}};
            div      <= 8'd0;
            req_a    <= 1'b0;
        end else if (div == (STRIDE - 1)) begin
            div      <= 8'd0;
            req_a    <= 1'b1;               // one-cycle request pulse
            sample_a <= sample_a + 1'b1;    // next sample index
        end else begin
            div      <= div + 8'd1;
            req_a    <= 1'b0;
        end
    end

    // ---------------------------------------------------------------
    // Domain B: THE BUG. Single-flop sample of req_a (insufficient sync),
    // rising-edge detect, and a direct capture of the clk_a-domain bus.
    // ---------------------------------------------------------------
    reg req_b0, req_b1;

    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) begin
            req_b0           <= 1'b0;
            req_b1           <= 1'b0;
            captured_b       <= {WIDTH{1'b0}};
            captured_valid_b <= 1'b0;
        end else begin
            req_b0           <= req_a;                 // <-- single-flop CDC
            req_b1           <= req_b0;
            captured_valid_b <= req_b0 & ~req_b1;      // rising edge of request
            if (req_b0 & ~req_b1)
                captured_b   <= sample_a;              // <-- direct multi-bit capture
        end
    end

    // ---------------------------------------------------------------
    // Two deliberately lint-visible defects, thematically tied to a
    // half-finished synchronizer (give LintCrux something concrete here).
    // ---------------------------------------------------------------
    // (1) width truncation: WIDTH+1 result assigned to a WIDTH net.
    wire [WIDTH-1:0] guard_band = sample_a + 9'd3;              // WIDTHTRUNC
    // (2) unused net: looks like a leftover/abandoned second sync stage.
    wire [WIDTH-1:0] sync_stage_unused = sample_a ^ captured_b; // UNUSEDSIGNAL

endmodule
