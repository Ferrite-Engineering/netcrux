# Bookmarks & annotations <span class="tier tier-pro">Pro</span>

Debugging a design is a process of building up context. Bookmarks and annotations let you pin that context to the schematic, a named marker on an element and a written note about what you found, and save it with the session.

## Bookmark or annotation? {#which}

A **bookmark** marks a place to return to: a named pointer you jump back to from a list. An **annotation** records what you found there: a Markdown note that stays on the element, with a badge on the schematic so you see it when you come back. Use a bookmark for "the FIFO full flag", and an annotation for "the full flag rises one cycle late when both pointers wrap".

## Bookmarks {#bookmarks}

1. **Add a bookmark.**

    Right-click a cell, wire or port and choose **Add Bookmark…**, or select it and use `Tools → Add Bookmark…`. Give it a **Name** and, optionally, a **Note**.

2. **Work from the Bookmarks tab.**

    `View → Show Bookmarks Panel` opens the **Bookmarks** tab in the right dock, beside the Inspector, so the schematic stays in view. Each row shows the bookmark's name, the kind of element it marks (cell, port, boundary port, net or scope) and the element's ID. A row whose bookmark has a note carries a small note marker; hover over the row to read the note in a tooltip. With the keyboard, Tab to a row and a screen reader reads the name, the element and the note.

3. **Go to a bookmark.**

    Click a row, or press Enter or Space on it, to select the element on the schematic. When the element is in another scope, NetCrux opens that scope first and brings the element into view.

4. **Edit or delete.**

    Use the **…** menu on a bookmark's row to **Edit Bookmark…** (rename, change the note) or **Delete Bookmark**.

5. **Close the tab.**

    Click the **×** on the tab, or choose `View → Show Bookmarks Panel` again. Your bookmarks are kept; reopening the tab lists them.

## Annotations {#annotations}

1. **Add an annotation.**

    Right-click an element and choose **Add Annotation…**, or use `Tools → Add Annotation…` with it selected. The **Body** is **Markdown**, so you can write structured notes (a heading, a list of what you ruled out, a link to an issue), and an **Author** is optional.

2. **See which elements are annotated.**

    An annotated cell carries a small round note badge on its top-right corner. An annotated pin carries one beside the pin, and an annotated boundary port one on the port's corner. Badges show when you are zoomed in far enough to see cell symbols, and are hidden in the zoomed-out overview, where cells are drawn as coloured blocks. A note on a net or a whole scope has no badge; find it in the Annotations tab.

3. **Open an element's note.**

    Click the badge, or right-click the annotated element and choose **Show Annotation**. The **Annotations** tab opens in the right dock, or comes to the front, scrolled to that element's note, which flashes briefly.

4. **Browse the Annotations tab.**

    `View → Show Annotations Panel` opens the tab, which lists every annotation in the design and renders each body as formatted Markdown.

5. **Edit or delete.**

    Use the row's menu to **Edit Annotation…** (the dialog shows the raw Markdown) or **Delete Annotation**. Close the tab with its **×**.

## Each design keeps its own {#per-design}

Bookmarks and annotations belong to the design in the tab where you made them. Switch to another tab and the Bookmarks and Annotations tabs list that design's entries instead, and a cell's badge only appears on the design it was annotated in. NetCrux also records which module an element was marked in, so a note on one module's `u_fifo` does not badge another module's `u_fifo`.

!!! note "They travel with the session"

    Bookmarks and annotations are saved in the `.netcrux` session file, which holds one tab's design. Save the session (++cmd+s++ / ++ctrl+s++) to keep them; opening the session brings them back. See [Sources, projects & sessions](files-and-projects.md#sessions).

!!! note "Bookmark colours"

    Bookmarks no longer have a colour. A session saved by an earlier version, with colours on its bookmarks, still opens: the bookmarks load and the colours are dropped.
