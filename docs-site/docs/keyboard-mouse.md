# Keyboard & mouse reference

NetCrux is built to be driven without the mouse: every command carries a menu, a label and — for the common ones — a default key binding you can change. This page is the single-screen reference for the default bindings, the keys the schematic canvas handles directly, and the pointer gestures on the canvas. The platform modifier is ++cmd++ on macOS and ++ctrl++ on Linux and Windows; bindings below are written macOS first.

## Keyboard shortcuts {#shortcuts}

These are the default bindings that ship with NetCrux. Every one of them is rebindable in `Settings → Keyboard Shortcuts`, and every command is also reachable from the menu bar and — when it can run — the command palette. The **Menu** column is where the command lives; `NetCrux` is the application menu on macOS (on Linux and Windows those commands sit at the bottom of `File`).

| Shortcut | Action | Menu |
|---|---|---|
| ++cmd+o++ / ++ctrl+o++ | Open Project… | File |
| ++cmd+shift+o++ / ++ctrl+shift+o++ | Open Source Files… | File |
| ++cmd+l++ / ++ctrl+l++ | Open Session… | File |
| ++cmd+i++ / ++ctrl+i++ | Import Vivado Filelist… | File |
| ++cmd+s++ / ++ctrl+s++ | Save Session As… | File |
| ++cmd+shift+e++ / ++ctrl+shift+e++ | Export as PNG… | File |
| ++alt+e++ | Export as SVG… | File |
| ++alt+j++ | Export as JSON… | File |
| ++cmd+w++ / ++ctrl+w++ | Close Tab | File |
| ++cmd+shift+w++ / ++ctrl+shift+w++ | Close Project | File |
| ++cmd+comma++ / ++ctrl+comma++ | Settings… | NetCrux |
| ++cmd+q++ / ++ctrl+q++ | Quit NetCrux — **Exit** on Linux and Windows | NetCrux (File on Linux and Windows) |
| ++cmd+shift+p++ / ++ctrl+shift+p++ | Command Palette… | View |
| ++cmd+equal++ or ++cmd+plus++ / ++ctrl+equal++ or ++ctrl+plus++ | Zoom In | View |
| ++cmd+minus++ / ++ctrl+minus++ | Zoom Out | View |
| ++cmd+0++ / ++ctrl+0++ | Zoom to Fit | View |
| ++cmd+1++ / ++ctrl+1++ | Toggle Hierarchy Tree | View |
| ++cmd+2++ / ++ctrl+2++ | Toggle Inspector | View |
| ++cmd+shift+x++ / ++ctrl+shift+x++ | Show Cross-Probe Panel | View |
| ++cmd+backslash++ / ++ctrl+backslash++ | Split Pane Right | View |
| ++ctrl+tab++ | Next Tab | View |
| ++ctrl+shift+tab++ | Previous Tab | View |
| ++cmd+shift+k++ / ++ctrl+shift+k++ | Toggle Theme | View |
| ++cmd+home++ / ++ctrl+home++ | Jump to Top | Navigate |
| ++cmd+bracket-left++ / ++ctrl+bracket-left++ | Pop Out of Scope | Navigate |
| ++bracket-left++ | Show Fanin | Navigate |
| ++bracket-right++ | Show Fanout | Navigate |
| ++z++ | Zoom to Selection | Navigate |
| ++escape++ | Clear Selection / Overlay | Navigate |
| ++cmd+f++ / ++ctrl+f++ | Search… | Search |
| ++cmd+shift+i++ / ++ctrl+shift+i++ | Tab Diagnostics… (reveal the panel) | Tools |
| ++cmd+3++ / ++ctrl+3++ | Tab Diagnostics (toggle the panel) | Tools |
| ++cmd+shift+m++ / ++ctrl+shift+m++ | App Diagnostics… | Tools |
| ++f1++ | About NetCrux | Help (NetCrux on macOS) |

Tab cycling uses ++ctrl++ on every platform, macOS included: ++cmd+tab++ is the system app switcher.

Zoom In answers to the modifier with `=` and with `+`, so it works on every keyboard layout: on a US layout `=` is the unshifted key, and on Swedish, German and most other European layouts `+` has its own key. ++cmd+shift+equal++ / ++ctrl+shift+equal++ and the numpad forms (numpad ++plus++, numpad ++minus++ and numpad ++0++ with the modifier) work as well. The extra forms follow the default binding: once you rebind Zoom In, Zoom Out or Zoom to Fit, only the key you chose triggers it. The menu shows the `=` form.

**Zoom to Selection** (++z++) frames the selected elements and, while a fanin or fanout trace is showing, every cell and wire the trace highlights. On macOS the menu bar shows no key beside it, or beside **Show Fanin** and **Show Fanout**: the macOS menu bar only displays keys that carry a modifier. The keys still work, and the command palette and the toolbar tooltip show them.

**Toggle Theme** switches to the built-in preset of the opposite brightness: from any dark preset to **Crux Light**, and from Crux Light to **Crux Dark**. See [Appearance & themes](appearance-and-themes.md#mode).

!!! note "The two bracket bindings"

    The ++bracket-left++ pairing is deliberate. A bare ++bracket-left++ shows the fanin of the current selection; ++cmd+bracket-left++ / ++ctrl+bracket-left++ pops out of the current hierarchy scope. The two live on the same key because they are the same mental direction — backwards, toward the driver or toward the parent.

!!! note "Actions without a default binding"

    A number of actions ship with no default key: **Close Pane**, **Focus Other Pane** and **Move Tab to Other Pane**; **New Workspace**, **Open Workspace…**, **Save Workspace As…** and **Reset Workspace…**; **Documentation**, **Check for Updates** and **Submit Issue…**; **Share Session…**, **Join Session…** and **Leave Session**; and every Pro action — cone of influence, X-Trace, the RTL source pane, the netlist diff (including **Next Diff** and **Previous Diff**), custom symbols, FSM, CDC, reset-domain and switching-activity analysis. All of them are reachable from the menu bar and the command palette, Pro actions also from the schematic context menu, and any of them can be given a binding of your own in `Settings → Keyboard Shortcuts`. The command palette opener also has a menu entry, so unbinding its key cannot lock you out of it.

## Schematic canvas keys {#canvas-keys}

The canvas handles a small set of keys directly whenever it has keyboard focus. It takes keyboard focus when the pointer moves onto it and when you click it with any button, so these keys work whenever the pointer is over the schematic. Moving the pointer onto the canvas never takes focus from a text field you are typing in, such as the hierarchy filter, or from an open menu; click the canvas to move focus there. These are separate from the rebindable set above: they are part of the canvas itself and do not appear in `Settings → Keyboard Shortcuts`.

| Key | Action |
|---|---|
| ++arrow-left++ ++arrow-right++ ++arrow-up++ ++arrow-down++ | Pan by a fixed step. |
| ++plus++ / ++equal++ / numpad ++plus++ | Zoom in around the center of the view. |
| ++minus++ / numpad ++minus++ | Zoom out around the center of the view. |
| ++0++ / numpad ++0++ | Fit the scope to the view. |
| ++alt+arrow-down++ / ++alt+arrow-up++ | Select the next / previous cell or module port, top to bottom then left to right — what a click does. |
| ++alt+arrow-right++ / ++alt+arrow-left++ | Step through the pins of that cell, each followed by the net on it (on a module port, its net). A net shared by two pins is visited once. |
| ++shift++ with either of the above | Add to the selection instead of replacing it — what a shift-click does. |
| ++enter++ | Push into the selected instance — what a double-click does. |
| ++shift+f10++ / ++menu++ | Open the context menu for the selected element: Copy Path, the traces, Find in Hierarchy, and in Pro the cross-probe and analysis entries. |
| ++backspace++ | Pop out of the scope, clearing the selection and trace overlay. |
| ++cmd+bracket-left++ / ++ctrl+bracket-left++ | Pop out of the scope. |
| ++escape++ | Clear the selection, the trace overlay, and a selected CDC or reset crossing, in one press. |

A screen reader announces each element the keyboard selects — a cell with its type, a module port, a pin with its cell, or a net by name — so the selection can be followed without seeing the canvas.

## Hierarchy tree keys {#hierarchy-keys}

The Hierarchy tree is a single ++tab++ stop: ++tab++ lands on the selected scope (or on the row you last moved to), and the arrow keys move within the tree. The expand arrows beside each row are for the pointer; the keys below do the same.

| Key | Action |
|---|---|
| ++arrow-down++ / ++arrow-up++ | Move to the next / previous visible row. |
| ++home++ / ++end++ | Move to the first / last row. |
| ++arrow-right++ | Expand the row; on a row that is already expanded, move to its first child. |
| ++arrow-left++ | Collapse the row; on a collapsed or leaf row, move to its parent. |
| ++enter++ / ++space++ | Select the scope, which the schematic canvas then shows. On a cell row, select the cell and show it on the canvas; on a **Show more** row, list the next page of cells. |

A screen reader reads each scope row as its scope and cell count, with whether it is expanded or collapsed and whether it is the selected scope, and each cell row as the cell's name and type.

## Panels {#panels}

| Key | Action |
|---|---|
| ++f6++ / ++shift+f6++ | Move to the next / previous region: the toolbar, the Hierarchy, the schematic, the Inspector, the bottom panel, and the statistics strip with the status bar. |
| ++cmd+shift++ / ++ctrl+shift++ + an arrow key | With focus inside the Hierarchy, the Inspector or the bottom panel, resize that panel: the arrow pointing toward the schematic grows it, the opposite arrow shrinks it. The new size is kept, as if you had dragged the divider. |

## Mouse & trackpad {#pointer}

Pointer gestures on the schematic canvas cover navigation and selection. Selection is modal in the usual way: a plain click replaces the selection, modifiers extend or toggle it.

| Gesture | Action |
|---|---|
| ++cmd++ / ++ctrl++ + scroll wheel | Zoom around the pointer. |
| Moving the pointer onto the canvas | Give the canvas keyboard focus, so the canvas keys work, unless a text field or a menu holds focus. |
| Scroll wheel or two-finger trackpad scroll | Pan. |
| Middle-mouse drag | Pan. |
| Left-click drag on the canvas | Pan. |
| Left-click an element | Select it. Clicking empty canvas clears the selection. |
| Left-click an annotation badge (free from NetCrux 1.1) | Select the annotated element and open the **Annotations** tab at its note. The keyboard route is the element's context menu: **Show Annotation**. |
| ++shift++ + click | Add to the selection. |
| ++cmd++ / ++ctrl++ + click | Toggle an element in or out of the selection. |
| Right-click (secondary tap) | Make the element under the pointer the primary selection and open the context menu. |
| Double-click a submodule instance | Push into that instance's scope. |
| Double-click empty canvas | Pop out to the parent scope. |
| Pinch / two-finger scale | Zoom. |

## Customizing shortcuts {#customizing}

Open **Settings** (++cmd+comma++ / ++ctrl+comma++) and select the **Keyboard Shortcuts** category. Every action is listed with its current binding. From there you can:

- **Start from a preset.** The **Preset** chooser loads a complete key map in one step — **NetCrux (Default)** ships today — and reads **Custom** once you hand-edit any binding.
- **Change a shortcut** with the pencil button, then type the new keys (++escape++ cancels).
- **Remove a shortcut**, leaving the action reachable from the menus and the palette.
- **Reset to default** for one action.
- **Reset all** bindings at once, behind a confirmation dialog.
- **Import…** and **Export…** the keymap as a JSON file (default name `netcrux.crux-keymap.json`, schema id `netcrux.keymap`) to share your bindings.

The list is keyboard-driven too: ++arrow-up++ and ++arrow-down++ move between shortcuts, ++enter++ changes the selected one, ++delete++ removes it and ++shift+delete++ restores its default.

Conflicts are detected as you type: a binding that collides shows **Also used by…**, the one that wins says **Takes precedence over…**, and the one that loses says **Won't fire — shadowed by…**, so you never end up with a silently dead key.

!!! note "Next steps"

    For what each surface is called and where it lives, see [The interface](interface.md). For how the canvas keys fit into scope navigation, see [Navigating the schematic](navigating.md).
