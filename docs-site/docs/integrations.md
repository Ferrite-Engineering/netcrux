# Cross-probe & the suite

NetCrux is one tool in the EDACrux suite, and it talks to its siblings over **CXP**, the cross-probe protocol. Select a net in NetCrux and have it highlight in a WaveCrux waveform; receive a selection from LintCrux and jump to it on the schematic. Elements travel as canonical, dot-separated hierarchical paths such as `top.cpu.alu.result`, so every tool means the same thing by the same name. The protocol itself is specified at [edacrux.app/cxp](https://edacrux.app/cxp), and NetCrux's exact message vocabulary is in the [CXP integration reference](integrations/cxp.md).

![Two EDACrux apps running side by side with their Cross-Probe panels open: NetCrux showing the VexRiscv schematic with its peer list (simcrux, wavecrux, lintcrux), and WaveCrux showing waveform lanes with the same connected peers plus a live 'Selection received' cross-probe event from LintCrux.](img/screenshots/CrossProbe.png)

*Two suite apps discovering each other over CXP — each Cross-Probe panel lists the connected peers, and inbound selections appear in the event feed.*

## CXP server settings {#cxp-settings}

Cross-probe is configured in `Settings → CXP Cross-Probe`:

- **Enable CXP server** — on by default. Cross-probe is meant to work without setup.
- **CXP port** — default `54323`, any value from 1 to 65535, applied when you press ++enter++.
- **Request attention on cross-probe** — bounce the dock icon or flash the taskbar when a peer's cross-probe is acted on. It never steals focus.
- **Broadcast selection automatically** — announce your selection to connected peers as you select.
- **CXP Status** — **Running on port 54323** or **Stopped**, and the number of connected peers.

The editor command used when a peer asks NetCrux to open a `file:line` lives separately, under `Settings → Editors → Editor command (open source)` (default `code -g {file}:{line}`). Discovery is automatic: every running suite app writes a small manifest to a shared per-user directory and the others pick it up within a couple of seconds. Cross-probe works between apps on the same machine only.

## Receiving cross-probes {#receive}

Every edition can **receive** cross-probes. When another suite tool asks NetCrux to highlight a scope, NetCrux navigates the hierarchy there; when it sends an instance, port, net or signal, NetCrux resolves the path against the current scope and selects the element — so a signal you click in WaveCrux lights up on the NetCrux schematic with no extra setup. A request that cannot be resolved is refused with a reason the sender can show.

!!! note "Routing is order-independent"

    A peer's subscription filter is tested against **every** element a message references, not just the first one, so a multi-element selection routes the same way whatever order it was made in. And a **cleared** selection reaches every subscriber, whatever filters they carry, so a peer is never left holding a stale highlight after the selection it was told about has been withdrawn.

## Formal and implementation-flow results, from NetCrux 1.2 {#formal-flow}

From NetCrux 1.2, SimCrux's formal verification and implementation-flow results
can send NetCrux what they found, and NetCrux acts on it in every edition. The
exact message vocabulary is in the
[CXP integration reference](integrations/cxp.md#formal-flow).

### Receiving a property {#receive-property}

When a formal property fails in SimCrux, **Show in NetCrux** sends the first
signal the property reads. NetCrux finds it in the scope its path names, selects
it, and draws its one-step fan-in, the logic that feeds it. The fan-in is drawn
only when the message says the signal belongs to a formal property (it carries
the property's kind or its label); a signal sent without either is selected and
nothing more. The path is never matched by its last segment in some other scope:
a name that is not there is declined with a reason, not guessed.

<span class="tier tier-pro">Pro</span> A property sent as itself, as
`<file>:<line>`, shows the cone of every signal the property reads, unioned. It
is read only from a source file of the design you have open. Open core answers
that it requires NetCrux Pro, in a message. The cone sits under the same Pro
feature as the [cone of influence](analysis.md).

### Receiving timing paths {#receive-timing}

When you select a timing path in SimCrux's Flow Runs, NetCrux highlights the
path's registers together, in the scope of the path's endpoint, and the Inspector
shows **Timing path from SimCrux**: how the registers were mapped, the start and
end registers, which of them sit in another scope or are not in this design, and
the statements. **Dismiss** removes it. It lands in the tab that is active when
it arrives. When SimCrux follows the path with a request to show its end
register, as **Cross-probe to** does, both registers stay highlighted and the
view is framed on the end register. A timing path sent on its own, with no registers beside it, is
declined, because its id is opaque.

### Fidelity labels {#fidelity}

Synthesis restructures logic, so a path is never tied to an exact line. The
label on a timing path says how near the mapping got, exactly as SimCrux sent
it, and NetCrux never upgrades it:

| Label | What it says |
|---|---|
| Register | The end is a register your RTL names |
| Statement | The end is the statement that assigns a register |
| Block | Only the block that contains it is known |
| Unmapped | No source location survives synthesis |

### Showing timing paths through a register {#show-paths}

On a register in the schematic, the context menu offers **Show timing paths
through this register**, beside **Cross-probe to**. It sends SimCrux the
register's RTL name, and SimCrux shows the paths that start or end there. It is
free in every edition. With no SimCrux running it is disabled and its tooltip
says to start SimCrux.

### Slack overlay {#slack}

<span class="tier tier-pro">Pro</span> NetCrux Pro can colour the registers of
the open design by the slack an implementation run reports. See
[Slack overlay](slack-overlay.md).

## Originating cross-probes {#originate}

Every edition can send, too. With **Broadcast selection automatically** on, each selection change is announced to connected peers. The **Cross-Probe** panel (`View → Show Cross-Probe Panel`, ++cmd+shift+x++ / ++ctrl+shift+x++, or the toolbar button) lists the discovered peers — each with a **Send selection to this peer** button that asks that peer to highlight what you have selected — plus unreachable peers and a log of recent events.

From NetCrux 1.1, sending is free in every edition, like receiving: the send button carries no tier badge and never opens an upgrade dialog. (Before 1.1 it was marked **PRO**.)

You can also cross-probe from the schematic itself: right-click an element and choose **Cross-probe to *peer*** for any connected peer, for example **Cross-probe to WaveCrux** (the entry reads **Cross-probe (no peers)** when none are connected). From NetCrux 1.1 this is free in every edition of the downloaded app too. The Pro <span class="tier tier-pro">Pro</span> analysis panels also carry an **Open in WaveCrux** button on their headers, so you can send the selected crossing or element straight to a waveform.

!!! note "Cross-probe from ROHD"

    From NetCrux 1.2, a ROHD netlist opens in NetCrux, and its elements cross-probe with a ROHD waveform by hierarchical path like any other design. See [ROHD + EDACrux](rohd-and-edacrux.md#cross-probe).

!!! note "Source locations over CXP"

    CXP also carries an open-source request: a tool can ask NetCrux to open a given `file:line`, which NetCrux hands to your editor command. That is how a cross-probe from another tool can land you directly in the RTL.

## Enterprise services <span class="tier tier-enterprise">Enterprise</span> {#enterprise}

Enterprise extends NetCrux from a single-engineer tool to an organization-scale one. Most of it ships today; what does not is marked.

- **Collaborative schematic sessions** — a live shared session with synchronized pointers, selection and scope, so several engineers can debug one schematic together. From NetCrux 1.1, joining a session is free; hosting is Enterprise. Start or join one from **File > Share Session…** and **File > Join Session…**, or from the **Collaborate** button in the status bar. See [Collaborative sessions](collaboration.md). On your **Local network**, peers are discovered over mDNS, which is what makes this usable in an airgapped lab: nothing leaves the room. **Over the internet**, sessions go through a relay and are end-to-end encrypted, with the key material carried in the invite and never held by the relay. Either way the host approves every join, and NetCrux warns when not everyone in the room has the same design open. See [Administration](administration.md#collaboration) for the security model and its limits.
- **Org-wide symbol libraries** — [custom cell symbols](customizing.md) distributed from your own share and named by your signed policy file, so a team's modules render consistently everywhere. A locked library wins over an engineer's own symbol for the same cell; an unlocked one yields to it, so a team default stays a default rather than becoming a veto.
- **Org-wide policy and audit logging** — suite-wide settings such as update channel and telemetry, plus NetCrux's symbol-library key, from a signed configuration file you distribute yourself, and an append-only audit log your existing log shipper can forward. Shared across the EDACrux suite; nothing hosted on our side.
- **Centralized source server** — *not built.* Resolving `file:line` against a Perforce or Git server, so source lookup works without a local checkout, is something we build against the server you actually run. [Contact us](mailto:support@ferriteengineering.com?subject=EDACrux%20Enterprise%20%E2%80%94%20Centralized%20source%20server) if you need it.

!!! note "See also"

    [Tiers & licensing](https://edacrux.app/licensing) maps every feature to its tier.
