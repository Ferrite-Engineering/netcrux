// Gate-level netlist with the forms a post-route netlist contains: escaped
// names, bus slices and concatenations, assigns between nets, supply nets,
// tie constants, unconnected pins, positional instances and an implicit net.
`timescale 1ns/1ps
module sub (a, b, y);
  input a, b;
  output y;
  wire t;
  AN2 u0 (.A(a), .B(b), .Y(t));
  INV u1 (t, y);
endmodule

module top (clk, d, q, bus_o, vdd, gnd, nc);
  input clk;
  input [3:0] d;
  output [3:0] q;
  output [1:0] bus_o;
  input vdd, gnd;
  output nc;
  wire [3:0] n;
  wire [7:0] big;
  wire [0:3] up;
  wire \esc[3]  ;
  wire \a.b ;
  wire [1:0] bb;
  supply0 s0;
  supply1 s1;
  tri tw;
  sub us0 (.a(d[0]), .b(d[1]), .y(n[0]));
  sub us1 (d[2], d[3], n[1]);
  INV g1 (.A(n[0]), .Y(n[2]));
  INV g2 (.A(), .Y(n[3]));
  INV g3 (.A(1'b0), .Y(\esc[3]  ));
  INV g4 (.A(s1), .Y(\a.b ));
  AN2 g5 (.A(s0), .B(gnd), .Y(tw));
  BUS2 g6 (.D({n[0], n[1]}), .Q(bb));
  BUS2 g7 (.D(d[3:2]), .Q(bus_o));
  INV g8 (.A(undeclared_net), .Y(nc));
  assign q = n;
  assign big[3:0] = d;
  assign big[7:4] = 4'b1010;
  assign up = {s1, s0, 1'bx, 1'bz};
endmodule
