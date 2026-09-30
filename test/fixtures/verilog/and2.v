// Two-input AND gate. The simplest possible pipeline fixture: one
// combinational cell, three single-bit ports.
module and2 (
    input  wire a,
    input  wire b,
    output wire y
);
  assign y = a & b;
endmodule
