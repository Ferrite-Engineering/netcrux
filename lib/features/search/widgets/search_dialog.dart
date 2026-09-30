// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/help_urls.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/search/design_search_service.dart';

/// Modal search overlay (Cmd/Ctrl+F), hosted on the suite-standard
/// [CruxSearchDialog] shell (query field, debounce, ↑/↓/Enter navigation,
/// empty state).
///
/// NetCrux supplies the three search-mode chips via the shell's header
/// seam, the [DesignSearchService] walk, and the result-activation side
/// effects: jump the hierarchy notifier to the owning scope, select the
/// matching cell or net (when applicable), then the shell closes the
/// dialog.
class SearchDialog extends ConsumerStatefulWidget {
  /// Creates a search dialog.
  const SearchDialog({super.key});

  /// Pushes the dialog onto the Navigator above [context].
  ///
  /// The dialog mounts under the root navigator, outside the active
  /// tab's per-tab `UncontrolledProviderScope`, so its per-tab reads
  /// (`hierarchyTreeProvider`, `selectedElementProvider`,
  /// `traceOverlayProvider`) would otherwise resolve against the empty
  /// root container — searching an empty model and applying selection to
  /// no tab. [container] is the active tab's `ProviderContainer`; the
  /// dialog subtree is wrapped in an [`UncontrolledProviderScope`] backed
  /// by it so the search reads and mutates the active tab's state.
  static Future<void> show(
    BuildContext context, {
    required ProviderContainer container,
  }) {
    // Re-entrancy guard: Cmd/Ctrl+F auto-repeat or a double-tap on the menu /
    // palette entry must not stack a second search dialog. Guarded inside the
    // opener so every caller is covered.
    return ModalGuard.run(
      'search',
      () => showDialog<void>(
        context: context,
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: const SearchDialog(),
        ),
      ),
    );
  }

  @override
  ConsumerState<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<SearchDialog> {
  static const DesignSearchService _service = DesignSearchService();

  SearchMode _mode = SearchMode.substring;

  List<SearchResult> _search(String query) {
    final model = ref.read(hierarchyTreeProvider).model;
    if (model == null) return const <SearchResult>[];
    return _service.search(model: model, query: query, mode: _mode);
  }

  void _applyResult(SearchResult result) {
    // Recorded on *activation*, not on every keystroke: the shell re-runs the
    // walk on each debounced edit, so counting there would measure typing.
    // Activating a hit is the point at which the search did its job, and the
    // mode is the thing worth knowing. `SearchMode` is a Dart enum, so
    // it reaches the wire through `telemetryEnumToken`; the query string never
    // does, under any circumstances.
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'search.used',
            properties: <String, Object?>{'mode': telemetryEnumToken(_mode)},
          ),
        );
    // The AUDIT event, on the same activation seam and for the same reason —
    // recording each debounced keystroke would measure typing, not searching.
    // **The query string is not in the payload, and must never be.** A search
    // term in a netlist is a signal or instance name, which is design IP; this
    // file is read by whoever runs the organization's log shipper, and "what
    // were people looking for in our RTL" is not a question an audit trail is
    // entitled to answer. What it records is that a search ran, in which mode,
    // and what class of thing was activated.
    ref
        .read(cruxAuditRecorderProvider)
        .record(
          NetCruxAuditKinds.searchExecuted,
          payload: <String, Object?>{
            'mode': _mode.name,
            'resultKind': result.kind.name,
          },
        );
    ref
      ..read(hierarchyTreeProvider.notifier).selectScope(result.scopeNode)
      ..read(traceOverlayProvider.notifier).clear();
    final selectionNotifier = ref.read(selectedElementProvider.notifier);
    final revealNotifier = ref.read(revealRequestProvider.notifier);
    switch (result.kind) {
      case SearchResultKind.instance:
      case SearchResultKind.cell:
        // Select the cell AND ask the canvas to reveal it — in a large
        // design the selected cell is almost always off-screen, so the
        // selection was previously set invisibly. The reveal is parked in
        // a provider (not driven imperatively) because switching scope
        // re-lays-out asynchronously; the gesture handler centers on the
        // cell once its scope's layout is ready.
        selectionNotifier.select(SelectedElement.cell(cellId: result.name));
        revealNotifier.request(result.name);
      case SearchResultKind.net:
        // A net has no on-canvas body of its own — reveal the cell that
        // DRIVES it (e.g. clicking a register signal jumps to its
        // flip-flop) instead of the old behaviour of clearing the
        // selection (which left the click doing nothing visible).
        final model = ref.read(hierarchyTreeProvider).model;
        final module = model == null ? null : result.scopeNode.resolve(model);
        final driver = module == null
            ? null
            : DesignSearchService.driverCellForNet(module, result.name);
        if (driver != null) {
          selectionNotifier.select(SelectedElement.cell(cellId: driver));
          revealNotifier.request(driver);
        } else {
          // Undriven (a module input / constant / dangling net): nothing to
          // center on, but at least switch to its scope (done above).
          selectionNotifier.clear();
        }
    }
  }

  Widget _modeChips(BuildContext context, VoidCallback refresh) {
    final l10n = L10N.of(context);
    void select(SearchMode mode) {
      setState(() => _mode = mode);
      refresh();
    }

    return Row(
      children: <Widget>[
        ChoiceChip(
          label: Text(l10n.searchModeSubstring),
          selected: _mode == SearchMode.substring,
          onSelected: (_) => select(SearchMode.substring),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text(l10n.searchModeGlob),
          selected: _mode == SearchMode.glob,
          onSelected: (_) => select(SearchMode.glob),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text(l10n.searchModeRegex),
          selected: _mode == SearchMode.regex,
          onSelected: (_) => select(SearchMode.regex),
        ),
        const Spacer(),
        // Contextual docs: the "Search Design" section of the navigating
        // guide (glob / regex syntax, result activation semantics).
        CruxHelpLink(
          url: HelpUrls.navigating,
          tooltip: l10n.helpLinkLearnMore,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxSearchDialog<SearchResult>(
      title: l10n.searchDialogTitle,
      hintText: l10n.searchDialogHint,
      emptyLabel: l10n.searchNoResults,
      search: _search,
      headerBuilder: _modeChips,
      onActivateResult: _applyResult,
      rowBuilder:
          (
            rowContext,
            result, {
            required highlighted,
            required onActivate,
          }) {
            final kindLabel = switch (result.kind) {
              SearchResultKind.instance => l10n.searchResultInstance,
              SearchResultKind.cell => l10n.searchResultCell,
              SearchResultKind.net => l10n.searchResultNet,
            };
            return CruxSearchResultTile(
              title: result.name,
              subtitle: result.scope,
              leading: _kindIcon(result.kind),
              trailingChipLabel: kindLabel,
              highlighted: highlighted,
              onTap: onActivate,
            );
          },
    );
  }

  Icon _kindIcon(SearchResultKind kind) {
    switch (kind) {
      case SearchResultKind.instance:
        return const Icon(Icons.layers_outlined, size: 18);
      case SearchResultKind.cell:
        return const Icon(Icons.crop_square_outlined, size: 18);
      case SearchResultKind.net:
        return const Icon(Icons.linear_scale, size: 18);
    }
  }
}
