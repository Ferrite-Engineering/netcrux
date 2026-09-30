# Bookmarks & annotations <span class="tier tier-pro">Pro</span>

Debugging a design is a process of building up context. Bookmarks and annotations let you pin that context to the schematic — a named marker on an element, and a written note about what you found — and save it with the session.

## Bookmarks {#bookmarks}

1. **Add a bookmark.**

    Right-click a cell, wire or port and choose **Add Bookmark…**, or select it and use `Tools → Add Bookmark…`. Give it a **Name**, and optionally a **Color** (a `#RRGGBB` value) and a **Note**.

2. **Work from the Bookmarks panel.**

    `View → Show Bookmarks Panel` lists every bookmark in the session, each with its color swatch, the kind of element it marks (cell, port, boundary port or net) and the element's ID.

3. **Edit or delete.**

    Use the **…** menu on a bookmark's row to **Edit Bookmark…** (rename, recolor, re-note) or **Delete Bookmark**.

## Annotations {#annotations}

1. **Add an annotation.**

    Right-click an element and choose **Add Annotation…**, or use `Tools → Add Annotation…` with it selected. The **Body** is **markdown**, so you can write structured notes — a heading, a list of what you ruled out, a link to an issue — and an **Author** is optional.

2. **Browse the Annotations panel.**

    `View → Show Annotations Panel` collects every annotation in the session and renders each body as formatted markdown.

3. **Edit or delete.**

    Use the row's menu to **Edit Annotation…** (the dialog shows the raw markdown) or **Delete Annotation**.

!!! note "They travel with the session"

    Bookmarks and annotations are saved in the `.netcrux` session file. Save the session (++cmd+s++ / ++ctrl+s++) to keep them; opening the session brings them back. See [Sources, projects & sessions](files-and-projects.md#sessions).
