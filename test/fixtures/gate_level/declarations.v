module m3 (input  [3:0] a, b,
           output wire y,
           inout  io);
  supply0 s0, s1x;
  supply1 vv;
  wire [3:0] w1, w2;
  tri t1;
  wire
     w3;
  INV  u1
     (.A(a[0]),
      .Y(y));
  INV u2 (.A(w1[0]), .Y(w3)) ;
  INV \u3/x  (.A(w2[1]), .Y(w2[2]));
endmodule

module m4 (a, b, y);
  output y;
  input a;
  input b;
  wire a;
  INV u (a, y);
endmodule

module m5 (input x, output z);
  m3 inst (.a({x, x, x, x}), .b(4'b0000), .y(z), .io());
endmodule
