module inc (input [1:0] a, output [1:0] y);
  // One more than a, modulo four.
  assign y = a + 2'd1;
endmodule
