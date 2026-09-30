# Administration <span class="tier tier-enterprise">Enterprise</span>

Org-wide symbol libraries, the security model behind collaborative schematic sessions and its limits, the audit events NetCrux records, and what its policy keys actually do. This page is for the person deploying NetCrux across a fleet — the rest of these docs are for the engineer at the keyboard, and you may never open the application at all.

!!! note "The file itself is documented once, for the whole suite"

    One `.crux-policy.json` configures all four EDACrux products. Where it goes on each platform, how you sign it, discovery order, precedence and the full key table live in [the policy file reference](https://edacrux.app/policy-reference); the rollout procedure is [Deployment](https://edacrux.app/deployment). This page covers only what NetCrux's own keys do.

!!! note "Licensing, and when this page starts to bite"

    In the 0.8.x public beta builds every tier is unlocked and no licenses are issued, so the keys below are in force for whoever runs the build and there is no license to deploy alongside the policy file. From 1.0 that changes: Open Core stays free, and the Enterprise capabilities this page configures require an Enterprise license. The file itself parses, lints and signs either way, so you can write and validate one before you need it.

## NetCrux's policy keys {#keys}

All under `products.netcrux`. **NetCrux registers two keys, and both are in force.**

| Key | What it does | State |
|---|---|---|
| `symbolLibraries` | Org-wide custom-symbol packs on your own share, optionally mandatory. [Below.](#symbols) | In force |
| `crossProbePeerAllowlist` | Which products this seat may cross-probe to — a filter, not an access control. [Below.](#crossprobe-allowlist) | In force |

!!! warning "This page listed five keys until 2026-09-19, and three of them never existed"

    `defaultSettings`, `sourceServerEndpoints` and `remoteApiServer` were named
    here as **Reserved**. No NetCrux release ever registered any of them — they
    were keys this page invented — and they are now out of the schema entirely,
    so `crux-policy lint` reports each as *"unknown to this version of the CLI
    … check the spelling"*. **Delete them from any policy file that carries
    them.** A centralized source server is still unbuilt;
    [tell us](mailto:support@ferriteengineering.com) if you need one, and the
    key comes back when a reader ships rather than when a plan proposes it.

    `crossProbePeerAllowlist` was listed as Reserved in the same table and is
    **enforced** — read the next section before you deploy one.

## Which peers may be cross-probed to {#crossprobe-allowlist}

A list of **product names** — `"wavecrux"`, `"lintcrux"`, `"simcrux"` — naming the products this seat may send a cross-probe to. Matched on the product name rather than a `peerId` or a host, because a peer id is per-process and a host is per-machine, and neither is something an administrator can write down in advance.

```json
"products": {
  "netcrux": {
    "crossProbePeerAllowlist": ["wavecrux"]
  }
}
```

!!! warning "A filter, not an access control"

    The product name this key matches is the one a peer **claims for itself**: it comes from the peer's own discovery manifest and `hello`, and nothing verifies it. Any program running as the engineer can publish a manifest that says `"wavecrux"`, and NetCrux will list it — and send it cross-probes — exactly as it would the real WaveCrux.

    That is not a hole the allowlist was meant to close, and no key matching on a peer's identity could close it. Appearing in NetCrux's peer list takes writing a manifest into the engineer's private CXP directory, and connecting to NetCrux takes the token in NetCrux's own manifest. Both need a program that can already read and write the engineer's files — and such a program can read the design without asking NetCrux for anything. The [CXP specification](https://edacrux.app/cxp#11-security-considerations) says the same of every such policy: it keeps well-behaved tools out of a workflow, and keeps out nothing that means harm.

    So use it to decide which of the suite's tools a seat cross-probes to — to keep a workflow narrow — and not to keep a program out. What keeps an untrusted program away from a design is the operating system's account boundary, not this key.

**Three behaviours to know before you write one, and the middle one is the trap:**

- **Absent means no restriction.** Every seat without a policy file, and every policy file that does not name the key, offers every peer it discovers. That is the un-deployed default.
- **An empty list means *nothing is allowed*, and it is honoured as one.** `"crossProbePeerAllowlist": []` blocks every peer. It is not "the key is present but says nothing" — a key an administrator wrote is treated as an intent to restrict, and the strictest posture has to be expressible. If you deployed one while this page still said the key was inert, **you silently turned cross-probing off**, and turning it back on means removing the key or naming the products.
- **Locked and unlocked behave identically here.** This is a restriction, not a default: there is no engineer-level allowlist for it to sit above or below, so an unlocked value is still the only answer available. `locked` is read and reported so an audit trail can tell a mandate from a suggestion, and changes no outcome.

Entries are trimmed and matched case-insensitively; a blank or non-string entry is dropped. See [CXP integration](integrations/cxp.md) for what cross-probing is.

Registering a key is not implementing the feature behind it, and from outside the two are indistinguishable — a reserved key and a working key look identical in a file that lints clean. Today NetCrux has no reserved keys; if there is a control you need, [tell us which](mailto:support@ferriteengineering.com).

## Org-wide symbol libraries {#symbols}

NetCrux's [custom cell symbols](customizing.md) are stored as a `<symbolId>.json` plus an optional sibling `.svg`, and NetCrux loads a directory of them and shadows on module type. **This key is the distribution and locking layer over that mechanism, not a second symbol system.** An administrator publishes a pack by copying the files an engineer already saved from the symbol editor.

```json
"products": {
  "netcrux": {
    "symbolLibraries": {
      "value": [
        { "path": "/mnt/eng-share/cad/symbols/house-style",
          "sha256": "b41c9e…" }
      ],
      "locked": true
    }
  }
}
```

A bare path string works too, and a bare list of path strings works — that is what you write first, and refusing it would make the simplest case the one that needs the manual. When several packs are listed, a later pack shadows an earlier one. An unusable entry is dropped without costing you the others.

**Nothing is hosted.** A "share" is a path you already have: an NFS mount, a mapped drive, a synced folder, a git checkout. There is no download, no URL and no cache, because each of those is something we would have to run or something that fails differently on an airgapped machine. A pack that is missing — an unmounted share, a laptop off the VPN — is skipped, so engineers keep working with their own symbols.

### Locked is the mandatory-pack case, and unlocked is not {#symbols-precedence}

This is the distinction to get right before you deploy:

- **Unlocked** — the org pack is a *policy default* and sits **below** the engineer's own per-user and per-project symbols. Both of those are "the user setting" in the suite's precedence order, so an engineer who has drawn their own symbol for a cell keeps seeing it.
- **Locked** — the org pack outranks both. That is the mandatory-pack case, for an organization standardising on a corporate style, and it is the only setting that overrides work an engineer has already done.

### Pinning a pack by content hash {#symbols-pinning}

A pack is a directory, so its digest is over **the manifest of its files** — each `.json` and `.svg` name with its own SHA-256, sorted — rather than over any single file. That is what makes "the approved pack" mean the set you vetted: adding a rogue symbol to a pinned pack is a mismatch, not an addition nobody notices. A pinned pack that does not match is not loaded.

Pinning is **optional**, and its absence is not laxity: a house-style pack the team edits monthly should not need a policy-file commit and a re-sign each time. The distinction from WaveCrux's plugin allowlist is worth borrowing, because the two look similar and are not: **that decides whether to execute code; this decides whether to draw a rectangle differently.**

## Collaborative schematic sessions {#collaboration}

Several engineers viewing one schematic with synchronized pointers, selection and scope. Engineers start and join sessions from the **Collaborate** button in the status bar. The design is WaveCrux's, reused rather than reinvented, so the security properties and the limits are the same in both products.

### How a session starts {#collab-start}

- **Local network.** The host shares; NetCrux advertises the session over mDNS and listens on **TCP 7891**. That is one above WaveCrux's port on purpose, so both products can host a local-network session on the same machine without colliding. Open it between engineering workstations if your segment filters. A joiner can also enter the host's address by hand where mDNS is blocked.
- **Internet.** The host copies an **invite** and sends it to the people they want in the room. The relay address is a setting, **Relay address** under `Settings → Collaboration`, and defaults to `wss://relay.netcrux.app`. The relay is stateless and message-agnostic, and it never holds key material — the invite carries it — so **an organization that would rather not route sessions through us at all can point every client at a relay it runs**, which is the answer most Enterprise deployments want anyway. [Talk to us](mailto:support@ferriteengineering.com) before you stand one up.
- **Either way, the host approves each join.** A request that goes unanswered for sixty seconds is auto-denied, so a joiner is never left waiting on a host who walked away — an unanswered request resolves to a stated refusal rather than to silence. For bench demos, `Settings → Collaboration` has **Let local-network joiners in without asking**; it resets every launch and never applies to internet sessions.

### The security model, in the terms a reviewer asks in {#collab-model}

```text
ABC123-Zm9vYmFyYmF6cXV4MTIzNDU2
└room┘ └───── secret, never transmitted ─────┘
```

**The invite carries key material the relay never sees.** Every frame is sealed under a key derived from the second half of the invite; the room code, which is all the relay routes on, is the first half. A peer without the secret produces frames whose authentication tag fails, so it is dropped and **never enters the roster**.

Authentication therefore falls out of encryption. There are **no accounts, no identity service and no directory**, and nothing of ours in that path beyond a stateless message router. A breach of the relay, or a legal demand against it, yields ciphertext.

### What it does not protect against {#collab-limits}

Listed rather than left to be inferred. An Enterprise security review will ask about every one of these, and finding them absent is worse than finding them stated.

- **Metadata and traffic analysis.** The relay still sees room codes, IP addresses, connection times, and message sizes and rates. It can tell that five people collaborated for forty minutes. Encryption does not fix that and we do not claim it does.
- **The malicious invitee.** Anyone holding the invite is fully trusted. **There is no per-participant identity and no revocation.**
- **No forward secrecy, and no rekey on membership change.** Someone who was in the room keeps a key that works for the session's lifetime and can rejoin with it. Proper rekeying needs pairwise channels the protocol does not have, and it was deliberately not built in this version. The operating rule instead: **the invite is the credential for the life of the session — to revoke access, end the session and start a new one.**
- **Local-network sessions are not encrypted.** Local-network sessions are peer-to-peer with zero-config discovery, so there is no out-of-band invite to carry key material and no meaningful secret to derive one from; encrypting under a key anyone on the segment could reconstruct would be theatre. The meaningful control there is host approval on join, and a local-network session never touches the relay at all — which is also what makes it work in an airgapped lab.

WaveCrux's collaborative viewing uses the same design, so [the same limits apply there](https://docs.wavecrux.app/administration#collab-limits), in the same terms.

## Audit events NetCrux records {#audit}

Turned on with `suite.audit.path`, suite-wide. The envelope, the format, rotation and failure behaviour are in [the audit log reference](https://edacrux.app/audit-log).

| Kind | When | Payload |
|---|---|---|
| `schematic.opened` | A design is opened — including re-opening one already open, which is exactly the repeat access an investigation looks for. | `source`, `fileCount`, `topModule` |
| `session.saved` | A session is written. Only on a real write: a cancelled picker and a failed write both record nothing. | `path` |
| `crossprobe.originated` | A cross-probe is sent to another product from the schematic context menu. | `peerId`, `elementKind`, `honored` |
| `search.executed` | A search result is activated. | `mode`, `resultKind` |

**Four kinds, all of which fire.** `sourceserver.fetched` was listed here as *"registered, no producer"* until 2026-09-19 and has been **removed from the registry**: the centralized source server is unbuilt, and carrying a kind for it meant a catalogue whose reader could not tell "this exists and is quiet" from "this will never exist". It returns when the feature does.

### What these payloads deliberately do not carry {#audit-withheld}

This file is read by whoever runs your log shipper, which is usually not the team whose RTL is being described. These absences are worth naming because they are the ones a reviewer checks for:

- **No design source paths.** `schematic.opened` records the top module and the file *count*, never the paths — a source path carries a home directory and a project code name.
- **No search queries.** A search term in a netlist is a signal or instance name, which is design IP. "What were people looking for in our RTL" is not a question this file is entitled to answer, so it records that a search ran, in which mode, and what class of thing was activated.
- **No cross-probed element paths.** A hierarchical path is design structure. The event records the peer, the element *kind*, and whether the peer honoured the probe.

`session.saved` does record the path the engineer chose to write to. It is the one place NetCrux writes a filesystem path into a payload, and it is there because the path *is* the event.

## X-Trace, for a reviewer reading a chain {#tracing}

[X-Trace](tracing.md#x-trace) is documented for the engineer elsewhere. One property matters when a trace is used as evidence in a review: **the walk follows the first input pin at each cell, so the chain it reports is one route through a cone that usually has many.** It is a path, not the path — a genuine answer to "where could this have come from" and not a complete answer to "everywhere it could have come from". Use [Cone of Influence](tracing.md#cone) when you need the whole set.

## Managed installs and updates {#packaging}

**A managed install does not update itself.** An application installed by MSI, `.deb` or `.rpm` makes no update check at all, so it will not offer an in-app update and will not nag — the version is your deployment tooling's business, which is the point of packaging it that way. That behaviour outranks every policy key, including `suite.updateChannel`, because it describes how the application was installed rather than what you configured.

!!! note "Not yet published"

    No release has yet been published as MSI, `.deb` or `.rpm` packages — the [download page](https://netcrux.app/download) lists what actually exists today: the macOS disk image, the Linux AppImage and `.tar.gz`, and the Windows installer and `.zip`. Until those packages appear there, deploy the existing artifacts with your own tooling.

For installs that do update themselves, pinning, channel selection and an on-prem manifest mirror are suite-wide keys — [the reference](https://edacrux.app/policy-reference#suite-keys) has them, and [Deployment](https://edacrux.app/deployment#updates) has the behaviours worth knowing before you write one.

!!! tip "See also"

    [Policy file reference](https://edacrux.app/policy-reference) · [Audit log](https://edacrux.app/audit-log) · [Deployment](https://edacrux.app/deployment) · [The end-to-end administrator workflow](https://edacrux.app/for/devops-engineers) · [Custom cell symbols](customizing.md), for what a pack contains
