#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0
"""Generate a synthetic structural gate-level Verilog netlist.

Stands in for a post-route netlist when measuring NetCrux at a scale no
checked-in fixture reaches. The design is N standard cells of five types
(inverter, NAND2, NOR2, D flip-flop, buffer) instantiated by name with named
ports, each carrying power, ground and bulk pins that a Liberty file read for
Yosys does not declare. Most of the cells sit in one large flat module; the
rest are spread over a three-level hierarchy of uniquified modules.

    python3 tool/gen_gate_netlist.py --gates 1000000 --out design.v
    python3 tool/gen_gate_netlist.py --gates 1000000 --out design.v \
        --lib-out cells.lib

Then produce the JSON the way a flow script would:

    yosys -p "read_liberty -lib cells.lib; read_verilog design.v; \
              hierarchy -top top; proc; write_json design.json"

The cell names and pin names are parameters (see --cells), so the same
generator can target any library that has an inverter, NAND2, NOR2, a D
flip-flop and a buffer. The defaults are generic names, and --lib-out writes a
matching minimal Liberty file.

--awkward N adds one more module of N cells that uses the forms a post-route
netlist has and a plain generator does not: escaped names, bus pins connected
to concatenations, slices and whole buses, assigns between nets and to slices
and constants, supply nets, tie constants, unconnected pins, positional
instances, an implicit net, an instance of a module defined later, and cells
from a second library given as header-only Verilog models. The models go to
--models-out:

    python3 tool/gen_gate_netlist.py --gates 20000 --awkward 2000 \
        --out design.v --lib-out cells.lib --models-out models.v

The output is deterministic for a given --seed, and unchanged when
--awkward is not given.
"""

from __future__ import annotations

import argparse
import random
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class CellType:
    """One library cell: its name and the pin each role maps to."""

    kind: str
    name: str
    inputs: tuple[str, ...]
    output: str
    clock: str | None = None


def default_cells() -> dict[str, CellType]:
    return {
        "inv": CellType("inv", "INV_X1", ("A",), "ZN"),
        "nand2": CellType("nand2", "NAND2_X1", ("A1", "A2"), "ZN"),
        "nor2": CellType("nor2", "NOR2_X1", ("A1", "A2"), "ZN"),
        "dff": CellType("dff", "DFF_X1", ("D",), "Q", clock="CK"),
        "buf": CellType("buf", "BUF_X1", ("I",), "Z"),
    }


# Power, ground and bulk pins every instance connects. A Liberty file read with
# `read_liberty -lib` declares none of them, so each is an undeclared pin on a
# black-box cell.
POWER_PINS = (("VDD", "VDD"), ("VSS", "VSS"), ("VNB", "VBULK"))

# Weights of the cell kinds in the generated logic.
KIND_WEIGHTS = (("inv", 0.22), ("nand2", 0.32), ("nor2", 0.22), ("dff", 0.14), ("buf", 0.10))


def parse_cell_overrides(spec: str | None, cells: dict[str, CellType]) -> None:
    """Apply --cells overrides: kind=Name:in1,in2:out[:clk], comma-separated
    with ';' between kinds."""
    if not spec:
        return
    for part in spec.split(";"):
        part = part.strip()
        if not part:
            continue
        kind, rest = part.split("=", 1)
        fields = rest.split(":")
        if kind not in cells or len(fields) < 3:
            raise SystemExit(f"bad --cells entry: {part!r}")
        clock = fields[3] if len(fields) > 3 and fields[3] else cells[kind].clock
        cells[kind] = CellType(
            kind, fields[0], tuple(fields[1].split(",")), fields[2], clock
        )


def liberty_text(cells: dict[str, CellType]) -> str:
    lines = ['library ("gen_cells") {', '  delay_model : "table_lookup";']
    for cell in cells.values():
        lines.append(f'  cell ("{cell.name}") {{')
        lines.append("    area : 1.0;")
        for pin in cell.inputs:
            lines.append(f'    pin ("{pin}") {{ direction : "input"; capacitance : 0.002; }}')
        if cell.clock:
            lines.append(
                f'    pin ("{cell.clock}") {{ direction : "input"; clock : true; capacitance : 0.002; }}'
            )
        if cell.kind == "dff":
            lines.append('    ff ("IQ", "IQN") { clocked_on : "' + cell.clock + '"; next_state : "' + cell.inputs[0] + '"; }')
            function = "IQ"
        elif cell.kind == "inv":
            function = f"!{cell.inputs[0]}"
        elif cell.kind == "buf":
            function = cell.inputs[0]
        elif cell.kind == "nand2":
            function = f"!({cell.inputs[0]} & {cell.inputs[1]})"
        else:
            function = f"!({cell.inputs[0]} | {cell.inputs[1]})"
        lines.append(
            f'    pin ("{cell.output}") {{ direction : "output"; function : "{function}"; }}'
        )
        lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


class Emitter:
    def __init__(self, rng: random.Random, cells: dict[str, CellType]) -> None:
        self.rng = rng
        self.cells = cells
        self.kinds = [k for k, _ in KIND_WEIGHTS]
        self.weights = [w for _, w in KIND_WEIGHTS]
        self.counter = 0

    def instance_name(self, scope: str) -> str:
        self.counter += 1
        # A mix of flat auto names and slash-separated hierarchical names the
        # way a place-and-route tool writes them; the latter are escaped
        # identifiers (backslash, name, one terminating space).
        n = self.counter
        if n % 7 == 0:
            return f"\\{scope}/u_{n % 97}/g{n} "
        return f"_{n:07d}_"

    def net_name(self, scope: str, index: int) -> str:
        if index % 11 == 0:
            return f"\\{scope}/w{index}[{index % 32}] "
        return f"n{index}"

    def logic(
        self,
        out,
        scope: str,
        count: int,
        sources: list[str],
        clk: str,
    ) -> list[str]:
        """Write `count` cells into `out`; return the nets they drive.

        `sources` seeds the nets a gate may read. Reads are mostly local (the
        last few hundred nets) and sometimes far, which gives long cones.
        """
        rng = self.rng
        pool = list(sources)
        driven: list[str] = []
        decls: list[str] = []
        body: list[str] = []
        power = ", ".join(f".{pin}({net})" for pin, net in POWER_PINS)
        for index in range(count):
            kind = rng.choices(self.kinds, self.weights)[0]
            cell = self.cells[kind]
            wire = self.net_name(scope, index)
            decls.append(f"  wire {wire};")
            picks = []
            for _ in cell.inputs:
                if rng.random() < 0.9:
                    lo = max(0, len(pool) - 400)
                    picks.append(pool[rng.randrange(lo, len(pool))])
                else:
                    picks.append(pool[rng.randrange(len(pool))])
            pins = [f".{p}({n})" for p, n in zip(cell.inputs, picks)]
            if cell.clock:
                pins.append(f".{cell.clock}({clk})")
            pins.append(f".{cell.output}({wire})")
            body.append(
                f"  {cell.name} {self.instance_name(scope)} "
                f"({', '.join(pins)}, {power});"
            )
            pool.append(wire)
            driven.append(wire)
        out.write("\n".join(decls))
        out.write("\n")
        out.write("\n".join(body))
        out.write("\n")
        return driven


def write_leaf(em: Emitter, out, name: str, gates: int) -> None:
    ins = [f"i{k}" for k in range(8)]
    outs = [f"o{k}" for k in range(8)]
    out.write(f"module {name} (clk, VDD, VSS, VBULK, {', '.join(ins + outs)});\n")
    out.write("  input clk, VDD, VSS, VBULK;\n")
    out.write(f"  input {', '.join(ins)};\n")
    out.write(f"  output {', '.join(outs)};\n")
    driven = em.logic(out, name, gates, ins, "clk")
    for k, o in enumerate(outs):
        out.write(f"  assign {o} = {driven[-1 - k]};\n")
    out.write("endmodule\n\n")


def write_group(em: Emitter, out, name: str, children: list[str], own: int) -> None:
    """A module that instantiates `children` in a chain plus `own` gates."""
    ins = [f"i{k}" for k in range(8)]
    outs = [f"o{k}" for k in range(8)]
    out.write(f"module {name} (clk, VDD, VSS, VBULK, {', '.join(ins + outs)});\n")
    out.write("  input clk, VDD, VSS, VBULK;\n")
    out.write(f"  input {', '.join(ins)};\n")
    out.write(f"  output {', '.join(outs)};\n")
    prev = ins
    for c, child in enumerate(children):
        nxt = [f"{name}_c{c}_o{k}" for k in range(8)]
        out.write(f"  wire {', '.join(nxt)};\n")
        conns = ", ".join(
            [".clk(clk)", ".VDD(VDD)", ".VSS(VSS)", ".VBULK(VBULK)"]
            + [f".i{k}({prev[k]})" for k in range(8)]
            + [f".o{k}({nxt[k]})" for k in range(8)]
        )
        out.write(f"  {child} u_{c} ({conns});\n")
        prev = nxt
    if own:
        driven = em.logic(out, name, own, prev, "clk")
        prev = driven[-8:] if len(driven) >= 8 else prev
    for k, o in enumerate(outs):
        out.write(f"  assign {o} = {prev[k]};\n")
    out.write("endmodule\n\n")


# Cells of the second library, which exist only as header-only Verilog models.
MODEL_CELLS = (
    ("MUX2_X1", "(* blackbox *)\nmodule MUX2_X1 (A0, A1, S, Z);\n"
                "  input A0, A1, S;\n  output Z;\nendmodule\n"),
    ("BUS4_X1", "(* blackbox *)\nmodule BUS4_X1 (input [3:0] D, output [3:0] Q);\n"
                "endmodule\n"),
    ("TIE_X1", "(* blackbox *)\nmodule TIE_X1 (output H, output L);\nendmodule\n"),
)


def models_text() -> str:
    """Header-only Verilog models for the second library's cells."""
    return "// Cell models (headers only) for tool/gen_gate_netlist.py --awkward\n" + "".join(
        text for _, text in MODEL_CELLS
    )


def write_awkward(em: Emitter, out, name: str, count: int) -> None:
    """A module of `count` cells that exercises the awkward forms."""
    rng = em.rng
    cells = em.cells
    inv, nand2, dff, buf = cells["inv"], cells["nand2"], cells["dff"], cells["buf"]
    ins = [f"i{k}" for k in range(8)]
    outs = [f"o{k}" for k in range(8)]
    out.write(f"module {name} (clk, VDD, VSS, VBULK, {', '.join(ins + outs)});\n")
    out.write("  input clk, VDD, VSS, VBULK;\n")
    out.write(f"  input {', '.join(ins)};\n")
    out.write(f"  output {', '.join(outs)};\n")
    out.write("  supply0 gnd_n;\n  supply1 vdd_n;\n")
    power = ", ".join(f".{pin}({net})" for pin, net in POWER_PINS)
    buses = max(2, count // 40)
    for b in range(buses):
        out.write(f"  wire [7:0] bus{b};\n")
        out.write(f"  wire [0:3] up{b};\n")
    pool = list(ins)
    decls: list[str] = []
    body: list[str] = []
    asserts: list[str] = []

    def pick() -> str:
        lo = max(0, len(pool) - 64)
        return pool[rng.randrange(lo, len(pool))]

    def fresh(kind: str, i: int) -> str:
        n = f"a{i}_{kind}"
        if i % 5 == 0:
            n = f"\\{name}/{kind}{i}[{i % 16}] "
        decls.append(f"  wire {n};")
        return n

    for i in range(count):
        kind = i % 11
        if kind == 0:
            # Named instance, escaped instance name, power pins on supply nets.
            w = fresh("n", i)
            body.append(
                f"  {inv.name} \\{name}/u{i} /*c*/ (.{inv.inputs[0]}({pick()}), "
                f".{inv.output}({w}), .VDD(vdd_n), .VSS(gnd_n), .VNB(gnd_n));"
            )
            pool.append(w)
        elif kind == 1:
            # Positional instance of a header-only model cell.
            w = fresh("m", i)
            body.append(f"  MUX2_X1 mx{i} ({pick()}, {pick()}, {pick()}, {w});")
            pool.append(w)
        elif kind == 2:
            # Bus pins: concatenation in, part select out.
            lo = (i % 5) * 1
            body.append(
                f"  BUS4_X1 bs{i} (.D({{{pick()}, {pick()}, 1'b0, {pick()}}}), "
                f".Q(bus{i % buses}[{lo + 3}:{lo}]));"
            )
            for k in range(4):
                pool.append(f"bus{i % buses}[{lo + k}]")
        elif kind == 3:
            # Tie constant on an input and an unconnected output.
            body.append(
                f"  {nand2.name} t{i} (.{nand2.inputs[0]}(1'b1), "
                f".{nand2.inputs[1]}({pick()}), .{nand2.output}(), {power});"
            )
        elif kind == 4:
            # Alias through an assign, then use the alias.
            w = fresh("q", i)
            al = f"al{i}"
            decls.append(f"  wire {al};")
            asserts.append(f"  assign {al} = {pick()};")
            body.append(
                f"  {buf.name} b{i} (.{buf.inputs[0]}({al}), .{buf.output}({w}), {power});"
            )
            pool.append(w)
        elif kind == 5:
            # Flip-flop reading a whole bus bit and a reversed-range bit.
            w = fresh("f", i)
            body.append(
                f"  {dff.name} ff{i} (.{dff.inputs[0]}(up{i % buses}[{i % 4}]), "
                f".{dff.clock}(clk), .{dff.output}({w}), {power});"
            )
            pool.append(w)
        elif kind == 6:
            # Implicit net: used in a connection without a declaration.
            w = fresh("p", i)
            body.append(
                f"  {inv.name} im{i} (.{inv.inputs[0]}(implicit_{i}), .{inv.output}({w}), {power});"
            )
            pool.append(w)
        elif kind == 7:
            # Tie cell outputs onto slices.
            body.append(f"  TIE_X1 tie{i} (.H(bus{i % buses}[7]), .L(up{i % buses}[0]));")
        elif kind == 8:
            # Slice assigns: a bus half from another bus, the other from a constant.
            b = i % buses
            asserts.append(f"  assign bus{b}[3:0] = bus{(b + 1) % buses}[7:4];")
            asserts.append(f"  assign up{b}[1:3] = 3'b101;")
        elif kind == 9:
            # A module defined later in the file, positional.
            w = fresh("s", i)
            body.append(f"  late_leaf l{i} ({pick()}, {pick()}, {w});")
            pool.append(w)
        else:
            # Replication and wide constant into a bus pin.
            body.append(
                f"  BUS4_X1 rp{i} (.D({{2{{{pick()}, 1'bx}}}}), .Q());"
            )
    out.write("\n".join(decls) + "\n")
    out.write("\n".join(body) + "\n")
    out.write("\n".join(asserts) + "\n")
    for k, o in enumerate(outs):
        out.write(f"  assign {o} = {pick()};\n")
    out.write("endmodule\n\n")
    tied = ", ".join(
        [".VDD(1'b1)", ".VSS(1'b0)", ".VNB(1'b0)"]
    )
    out.write(
        "module late_leaf (a, b, y);\n  input a, b;\n  output y;\n"
        f"  {nand2.name} g (.{nand2.inputs[0]}(a), .{nand2.inputs[1]}(b), "
        f".{nand2.output}(y), {tied});\n"
        "endmodule\n\n"
    )


def generate(gates: int, out, seed: int, cells: dict[str, CellType], hier_fraction: float, awkward: int = 0) -> dict[str, int]:
    rng = random.Random(seed)
    em = Emitter(rng, cells)
    hier_gates = int(gates * hier_fraction)
    leaves_per_mid, mids_per_cluster, clusters = 4, 4, 4
    leaf_count = leaves_per_mid * mids_per_cluster * clusters
    per_leaf = max(8, hier_gates // leaf_count)
    own_per_group = max(0, per_leaf // 8)
    counts = {"leaf_modules": leaf_count}

    out.write("// Synthetic gate-level netlist (tool/gen_gate_netlist.py)\n\n")
    leaf_names = []
    for i in range(leaf_count):
        name = f"leaf_{i}"
        write_leaf(em, out, name, per_leaf)
        leaf_names.append(name)
    mid_names = []
    for m in range(mids_per_cluster * clusters):
        name = f"mid_{m}"
        kids = leaf_names[m * leaves_per_mid : (m + 1) * leaves_per_mid]
        write_group(em, out, name, kids, own_per_group)
        mid_names.append(name)
    cluster_names = []
    for c in range(clusters):
        name = f"cluster_{c}"
        kids = mid_names[c * mids_per_cluster : (c + 1) * mids_per_cluster]
        write_group(em, out, name, kids, own_per_group)
        cluster_names.append(name)

    if awkward:
        write_awkward(em, out, "awkward_core", awkward)

    flat_gates = max(1, gates - leaf_count * per_leaf - (len(mid_names) + clusters) * own_per_group)
    out.write("module flat_core (clk, VDD, VSS, VBULK, " + ", ".join(
        [f"i{k}" for k in range(16)] + [f"o{k}" for k in range(16)]) + ");\n")
    out.write("  input clk, VDD, VSS, VBULK;\n")
    out.write("  input " + ", ".join(f"i{k}" for k in range(16)) + ";\n")
    out.write("  output " + ", ".join(f"o{k}" for k in range(16)) + ";\n")
    driven = em.logic(out, "flat_core", flat_gates, [f"i{k}" for k in range(16)], "clk")
    for k in range(16):
        out.write(f"  assign o{k} = {driven[-1 - k]};\n")
    out.write("endmodule\n\n")

    out.write("module top (clk, VDD, VSS, VBULK, " + ", ".join(
        [f"in{k}" for k in range(16)] + [f"out{k}" for k in range(16)]) + ");\n")
    out.write("  input clk, VDD, VSS, VBULK;\n")
    out.write("  input " + ", ".join(f"in{k}" for k in range(16)) + ";\n")
    out.write("  output " + ", ".join(f"out{k}" for k in range(16)) + ";\n")
    out.write("  wire " + ", ".join(f"core_o{k}" for k in range(16)) + ";\n")
    conns = ", ".join(
        [".clk(clk)", ".VDD(VDD)", ".VSS(VSS)", ".VBULK(VBULK)"]
        + [f".i{k}(in{k})" for k in range(16)]
        + [f".o{k}(core_o{k})" for k in range(16)]
    )
    out.write(f"  flat_core u_core ({conns});\n")
    if awkward:
        aconns = ", ".join(
            [".clk(clk)", ".VDD(VDD)", ".VSS(VSS)", ".VBULK(VBULK)"]
            + [f".i{k}(in{k})" for k in range(8)]
            + [f".o{k}(awk_o{k})" for k in range(8)]
        )
        out.write("  wire " + ", ".join(f"awk_o{k}" for k in range(8)) + ";\n")
        out.write(f"  awkward_core u_awk ({aconns});\n")
    prev = [f"core_o{k}" for k in range(8)]
    for c, cluster in enumerate(cluster_names):
        nxt = [f"top_c{c}_o{k}" for k in range(8)]
        out.write("  wire " + ", ".join(nxt) + ";\n")
        conns = ", ".join(
            [".clk(clk)", ".VDD(VDD)", ".VSS(VSS)", ".VBULK(VBULK)"]
            + [f".i{k}({prev[k]})" for k in range(8)]
            + [f".o{k}({nxt[k]})" for k in range(8)]
        )
        out.write(f"  {cluster} u_cluster_{c} ({conns});\n")
        prev = nxt
    for k in range(16):
        src = prev[k] if k < 8 else f"core_o{k}"
        out.write(f"  assign out{k} = {src};\n")
    out.write("endmodule\n")
    counts.update(flat_gates=flat_gates, leaf_gates=per_leaf, total_instances=em.counter)
    return counts


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--gates", type=int, required=True, help="number of cells")
    parser.add_argument("--out", required=True, help="Verilog output path")
    parser.add_argument("--lib-out", help="also write a minimal Liberty file here")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument(
        "--awkward",
        type=int,
        default=0,
        metavar="N",
        help="add a module of N cells that uses awkward forms (needs --models-out)",
    )
    parser.add_argument(
        "--models-out",
        help="write header-only Verilog models for the second library (used by --awkward)",
    )
    parser.add_argument(
        "--hier-fraction",
        type=float,
        default=0.15,
        help="share of cells placed in the hierarchy rather than the flat module",
    )
    parser.add_argument(
        "--cells",
        help="override cell and pin names: 'inv=NAME:in:out;nand2=NAME:a,b:out;"
        "dff=NAME:d:q:clk;...' (kinds: inv nand2 nor2 dff buf)",
    )
    args = parser.parse_args(argv)
    cells = default_cells()
    parse_cell_overrides(args.cells, cells)
    if args.lib_out:
        with open(args.lib_out, "w", encoding="utf-8") as lib:
            lib.write(liberty_text(cells))
    if args.awkward and not args.models_out:
        raise SystemExit("--awkward needs --models-out for the second library")
    if args.models_out:
        with open(args.models_out, "w", encoding="utf-8") as models:
            models.write(models_text())
    with open(args.out, "w", encoding="utf-8", buffering=1 << 20) as out:
        counts = generate(args.gates, out, args.seed, cells, args.hier_fraction, args.awkward)
    print(counts, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
