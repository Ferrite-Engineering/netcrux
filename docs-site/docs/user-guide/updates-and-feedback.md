# Updates, issues & privacy

Three pieces of plumbing every NetCrux build carries: the update check, the issue reporter, and anonymous usage statistics.

## Update checks {#update-checks}

NetCrux checks a release manifest and tells you when a newer version is out. It never downloads or installs anything by itself.

**What happens.** On launch, once every 24 hours while the app is running, and when the app returns to the foreground, NetCrux fetches `https://updates.netcrux.app/manifest.json` (10-second timeout). If the latest version is newer than the running build, a strip appears above the app content:

> **NetCrux 0.9.0 is available.** &nbsp; [View Changes] &nbsp; [Update Now] &nbsp; ✕

- **View Changes** opens the release changelog. It appears only when the manifest carries a changelog URL.
- **Update Now** opens `https://netcrux.app/download` in your browser. There is no in-app download and no self-update.
- **✕** dismisses the banner for this session and this version only. A release flagged mandatory has no dismiss button.

**Turning it off.** `Settings → General → Automatically check for updates` (on by default). It gates the launch check, the daily check and the on-resume check. Installations deployed by an organization's packaging tooling (MSI, `.deb` or `.rpm`) skip the check entirely.

**Checking by hand.** `Help → Check for Updates` (in the NetCrux application menu on macOS), the command palette, or the **Check for Updates** button in the About box (++f1++). The manual check runs even when the automatic setting is off. You get a "Checking for updates…" notice, then either the banner, "You're on the latest version (x.y.z).", or "Couldn't check for updates."

**What is sent.** A plain `GET` for a static manifest. The only thing it carries is your app version and operating system, in the `User-Agent` header. Never design, source, netlist or session data.

The banner does not render in the web viewer.

## Reporting issues {#reporting-issues}

The fastest way to get something fixed is the built-in issue reporter — `Help → Submit Issue…`, the command palette, or the **Submit Issue…** button in the About box (++f1++).

1. **Give the issue a short summary** in **Issue Summary**.

2. **Choose what to attach.** NetCrux assembles the diagnostic context as categories, each with a live preview of exactly what will be included:

    | Category | What it attaches |
    | --- | --- |
    | **App & Environment** *(always included)* | App name, version and build number, build SHA, platform, OS, architecture, screen DPI, locale, Flutter and Dart SDK versions. |
    | **Session State** | Open-tab and pane **counts**; whether Yosys was detected (`available` / `unavailable` / `not probed` — never its path); source-file count for the active tab; source **language names**; elaboration state (`no design` / `not run` / `in progress` / `succeeded` / `failed`); module, cell and net **counts**; whether the schematic is laid out; whether something is selected; whether a trace overlay is active; and which analysis panes are open, from a fixed vocabulary. |
    | **Diagnostics** | The last 100 warning-or-higher log entries plus the last 20 entries at any level, captured this session. |
    | **Screenshot** | A PNG of the app window, saved to your temp directory and revealed in your file manager so you can drag it in. Desktop only. |
    | **Pro State** <span class="tier tier-pro">Pro</span> | Offered only when a Pro analysis surface holds a result on the active tab: which surfaces are active, and design counts. |

3. **Submit.** NetCrux copies the report to your clipboard and opens a pre-filled new issue on the NetCrux GitHub repository in your browser. Short reports are pre-filled into the issue body; otherwise paste from the clipboard. Drag in the screenshot if one was captured.

### Privacy posture {#reporter-privacy}

Every field is a count, a fixed enumeration value, or a language or format name. The report never contains:

- source-file paths or the project path;
- module, instance or net names from your RTL;
- Yosys stderr — deliberately excluded, because it quotes source paths verbatim and would leak your filesystem layout into a public issue tracker;
- file contents of any kind.

Everything except **App & Environment** is a toggle, and nothing leaves your machine until you press **Submit**.

`Tools → App Diagnostics…` (++cmd+shift+m++ / ++ctrl+shift+m++) shows the same privacy-scrubbed session snapshot inside the app, without filing anything. In release builds it is available only after you turn on `Settings → General → Enable diagnostics surfaces` (off by default).

## Usage statistics {#usage-statistics}

NetCrux can send anonymous usage statistics — feature and error counters, app and OS version, form factor, language and license tier — to help decide what to build and fix next. An error it did not handle is counted by its kind alone (for example, a state error in the widgets library), never with its message or stack trace. It never sends file names, net names, design data, or anything that identifies you.

- **In the 0.8.x public beta builds, usage statistics are off.** Nothing is collected, you are not asked, and the `Settings → Privacy` category does not appear. That is a property of the build rather than a setting you could change: collection is inert in a beta build by construction.
- **From 1.0 they are on by default**, and the first launch asks you with a **Help make NetCrux better** screen whose **Send anonymous usage statistics** switch you can turn off before you continue. In the EEA, the United Kingdom, Switzerland and South Korea the switch starts **off**, and nothing is sent unless you turn it on.
- **You can change your answer at any time** in `Settings → Privacy → Send anonymous usage statistics`. The same category shows your random **Installation ID** — the only identifier attached to what is collected, and not linked to you; send it to [support@ferriteengineering.com](mailto:support@ferriteengineering.com) if you want this installation's data deleted — and links to the telemetry documentation.
- An organization can switch collection off for a whole fleet with its [signed policy file](https://edacrux.app/policy-reference); that also suppresses the first-launch question.

The exact list of fields, the never-collect list and the code that sends them are documented at [edacrux.app/telemetry](https://edacrux.app/telemetry).
