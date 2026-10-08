# Collaborative sessions

Several engineers looking at one schematic at once: everyone's pointer and selection on everyone's screen, anchored to the same hierarchy scope. Sessions run in the downloaded NetCrux app; a build of the open-source `netcrux` repository and the web viewer do not offer them.

From NetCrux 1.1, joining a session is free; hosting is Enterprise. Only **Share Session…** asks for a license. A guest without one is admitted by the host and is a full participant.

| | Who can | Where |
|---|---|---|
| Host a session | <span class="tier tier-enterprise">Enterprise</span> | **File > Share Session…**, or the **Collaborate** button in the status bar |
| Join a session | Everyone with the downloaded app (from 1.1) | **File > Join Session…**, or the **Collaborate** button |
| Leave a session | Everyone in one | **File > Leave Session**, or the **×** on the session chip |

**Share Session…** carries the Enterprise badge before you choose it, in the File menu, the command palette and the Collaborate menu. **Join Session…** carries none.

## Starting a session {#share}

1. Choose **File > Share Session…** (or **Collaborate > Share Session…** in the status bar).
2. Enter the name the room will see you as.
3. Choose **Local network** or **Internet**:
    - **Local network.** Colleagues on the same network find the session automatically. Nothing leaves the room, and local-network sessions are **not encrypted**; the control is that you approve each person who asks to join.
    - **Internet.** The session goes through a relay and every message is end-to-end encrypted. You get an **invite** to send to the people you want in the room; it carries the session key, so send the whole line.
4. Choose **Start**.

When somebody asks to join, NetCrux shows **"{name} wants to join"** with **Approve** and **Deny**. An unanswered request is declined after sixty seconds, so nobody waits on a host who walked away.

## Joining a session {#join}

1. Choose **File > Join Session…** (or **Collaborate > Join Session…**).
2. Paste the invite the host sent you. For a local-network session, enter the session code the host reads out, or the host's address if your network blocks discovery.
3. Enter your name and choose **Join**. The dialog waits until the host lets you in, and says so if they decline or do not answer.

`Settings → Collaboration` holds your relay address, if your organization runs its own relay. It is open to everyone from NetCrux 1.1, because a guest needs it as much as a host does.

## While a session runs {#live}

The **Collaborate** button in the status bar becomes the session chip, showing the number of people in the room and who is presenting. Open it for the roster and, on an internet session, to copy the invite again. Its **×** leaves the session; for the host it ends it for everyone.

Everyone's pointer is drawn at screen size in their colour, and their selection as a dashed outline in the same colour. Both are shown only when they are looking at the same scope as you, since a position or an element in one module means nothing in another.

NetCrux warns when not everyone in the room has the same design open.

## Presenting and following {#presenter}

One person presents at a time, and everyone else sees what they show. The host presents when the session starts.

- **What follows.** Your schematic moves to the presenter's scope and frames the same part of the design they are looking at, whatever the size of your window. Their selection is outlined, and the elements their fanin, fanout or cone-of-influence trace lights glow in their colour, on top of your own schematic. Your own selection and trace overlay are never changed. The presenter's pointer has a ring around it.
- **The panel the presenter has open.** When the presenter brings an analysis panel to the front (CDC, reset domains, FSM, the diff, switching activity, the source view, bookmarks or annotations), the same panel opens at the front of your dock, showing your own results: nothing the presenter computed is sent, so run the analysis on your side to fill it. A Pro panel opens only if your edition includes Pro. If it does not, the status bar says the panel *requires NetCrux Pro* instead: following a presenter shows you the session, not the presenter's edition. Panels the session opened for you close again when the presenter moves on or the session ends; panels you opened yourself stay.
- **What the status bar says.** The presenter sees **You're presenting**. Everyone else sees **Presenting:** and the presenter's name, and **Following** *name*'**s view** while their schematic follows.
- **Looking away.** Pan, zoom or change scope and you stop following, without leaving the session or changing who presents. The status bar offers **Resume following** *name*; leave the view alone for twelve seconds and it resumes on its own. The button beside **Following** *name*'**s view** does the same from the keyboard.
- **Changing presenter.** Open the presenter menu (the presenter's name in the status bar). Anyone can choose **Request control**; the presenter and the host see *name* **wants to present** with **Approve** and **Deny**. The presenter, or the host at any time, can choose **Hand off to** *name* directly.
- **When someone leaves.** If the presenter leaves, the host presents again. If the host leaves, the person who has been in the session longest becomes host and presenter.

None of this needs a license: from NetCrux 1.1 a guest who joined for free can ask to present and present like anyone else.

## Security and its limits {#security}

How the invite, the relay and admission work, and what none of it protects against, is in [Administration](administration.md#collaboration).
