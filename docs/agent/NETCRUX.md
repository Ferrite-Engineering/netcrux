# NetCrux for coding agents

NetCrux reads a hardware design the way Yosys elaborates it and answers
questions about its structure from the command line or over the Model Context
Protocol. This file is for an agent, and for the person who configures one:
when to call NetCrux, how to read what it returns, and how to cite it so a
person can check the answer.

## Starting the server

```
netcrux mcp --root <project directory>
```

The server speaks MCP over stdin and stdout. Every path a tool receives must be
inside `--root` (the working directory when omitted), and so must every file a
`.crux-project` manifest or a `.f` filelist names; a path outside it, a
symbolic link that leads outside it, or a network path is refused and never
opened. The server writes nothing into the tree and makes no network call of
its own.

Each tool is also a command, with the same inputs as flags and the same output
with `--json`:

```
netcrux info rtl/top.sv rtl/alu.sv --json
netcrux search build/top.json fifo --kind cell --json
netcrux connections design.crux-project top.u_core.alu_y --json
```

A tool's text is byte for byte what the command writes, so a script and an
agent read the same document.

## The design

Every tool takes the same two inputs:

- `design`: Verilog, SystemVerilog or VHDL sources and `.f` filelists of
  them, which NetCrux elaborates with the Yosys on `PATH`, exactly as the
  desktop app does; or one Yosys JSON netlist (`yosys write_json`), read as
  it is; or one `.crux-project` manifest, which names either.
- `top`: the top module. Without it, the top Yosys picks or the netlist
  marks.

A filelist's `+define+` and `+incdir+` are passed on. A Liberty cell library
is not read by the command line: give a design that uses one as a Yosys JSON
netlist. A `.netcrux-project`, a session or a workspace is not read either.

The server keeps the two designs it read last, so several calls about one
design elaborate it once. A source that changes is elaborated again.

## When to call it

- **The question is about structure:** what a cell is connected to, what
  drives a net, where an instance sits in the hierarchy, what a module
  contains.
- **The source cannot answer it,** because generate blocks, parameters,
  `include` files or another language's generator (Amaranth, Chisel)
  decide what the design is. NetCrux answers from the elaborated design.

Start with `info` (the top module and the instance hierarchy), then `search`
to find the full name of each cell, net, port or module you need. Names in
`connections` are hierarchical, dot-separated and rooted at the top module
(`top.u_core.alu_y`), as `search` returns them; a name written from just
below the top (`u_core.alu_y`) is read the same way.

## The three tools

| Tool | Returns | Limits |
|---|---|---|
| `info` | The top module, the number of modules, the cells and named nets of every module (each module counted once), and the instances in pre-order with each one's module and cell count | 200 instances |
| `search` | Cells, nets, ports or modules (`kind`) whose name contains the query, ignoring case, or matches it as a glob with `glob: true`: each one's path, module, type (a cell's type, a port's direction) and width, and its location | `limit`: default 50, at most 500 |
| `connections` | For a cell, each pin with its direction and the net on it; for a net, the pins that drive it and the pins it drives, each with its location. One step, inside the module that holds it | 500 pins |

A port of the module appears among a net's drivers (an input) or loads (an
output) with `cell` set to the instance's own path. A net on a pin is written
as the whole net (`top.u.data`), a slice of one (`top.u.data[7:4]`, bits
counted from 0 at the net's least significant bit), a constant (`1'b0`), or a
concatenation of single bits, most significant first.

The fan-in and fan-out cone to a depth and the X trace are NetCrux Pro's.
Clock-domain crossings are LintCrux's to answer.

## Reading a document

Every answer is one JSON object with eight members, always present, in this
order:

| Member | Meaning |
|---|---|
| `schema_version` | `1` |
| `tool` | `{"name": "netcrux", "version": ...}` |
| `command` | The command or tool that ran |
| `outcome` | `completed` when there is an answer; otherwise `usage_error`, `input_error` or `engine_error` |
| `engines` | `[{"name": "yosys", "version": ..., "path": ...}]` when Yosys ran; empty for a netlist read from disk |
| `design` | `{"fingerprint": {"scheme": "netcrux-design-sha256/1", "value": ...}}`: the same value means the same design files, top and defines |
| `body` | The answer, or `null` when there is none |
| `diagnostics` | Errors that say why there is no answer, and warnings that qualify one |

**The `outcome` is the authority.** Read `body` only when `outcome` is
`completed`. On anything else, read the `error` diagnostics: their `message`
says what went wrong (for a Yosys failure, Yosys's own error line) and `fix`,
when present, what to do. The tool result's `isError` is true exactly when
there is no answer.

| Outcome | Exit code | Typical cause |
|---|---|---|
| `completed` | 0 | An answer; check the warnings |
| `usage_error` | 64 | A bad or missing input, a path outside the root, a NetCrux project file |
| `input_error` | 65 | No such file, a netlist that is not one, no such top module, no cell or net by that name |
| `engine_error` | 3 | Yosys is missing, stopped with an error, or timed out |

**Truncated lists say so.** `search` carries `total`, `returned` and
`truncated`; narrow the query or raise `limit` to see more. `info` and
`connections` carry `truncated` when their limit cut the list.

The schemas of every body are in this repository under `spec/mcp/schemas/`,
with a golden document for every outcome each tool can produce under
`spec/mcp/goldens/`.

## Citing

Every cell, net and port carries a `location`:

```json
{
  "file": "/work/build/top.json",
  "net": "top.u_core.alu_y",
  "module": "alu",
  "src": {"file": "/work/rtl/alu.sv", "line": 42, "column": 10},
  "link": "netcrux://open?file=%2Fwork%2Fbuild%2Ftop.json&net=top.u_core.alu_y"
}
```

**Cite every finding with its `link`**, which opens NetCrux on that design
with the cell or net selected and framed, so the person reviewing your answer
can check it in one click, **or with its `src` line**, the source line the
netlist records for it (for Amaranth, the Python line). Copy links from the
answer; do not build them.

`link` is `null` when NetCrux could not open it: the design was given as a
filelist or a manifest (a link names one design file), the schematic does not
draw the element (a net nothing is connected to), or the netlist marks no top
module. The location still names the file and the element, and `src` the
source line. A module found by `search` is located at its declaration, a
source location with no link.

Report what the document says. Every answer is the elaborated design's, as
Yosys wrote it; NetCrux adds no interpretation of its own.
