# Share a schematic in a review

You found the thing. Now you need someone else to see it. This recipe picks the right artifact for the reader.

| | |
|---|---|
| **Goal** | Show a reviewer exactly what you found in the schematic. |
| **Time** | About 5 minutes |
| **Tier** | Open Core. |
| **You will use** | [Export](../files-and-projects.md#export), the [trace overlay](../tracing.md#fanin-fanout) and [sessions](../files-and-projects.md#sessions). |

## Pick the right artifact {#pick}

| You want to… | Use |
| --- | --- |
| Paste a picture into a PR comment or chat | **PNG** — ++cmd+shift+e++ / ++ctrl+shift+e++ |
| Put a diagram in a document or slide | **SVG** — ++alt+e++ |
| Hand the netlist to another tool | **JSON** — ++alt+j++ |
| Let a colleague navigate it themselves | **Session** — ++cmd+s++ / ++ctrl+s++ |

## The picture route {#picture}

1. **Get the view right.**

    Navigate to the scope, set the zoom, select the element, and apply the trace overlay (++bracket-left++ or ++bracket-right++) so the relevant subgraph is highlighted and everything else is dimmed.

2. **Export PNG.**

    ++cmd+shift+e++ / ++ctrl+shift+e++ — the export captures the visible canvas *as drawn*, overlay and dimming included, which is exactly what makes the point. Only the part of the scope inside the canvas is in the image.

3. **Or export SVG.**

    ++alt+e++ when the reader will zoom in. SVG carries the whole scope's geometry but not the overlay.

All three exporters cover the **current scope only**.

## The session route {#session}

++cmd+s++ / ++ctrl+s++ writes a `.netcrux` file recording the source list, top module, scope path, zoom, pan, selection, overlay mode and expanded scopes. Your colleague opens it with `File → Open Session…` (or `netcrux --session <file>`) and keeps navigating from your design, which a screenshot does not allow.

They land where you were: the same scope, expanded rows, selection, zoom and pan.

A session references source *paths*, so it only works for someone who can see the same files. For a reader who cannot, export JSON instead: it carries the netlist slice for the scope with no dependency on the original RTL.

## Don't forget {#privacy}

Sessions and exports contain your design. Treat them with the same care as the RTL itself.
