module top(input a, output y, input vcck, input gndk);
  wire n1;
  INV u1 (.A(a), .Y(n1), .VCCK(vcck), .GNDK(gndk));
  INV u2 (.A(n1), .Y(y), .VCCK(vcck), .GNDK(gndk));
  MACRO m1 (.D(n1), .Q(), .CLK(a));
endmodule
