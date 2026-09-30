// Verilog top that instantiates a VHDL submodule `sub`. The black-box
// prototype below is what the Verilog parser sees before Yosys rebinds
// the instance to the GHDL-elaborated implementation during
// `hierarchy -check`.
(* blackbox *)
module sub (
    input  wire [3:0] a,
    output wire [3:0] y
);
endmodule

module top (
    input  wire [3:0] din,
    output wire [3:0] dout
);
  sub u_sub (.a(din), .y(dout));
endmodule
