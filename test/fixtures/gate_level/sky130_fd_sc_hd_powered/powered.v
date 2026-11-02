// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0
//
// A gate-level netlist in the shape place and route writes it: every
// sky130_fd_sc_hd instance wired to VPWR and VGND, its wells to VPB and VNB,
// except u_aoi, whose VNB is left unconnected on purpose. Hand-written; see
// PROVENANCE.md.
module powered (
  input  wire VPWR,
  input  wire VGND,
  input  wire clk,
  input  wire a,
  input  wire b,
  input  wire c,
  output wire q
);
  wire n_nand;
  wire n_aoi;

  sky130_fd_sc_hd__nand2_1 u_nand (
    .A(a), .B(b), .Y(n_nand),
    .VPWR(VPWR), .VGND(VGND), .VPB(VPWR), .VNB(VGND)
  );

  sky130_fd_sc_hd__a21oi_1 u_aoi (
    .A1(n_nand), .A2(c), .B1(a), .Y(n_aoi),
    .VPWR(VPWR), .VGND(VGND), .VPB(VPWR)
  );

  sky130_fd_sc_hd__dfxtp_1 u_ff (
    .CLK(clk), .D(n_aoi), .Q(q),
    .VPWR(VPWR), .VGND(VGND), .VPB(VPWR), .VNB(VGND)
  );
endmodule
