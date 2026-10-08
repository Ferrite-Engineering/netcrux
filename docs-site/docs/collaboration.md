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

The **Collaborate** button in the status bar becomes the session chip, showing the number of people in the room. Open it for the roster and, on an internet session, to copy the invite again. Its **×** leaves the session; for the host it ends it for everyone.

Everyone's pointer is drawn at screen size in their colour, and their selection as a dashed outline in the same colour. Both are shown only when they are looking at the same scope as you, since a position or an element in one module means nothing in another.

NetCrux warns when not everyone in the room has the same design open.

## Security and its limits {#security}

How the invite, the relay and admission work, and what none of it protects against, is in [Administration](administration.md#collaboration).
