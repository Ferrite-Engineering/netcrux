// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/workspace/providers/active_tab_action_flags_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

/// Attribute key carrying the open-tab count to a `*-pro` data provider.
const String kNetcruxIssueAttrOpenTabs = 'openTabCount';

/// Attribute key carrying whether the active tab has an elaborated design.
const String kNetcruxIssueAttrHasNetlist = 'hasNetlist';

/// Attribute key carrying the elaborated module count of the active tab.
const String kNetcruxIssueAttrModuleCount = 'moduleCount';

/// Attribute key carrying the elaborated cell count of the active tab.
const String kNetcruxIssueAttrCellCount = 'cellCount';

/// Attribute key carrying the sorted ids of the Pro analysis surfaces that
/// currently hold a result in the active tab (`cdc`, `resetDomain`, `fsm`,
/// `diff`, `waveform`, `activity`, `xTrace`).
///
/// The overlay seam (`cruxIssueReporterDataProviderProvider`) reads this to
/// build its "Pro State" category without re-resolving the active tab's
/// `ProviderContainer` itself — which it could not do from a plain `Provider`
/// body without repeating the root-mirror plumbing below.
const String kNetcruxIssueAttrActiveProSurfaces = 'activeProSurfaces';

/// Builds NetCrux's privacy-scrubbed [CruxIssueSessionContext] — the product
/// seam of the shared beta issue reporter.
///
/// **Privacy contract.** Every field is a count, a fixed enumeration value, or
/// a format/language name. Nothing here is derived from the user's filesystem
/// or from identifiers in their RTL: no source-file paths, no project path, no
/// module / instance / net names, no Yosys stderr (which quotes source paths
/// verbatim). The sibling test under `test/` asserts the rendered Session
/// State body contains no path separator against a realistically populated
/// session.
///
/// Per-tab state is read out of the **active tab's** own `ProviderContainer`
/// via [TabContainerManagerHolder], the same root-mirror route
/// [ActiveTabActionFlagsNotifier] uses. Reading those providers off `ref`
/// would resolve the empty root container instead of the loaded design — the
/// recurring per-tab scope-leak class.
///
/// Degrades to whatever it managed to collect when the workspace plumbing is
/// absent (a bare unit-test `ProviderContainer` has no tab manager), so the
/// reporter never fails to open because the session snapshot could not be
/// built.
CruxIssueSessionContext buildNetcruxIssueSessionContext(Ref ref) {
  final builder = CruxIssueSessionContextBuilder();

  final workspace = ref.watch(netcruxWorkspaceProvider).value;
  final yosys = ref.watch(yosysAvailabilityProvider).value;
  builder
    ..addCount(
      'Open tabs',
      workspace?.tabs.length ?? 0,
      attributeKey: kNetcruxIssueAttrOpenTabs,
    )
    ..addCount('Panes', workspace?.panes.length ?? 0)
    ..addText('Yosys', _yosysLabel(yosys));

  final flags = ref.watch(activeTabActionFlagsProvider);
  final container = _activeTabContainer(ref);

  var sourceFileCount = 0;
  var languages = const <String>[];
  var moduleCount = 0;
  var cellCount = 0;
  var netCount = 0;
  var elaboration = 'no design';

  if (container != null) {
    // `guard` makes the degradation this function's doc comment promises
    // actually true. Reaching the active tab's own container is a multi-step
    // walk through workspace plumbing, and the issue reporter exists to let a
    // user report a broken state — so it must still open when the state it
    // wants to describe is the broken thing. Whatever was collected before the
    // throw is kept.
    builder.guard(() {
      final project = container.read(currentProjectProvider);
      sourceFileCount = project.sourceFiles.length;
      languages = <String>{
        for (final path in project.sourceFiles)
          project.resolveLanguage(path).name,
      }.toList()..sort();

      final netlist = container.read(loadedNetlistProvider);
      final model = netlist.value;
      elaboration = switch (netlist) {
        AsyncError() => 'failed',
        AsyncLoading() => 'in progress',
        _ when model != null => 'succeeded',
        _ => sourceFileCount == 0 ? 'no design' : 'not run',
      };
      if (model != null) {
        moduleCount = model.modules.length;
        cellCount = _cellCount(model);
        netCount = _netCount(model);
      }
    });
  }

  builder
    ..addCount('Source files (active tab)', sourceFileCount)
    ..addList('Source languages', languages)
    ..addText('Elaboration', elaboration)
    ..addCount(
      'Modules',
      moduleCount,
      attributeKey: kNetcruxIssueAttrModuleCount,
    )
    ..addCount('Cells', cellCount, attributeKey: kNetcruxIssueAttrCellCount)
    ..addCount('Nets', netCount)
    ..addFlag(
      'Schematic laid out',
      value: flags.hasNetlist,
      attributeKey: kNetcruxIssueAttrHasNetlist,
    )
    ..addFlag('Selection', value: flags.hasSelection)
    ..addFlag('Trace overlay', value: flags.hasTraceOverlay)
    ..addList(
      'Active analysis panes',
      _activeProSurfaces(flags),
      attributeKey: kNetcruxIssueAttrActiveProSurfaces,
    );

  return builder.build();
}

/// Root-scope override binding [buildNetcruxIssueSessionContext] to the shared
/// reporter's product seam. Spread into the root container by `bootstrap`.
final Override netcruxIssueSessionContextOverride =
    cruxIssueSessionContextProvider.overrideWith(
      buildNetcruxIssueSessionContext,
    );

/// Resolves the active tab's per-tab container, or `null` when no tab is open
/// or `bootstrap` never ran (unit tests).
ProviderContainer? _activeTabContainer(Ref ref) {
  final activeTabId = ref.watch(
    netcruxWorkspaceProvider.select((ws) => ws.value?.activeTabId),
  );
  final manager = ref.watch(tabContainerManagerHolderProvider).manager;
  if (activeTabId == null || manager == null) return null;
  return manager.containerFor(activeTabId);
}

/// The sorted ids of the analysis surfaces holding a result in the active tab.
/// Fixed vocabulary — never a user-supplied name.
List<String> _activeProSurfaces(ActiveTabActionFlags flags) => <String>[
  if (flags.cdcAnalysisPresent) 'cdc',
  if (flags.resetAnalysisPresent) 'resetDomain',
  if (flags.fsmFocused) 'fsm',
  if (flags.comparisonActive) 'diff',
  if (flags.waveformLoaded) 'waveform',
  if (flags.activityColoringActive) 'activity',
  if (flags.hasXTraceResult) 'xTrace',
];

int _cellCount(NetlistModel model) {
  var total = 0;
  for (final module in model.modules.values) {
    total += module.cells.length;
  }
  return total;
}

int _netCount(NetlistModel model) {
  var total = 0;
  for (final module in model.modules.values) {
    total += module.nets.length;
  }
  return total;
}

/// Reports whether the Yosys engine resolved, never *where* it resolved to —
/// the executable path is exactly the kind of filesystem detail the privacy
/// contract excludes.
String _yosysLabel(YosysAvailability? availability) {
  if (availability == null) return 'not probed';
  return availability.isAvailable ? 'available' : 'unavailable';
}
