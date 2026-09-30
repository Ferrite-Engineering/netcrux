// Four-bit ripple-carry-style adder expressed at the RTL level. Yosys's
// proc pass will emit a $add cell against this; later passes (techmap,
// not run by the pipeline) would lower it to gates.
module adder4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,
    output wire [3:0] sum,
    output wire       cout
);
  assign {cout, sum} = a + b + cin;
endmodule
