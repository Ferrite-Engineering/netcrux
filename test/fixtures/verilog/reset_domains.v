// reset_domains — planted reset-domain bugs (deterministic, RTL-visible).
//
// Two defects a reset-domain review should catch:
//   (1) INCOMPLETE RESET: `alarm_r` is never placed in a reset branch, so it
//       powers up as X and the X propagates to the `alarm` output until the
//       first functional write clears it. Visible as red X in WaveCrux and a
//       deterministic testbench failure in SimCrux.
//   (2) MIXED RESET POLARITY / TWO DOMAINS: the main domain uses active-low
//       rst_main_n; the aux domain uses active-HIGH rst_aux. NetCrux's
//       reset-domain analysis recovers both domains and flags the polarity
//       split and the aux/main crossing of `data_r -> capture_r`.
module reset_domains (
    input  wire       clk,
    input  wire       rst_main_n,   // active-low  (main domain)
    input  wire       rst_aux,      // active-HIGH (aux domain) — polarity split
    input  wire       arm,
    output reg  [7:0] capture_r,
    output wire       alarm
);

    // main domain: a counter, correctly reset.
    reg [7:0] data_r;
    always @(posedge clk or negedge rst_main_n) begin
        if (!rst_main_n) data_r <= 8'd0;
        else             data_r <= data_r + 8'd1;
    end

    // aux domain: captures the main-domain bus (reset-domain crossing).
    always @(posedge clk or posedge rst_aux) begin
        if (rst_aux) capture_r <= 8'd0;
        else         capture_r <= data_r;
    end

    // BUG (1): alarm_r is missing from every reset branch -> X at power-up.
    reg alarm_r;
    always @(posedge clk) begin
        if (arm) alarm_r <= 1'b0;   // no reset arm: powers up X, clears only on `arm`
        else     alarm_r <= alarm_r; // holds (X until first arm)
    end
    assign alarm = alarm_r;

endmodule
