// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/core/web/web_launch_params.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/search/design_search_service.dart';

/// Applies the web viewer's `#scope=` and `#sig=` URL hints to a tab once its
/// netlist has loaded, so a shared link opens on the place it names.
///
/// `#scope=top.cpu.alu` is the dotted path the breadcrumb shows: the top
/// module's name, then instance names. `#sig=` names a net or cell; it is
/// looked up in the scope `#scope=` selected first, then anywhere in the
/// design, and the canvas centres on it — a net on the cell that drives it,
/// the same target a search result uses. A hint that names nothing in the
/// design is ignored, leaving the design at its root.
@immutable
class WebDeepLink {
  /// Creates a deep link from its two hints.
  const WebDeepLink({this.scope, this.signal});

  /// The link carried by [params].
  factory WebDeepLink.fromLaunchParams(WebLaunchParams params) =>
      WebDeepLink(scope: params.autoScope, signal: params.autoSignal);

  /// The `#scope=` hint, or null.
  final String? scope;

  /// The `#sig=` hint, or null.
  final String? signal;

  /// Pushes [model] into [tab]'s hierarchy if it is not there yet, then
  /// applies the scope and the signal, in that order.
  void applyTo(ProviderContainer tab, NetlistModel model) {
    final tree = tab.read(hierarchyTreeProvider.notifier);
    if (!identical(tab.read(hierarchyTreeProvider).model, model)) {
      tree.setModel(model);
    }
    final scope = this.scope;
    if (scope != null) tree.selectByPath(scopeSegments(scope, model));
    final signal = this.signal;
    if (signal != null) _revealSignal(tab, model, signal);
  }

  /// The instance-name path [scope] denotes: its dotted segments without the
  /// leading top-module name, which the hierarchy root already is.
  @visibleForTesting
  static List<String> scopeSegments(String scope, NetlistModel model) {
    final segments = scope.split('.').where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.first == model.topModule?.name) {
      segments.removeAt(0);
    }
    return segments;
  }

  static void _revealSignal(
    ProviderContainer tab,
    NetlistModel model,
    String signal,
  ) {
    final matches = const DesignSearchService()
        .search(
          model: model,
          query: '^${RegExp.escape(signal)}\$',
          mode: SearchMode.regex,
        )
        .where((r) => r.name == signal)
        .toList();
    if (matches.isEmpty) return;
    final current = tab.read(hierarchyTreeProvider).selected;
    final hit = matches.firstWhere(
      (r) => r.scopeNode == current,
      orElse: () => matches.first,
    );
    tab.read(hierarchyTreeProvider.notifier).selectScope(hit.scopeNode);
    final String? target;
    switch (hit.kind) {
      case SearchResultKind.instance:
      case SearchResultKind.cell:
        target = hit.name;
      case SearchResultKind.net:
        final module = hit.scopeNode.resolve(model);
        target = module == null
            ? null
            : DesignSearchService.driverCellForNet(module, hit.name);
    }
    if (target == null) return;
    tab
        .read(selectedElementProvider.notifier)
        .select(SelectedElement.cell(cellId: target));
    tab.read(revealRequestProvider.notifier).request(target);
  }
}
