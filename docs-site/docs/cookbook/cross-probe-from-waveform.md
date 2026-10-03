# Cross-probe from a waveform

You are staring at a glitch in WaveCrux and you want to see the logic that produced it. This recipe connects the two apps and moves a selection in both directions.

| | |
|---|---|
| **Goal** | Go from a signal in WaveCrux to its logic in NetCrux, and back. |
| **Time** | About 5 minutes |
| **Tier** | Open Core. Cross-probing from the schematic context menu is <span class="tier tier-pro">Pro</span>. |
| **You will use** | [Cross-probe & the suite](../integrations.md), the [CXP integration reference](../integrations/cxp.md) and [one-step tracing](../tracing.md#fanin-fanout). |

## Setup, once {#setup}

1. Leave `Settings → CXP Cross-Probe → Enable CXP server` on in both apps — it is on by default in both.
2. Set `Settings → Editors → Editor command (open source)` if you want source-open requests to land in your editor. The default is `code -g {file}:{line}`.
3. Start both apps on the same machine. Discovery is file-based and takes a couple of seconds.

Confirm it worked: open the Cross-Probe panel (++cmd+shift+x++ / ++ctrl+shift+x++, or the toolbar button, whose badge counts connected peers). You should see WaveCrux in the peer list and no **Cross-probe server is offline.** banner; `Settings → CXP Cross-Probe` reads **Running on port 54323**.

## Waveform → schematic {#to-schematic}

Load the design in NetCrux and the matching trace in WaveCrux, then ask WaveCrux to highlight the signal's scope or net. NetCrux:

- navigates the hierarchy to that scope, or selects the instance, port or net if it exists in the current scope — a bare signal name is matched against the current scope's nets, ports and cells;
- acks `honored: true`, or `honored: false` with a reason such as `Scope top.cpu.alu not found in current design` when the loaded design does not contain it.

Then press ++bracket-left++ in NetCrux to walk back to the driver — see [Trace a signal to its source](../cookbook-trace-a-signal.md).

## Schematic → waveform {#to-waveform}

Click a cell, port or net in NetCrux. With `Settings → CXP Cross-Probe → Broadcast selection automatically` on (the default), NetCrux broadcasts a `notify_selection` carrying the canonical element path and the scope path in `metadata`. Peers decide what to do with it.

You can also target one peer explicitly: in the Cross-Probe panel, press **Send selection to this peer** on that peer's row. The **PRO** badge beside the button marks this as a Pro <span class="tier tier-pro">Pro</span> feature; in Open Core the press opens the upgrade dialog instead. That sends a `request_highlight` and waits for the peer's ack. Nothing is shown when the peer honours it; if the peer went away or did not answer you get a notice that it could not act on the cross-probe, and a refusal shows the peer's reason. With nothing selected, or with the server off, the button does nothing.

With Pro <span class="tier tier-pro">Pro</span>, right-click the element and choose **Cross-probe → wavecrux** instead, or use **Open in WaveCrux** on an analysis panel's header.

## When nothing happens {#troubleshooting}

| Symptom | Check |
| --- | --- |
| No peers in the panel | Is the server enabled in both apps? Is anything else holding port 54323? |
| Peer visible, selections do not follow | Is **Broadcast selection automatically** on in the app you are clicking in? |
| Highlight refused | Read the reason on the ack — usually the design is not loaded or the path is not in the current scope. |
| Nothing works in the browser | CXP is desktop-only. Web builds cannot open sockets. |
