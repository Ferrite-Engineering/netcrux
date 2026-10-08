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

## The Annotations tab {#panel}

`View → Show Annotations Panel` opens the **Annotations** tab in the right dock, beside the Inspector, so the schematic stays in view. Choosing it again while the tab is on screen closes it; so does the **×** on the tab. Your annotations are kept either way.

Each row leads with the annotation's title, or the first line of its body when it has no title, then names the element (cell, port, boundary port, net or scope, and its ID) and the author. The rest of the body renders below as formatted Markdown.

- **Go to the element.** Click a row, or press Enter or Space on it, to select its element on the schematic and bring it into view. When the element is in another scope, NetCrux opens that scope first. If the design no longer has the element (it was renamed or removed), NetCrux says so instead.
- **Edit or delete.** Use the **…** menu on a row to **Edit Annotation…** (the dialog shows the title and the raw Markdown) or **Delete Annotation**. Clearing the title leaves an untitled annotation.
- **With a screen reader.** Tab to a row; it reads the title, the element, the author and the body.

## Badges on the schematic {#badges}

An annotated cell carries a small round note badge on its top-right corner. An annotated pin carries one beside the pin, and an annotated boundary port one on the port's corner. Badges show when you are zoomed in far enough to see cell symbols, and are hidden in the zoomed-out overview, where cells are drawn as coloured blocks. A note on a net or a whole scope has no badge; find it in the Annotations tab.

Click a badge, or right-click the annotated element and choose **Show Annotation**, to open the Annotations tab (or bring it to the front) scrolled to that element's note, which flashes briefly.

## Each design keeps its own {#per-design}

Annotations belong to the design in the tab where you made them. Switch to another tab and the Annotations tab lists that design's annotations instead, and a cell's badge only appears on the design it was annotated in. NetCrux also records which module an element was annotated in, so a note on one module's `u_fifo` does not badge another module's `u_fifo`.

!!! note "They travel with the session"

    Annotations are saved in the `.netcrux` session file, which holds one tab's design. Save the session (++cmd+s++ / ++ctrl+s++) to keep them; opening the session brings them back. See [Sources, projects & sessions](files-and-projects.md#sessions) and the [session file format](reference/session-format.md#annotations).
