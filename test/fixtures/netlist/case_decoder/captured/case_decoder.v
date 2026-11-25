// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0
//
// A wide case statement, the shape of an instruction decoder or an ALU's
// operation select: 64 opcodes choose among eight results. Yosys elaborates
// the case as 64 `$eq` comparators, one per opcode, whose outputs make up the
// select bus of a single `$pmux`.
module case_decoder (
  input  wire [7:0]  op,
  input  wire [31:0] a,
  input  wire [31:0] b,
  output reg  [31:0] y
);
  wire [31:0] r_add = a + b;
  wire [31:0] r_sub = a - b;
  wire [31:0] r_and = a & b;
  wire [31:0] r_or  = a | b;
  wire [31:0] r_xor = a ^ b;
  wire [31:0] r_sll = a << b[4:0];
  wire [31:0] r_srl = a >> b[4:0];
  wire [31:0] r_slt = {31'd0, $signed(a) < $signed(b)};

  always @* begin
    case (op)
      8'd0:   y = r_add;
      8'd1:   y = r_sub;
      8'd2:   y = r_and;
      8'd3:   y = r_or;
      8'd4:   y = r_xor;
      8'd5:   y = r_sll;
      8'd6:   y = r_srl;
      8'd7:   y = r_slt;
      8'd8:   y = r_add;
      8'd9:   y = r_sub;
      8'd10:  y = r_and;
      8'd11:  y = r_or;
      8'd12:  y = r_xor;
      8'd13:  y = r_sll;
      8'd14:  y = r_srl;
      8'd15:  y = r_slt;
      8'd16:  y = r_add;
      8'd17:  y = r_sub;
      8'd18:  y = r_and;
      8'd19:  y = r_or;
      8'd20:  y = r_xor;
      8'd21:  y = r_sll;
      8'd22:  y = r_srl;
      8'd23:  y = r_slt;
      8'd24:  y = r_add;
      8'd25:  y = r_sub;
      8'd26:  y = r_and;
      8'd27:  y = r_or;
      8'd28:  y = r_xor;
      8'd29:  y = r_sll;
      8'd30:  y = r_srl;
      8'd31:  y = r_slt;
      8'd32:  y = r_add;
      8'd33:  y = r_sub;
      8'd34:  y = r_and;
      8'd35:  y = r_or;
      8'd36:  y = r_xor;
      8'd37:  y = r_sll;
      8'd38:  y = r_srl;
      8'd39:  y = r_slt;
      8'd40:  y = r_add;
      8'd41:  y = r_sub;
      8'd42:  y = r_and;
      8'd43:  y = r_or;
      8'd44:  y = r_xor;
      8'd45:  y = r_sll;
      8'd46:  y = r_srl;
      8'd47:  y = r_slt;
      8'd48:  y = r_add;
      8'd49:  y = r_sub;
      8'd50:  y = r_and;
      8'd51:  y = r_or;
      8'd52:  y = r_xor;
      8'd53:  y = r_sll;
      8'd54:  y = r_srl;
      8'd55:  y = r_slt;
      8'd56:  y = r_add;
      8'd57:  y = r_sub;
      8'd58:  y = r_and;
      8'd59:  y = r_or;
      8'd60:  y = r_xor;
      8'd61:  y = r_sll;
      8'd62:  y = r_srl;
      8'd63:  y = r_slt;
      default: y = 32'd0;
    endcase
  end
endmodule
