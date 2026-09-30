// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show exit, stdout;
import 'package:crux_about_dialog/crux_about_dialog.dart';
import 'package:crux_eula/crux_eula.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/app_router.dart';
import 'package:netcrux/core/about/netcrux_vendored_licenses.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';
import 'package:netcrux/core/cli/cli_launch_intent_provider.dart';
import 'package:netcrux/core/eula/netcrux_eula_storage.dart';
import 'package:netcrux/core/issue_reporter/netcrux_issue_reporter_strings.dart';
import 'package:netcrux/core/platform/netcrux_linux_desktop_app.dart';
import 'package:netcrux/core/platform_utils.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_storage.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_strings.dart';
import 'package:netcrux/core/theme/netcrux_theme.dart';
import 'package:netcrux/core/theme/netcrux_theme_tokens.dart';
import 'package:netcrux/core/updates/netcrux_update_strings.dart';
import 'package:netcrux/core/web/web_launch_params.dart';
import 'package:netcrux/core/web/web_launch_params_provider.dart';
import 'package:netcrux/core/web/window_location.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/beta_expiry/widgets/beta_expiry_gate.dart';
import 'package:netcrux/features/eula/netcrux_eula_overrides.dart';
import 'package:netcrux/features/issue_reporter/netcrux_issue_reporter_overrides.dart';
import 'package:netcrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/telemetry/netcrux_telemetry_overrides.dart';
import 'package:netcrux/features/update/netcrux_update_overrides.dart';
import 'package:netcrux/features/workspace/screens/workspace_screen.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/netcrux_color_theme_bootstrap.dart';
import 'package:netcrux/plugins/extra_localizations_delegates_provider.dart';
import 'package:netcrux/services/cli/cli_args.dart';
import 'package:netcrux/services/file_open/incoming_document_service.dart';
import 'package:netcrux/services/logging/severe_log_stderr_sink.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:netcrux/services/yosys/yosys_executable_provider.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:netcrux/shared/widgets/yosys_process_reaper.dart';

/// Root-scope overrides that every host of [NetcruxApp] must install.
///
/// Two `crux_shared` packages deliberately ship a **throwing** default so an
/// unwired product fails at composition rather than silently misbehaving —
/// `cruxUpdateConfigProvider` (no manifest, no product name) and
/// `cruxIssueReporterConfigProvider` (which repository would the report go
/// to?). [NetcruxApp] mounts the update banner and the screenshot boundary
/// from `MaterialApp.builder`, so anything that mounts the root widget —
/// `bootstrap`, and the widget tests that build their own root container —
/// needs these bound.
///
/// Collected here rather than inlined in `bootstrap` so a test cannot boot a
/// half-wired app and discover the gap as an unrelated-looking provider
/// exception.
final List<Override> netcruxAppOverrides = <Override>[
  // `crux_updates`: the manifest configuration, build info, the persisted
  // auto-check setting, the URL launcher, and both halves of the
  // observed-server-time loop that hardens beta expiry against a device-clock
  // rollback.
  ...netcruxUpdateOverrides,
  // `crux_issue_reporter`: the GitHub target, build info, and the
  // privacy-scrubbed session contributor. The overlay's extra "Pro State"
  // category arrives via `cruxIssueReporterDataProviderProvider`, whose
  // open-core default contributes nothing.
  ...netcruxIssueReporterOverrides,
  // `crux_audit`: the product id stamped into every audit event this
  // installation records. One JSONL file holds four products' events and this
  // is what makes it filterable — the same string the policy namespace uses,
  // so filtering the log and writing `.crux-policy.json` share one vocabulary.
  // Emission is unconditional; the SINK is what an administrator gates, and it
  // is `NoopAuditSink` until one sets `suite.audit.path`.
  cruxAuditProductIdProvider.overrideWithValue(NetCruxPolicyKeys.productId),
  // `crux_telemetry`: the product slug, the consent/installation-id store,
  // the URL launcher, the app version, the form-factor derivation, and the
  // locale. `cruxTelemetryConfigProvider` has no default binding, so anything
  // that touches the telemetry graph — including every workspace mutation —
  // needs these bound, which is why they live in the list every host installs
  // rather than inline in `bootstrap`.
  // Bind the EULA gate's persistence and quit path. Acceptance is required at
  // every edition, Open Core included (EULA 2.1).
  ...netcruxEulaOverrides,
  ...netcruxTelemetryOverrides,
];

/// Starts capturing diagnostics. Idempotent under hot restart.
///
/// The issue reporter's ring buffer takes every log record, and uncaught
/// framework and async errors are routed into the log (the console dumps are
/// preserved), so a failure during the session lands in a bug report. The
/// buffer is memory only, though; off the web, [SevereLogStderrSink] also
/// writes SEVERE records to stderr, the one trace a release build leaves once
/// the session is gone. [stderrSink] replaces the process-wide sink in tests.
@visibleForTesting
void attachDiagnosticSinks({SevereLogStderrSink? stderrSink}) {
  CruxIssueReporterLogBuffer.instance
    ..attachToLogging()
    ..captureFlutterErrors();
  if (!kIsWeb) (stderrSink ?? SevereLogStderrSink.instance).attach();
}

/// Forgets this installation's EULA acceptance when [args] carry
/// `--reset-eula`, so the agreement is presented again on this launch.
///
/// A testing affordance: once accepted, the agreement never returns until
/// `kCruxEulaVersion` changes, which makes the one surface with legal weight
/// the hardest to review twice. [storage] replaces the product store in tests.
@visibleForTesting
Future<void> resetEulaIfRequested(
  List<String> args, {
  CruxEulaStorage storage = const NetcruxEulaStorage(),
}) async {
  if (args.contains('--reset-eula')) {
    await resetCruxEulaAcceptance(storage);
  }
}

/// Entry-point body shared by the open-core `lib/main.dart` and the
/// Pro overlay's `lib/main.dart`. Open-core calls
/// `bootstrap(args: args)`; the Pro overlay calls
/// `bootstrap(args: args, extraOverrides: proOverrides)` to layer Pro/
/// Enterprise provider implementations on top without forking the bootstrap
/// logic.
///
/// CLI args are parsed by [CliArgParser] and the result is published into
/// [cliLaunchIntentProvider] so feature code reads it via Riverpod rather
/// than a global. The Welcome screen consults the provider on first build
/// to decide whether to land on `/` or auto-navigate into the project
/// viewer once that path is wired up.
///
/// [extraOverrides] are root-scope overrides; [extraTabOverrides] are
/// appended to every per-tab container's override list (after
/// [netcruxTabOverridesFactory], so later overrides win) via
/// [TabContainerManager]. The Pro overlay uses the tab hook to scope its own
/// providers per-tab — e.g. an analysis service whose `ref` must resolve the
/// active tab's `loadedNetlistProvider`. A root-scope override of such a
/// provider silently reads the root container's empty project instead of the
/// loaded design — the recurring per-tab scope-leak class. Per-tab services
/// belong in [extraTabOverrides].
///
/// [linuxDesktopApp] is the running binary's freedesktop identity, written
/// into the AppImage desktop entry on first run. Null means open core's
/// ([netcruxLinuxDesktopApp]); the Pro overlay passes its own. Nullable
/// rather than defaulted because the identity carries declared MIME types,
/// which validate their arguments and so cannot be `const`.
///
/// Mirrors the pattern WaveCrux documents in its `docs/ARCHITECTURE.md`
/// §10 (Extension Points). When adding extension-point providers, follow the
/// open-core-first rule: define the interface and a default implementation
/// here in the open-core repo, then add the Pro override in the overlay.
Future<void> bootstrap({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  List<Override> extraTabOverrides = const [],
  LinuxDesktopApp? linuxDesktopApp,
  @visibleForTesting void Function(int code) exitProcess = exit,
  @visibleForTesting
  IncomingDocumentService incomingDocuments = const IncomingDocumentService(),
}) async {
  // `--help` / `-h` short-circuits before the platform binding so the
  // ergonomic `netcrux --help` prints usage on stdout and exits cleanly,
  // matching every other CLI tool an HDL engineer reaches for. Mirrors
  // WaveCrux's contract (wavecrux/lib/app.dart).
  if (args.contains('--help') || args.contains('-h')) {
    // ignore: avoid_print, intentional CLI help output
    print(cliHelpText());
    // Returning is not enough: a desktop runner creates its window at launch
    // and keeps its event loop running after `main` returns, so the process
    // would never end. Flush the usage text, then exit.
    await stdout.flush();
    exitProcess(0);
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();

  // `--reset-telemetry-consent` puts this installation back to "never
  // answered", so the one-time disclosure mounts again this launch rather than
  // next one. A testing affordance: the dialog is deliberately
  // once-per-installation, which makes it the surface hardest to see twice.
  //
  // Before the container is built, because `TelemetryConsentStore` starts
  // reading the persisted value the moment anything touches the telemetry
  // graph. The installation id is left alone — see `resetTelemetryConsent`.
  if (args.contains('--reset-telemetry-consent')) {
    await resetTelemetryConsent(const NetcruxTelemetryStorage());
  }
  // `--reset-eula` does the same for the licence agreement, which is gated
  // once per installation on `kCruxEulaVersion`. Before the container is
  // built for the same reason: the acceptance store reads the persisted
  // version the moment the gate first asks.
  await resetEulaIfRequested(args);
  // Start capturing diagnostics before the first provider is constructed, so
  // an early-startup warning (a failed workspace restore, a Yosys probe
  // failure) is already captured by the time a user opens the issue reporter.
  attachDiagnosticSinks();
  // Flutter builds LicenseRegistry from every pub package's LICENSE file,
  // which misses anything vendored — elkjs ships as an asset, not a
  // package, and EPL-2.0 §3.1(b) is the obligation that most needs to be
  // visible. Registering here (a stream factory, so the asset is read only
  // if the user opens the license page) puts it alongside the rest.
  registerCruxVendoredLicenses(kNetcruxVendoredLicenses);
  // Suite-shared launch recovery flags (`--reset` / `--no-restore`),
  // parsed by the WaveCrux-ported `services/cli/cli_args.dart` module and
  // stripped before [CliArgParser] runs — its flag-stripping heuristic
  // would otherwise swallow the positional that follows a bare boolean
  // flag (`netcrux --reset top.v` must still open `top.v`).
  final launchFlags = parseCliArgs(args);
  final launchArgs = stripLaunchFlags(args);
  const parser = CliArgParser();
  // A document macOS launched the app to open (a Finder double-click) takes
  // the same route as that path on the command line, when the command line
  // names nothing itself.
  final launchIntent = await parser.parseLaunch(
    launchArgs,
    openedDocument: incomingDocuments.initialDocument,
  );
  final yosysOverride = parser.yosysPathOverride(launchArgs);

  // `--reset` is the documented escape hatch for a session so corrupt it
  // wedges startup: wipe the auto-managed workspace.json and every per-tab
  // session sidecar, then launch into an empty workspace. Runs BEFORE the
  // root container exists so the workspace notifier's first load sees
  // nothing to restore. Scoped to session state — settings, keymap, and
  // recent files are kept. No-op on web (no on-disk session there).
  if (!kIsWeb && launchFlags.reset) {
    final workspaceService = WorkspaceService<NetcruxTabPayload>(
      codec: const NetcruxWorkspaceCodec(),
    );
    await workspaceService.clear();
    await workspaceService.clearAllSidecars();
    // ignore: avoid_print, intentional CLI confirmation on stdout
    print('NetCrux: cleared saved session and workspace state (--reset).');
  }
  // On web, parse `window.location.search` + `window.location.hash`
  // for the `?json=…`, `#scope=…`, `#sig=…` deep-link contract. On
  // desktop the stub returns [WebLaunchParams.empty], so the workspace's
  // `?json=` launch step has nothing to open. The conditional
  // import in `window_location.dart` selects the right impl.
  final webLaunch = kIsWeb ? readWebLaunchParams() : WebLaunchParams.empty;
  // Construct the root ProviderContainer ourselves so the per-tab and
  // per-pane TabContainerManager / PaneContainerManager instances can
  // parent their child containers under it. The container is then
  // handed off to UncontrolledProviderScope, which never disposes it
  // — bootstrap owns the container for the app's lifetime.
  // Register the suite-shared chrome token catalog so Settings →
  // Appearance and `.crux-theme.json` packs resolve every chrome token
  // id to a registered descriptor.
  registerNetcruxThemeTokens();

  final rootContainer = ProviderContainer(
    overrides: <Override>[
      // Open-core overrides go here first. Pro overrides are spread last
      // so later overrides win for any shared extension-point provider.
      cliLaunchIntentProvider.overrideWithValue(launchIntent),
      cliYosysPathOverrideProvider.overrideWithValue(yosysOverride),
      webLaunchParamsProvider.overrideWithValue(webLaunch),
      // `--no-restore` skips this launch's workspace rehydration without
      // deleting anything: the injected restore gate short-circuits
      // `shouldRestoreOnLaunch` so `workspace.json` is never loaded (and
      // stays untouched on disk for the next normal launch).
      if (launchFlags.noRestore)
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(restoreGate: () async => false),
        ),
      // Bridge NetCrux persistence (AppSettings.core.activeThemeName +
      // themeOverrides) into crux_theme's cruxColorThemeProvider, exactly
      // as WaveCrux does. Spread before extraOverrides so the Pro overlay
      // can layer its own override on top per the open-core conflict
      // semantics.
      netcruxCruxColorThemeOverride,
      ...netcruxAppOverrides,
      ...extraOverrides,
    ],
  );
  final tabContainerManager = TabContainerManager(
    rootContainer: rootContainer,
    // The Pro overlay's `extraTabOverrides` spread AFTER the open-core
    // list so later overrides win, matching the root-container conflict
    // semantics above. Open-core passes an empty list.
    overridesFactory: (tabId) => <Override>[
      ...netcruxTabOverridesFactory(tabId),
      ...extraTabOverrides,
    ],
  );
  final paneContainerManager = PaneContainerManager(
    rootContainer: rootContainer,
    overridesFactory: netcruxPaneOverridesFactory,
  );
  // Publish the tab-container manager to root-scope providers (the
  // active-tab action-flags mirror behind `netcruxActionContextProvider`
  // needs to reach the active tab's container from the root). Must happen
  // before `runApp` so no provider ever observes the unset holder.
  rootContainer.read(tabContainerManagerHolderProvider).manager =
      tabContainerManager;
  // Register both container managers as structural scope reconcilers.
  // `WorkspaceNotifier` emits a snapshot of the live tab/pane ids after
  // every state transition and each manager prunes itself against it.
  // Without this, closing a tab never disposes its `ProviderContainer`
  // — every provider, subscription, and timer it holds survives for the
  // process lifetime — and, worse, because tab ids round-trip through
  // the workspace document, reloading a workspace can hand a revived id
  // the dead tab's container and bleed its state into the new tab.
  // Eviction is a property of the workspace's shape rather than a call
  // each site has to remember.
  rootContainer.read(netcruxWorkspaceProvider.notifier)
    ..addScopeReconciler(tabContainerManager)
    ..addScopeReconciler(paneContainerManager);

  // Say which policy file won, or that one was refused
  // (<https://edacrux.app/policy-reference#failures>). Without this call a
  // file whose signature fails is refused **silently**: from inside a running
  // app a refused policy and an absent one are indistinguishable, and telling
  // those two apart is the whole point of the distinction. A refusal means the
  // administrator's policy is not in force, so saying nothing is fail-open with
  // no signal.
  //
  // The two halves land in different places and `reportPolicyLoad` decides
  // which — a refusal CANNOT reach the audit sink, because the sink's path
  // comes from `suite.audit.path`, which comes from the file that was just
  // refused. See `crux_license`'s `PolicyReportDestination`.
  //
  // Here rather than in the Pro overlay: the policy file is honoured at every
  // tier for the day-one keys, so an open-core seat pointed at a bad file has
  // to be told too.
  reportPolicyLoad(
    result: rootContainer.read(cruxPolicyProvider),
    // Names any key the administrator set that this build does not act on.
    productId: NetCruxPolicyKeys.productId,
    recorder: rootContainer.read(cruxAuditRecorderProvider),
  );

  // Windows/Linux only: switch the window to frameless (TitleBarStyle.hidden)
  // and show it once ready, so the in-window VS Code-style title bar drawn by
  // DesktopMenuBar replaces the OS title bar. No-op / never invoked elsewhere
  // (macOS keeps its native menu; web has no window). Geometry restore across
  // sessions is not wired yet — the window opens at the default size.
  if (useCustomWindowChrome) {
    await initWindowChrome();
  }

  // AppImage first-run desktop self-integration (Linux/Wayland): write the
  // host-side .desktop + hicolor icons so GNOME/Ubuntu matches this window's
  // app_id to its dock icon. Inert off Linux and off AppImage; never throws.
  // The identity is the running binary's — open core's by default, the
  // overlay's when the overlay passes its own.
  await maybeIntegrateDesktopEntry(linuxDesktopApp ?? netcruxLinuxDesktopApp);

  runApp(
    UncontrolledProviderScope(
      container: rootContainer,
      child: WorkspaceManagersScope(
        tabContainerManager: tabContainerManager,
        paneContainerManager: paneContainerManager,
        child: const NetcruxApp(),
      ),
    ),
  );
}

/// Root widget that wires the NetCrux theme, localization, and routing
/// into a [MaterialApp.router]. The Welcome screen lives at `/`; future
/// routes (project viewer, settings, about) are registered in
/// [appRouterProvider].
class NetcruxApp extends ConsumerWidget {
  /// Creates the root application widget.
  const NetcruxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final extraDelegates = ref.watch(extraLocalizationsDelegatesProvider);
    // Apply the persisted UI language (Appearance → Language). Without this,
    // CoreSettings.locale is persisted but never applied, and the four shipped
    // translations are unreachable except via the OS language.
    final localeTag = ref.watch(
      appSettingsProvider.select((s) => s.value?.core.locale),
    );
    final locale = _toLocale(localeTag ?? 'en');
    // Drive the Material brightness from the active preset (so picking
    // WaveCrux Light flips the chrome to light, Solarized Dark to dark,
    // etc.) and apply the preset's chrome tokens onto the base NetCrux
    // theme. See applyChromeTokens in package:crux_theme/crux_theme.dart.
    final cruxColorTheme = ref.watch(cruxColorThemeProvider);
    final chromeExt = CruxThemeExtension(theme: cruxColorTheme);
    final themeMode = themeModeFromBrightness(cruxColorTheme);
    final lightTheme = applyChromeTokens(
      NetcruxTheme.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    final darkTheme = applyChromeTokens(
      NetcruxTheme.dark().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    // High-contrast variants are selected by MaterialApp when the OS
    // "increase contrast" accessibility setting is on (MediaQuery.highContrast),
    // hardening the seed-derived borders to fully-opaque outline colors.
    final highContrastLightTheme = applyChromeTokens(
      NetcruxTheme.highContrastLight().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    final highContrastDarkTheme = applyChromeTokens(
      NetcruxTheme.highContrastDark().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    // Wrap the MaterialApp in WorkspaceLifecycleObserver so the auto-saved
    // workspace.json gets flushed on AppLifecycleState.paused / detached
    // (mobile background or desktop close). The observer reads
    // `netcruxWorkspaceProvider`'s notifier and calls flushPendingSave().
    return YosysProcessReaper(
      child: WorkspaceLifecycleObserver<NetcruxTabPayload>(
        provider: netcruxWorkspaceProvider,
        child: MaterialApp.router(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          onGenerateTitle: (context) => L10N.of(context).appTitle,
          theme: lightTheme,
          darkTheme: darkTheme,
          highContrastTheme: highContrastLightTheme,
          highContrastDarkTheme: highContrastDarkTheme,
          themeMode: themeMode,
          localizationsDelegates: [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            ...extraDelegates,
          ],
          supportedLocales: L10N.supportedLocales,
          locale: locale,
          routerConfig: router,
          builder: _buildAppChrome,
        ),
      ),
    );
  }

  /// Wraps the routed content in the app-wide chrome that must sit *inside*
  /// `MaterialApp` (so `L10N.of` and the localization delegates resolve) but
  /// *above* the router's content.
  ///
  /// Layering, outermost first:
  ///
  /// 1. A nested [ProviderScope] supplying the localized string bundles for
  ///    the two `crux_shared` packages that render user-visible copy. Both
  ///    interfaces need `L10N.of(context)`, which the root container built by
  ///    `bootstrap` cannot reach. Neither provider has dependents inside its
  ///    package beyond the widgets read here, so scoping them does not move
  ///    `updateStatusProvider` (and its launch/periodic timer) off the root.
  /// 2. The screenshot [RepaintBoundary] the beta issue reporter captures.
  ///    Placed above the banners so a report shows exactly what the user saw,
  ///    banners included.
  /// 3. [BetaExpiryGate], so a blocking expiry modal covers the update banner
  ///    — an expired build must not offer a second, competing call to action.
  /// 4. [UpdateBanner], the dismissible "a newer NetCrux is available" strip.
  /// 5. [DesktopMenuBar], which wraps *every* route rather than living inside
  ///    `WorkspaceScreen`. On Windows/Linux it draws the frameless window's
  ///    title bar and its min/maximize/close caption buttons, so mounting it
  ///    inside a screen meant navigating to /settings removed the title bar
  ///    and left no way to close the window with the mouse. Menu items
  ///    dispatch by firing a [NetcruxActionIntent] from the focused context,
  ///    which walks up to the `Actions` widget `ShortcutManagerWidget`
  ///    registers inside the workspace screen — the same path the keyboard
  ///    and command palette already use.
  static Widget _buildAppChrome(BuildContext context, Widget? child) {
    final l10n = L10N.of(context);
    final Widget app = ProviderScope(
      overrides: [
        cruxUpdateStringsProvider.overrideWithValue(NetcruxUpdateStrings(l10n)),
        cruxIssueReporterStringsProvider.overrideWithValue(
          NetcruxIssueReporterStrings(l10n),
        ),
        // The consent surfaces render their own copy, so the disclosure needs
        // the NetCrux ARB bundle exactly the way the update banner does — and
        // for the same reason it cannot live in the root container built by
        // `bootstrap`, which has no `BuildContext`.
        cruxTelemetryStringsProvider.overrideWithValue(
          NetcruxTelemetryStrings(l10n),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) => RepaintBoundary(
          key: ref.watch(cruxAppScreenshotBoundaryKeyProvider),
          child: DesktopMenuBar(
            onAction: _dispatchFromMenu,
            child: BetaExpiryGate(
              // Below the expiry gate so an expired build's blocking modal
              // still wins — an expired build has nothing to collect and the
              // user can do nothing about it — and above the update banner so
              // the one-time disclosure is not competing for the top of the
              // window with an update prompt. Renders its child untouched for
              // the whole beta: without the dev flag it never mounts at all.
              child: CruxEulaGate(
                // OUTSIDE the telemetry disclosure, and that ordering is not a
                // preference. The disclosure asks for consent to a term the
                // EULA itself defines (EULA 8), so collecting it first would
                // have the user answering a question about a contract they had
                // not been shown. It is also the only ordering under which the
                // EEA/UK/CH/KR opt-in default is defensible.
                //
                // Inside the expiry gate, on the same rule that puts the
                // disclosure there: an expired build has nothing to license.
                //
                // Not localized — see CruxEulaStrings. The agreement is
                // executed in English, so its chrome stays English rather than
                // implying a translated contract exists.
                isPhoneLayout: !isDesktopPlatform,
                child: TelemetryConsentGate(
                  // NetCrux's own layout idiom, handed to the shared widget
                  // rather than re-derived inside it. `isDesktopPlatform` is
                  // the single bit every adaptive surface in this app reads, so
                  // the sheet presentation appears exactly where `openAdaptive`
                  // would push a route instead of showing a dialog.
                  isPhoneLayout: !isDesktopPlatform,
                  // The package defaults are the desktop Material values and
                  // already clear the 44 dp consent floor; NetCrux has no
                  // device-metrics system of its own to feed in.
                  child: UpdateBanner(child: child ?? const SizedBox.shrink()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Windows/Linux: restore the drop shadow + drag-to-resize edges the
    // frameless window loses. No-op wrapper elsewhere.
    return useCustomWindowChrome ? buildWindowFrame(app) : app;
  }

  /// Routes a menu selection to the active screen's action handler.
  ///
  /// The menu bar sits above the router, so it cannot call
  /// `WorkspaceScreen._dispatchAction` directly. Firing the intent from the
  /// focused context walks up to the `Actions` widget the screen registers,
  /// landing on the same dispatcher the keyboard and palette use. Falls back
  /// to the root navigator's context when nothing holds focus (e.g. right
  /// after launch, before the canvas takes it).
  static void _dispatchFromMenu(NetcruxAction action) {
    // Quit must work on EVERY route. The intent round-trip below lands on
    // the Actions handler the WORKSPACE screen registers, so on the welcome
    // route a menu Quit silently no-oped (the app could only be quit from
    // the Dock). Handle it here, with the same semantics as the workspace
    // dispatcher's case.
    if (action == NetcruxAction.quit) {
      exit(0);
    }
    // Prefer the focused context so a screen-specific handler still wins,
    // but only when it actually resolves one: right after launch primary
    // focus sits on the route's modal focus scope, which is ABOVE the
    // screen's `Actions` widget, so the walk-up finds nothing and the
    // selection silently no-ops. Fall back to an anchor mounted BELOW that
    // `Actions` widget rather than to `rootNavigatorKey`, whose context is
    // the Navigator's own — above the routes, and so equally unreachable.
    final focusCtx = WidgetsBinding.instance.focusManager.primaryFocus?.context;
    final ctx =
        (focusCtx != null &&
            Actions.maybeFind<NetcruxActionIntent>(focusCtx) != null)
        ? focusCtx
        : workspaceActionsAnchorKey.currentContext;
    if (ctx == null) return;
    Actions.maybeInvoke<NetcruxActionIntent>(ctx, NetcruxActionIntent(action));
  }

  Locale _toLocale(String tag) => switch (tag) {
    'zh_CN' => const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
    'ja' => const Locale('ja'),
    'ko' => const Locale('ko'),
    _ => const Locale('en'),
  };
}
