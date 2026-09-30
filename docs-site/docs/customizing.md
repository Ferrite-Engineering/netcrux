# Custom cell symbols <span class="tier tier-pro">Pro</span>

NetCrux draws AND, OR, NOT, multiplexer, flip-flop and latch primitives as recognizable gate symbols out of the box, and everything else as a labeled rectangle. With Pro you can give your own modules a custom symbol too — so a hand-built arbiter or a vendor primitive renders as a meaningful shape instead of a generic box, everywhere it appears.

## Open the Symbol Manager {#symbol-manager}

Custom symbols live in the **Custom Cell Symbols** manager, opened with `Tools → Open Custom Cell Symbol Manager…` or the command palette. It lists every symbol in scope, with a **Filter by module type…** field, and is where you create, import, edit and delete them. The canvas context menu offers shortcuts for the right-clicked cell's module: **Create Symbol for This Module**, **Edit Symbol for This Module** and **Remove Symbol for This Module**.

## Create or import a symbol {#create}

1. **Start a new symbol.**

    Click **New Symbol** to begin from scratch, or **Import from SVG…** (also `Tools → Import Symbol from SVG…`) to bring in an existing drawing as the starting point.

2. **Edit the SVG content.**

    The first tab, **SVG Content**, holds the drawing with a live **Preview** beside it — edit the markup and watch the symbol update.

3. **Place the port anchors.**

    The **Port Anchors** tab is where you tell NetCrux where each port attaches. **Add port**, pick a side (**Left**, **Right**, **Top** or **Bottom**) and set its position with the slider, so wires connect to the right point on your shape rather than the bounding box.

4. **Fill in the metadata.**

    The **Metadata** tab binds the symbol to a **Module type** (the module it represents), plus **Author**, **Notes**, and the **Storage scope**: **Project (this project only)** or **User library (all projects)**.

5. **Save.**

    **Save** writes the symbol. If a symbol already exists for that module type, NetCrux says so rather than overwriting it.

### Every SVG is sanitized {#sanitizer}

On import and save, NetCrux runs the SVG through a **sanitizer** that strips `<script>` and `<foreignObject>` elements, `<use>` and `<image>` elements that reference external `http://`, `https://` or `file://` resources, every `on*` event attribute, and `javascript:` URLs, and tells you what it removed. A symbol is artwork, never executable — so a shared symbol library cannot carry active content. Inline `data:` images are kept.

## Project vs. user scope, and shadowing {#scope}

A symbol has a **scope**. Project symbols live in a `.netcrux-symbols/` directory beside the `.netcrux-project` file and travel with it; user symbols live in your personal library (under NetCrux's application-support folder) and follow you across projects. The project scope is available only when the active tab was opened from a `.netcrux-project` — otherwise symbols are saved to the user library.

When both a project and your user library define a symbol for the same module type, the **project symbol wins** — it shadows the user one, so a project can pin its own look without disturbing your defaults. An organization can also distribute symbol packs; see [Org-wide symbol libraries](administration.md#symbols).

## How the schematic repaints {#repaint}

When you save a symbol, the schematic **repaints**: every instance of the matching module type in the current design renders with the new shape immediately, with no reload or re-elaboration. Editing a symbol is a live, iterative loop. Removing a symbol returns its instances to the default rendering.

!!! tip "Recipe"

    The [Make a custom symbol](cookbook-custom-symbol.md) recipe builds one end to end and reuses it across projects.
