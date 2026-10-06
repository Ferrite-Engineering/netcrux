# Custom cell symbols <span class="tier tier-pro">Pro</span>

NetCrux draws AND, OR, NOT, multiplexer, flip-flop and latch primitives as recognizable gate symbols out of the box, and everything else as a labeled rectangle. With Pro you can give your own modules a custom symbol too — so a hand-built arbiter or a vendor primitive renders as a meaningful shape instead of a generic box, everywhere it appears.

## Open the Symbol Manager {#symbol-manager}

Custom symbols live in the **Custom Cell Symbols** manager, opened with `Tools → Open Custom Cell Symbol Manager…` or the command palette. It lists every symbol in scope, with a **Filter by module type…** field, and is where you create, import, edit and delete them. The canvas context menu offers shortcuts for the right-clicked cell's module: **Create Symbol for This Module**, **Edit Symbol for This Module** and **Remove Symbol for This Module**.

## Create or import a symbol {#create}

1. **Start a new symbol.**

    Click **New Symbol** to begin from scratch, or **Import from SVG…** (also `Tools → Import Symbol from SVG…`) to bring in an existing drawing as the starting point.

2. **Edit the SVG content.**

    The first tab, **SVG Content**, holds the drawing with a live **Preview** beside it — edit the markup and watch the symbol update. To start from a drawing on disk, click **Load from file…** above the editor and pick an `.svg` file: it runs through the [sanitizer](#sanitizer), replaces the content (after asking, if you have edited it), and keeps the module type the editor already has.

3. **Place the port anchors.**

    The **Port Anchors** tab is where you tell NetCrux where each port attaches. **Add port**, type the port's name exactly as the module declares it, pick a side (**Left**, **Right**, **Top** or **Bottom**) and set its position with the sliders, so wires connect to the right point on your shape rather than the bounding box. See [How a symbol is sized](#sizing) for how an anchor becomes a pin.

4. **Fill in the metadata.**

    The **Metadata** tab binds the symbol to a **Module type** (the module it represents), plus **Author**, **Notes**, and the **Storage scope**: **Project (this project only)** or **User library (all projects)**.

5. **Save.**

    **Save** writes the symbol. If a symbol already exists for that module type, NetCrux says so rather than overwriting it.

### Every SVG is sanitized {#sanitizer}

On import and save, NetCrux runs the SVG through a **sanitizer** that strips `<script>` and `<foreignObject>` elements, `<use>` and `<image>` elements that reference external `http://`, `https://` or `file://` resources, every `on*` event attribute, and `javascript:` URLs, and tells you what it removed. A symbol is artwork, never executable — so a shared symbol library cannot carry active content. Inline `data:` images are kept.

## Project vs. user scope, and shadowing {#scope}

A symbol has a **scope**. Project symbols live in a `.netcrux-symbols/` directory beside the `.netcrux-project` file and travel with it; user symbols live in your personal library (under NetCrux's application-support folder) and follow you across projects. The project scope is available only when the active tab was opened from a `.netcrux-project` — otherwise symbols are saved to the user library.

When both a project and your user library define a symbol for the same module type, the **project symbol wins** — it shadows the user one, so a project can pin its own look without disturbing your defaults. An organization can also distribute symbol packs; see [Org-wide symbol libraries](administration.md#symbols).

## How a symbol is sized, labelled and pinned {#sizing}

A cell drawn with a custom symbol is laid out in the symbol's shape, so the drawing fills the cell with no empty bands around it and the wires meet the drawing's edges.

- **Shape.** The cell takes the aspect ratio of the drawing: the SVG's `viewBox`, or its `width` and `height` when it has no `viewBox`. Its height is enough for the busier of the left and right sides at 10 units per pin (the same room an ordinary cell gives its pins), and its width follows from the aspect ratio. A symbol with pins on the top or bottom also gets enough width for them. Very thin or very wide drawings are held between 1:5 and 5:1.
- **Pins.** Each port whose name matches an anchor's port name sits on that anchor's side, at the anchor's position along that side: the vertical position for **Left** and **Right**, the horizontal one for **Top** and **Bottom**. The other coordinate is ignored, because the pin is always on the edge. Ports that ask for the same spot, or come closer than 10 units, are spread apart around it in declaration order, and no pin sits on a corner. A port with no anchor keeps its usual side (inputs left, outputs right), spaced evenly along it.
- **Pin names.** At full detail, each pin that an anchor names exactly is labelled with its port name, in small text just inside the drawing beside the pin. An anchor whose name matches no port of the module gets no label and no pin; NetCrux never matches anchors by order or position. A bus shows its port name only.
- **Instance name.** The cell's instance name is drawn outside the drawing: centred below it, or above it when another cell or module port sits right below. It never covers the artwork.

Cells without a custom symbol are laid out and labelled exactly as before.

## How the schematic updates {#repaint}

When you save a symbol, the schematic **updates**: every instance of the matching module type in the current scope is laid out again in the new shape and renders with the new drawing, with no reload or re-elaboration. Editing a symbol is a live, iterative loop. Removing a symbol returns its instances to the default rendering and layout.

!!! tip "Recipe"

    The [Make a custom symbol](cookbook-custom-symbol.md) recipe builds one end to end and reuses it across projects.
