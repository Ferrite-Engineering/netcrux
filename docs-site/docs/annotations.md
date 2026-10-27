# Annotations

Debugging a design is a process of building up context. Annotations let you pin that context to the schematic: a note on a cell, wire, port or scope that records what you found there, saved with the session and listed in one place so you can jump straight back to it.

From NetCrux 1.1, annotations are free in every edition, Open Core included. Annotations written during a collaborative session are shared with everyone in it; see [Notes in a session](collaboration.md#notes).

## What an annotation holds {#what}

An annotation is pinned to one element and has two parts, both optional, though at least one must be filled in:

- **Title**: one line, shown as the annotation's row in the Annotations tab. Use it for a short label you will recognise in a list, such as "FIFO full flag".
- **Body**: Markdown, for the longer note: a heading, a list of what you ruled out, a link to an issue. Write "the full flag rises one cycle late when both pointers wrap" here.

An optional **Author** records who wrote it.

## Add an annotation {#add}

1. **Open the dialog.**

    Right-click a cell, wire or port and choose **Add Annotation…**, or select it and use `Tools → Add Annotation…`. With nothing selected, the command palette's **Add Annotation…** first asks you to pick an element in the current scope.

2. **Fill in a title, a body, or both.**

    The **Title** field sits above **Body (markdown)**. A title alone is enough for a quick marker; a body alone is fine for a note, and its first line then stands in for the title. **Save** with both empty is refused, and the dialog says "Add a title or a body."

### In the Inspector, from NetCrux 1.2 {#inspector}

From NetCrux 1.2 there is no annotation dialog: annotations are written and edited in the [Inspector](interface.md#inspector), beside the schematic.

- **Add.** **Add Annotation…** (from the context menu, `Tools → Add Annotation…` or the command palette) selects the element and opens the Inspector on it with a **New annotation** form, the cursor in **Title**. The Inspector's **Annotations** section on any element also has an **Add Annotation** button. Press **Add Annotation** under the form, or Enter in the Title field, to save; **Discard** drops it. With both fields empty the form says "Add a title or a body."
- **Edit.** Each of your annotations on the selected element is its own form in the Inspector. Change it and press **Save**, or **Revert** to go back to what is stored. The Annotations tab's **Edit Annotation…** selects the element and puts the cursor in that annotation's title.
- **Unsaved changes stay put.** While a form has unsaved changes the Inspector keeps showing that element even if you select something else, and says "Apply or revert the changes to Cell *name* to follow the selection." Switching dock tabs keeps what you typed. Escape returns to the schematic without losing it.
- **In a session.** A note another participant wrote shows as read-only rows. The room sees that you are writing a note from your first keystroke until you save or discard it.

## The Annotations tab {#panel}

`View → Show Annotations Panel` opens the **Annotations** tab in the right dock, beside the Inspector, so the schematic stays in view. Choosing it again while the tab is on screen closes it; so does the **×** on the tab. Your annotations are kept either way.

Each row leads with the annotation's title, or the first line of its body when it has no title, then names the element (cell, port, boundary port, net or scope, and its ID) and the author. The rest of the body renders below as formatted Markdown.

- **Go to the element.** Click a row, or press Enter or Space on it, to select its element on the schematic and bring it into view. When the element is in another scope, NetCrux opens that scope first. If the design no longer has the element (it was renamed or removed), NetCrux says so instead.
- **Edit or delete.** Use the **…** menu on a row to **Edit Annotation…** (the dialog shows the title and the raw Markdown; from NetCrux 1.2 the Inspector does, see [above](#inspector)) or **Delete Annotation**. Clearing the title leaves an untitled annotation.
- **With a screen reader.** Tab to a row; it reads the title, the element, the author and the body.

## Badges on the schematic {#badges}

An annotated cell carries a small round note badge on its top-right corner. An annotated pin carries one beside the pin, and an annotated boundary port one on the port's corner. Badges show when you are zoomed in far enough to see cell symbols, and are hidden in the zoomed-out overview, where cells are drawn as coloured blocks. A note on a net or a whole scope has no badge; find it in the Annotations tab.

Click a badge, or right-click the annotated element and choose **Show Annotation**, to open the Annotations tab (or bring it to the front) scrolled to that element's note, which flashes briefly.

## Callouts on the schematic, from NetCrux 1.2 {#callouts}

From NetCrux 1.2, NetCrux draws each annotation on the schematic itself, beside its element, the way WaveCrux draws notes on a waveform. Annotation callouts are free in every edition, like the annotations, the Annotations tab and the badges.

Callouts are on by default. Turn them off or on with `View → Show Annotation Callouts`, or **Show Annotation Callouts** in the command palette.

- **What a callout shows.** A small balloon with a line to the element, holding the note's number, its title (or the first line of its body) and the start of the body. Hover over the balloon to read the whole note, or press Enter on it to open the Annotations tab at that note; double-click its text to edit the note in the Inspector. The number is the note's place in the order the notes were written.
- **Where it sits.** A callout on a cell, a pin or a boundary port starts just above the element's top-right corner; one on a net starts above the middle of its wire. Drag the balloon anywhere: the line stays attached to the element, and the note stays on the same element. NetCrux remembers where you put it, in the session file.
- **Fold it to a dot.** Use the fold button on the balloon to reduce it to its numbered dot; click the dot to open it again. A folded note is still listed and still saved.
- **Zoom.** Zoomed in far enough to read cell labels, callouts show their text. Zoomed out to where cells are drawn as plain symbols, each callout is its numbered dot, and clicking a dot opens the note in the Annotations tab. In the zoomed-out overview, where cells are coloured blocks, callouts are hidden.
- **Scope.** Callouts follow the scope on screen. A note on an element inside a child module is drawn when that module is open, and is listed in the Annotations tab under **Outside the current scope** otherwise. A note on a whole scope has no callout.
- **Busy schematics.** At most six callouts open as balloons at once; the rest are drawn as numbered dots.
- **Keyboard.** Tab reaches each callout on the canvas. Enter opens the note in the Annotations tab, and Space folds or unfolds it. A screen reader announces the note's number, its title and its element.
- **In a session.** Everyone in a collaborative session sees the same callouts in the same places. Moving or folding somebody else's note is not offered, as editing it is not.
- **Exports.** Callouts are an on-screen aid: PNG and SVG exports of the schematic do not include them.

## When the design changes, from NetCrux 1.2 {#drift}

From NetCrux 1.2, every edition records what an element is when you annotate it: a cell's type and parameters, a pin's direction and width, a boundary port's direction and width, and what drives a net. When the design is elaborated again (after a source edit, for example), NetCrux compares each note's element with what it recorded:

- **Drifted.** The element is still there but has changed, for example a register's width or a gate's type. The note's row in the Annotations tab is marked **Drifted**, and its callout is drawn in amber with a dashed line and italic text. The note is unchanged; it may simply describe the design as it was, so check whether it still holds. Editing a note's words keeps the record from when it was written, so the mark stays until the element matches again.
- **Missing from this design.** The design no longer has the element (renamed or removed). The Annotations tab lists such notes in their own group at the end. Choosing one says the element is not in this design.

Notes written before NetCrux 1.2 have no record to compare against and are never marked drifted; they gain one the next time you save an edit to them.

## Each design keeps its own {#per-design}

Annotations belong to the design in the tab where you made them. Switch to another tab and the Annotations tab lists that design's annotations instead, and a cell's badge only appears on the design it was annotated in. NetCrux also records which module an element was annotated in, so a note on one module's `u_fifo` does not badge another module's `u_fifo`.

!!! note "They travel with the session"

    Annotations are saved in the `.netcrux` session file, which holds one tab's design. Save the session (++cmd+s++ / ++ctrl+s++) to keep them; opening the session brings them back. See [Sources, projects & sessions](files-and-projects.md#sessions) and the [session file format](reference/session-format.md#annotations).
