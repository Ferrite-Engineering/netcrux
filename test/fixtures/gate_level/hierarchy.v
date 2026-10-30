// Instances before their module definitions, positional connections to a
// module defined later, cell types nothing defines, a module nothing uses.
module top2 (a, b, y, z, e);
  input a; input b; output y; output z; inout e;
  wire [1:0] v;
  leafb l1 (a, b, y);
  leafb l2 (.a(a), .b(b));
  MISSING m1 (a, v[1], {y, z});
  MISSING2 m2 (.P(a), .Q(v[0]), .R(e), .S());
  AN2 g (.A(a), .Y(v[1]));
  assign {v[0], e} = {2{a}};
endmodule

module leafb (input a, input b, output y, output z);
  wire w;
  AN2 u (.A(a), .B(b), .Y(w));
  assign y = w;
  assign z = 1'b1;
endmodule

module unusedm (input a);
  wire q;
  AN2 x (.A(a), .Y(q));
endmodule
