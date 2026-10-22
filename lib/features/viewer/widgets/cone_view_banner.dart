// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/shortcuts/action_tier_label.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/services/cone_view_controller.dart';
import 'package:netcrux/features/workspace/services/pro_action_gate.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/net_name_lookup.dart';
import 'package:netcrux/services/schematic/transitive_cone_resolver_provider.dart';

/// The bar above the schematic while it shows a cone view: what the cone
/// is (its root and how many of the scope's cells it holds), its direction
/// and depth, and Show Whole Scope. Renders nothing for a whole-scope
/// layout.
///
/// Each control is one Tab stop. Choosing a direction or a depth lays the
/// cone out again; All levels is the Pro form and goes through the same
/// tier gate as View > Cone View, All Levels. A new cone is announced.
class ConeViewBanner extends ConsumerStatefulWidget {
  /// Creates the bar.
  const ConeViewBanner({super.key});

  @override
  ConsumerState<ConeViewBanner> createState() => _ConeViewBannerState();
}

class _ConeViewBannerState extends ConsumerState<ConeViewBanner> {
  ConeViewExtent? _announced;

  @override
  Widget build(BuildContext context) {
    final laidOut = ref.watch(currentLaidOutGraphProvider).value;
    final extent = laidOut?.cone;
    if (laidOut == null || extent == null) {
      _announced = null;
      return const SizedBox.shrink();
    }
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final request = extent.request;
    final model = ref.watch(loadedNetlistProvider).value;
    final summary = l10n.coneViewSummary(
      _rootLabel(
        laidOut,
        request.root,
        model == null ? null : request.scope.resolve(model),
      ),
      laidOut.graph.cells.length,
      extent.scopeCellCount,
    );
    if (_announced != extent) {
      _announced = extent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) announceCrux(context, summary);
      });
    }
    final controller = ConeViewController(ref.read);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // A wrap rather than a row: in a narrow pane (a split, or a docked
        // panel open) the controls drop below the description instead of
        // running off the edge.
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            CruxSegmentedControl<ConeViewDirection>(
              dense: true,
              semanticLabel: l10n.coneViewDirection,
              selected: request.direction,
              onChanged: controller.setDirection,
              segments: <CruxSegment<ConeViewDirection>>[
                CruxSegment<ConeViewDirection>(
                  value: ConeViewDirection.fanIn,
                  label: l10n.coneViewFanIn,
                ),
                CruxSegment<ConeViewDirection>(
                  value: ConeViewDirection.fanInAndFanOut,
                  label: l10n.coneViewFanInAndFanOut,
                ),
              ],
            ),
            CruxPopUpButton<int?>(
              dense: true,
              semanticLabel: l10n.coneViewDepth,
              value: request.depth,
              onChanged: (depth) => _chooseDepth(controller, depth),
              items: <CruxPopUpItem<int?>>[
                for (final depth in kConeViewDepths)
                  CruxPopUpItem<int?>(
                    value: depth,
                    label: l10n.coneViewDepthLevels(depth),
                  ),
                CruxPopUpItem<int?>(
                  value: null,
                  label:
                      l10n.coneViewDepthAll +
                      tierLabelSuffix(LicenseTier.pro, l10n),
                ),
              ],
            ),
            TextButton(
              onPressed: controller.exit,
              child: Text(l10n.actionExitConeView),
            ),
          ],
        ),
      ),
    );
  }

  /// Applies a depth chosen in the bar. All levels is the Pro form: the
  /// tier gate explains a refusal, and a build with no walk for it says it
  /// requires NetCrux Pro.
  void _chooseDepth(ConeViewController controller, int? depth) {
    if (depth != null) {
      controller.setDepth(depth);
      return;
    }
    const action = NetcruxAction.showConeViewAllLevels;
    if (!allowProAction(context, ref, action)) return;
    if (ref.read(transitiveConeResolverProvider) == null) {
      final l10n = L10N.of(context);
      showCruxInfoSnack(context, l10n.actionRequiresPro(action.label(l10n)));
      return;
    }
    controller.setDepth(null);
  }

  /// The name the bar gives the cone's [root]: the cell, the pin, the
  /// boundary port, or the wire's net in [module] (its driving pin when
  /// unnamed).
  static String _rootLabel(
    LaidOutGraph laidOut,
    SelectedElement root,
    Module? module,
  ) {
    switch (root) {
      case SelectedElementNone():
        return '';
      case SelectedElementCell(:final cellId):
        return cellId;
      case SelectedElementPort(:final portId):
        return portId;
      case SelectedElementBoundaryPort(:final portName):
        return portName;
      case SelectedElementWire(:final edgeId, :final netId):
        return netNameForId(module, netId) ??
            laidOut.graph.findEdge(edgeId)?.sourcePortId ??
            edgeId;
    }
  }
}
