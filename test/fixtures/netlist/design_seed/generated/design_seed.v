// Informational RTL equivalent of design_seed.netlist.json — never parsed
// by tests. Regenerate everything with:
//   dart run tool/generate_design_seed_fixture.dart

module top(input clk, input rst, output dout);
  wire cpu_dout;
  cpu u_cpu(.CLK(clk), .RST(rst), .DOUT(cpu_dout));
  reg dma_reg_q;
  always @(posedge clk) dma_reg_q <= cpu_dout;
  assign dout = dma_reg_q;
endmodule

module cpu(input CLK, input RST, output DOUT);
  wire pc_q, alu_y;
  alu u_alu(.A(pc_q), .B(pc_q), .Y(alu_y));
  reg pc_reg_q;
  always @(posedge CLK) pc_reg_q <= alu_y;
  assign DOUT = alu_y;
endmodule

module alu(input A, input B, output Y);
  assign Y = A ^ B;
endmodule
