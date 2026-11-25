# NetCrux for coding agents

NetCrux reads a hardware design the way Yosys elaborates it and answers
questions about its structure over the Model Context Protocol (MCP), so a
coding agent can ask what a cell is connected to without guessing from source.
Every answer is also a command, with the same output.

## What the server offers

The server is started with `netcrux mcp --root <project directory>`. It speaks
MCP over standard input and output, runs on your machine, writes nothing into
your tree and makes no network call of its own. Every path a tool receives must
be inside `--root` (the working directory when omitted), and so must every file
a `.crux-project` manifest or a `.f` filelist names; a path outside it, a
symbolic link that leads outside it, or a network path is refused and never
opened.

Every tool takes `design`: Verilog, SystemVerilog or VHDL sources and `.f`
filelists, which NetCrux elaborates with the Yosys on `PATH`; or one Yosys JSON
netlist; or one `.crux-project` manifest. An optional `top` names the top
module.

| Tool | What it returns |
|---|---|
| `info` | The top module, the module count, the cells and named nets of each module, and the instances in pre-order |
| `search` | Cells, nets, ports or modules whose name contains the query (or matches a glob): path, module, type, width and location |
| `connections` | For a cell, each pin with its direction and net; for a net, the pins that drive it and the pins it drives. One step, inside the module that holds it |

NetCrux Pro adds two, served by the Pro command in the desktop bundle:

| Tool | What it returns |
|---|---|
| `cone` | The cells that drive a cell or net (`fanin`) or that it drives (`fanout`), with distance and location, nearest first |
| `trace_x` | One driver route back from a net to a structural source of X, why the walk stopped, and why the origin is one |

`trace_x` reads no waveform: what it names is a candidate for where an X comes
from, not a proven cause. Check it against the simulation. Both Pro tools need a
Pro licence, read on every call from `--license-file`, then the
`NETCRUX_LICENSE_FILE` environment variable, then the organisation's
`.crux-policy.json`, and checked offline. Below Pro each answers with a licence
error and runs nothing; the three other tools answer at every tier.

Each tool is also a command, with the same inputs as flags and the same output
with `--json`:

```
netcrux info rtl/top.sv rtl/alu.sv --json
netcrux search build/top.json fifo --kind cell --json
netcrux connections design.crux-project top.u_core.alu_y --json
```

A tool's text is byte for byte what the command writes, so a script and an
agent read the same document.

## Register it with your agent

The `netcrux` command must be on the `PATH` of the program that starts the
server. The instructions below were checked against each host's own
documentation on 2026-11-24; hosts change, so check theirs if a step differs.
To use Pro, replace `netcrux` with the Pro command from the desktop bundle.

=== "Claude Code"

    Add the server for the current project:

    ```
    claude mcp add --transport stdio netcrux -- netcrux mcp --root /path/to/project
    ```

    Everything after `--` is the command that starts the server. By default the
    entry is private to you and the project. To share it with your team, add
    `--scope project`, which writes `.mcp.json` in the project root:

    ```json
    {
      "mcpServers": {
        "netcrux": {
          "command": "netcrux",
          "args": ["mcp", "--root", "${CLAUDE_PROJECT_DIR:-.}"]
        }
      }
    }
    ```

    Claude Code asks each person to approve a project server the first time.
    Run `claude mcp list`, or `/mcp` inside Claude Code, to see that it
    connected.

=== "VS Code"

    With the EDACrux NetCrux extension installed, there is nothing to
    configure. The extension registers the server with the editor for each
    workspace folder you open, with that folder as `--root`, and the editor asks
    you before it first runs. It needs a folder open in a trusted workspace.
    It finds the Pro command or `netcrux` through the extension's executable
    setting, then your `PATH`. Turn registration off with the extension's MCP
    registration setting, both in the editor's Settings under the NetCrux
    extension.

    Without the extension, add the server to `.vscode/mcp.json` in the
    workspace (VS Code's own file uses `servers`, not `mcpServers`):

    ```json
    {
      "servers": {
        "netcrux": {
          "type": "stdio",
          "command": "netcrux",
          "args": ["mcp", "--root", "${workspaceFolder}"]
        }
      }
    }
    ```

    Or run **MCP: Add Server** from the Command Palette and choose a command
    (stdio) server.

=== "Cursor"

    Create `.cursor/mcp.json` in the project (or `mcp.json` in `.cursor` in your
    home folder for every project):

    ```json
    {
      "mcpServers": {
        "netcrux": {
          "type": "stdio",
          "command": "netcrux",
          "args": ["mcp", "--root", "${workspaceFolder}"]
        }
      }
    }
    ```

    Then open **Customize** in the sidebar and confirm the server is enabled.
    If it does not connect, open the Output panel and choose "MCP Logs".

An editor that does not offer the registration API gets the same snippet from
the **Copy NetCrux MCP Server Configuration** command in the Command Palette.

## When an agent should call it

- The question is about structure: what a cell is connected to, what drives a
  net, where an instance sits in the hierarchy, what a module contains.
- The source cannot answer it, because generate blocks, parameters, `include`
  files or another language's generator (Amaranth, Chisel) decide what the
  design is. NetCrux answers from the elaborated design.

The agent should start with `info`, then `search` to find the full name of each
cell, net, port or module, then `connections`. Names are hierarchical,
dot-separated and rooted at the top module (`top.u_core.alu_y`), as `search`
returns them. Clock-domain crossings are LintCrux's to answer.

## Read the outcome first

Every answer is one JSON document. Its `outcome` is the authority: read the
`body` only when it is `completed`; on anything else, the error diagnostics say
what went wrong (for a Yosys failure, Yosys's own error line) and what to do.
The design fingerprint in the document tells two answers about the same design
apart from answers about different ones. A list that was cut says so
(`truncated`); narrow the query or raise `limit`.

## Cite with the link

Every cell, net and port carries a `location` with a `link` and, where the
netlist records it, the `src` line that produced it:

```
netcrux://open?file=%2Fwork%2Fbuild%2Ftop.json&net=top.u_core.alu_y
```

Tell the agent to cite every finding with its link. The link opens NetCrux on
that design with the cell or net selected and framed, so you can check the
answer in one click. The agent should copy links from the answer rather than
build them; where a link is `null`, it cites the `src` line instead. The forms
are described on the [agent link convention](https://edacrux.app/agent-links)
page.

An answer is the elaborated design's, as Yosys wrote it. NetCrux adds no
interpretation of its own.
