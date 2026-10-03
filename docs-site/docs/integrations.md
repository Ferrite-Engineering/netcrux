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

## Originating cross-probes {#originate}

Every edition can send, too. With **Broadcast selection automatically** on, each selection change is announced to connected peers. The **Cross-Probe** panel (`View → Show Cross-Probe Panel`, ++cmd+shift+x++ / ++ctrl+shift+x++, or the toolbar button) lists the discovered peers — each with a **Send selection to this peer** button that asks that peer to highlight what you have selected — plus unreachable peers and a log of recent events.

The send button carries a **PRO** badge on its left, because sending to one chosen peer from the panel is a Pro <span class="tier tier-pro">Pro</span> feature. The badge is there in every edition, so you can see the tier before you press it. In Open Core, pressing it sends nothing and opens the upgrade dialog instead; the panel's peer list, unreachable-peer warnings and event log stay available in every edition, as does the automatic broadcast.

Pro <span class="tier tier-pro">Pro</span> adds cross-probing from the schematic itself: right-click an element and choose **Cross-probe → *peer*** for any connected peer (the entry reads **Cross-probe → (no peers)** when none are connected). The Pro analysis panels also carry an **Open in WaveCrux** button on their headers, so you can send the selected crossing or element straight to a waveform.

!!! note "Source locations over CXP"

    CXP also carries an open-source request: a tool can ask NetCrux to open a given `file:line`, which NetCrux hands to your editor command. That is how a cross-probe from another tool can land you directly in the RTL.

## Enterprise services <span class="tier tier-enterprise">Enterprise</span> {#enterprise}

Enterprise extends NetCrux from a single-engineer tool to an organization-scale one. Most of it ships today; what does not is marked.

- **Collaborative schematic sessions** — a live shared session with synchronized pointers, selection and scope, so several engineers can debug one schematic together. Start one from the **Collaborate** button in the status bar: **Share this schematic…** or **Join a session…**. On your **Local network**, peers are discovered over mDNS, which is what makes this usable in an airgapped lab: nothing leaves the room. **Over the internet**, sessions go through a relay and are end-to-end encrypted, with the key material carried in the invite and never held by the relay. Either way the host approves every join, and NetCrux warns when not everyone in the room has the same design open. See [Administration](administration.md#collaboration) for the security model and its limits.
- **Org-wide symbol libraries** — [custom cell symbols](customizing.md) distributed from your own share and named by your signed policy file, so a team's modules render consistently everywhere. A locked library wins over an engineer's own symbol for the same cell; an unlocked one yields to it, so a team default stays a default rather than becoming a veto.
- **Org-wide policy and audit logging** — suite-wide settings such as update channel and telemetry, plus NetCrux's symbol-library key, from a signed configuration file you distribute yourself, and an append-only audit log your existing log shipper can forward. Shared across the EDACrux suite; nothing hosted on our side.
- **Centralized source server** — *not built.* Resolving `file:line` against a Perforce or Git server, so source lookup works without a local checkout, is something we build against the server you actually run. [Contact us](mailto:support@ferriteengineering.com?subject=EDACrux%20Enterprise%20%E2%80%94%20Centralized%20source%20server) if you need it.

!!! note "See also"

    [Tiers & licensing](https://edacrux.app/licensing) maps every feature to its tier.
