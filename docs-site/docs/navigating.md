# Navigating the schematic

A real design is ten levels deep. NetCrux is built so you can move through that hierarchy with the keyboard and never lose your place — push in, pop out, jump to the top, and search the whole design from one dialog.

## Push in and pop out {#push-pop}

A NetCrux tab always shows exactly one **scope** — one module instance's interior. To descend into a submodule instance, **double-click** it on the canvas (or select it and press ++enter++), or click its row in the [hierarchy tree](interface.md#hierarchy) (++cmd+1++ / ++ctrl+1++) to jump straight to that scope — from the keyboard, move to the row with the arrow keys and press ++enter++ (see [Hierarchy tree keys](keyboard-mouse.md#hierarchy-keys)). To come back up one level, use **Pop Out of Scope** (++cmd+bracket-left++ / ++ctrl+bracket-left++), the toolbar's **Pop Out of Scope** button, ++backspace++ on the focused canvas, or double-click empty canvas. Pushing in, popping out and jumping to the top clear the selection and any trace overlay.

| Action | Input | Effect |
| --- | --- | --- |
| Push into an instance | double-click it on the canvas | The canvas lays out that instance's module body. |
| Go to any scope | click it in the hierarchy tree | The canvas shows that scope. |
| Pop out | ++cmd+bracket-left++ / ++ctrl+bracket-left++, ++backspace++, or double-click empty canvas | Back to the parent scope. |
| Jump to top | ++cmd+home++ / ++ctrl+home++ | Straight to the design root. |
| Jump to any level | click a breadcrumb | Every crumb in the breadcrumb bar is clickable. |

## The breadcrumb and Jump to Top {#breadcrumb}

The breadcrumb bar across the top of the canvas shows your full scope path — for example `top › cpu › alu`. Click any crumb to jump straight to that level. To return to the very top of the hierarchy in one move, use **Jump to Top** (++cmd+home++ / ++ctrl+home++) or the toolbar button of the same name.

A scope path is dot-separated and starts at the design root — `top.cpu.alu`. This is the same canonical form NetCrux uses on the wire for [cross-probe](integrations/cxp.md#path-formats), and **Copy Path** on the canvas context menu puts an element's full path on the clipboard in that form.

## Zoom and pan {#zoom-pan}

Zoom with the keyboard, using **Zoom In** (++cmd+equal++ / ++ctrl+equal++, or ++cmd+plus++ / ++ctrl+plus++), **Zoom Out** (++cmd+minus++ / ++ctrl+minus++), each a 1.25× step, and **Zoom to Fit** (++cmd+0++ / ++ctrl+0++), or with the mouse: ++cmd++ / ++ctrl++ + scroll wheel zooms around the pointer, and a pinch zooms on a trackpad. Pan by dragging, with the middle mouse button, the scroll wheel or a two-finger trackpad scroll, or the arrow keys. The toolbar carries matching **Zoom In**, **Zoom Out**, **Zoom to Fit** and **Zoom to Selection** buttons, and vertical and horizontal scrollbars flank the canvas so an off-screen cell is always reachable without a gesture. Every step zoom, from the keys, the toolbar or the menu, keeps the point at the centre of the view where it is. The canvas fits itself to the scope whenever a new scope lays out.

Zoom In takes `=` and `+` with the modifier, so it works on every keyboard layout: on a US layout `=` is the unshifted key, and on Swedish, German and most other European layouts `+` has its own key. The numpad ++plus++, ++minus++ and ++0++ work with the modifier too.

The bare ++equal++ (or ++plus++), ++minus++ and ++0++ keys zoom and fit while the pointer is over the schematic. The canvas takes keyboard focus when the pointer moves onto it, and when you click it with any button, so after working in a panel you only have to move the pointer back. A text field you are typing in, such as the hierarchy filter, keeps focus when the pointer passes over the schematic; click the canvas, or use the modifier forms, which work from anywhere in the window. The full list of canvas keys and gestures is in the [Keyboard & mouse reference](keyboard-mouse.md#canvas-keys).

## Zoom to Selection {#zoom-to-selection}

**Zoom to Selection** (++z++, the toolbar button beside **Zoom to Fit**, the `Navigate` menu or the command palette) frames what you have selected. With several elements selected it frames all of them, and while a [fanin or fanout trace](tracing.md#fanin-fanout) is showing it frames every cell and wire the trace highlights, so after tracing from a pin one key shows the whole trace. A single cell lands at a readable zoom rather than filling the window. It is greyed out until something is selected.

It is also the way back to an element after panning away: choose a cell in [Search](#search) or in the filtered [hierarchy tree](interface.md#hierarchy), look around, then press ++z++ to return to it.

## Three-band level-of-detail {#lod}

As you zoom out, NetCrux drops detail in three bands so a large module stays readable: at zoom 0.75 and above you see full symbols with port and wire labels; between 0.25 and 0.75 labels drop out and wires simplify; below 0.25 cells collapse to solid blocks colored by cell family. You do not configure this — it tracks the zoom level automatically, and it is what keeps the frame rate flat on large scopes.

## Search Design {#search}

The **Search Design** dialog (++cmd+f++ / ++ctrl+f++, or the toolbar's **Search…** button) searches instance, cell and net names in every scope of the design, not just the one on the canvas. It needs a laid-out design, so it is disabled until elaboration finishes.

1. **Open it and type a query.**

    Press ++cmd+f++ / ++ctrl+f++ and type. Each result shows its name, its kind (**Instance**, **Cell** or **Net**) and the scope that owns it. The list is capped at 500 results.

2. **Choose the match mode.**

    The mode chips pick how the query matches, all case-insensitively. The dialog opens in **Substring** mode each time.

    | Mode | Behaviour |
    | --- | --- |
    | **Substring** | The name contains the query. |
    | **Glob** | `*` and `?` wildcards, matched against the whole name — `*_valid` finds every name ending in `_valid`. |
    | **Regex** | A regular expression, matched anywhere in the name. |

3. **Jump to a result.**

    Choosing a result (click it, or ++arrow-up++ / ++arrow-down++ then ++enter++) navigates to the owning scope, clears any trace overlay, and centers the canvas on the result. An instance or cell is selected. A net has no body of its own, so NetCrux selects the cell that drives it; an undriven net — a module input or a constant — leaves nothing selected.

To find a cell without opening a dialog, type part of its name or its type in the hierarchy tree's **Filter scopes and cells…** field: matching cells are listed under their scope, and choosing one does the same as choosing a Search result. See [Hierarchy tree](interface.md#hierarchy).

## The command palette {#palette}

The **command palette** (++cmd+shift+p++ / ++ctrl+shift+p++) is a fuzzy-filtered list of every action that can run right now. If you can name it, you can run it from the palette without hunting through menus — and the palette shows each action's keyboard shortcut and tier, so it doubles as a way to learn the bindings.

## Panel toggles {#panels}

Three shortcuts toggle the surrounding panels so you can give the canvas the whole window when you need it: **Toggle Hierarchy Tree** (++cmd+1++ / ++ctrl+1++), **Toggle Inspector** (++cmd+2++ / ++ctrl+2++), and **Tab Diagnostics** (++cmd+3++ / ++ctrl+3++). **Show Cross-Probe Panel** (++cmd+shift+x++ / ++ctrl+shift+x++) opens the cross-probe panel beside the inspector. A collapsed panel leaves a slim strip of its tab icons along the window edge; click one to bring the panel back.

!!! tip "Rebind anything"

    Every shortcut on this page except the fixed canvas keys is editable in `Settings → Keyboard Shortcuts`. View the current bindings, change any of them, reset to defaults, and import or export your keymap. See [Customizing shortcuts](keyboard-mouse.md#customizing).

!!! note "Next steps"

    Once you can move around the design, learn to [trace signals](tracing.md) through it.
