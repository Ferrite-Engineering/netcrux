# netcrux

Open-core EDA tool, part of Ferrite Engineering's EDACrux suite.

Architecture & engineering manual (read sections explicitly when needed; no auto-load): `docs/ARCHITECTURE.md`

**IMPORTANT:** The manual is not auto-loaded into context (no `@` prefix). Don't bulk-read it; locate the right anchor with `grep` first, then read the specific section. The public suite policy pages — licensing, telemetry, the policy file, CXP — live at `https://edacrux.app`.

## Reference implementation: WaveCrux

WaveCrux is the canonical implementation of this open-core + Pro/Enterprise overlay pattern. When a convention, file layout, naming choice, or architectural seam is unclear in this project, consult WaveCrux first:

- Open-core repo: `wavecrux` (`https://github.com/Ferrite-Engineering/wavecrux`)
- Open-core conventions: `wavecrux/CLAUDE.md`
- Engineering manual: `wavecrux/docs/ARCHITECTURE.md`

Match WaveCrux's pattern unless this project has a documented reason to diverge. When you find yourself solving a problem that WaveCrux likely already solved, read its implementation before writing a new one.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod with code generation (`@riverpod` annotations via `riverpod_generator`)
- **Domain Models:** Plain immutable Dart classes with `copyWith`/equality (no freezed)
- **Lints:** `very_good_analysis` (zero-warnings policy)
- **Elaboration:** Yosys (and standalone GHDL for VHDL) run as subprocesses through the shared `crux_yosys` package
- **Layout:** elkjs, vendored under `assets/elk/`, run through `flutter_js` on desktop and natively in the browser on web
- **Panel layout:** the shared `crux_ide_layout` package, wrapped by `NetcruxIdeLayout`

`docs/ARCHITECTURE.md` §2 has the detail. Default to WaveCrux's choices when a new dependency's domain overlaps.

## Platform Targets

Desktop-first (Linux/macOS/Windows), plus a **read-only web viewer**. **Mobile is out of scope; web is not** — a static, read-only schematic viewer is built from this open-core package.

| Platform | Notes |
|----------|-------|
| **Linux** | Primary target; x86_64 |
| **macOS** | Universal binary (Intel + Apple Silicon) |
| **Windows** | x86_64 |
| **Web** | Read-only schematic viewer only. Renders a Yosys **netlist** JSON (elaborated netlist, not pre-laid-out) and lays it out **client-side** with elkjs running natively in the browser (`elk_web_solver_web.dart` — no flutter_js, no isolate). A design reaches it two ways: **Open Netlist JSON…** (a browser file pick, read in the page) and the `?json=<url>` / `#scope=` / `#sig=` deep link, which `WorkspaceScreen` opens and `WebDeepLink` (`lib/features/workspace/services/web_deep_link.dart`) navigates. Both go through the same `PrebuiltNetlistLoader` a desktop `.json` source uses; `hdlElaborationSupportedProvider` is the seam that sends every browser design down that path. Elaboration is desktop-only: browsers can't spawn the Yosys/GHDL subprocess, so `NetcruxActionContext.isBrowser` hides every action that needs a local file system, a subprocess or a socket, and every Pro action. Deployed to `app.netcrux.app` from `wrangler.jsonc`. The web build is Open-Core-only (no paid tiers on web — client-side gating is bypassable). |

There is no `Device Class` system in netcrux — the equivalent rules in WaveCrux exist because WaveCrux runs on phone/tablet/desktop. The web viewer targets desktop-class browser viewports (`NetcruxIdeLayout`, over the shared `crux_ide_layout` package, is the only layout, browser included — the legacy `panes` package itself has zero direct imports in this repo), so read those rules in `wavecrux/CLAUDE.md` as background but do not import the breakpoint or `MobileMetrics` infrastructure unless and until netcrux gains a phone/tablet target.

## Build & Run Commands

```bash
# Code generation (Riverpod @riverpod providers)
dart run build_runner build --delete-conflicting-outputs

# Run app (desktop; `flutter build web` for the read-only web viewer)
flutter run -d macos    # or -d linux, -d windows

# Run all tests
flutter test

# Run single test file
flutter test test/path/to/test_file.dart

# Browser-only tests (@TestOn('browser')), headless Chrome
tool/run_web_tests.sh

# Lint (zero warnings policy — CI also fails on infos)
flutter analyze --fatal-infos --fatal-warnings

# Generate localization files (flutter gen-l10n)
# Runs automatically during build/run when `generate: true` is set in pubspec
flutter gen-l10n
```

## Coding Conventions

### IMPORTANT: Project config filename is `<name>.netcrux-project` (NOT a dotfile)

NetCrux already follows the cross-suite naming convention: the canonical
per-project config is a user-named file with the `.netcrux-project`
extension (e.g. `golden_v1.netcrux-project`). Do NOT introduce dotfile
names like `.netcrux.yaml`, `.netcrux-config`, etc. for user-visible
files. See
[crux-shared/docs/adr/0001-project-config-filename-convention.md](crux-shared/docs/adr/0001-project-config-filename-convention.md)
for the cross-suite rationale (SimCrux once carried a dotfile filename and
renamed away from it; the ADR locks the convention in for every product). Pure tooling caches (e.g. a hypothetical `.netcrux-cache/`) may
still use a dotfile name; consult the ADR before adding one.

The suite design manifest follows the same rule: it is `<design>.crux-project`
(e.g. `uart_tx.crux-project`). Recognize it with
`CruxProjectParser.isManifestPath`, filter pickers with
`kCruxProjectExtension`, and never compare a basename against a literal
`.crux-project` — that legacy bare name still opens, with a localized rename
notice, only because older manifests carry it.

### IMPORTANT: No Hardcoded Strings

Every user-facing string MUST come from the localization system (ARB files). No string literals displayed to users anywhere in widget, screen, or service code. The only exception is test code.

Localization is fully wired (see below) — there are no `TODO(setup)` placeholder strings left in `lib/`. Every new user-facing string goes straight into the ARB files; do not reintroduce hardcoded-string placeholders.

### IMPORTANT: Tests Required for All New Code

Every new or modified Dart file in `lib/` MUST have a corresponding test file in `test/` mirroring the same directory structure. When generating production code, YOU MUST also generate the tests in the same response. Do not wait to be asked — tests are not optional.

- Domain models: Unit tests for equality, copyWith, and any computed properties.
- Services: Unit tests covering happy path, edge cases, and error handling.
- Providers: Unit tests using `ProviderContainer`. Verify state transitions and async behavior.
- Widgets: Widget tests for key interactions and layout. Locale sweep (`en`, `zh_CN`, `ja`, `ko`) once localization is set up. Use `expect(tester.takeException(), isNull)` after pumping.
- Use `mocktail` (not `mockito`).
- Test file naming: `test/<mirror of the lib path>/<file>_test.dart`

### IMPORTANT: Widget Architecture

- **One widget per file.** Each public widget class lives in its own `.dart` file in `snake_case`.
- **Keep widgets small.** If `build()` exceeds ~50 lines or has 3+ nesting levels, extract child sections into their own files.
- **Build for reuse.** Leaf widgets accept data and callbacks via constructor.
- **Stateless over stateful.** Prefer `ConsumerWidget` with Riverpod. Only use `StatefulWidget` for local mutable state (animations, focus, gesture handlers).
- **Composition over configuration.** Distinct widget variants over boolean flags.

### IMPORTANT: Comment Hygiene — comments describe the code, not the work

A comment is read by someone who has no access to the process that produced it. Write clinically: state what the code does and why it is shaped that way. Four classes of prose fail that standard and are rejected by `test/static/comment_hygiene_test.dart` (identical copy in the Pro overlay):

1. **Backlog / track identifiers as anchors.** A quality-round or execution-prompt row id is deleted when the round closes, leaving the comment unresolvable. Plan phases, plan sections, work-stream ids and audit finding ids fail the same way for a reader of this repository, because the documents that define them are not in it — `test/static/no_private_references_test.dart` rejects them anywhere in the tree. State the reason inline; when a reference is genuinely needed, cite a document in this repository by name and section (`docs/ARCHITECTURE.md` §6.2) or a public page (`https://edacrux.app/cxp`).
2. **Dates as process notes.** A stamp narrating when work happened duplicates `git log` and tells a reader nothing about the code. Dates that are *data* — licence headers, fixture payloads, format examples — are unaffected.
3. **Session / process voice.** `this round`, `for now`, `as discussed`, `we decided`, person-addressed `TODO(...)`. Prose scoped to the sitting that wrote it expires the moment that sitting ends. If a limitation is real, state the limitation and its condition ("the platform picker lands with the workspace file-open integration"), not the schedule.
4. **Reviewer voice.** `as you can see`, `we renamed`, `before this change`, `in this commit`. Change narration belongs in the commit message; the comment describes the code that now exists.

The guard scans comment text only (string literals are skipped, so identifier-shaped domain data is never flagged) and covers all four classes over `lib/`, plus class 1 over `test/` and `integration_test/` — the identifier-anchor defect has recurred in test files. Its allowlist is empty by design: a violation is rewritten, not listed.

### IMPORTANT: Documentation Claims Are Checked

`CLAUDE.md`, `docs/ARCHITECTURE.md`, and both verification documents make claims a reader is entitled to trust, and `test/static/doc_truth_test.dart` (identical copy in the Pro overlay) holds them to it:

1. **Paths must resolve.** Every repo-relative path written in backticks or as a Markdown link target must exist. A path a document states does *not* exist is checked in the same direction — it must stay gone.
2. **Stated quantities must be derived.** A number computable from the tree (ARB file count, per-tab override count) must equal the computed value. Prefer prose with no figure when the quantity churns: an ARB key total forces a document edit on every string added and tells the reader nothing, so it is written without a number rather than guarded.
3. **Inventories are generated-in-place.** A document that enumerates an override list's membership does so inside an `<!-- inventory: <listName> -->` block, which must equal the parsed list exactly in both directions.

When a path in a document points at something illustrative or hypothetical, write it as a template (`test/<mirror of the lib path>/<file>_test.dart`) or put it in a fenced block — both are outside the extractor's scope. References to another public repository carry its name as a prefix (`wavecrux/docs/…`) so they read as prose rather than as a broken local path; private repositories are not referenced at all. Do not add allowlist entries; correct the document.

### IMPORTANT: Screen-reader and keyboard accessibility

An external NVDA pass (2026-09-14, on WaveCrux) found the shared workspace chrome unusable by ear in ways every automated guard passed: silence at launch, bare "text" Tab stops, a search field that absorbed its dock's label, Space not activating buttons, a failed load announced as nothing. NetCrux is built from the same chrome. These are the rules for any UI change here.

- **A new or changed surface gets a focus walk.** Follow `test/accessibility/screen_reader_test.dart`: `expectFocusAnnounced` where focus must land, `walkFocus` + `expectCleanFocusWalk`, and for a primary surface a transcript golden under `test/accessibility/goldens/` that you read before committing (`flutter test --update-goldens test/accessibility`). A golden diff is a change in what a blind user hears — review it like a UI diff.
- **Focus always lands somewhere named.** `WorkspaceScreen` is a `CruxFocusRegionScope`: top-level chrome goes in a `CruxFocusRegion` (the toolbar, a tab's stats strip + status bar), the start screen is the primary region while no tab is open, and a tab's `NetcruxIdeLayout` panes are regions already — never wrap one in another region. Never add an unnamed `Focus(autofocus: true)` holder around a large subtree — it absorbs every label below it.
- **One name per control, one node per row.** A label or a tooltip, not both. A list row is one named node (`semanticLabel`, `excludeFromSemantics` on the row gesture, `ExcludeSemantics` on text the label already says). A text field inside a labelled dock is its own `Semantics(container: true)`, or it takes the dock's name.
- **Errors and completions are announced** with `announceCrux` — a snackbar or a red pane is silent on desktop.
- **Space and Enter belong to the focused control.** A bare-key binding must not consume them when the focused widget accepts `ActivateIntent` (see `lib/core/shortcuts/shortcut_manager_widget.dart`).
- **Every pointer action on an element has a key.** On the focused schematic canvas Alt+Arrow selects cells, ports, pins and nets (the click), Enter pushes in (the double-click) and Shift+F10 / the Menu key opens the element menu (the right-click), each announced — see `lib/features/viewer/widgets/schematic_gesture_handler.dart` and `test/features/viewer/widgets/schematic_gesture_handler_keyboard_reach_test.dart`. A new pointer action gets its keyboard path in the same change; a context-menu entry is reachable automatically.
- **A list or tree is one Tab stop.** Arrow keys move a roving focus between rows that are each one named node — `lib/features/hierarchy/widgets/hierarchy_tree_panel.dart` is the pattern (Up/Down/Home/End, Right/Left expand and collapse, a row off screen scrolled in and focused after layout). Row buttons such as expand chevrons stay out of the Tab order. Change another row's focus-node properties from a focus listener only after a microtask.
- **No arrows or box glyphs in ARB strings** — `test/static/speakable_strings_test.dart` enforces it. Write menu paths as `Settings > Engines` and mappings in words.

### Dart Style

- Effective Dart guidelines.
- Files: `snake_case.dart`. Classes: `PascalCase`. Variables/functions: `camelCase`. Constants: `camelCase` (Dart convention). Providers: `camelCase` ending in `Provider`. Private members: `_prefixed`.
- No `!` operator unless the non-null contract is provably guaranteed and documented with a comment.

### Riverpod

- Use `@riverpod` annotation (code generation) for all providers, **except** the two sanctioned manual-provider classes below.
- Providers live in `providers/` within each feature module.
- Providers should be thin — delegate logic to services.
- Never use `ref.read` in a widget's `build` method — use `ref.watch`.

**Sanctioned manual `Provider`/`NotifierProvider` exceptions** (nearly half of this repo's providers fall in these two classes — it is the norm here, not a lint-suppressed exception):

1. **Extension-point seam providers and their opener callbacks.** Every Pro/Enterprise seam — `coneOfInfluenceServiceProvider`, `xTraceServiceProvider`, `bookmarkAnnotationStoreProvider`, the `*_service_provider.dart` family in `services/<feature>/`, and the `*_pane_openers.dart` callback-typed providers (`addBookmarkDialogOpenerProvider`, `showCdcAnalysisPaneOpenerProvider`, etc.) — is declared as a manual `Provider`, never `@riverpod`. This lets the Pro overlay's `proOverrides` call `.overrideWith(...)` on the exact declaration without the Pro repo needing the open-core build_runner-generated part file for that provider. Open-core registers the no-op default (`Noop*Service`, a no-op opener callback) so the action stays discoverable and badged; the Pro overlay swaps in the real implementation and overrides `proOverlayInstalledProvider` to true. The Pro-action gate (`allowProAction`) refuses a Pro-tier action in a build without the overlay with a "requires NetCrux Pro" snackbar, so the no-op is never a silent dead end — a Pro action invoked from outside the dispatcher goes through the same gate. New extension-point seams follow this pattern — see any `services/*/`-level `*_service_provider.dart` for the shape.
2. **Per-tab / per-pane state `Notifier`s overridden by the tab/pane registries.** `netcrux_tab_overrides.dart` gives every tab its own `ProviderContainer` and `netcrux_pane_overrides.dart` every pane (it re-binds only the pane render stats), re-instantiating each scoped provider via `.overrideWith(SomeNotifier.new)`; the Pro overlay's `proTabOverrides` extends the per-tab list. Both manual `Notifier` subclasses (`CdcAnalysisNotifier` here; `SelectedFsmNotifier` and the diff/activity/reset-domain pane-state notifiers in `proTabOverrides`) and `@Riverpod(keepAlive: true)`-codegen notifiers (`HierarchyTreeNotifier`, `SelectedElementNotifier`, `TraceOverlayNotifier`, `ViewportTransformNotifier`) appear in these registries side by side — codegen is not incompatible with per-tab scoping. The Pro-panel-adjacent state notifiers (FSM/CDC/diff/activity/reset-domain) are manual by established convention within those feature modules, matching the seam provider they sit beside in the same `providers/` directory; core viewer state (hierarchy, selection, trace overlay, viewport) is codegen. When adding a new per-tab state notifier, default to `@riverpod` unless it is the state half of a Pro extension-point seam.

### Localization

- 4 target languages shipped: English (`en`), Simplified Chinese (`zh_CN`), Japanese (`ja`), Korean (`ko`). Same as WaveCrux. These map to **five** ARB files, because `app_zh.arb` mirrors `app_zh_CN.arb` (see below) so a bare `zh` locale still resolves to Simplified Chinese — "four-locale parity" throughout this doc counts languages, not files.
- ARB files live in `lib/l10n/`. `app_en.arb` is the primary source of truth.
- `app_zh.arb` mirrors `app_zh_CN.arb` (identical translations, `@@locale` set to `zh`) so users on a bare `zh` locale get Simplified Chinese.
- Every message must have a corresponding `@<key>` metadata entry with a `description` field (in English).
- **Translation house style and glossary:** [`.claude/instructions.md`](.claude/instructions.md) is the NetCrux house style for CJK translations (core principles, mandatory NetCrux glossary, suite-wide term rulings, ICU plural rules including the `=1` case requirement, button-label length targets, per-language rules); the suite-canonical original lives in `wavecrux/.claude/instructions.md`. [`assets/l10n/glossary.json`](assets/l10n/glossary.json) is the machine-readable version of the glossary (with each term's never-use renderings, which the l10n house-style guard enforces) + acronym never-translate list + pluralization templates. Read both before adding or modifying any CJK string, and when DeepSeek/Claude/another translator audits the ARB files, point them at these two files first.
- **Static house-style guard:** `test/static/l10n_house_style_guard_test.dart` enforces key parity across locales, the `app_zh.arb` ↔ `app_zh_CN.arb` mirror, ICU `=1` plural cases, U+2026 ellipsis, and CJK punctuation width. It must pass in every commit that touches `lib/l10n/`.

Localization is set up: `lib/l10n/` carries the five ARB files (`app_en`, `app_zh_CN`, `app_zh`, `app_ja`, `app_ko`) with generated output in `lib/l10n/generated/`. Mirror `wavecrux/lib/l10n/` exactly.

## Project Structure

The directory layout mirrors WaveCrux's open-core structure:

```
lib/
├── app.dart            # bootstrap function + root widget
├── main.dart           # calls bootstrap(args: args)
├── app_router.dart     # go_router config (composition root)
├── netcrux_color_theme_bootstrap.dart  # applies the color-scheme setting (composition root)
├── core/               # Shared utilities, constants, extensions, theme
├── l10n/               # Localization: ARB source files + generated/
├── domain/             # Pure Dart: models, enums, interfaces — ZERO Flutter imports
├── services/           # Non-UI services — business logic
├── features/           # Feature modules (each owns its providers, screens, widgets)
├── shared/             # Shared widgets
└── plugins/            # Plugin discovery and loading infrastructure (when needed)
verification/           # Binding pre-release manual-verification manual
integration_test/       # macOS integration journeys
test/                   # Unit / widget / static tests (mirror of lib/)
docs/                   # ARCHITECTURE.md — the engineering manual
docs-site/              # MkDocs source of the user documentation
examples/               # Ready-to-open example projects
crux-shared/            # Git submodule: the suite-shared packages
```

See `wavecrux/lib/` for a fully populated reference.

## Key Architecture Rules

### IMPORTANT: Wire every new action into the action descriptor

Adding or changing a user-facing action means editing the exhaustive `descriptorFor` table in `lib/core/shortcuts/netcrux_action_descriptors.dart` — **never** re-introduce a per-surface "hidden actions" set or a per-surface enablement copy; those drifted apart per surface and were deleted. The three discovery surfaces (`DesktopMenuBar`, `CommandPaletteDialog`, `NetcruxToolbar`) and the keyboard dispatch path (`ShortcutManagerWidget.actionContextResolver`, wired by `WorkspaceScreen`) consume the table only via the derived selectors `groupedActionsFor` / `paletteActionsFor` / `isActionEnabled` over the shared `netcruxActionContextProvider` snapshot. Guardrails: (1) `descriptorFor` is an exhaustive `switch` — a new `NetcruxAction` fails to compile until a case is added; (2) `test/core/shortcuts/action_surface_conformance_test.dart` fails if any surface diverges from the table; (3) gating inputs are added as fields on `NetcruxActionContext` (mirrored from the active tab by `activeTabActionFlagsProvider`), not read ad-hoc inside a surface. Toolbar placement is opt-in: list `NetcruxActionSurface.toolbar` in the descriptor *and* add the keyed button in `NetcruxToolbar`; the conformance test cross-checks the two. See `docs/ARCHITECTURE.md` §6.5. Tier stays declared once on `NetcruxActionRequiredTier.requiredTier`; post-beta insufficient-tier activation shows `NetcruxUpgradeDialog` (the suite convention), and a Pro-tier action in an open-core build says it requires NetCrux Pro, rather than silently no-oping.

- **Domain layer has zero Flutter imports.** Pure Dart only. Models, enums, and interfaces live here.
- **Features depend on domain interfaces**, not service implementations.
- **The Pro overlay consumes this repo as a Git submodule.** It registers Pro/Enterprise concrete implementations via Riverpod overrides spread into the `bootstrap()` `ProviderScope`. Do not fork open-core code in the Pro overlay; if a Pro feature needs a new hook, define the extension-point interface here first, push, bump the submodule pin, then add the Pro implementation. See `wavecrux/CLAUDE.md` for the binding rule.
- **Open-core conflict semantics:** open-core overrides come first; Pro overrides spread last; later overrides win. Mirrors WaveCrux.

### IMPORTANT: Every `lib/` file is reachable from an entry point

`test/static/import_reachability_guard_test.dart` walks the import graph from `lib/main.dart` (every conditional-import branch counts) and fails on any hand-written `lib/` file it does not reach. A file nothing imports keeps its own tests green, so this is the check that notices. Delete or wire an orphan; an exemption is only for a file another consumer owns — the Pro overlay, or tests and tools — and the guard verifies that consumer still imports it (the overlay half when this repo is checked out as the overlay's submodule). The Pro overlay carries its own copy with an empty allowlist.

### IMPORTANT: Verification Documentation Required

The `verification/` folder is the binding pre-release manual-verification reference for every Open Core NetCrux feature. Verification entries are written as features land, not retrofitted later.

- [`verification/VERIFICATION_GUIDE.md`](verification/VERIFICATION_GUIDE.md) — detailed pre-release verification reference for every Open Core feature.
- [`verification/VERIFICATION_CHECKLIST.md`](verification/VERIFICATION_CHECKLIST.md) — quick sign-off bullet list per release.
- [`verification/fixtures/`](verification/fixtures/) — committed fixtures (elaboration sources, layout regression inputs/outputs, cross-probe scenarios) with `.expected.*.json` companions and regenerator scripts under `tool/`. Layout documented in `verification/fixtures/README.md`.

When you implement a new Open Core feature, add an extension-point seam, or make any change visible to a user of the open-core build, the same change set MUST:

1. **Add or update the feature's section** in `verification/VERIFICATION_GUIDE.md`. Populate: what it does (plain language), setup, step-by-step expected behavior, edge cases. The Automation Assessment / Coverage tag is mandatory on every bullet.
2. Add or update the corresponding bullet group in `verification/VERIFICATION_CHECKLIST.md`, including any new fixture references.
3. Commit any new fixtures under `verification/fixtures/<area>/` alongside their `.expected.*.json` companions, with the regenerator script under `tool/` documented in `verification/fixtures/README.md`.
4. **Pro features go in the Pro overlay verification, not here.** If your work is a Pro/Enterprise feature, the verification entry belongs in the Pro overlay's own verification guide. This open-core guide covers only what every open-core user can see.
5. **Don't ship implementation without its verification entry.** A feature shipping in code without a populated verification entry in the same commit set is a code-review-blocking defect — same rule as WaveCrux.

## User documentation lives in `docs-site/`

`docs-site/docs/` (MkDocs Material) is the source of truth for user
documentation, published at `https://docs.netcrux.app`. A change to
user-visible behaviour — a label, shortcut, flag, config key, file
format, tier or platform availability — updates the affected page in the
same change. Build with `mkdocs build --strict` from `docs-site/` (pinned
versions in `.github/workflows/docs.yml`); CI fails a broken link or
anchor. Keep page file names stable: in-app help links point at them.

## Git Conventions

- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- Branch naming: `feature/xxx`, `fix/xxx`. `main` is always deployable.

## Changes land through pull requests

Until the 1.0 code freeze, maintainers commit directly to `main`. From the
code freeze on, every change — by anyone — lands through a pull request
whose description documents the issue or feature, the fix or
implementation, how it was verified (tests added, CI gates passed), and
the user documentation updated in the same PR. Contributors sign a CLA
before a first merge, as described in `CONTRIBUTING.md`.

## Licensing

Apache License 2.0 — see [`LICENSE`](LICENSE), with third-party attributions in `NOTICES` and the name/logo policy in `TRADEMARK.md`. Contributions require a signed CLA (`CONTRIBUTING.md`).

## Suite UI consistency (MANDATORY for any UI change)

The four Crux apps (WaveCrux, NetCrux, LintCrux, SimCrux) are built as if they
were ONE app, and WaveCrux is the canon. The rules:

1. **Mirror-check:** a change to a shared surface (menus, toolbar, status bar,
   docks/panels, welcome screen, window chrome, Settings, dialogs, shortcuts,
   shared l10n keys) must be applied to the OTHER THREE apps in the same
   session — or explicitly flagged as pending in your final report. Never
   diverge silently. The sibling apps live at
   sibling checkouts of `wavecrux`, `netcrux`, `lintcrux` and `simcrux`.
2. **New surface:** adding a dialog / panel / dock tab / settings category /
   banner here requires answering "do the other three apps need this?" — and
   generic chrome starts life in crux-shared (`crux_dock`, `crux_workspace`,
   `crux_settings_ui`, `crux_cxp_ui`, ...), never as an app-local copy.
3. **Canon details:** WaveCrux is canonical unless the suite has settled a
   difference deliberately. Workflow dialogs are `barrierDismissible: false`;
   settings categories use the shared `CruxSettingsCategoryId` order and
   icons; l10n keys for shared strings use WaveCrux-style names in all four
   apps; the Language picker requires `MaterialApp.locale` wiring.
4. **Verify like CI:** `flutter analyze --fatal-infos --fatal-warnings` (the
   crux-shared Consumer CI fails on infos; plain `dart analyze` won't) + the
   full test suite for every repo you touched.
5. **User docs:** if you changed a user-visible usage model (panel
   behavior, shortcut, settings layout, menu location, dialog flow), update
   `docs-site/docs/` in the same change — grep it for the OLD wording — and
   check the other three products' documentation when the change was
   suite-wide.
