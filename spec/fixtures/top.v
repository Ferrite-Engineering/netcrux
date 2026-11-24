module top (
  input        clk,
  input  [1:0] a,
  output [1:0] y
);
  wire [1:0] n;
  wire spare;
  inc u_inc (.a(a), .y(n));
  reg [1:0] q;
  always @(posedge clk) q <= n;
  assign y = q;
endmodule
