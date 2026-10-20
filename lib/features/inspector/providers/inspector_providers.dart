// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';

/// Opens this tab's Inspector with keyboard focus. Every opener calls
/// [CruxInspectorController.open]: the schematic's *Properties* context-menu
/// entry, `View > Properties` and its shortcut, Add Annotation and the
/// Annotations panel's Edit.
///
/// Per-tab (re-bound in `netcruxTabOverridesFactory`): a controller shared by
/// two tabs would let an open in one tab move focus in the other, and the
/// held draft it keeps belongs to one tab's design. Revealing the dock tab is
/// root chrome, so [CruxInspectorController.onReveal] reaches the root-scoped
/// [rightDockTabProvider], which also opens the right region.
final inspectorControllerProvider = Provider<CruxInspectorController>(
  buildInspectorController,
  name: 'inspectorControllerProvider',
);

/// The body of [inspectorControllerProvider], shared with its per-tab
/// re-binding.
CruxInspectorController buildInspectorController(Ref ref) {
  final dock = ref.read(rightDockTabProvider.notifier);
  final controller = CruxInspectorController(
    onReveal: () => dock.reveal(kRightDockTabInspector),
  );
  ref.onDispose(controller.dispose);
  return controller;
}

/// The annotation whose title field the Inspector should focus when it next
/// shows that annotation's section, or null. Set by the Annotations panel's
/// Edit and by Add Annotation (the new draft's key); the section takes it.
///
/// Per-tab, like the controller.
final inspectorFocusRequestProvider =
    NotifierProvider<InspectorFocusRequest, String?>(
      InspectorFocusRequest.new,
      name: 'inspectorFocusRequestProvider',
    );

/// Notifier behind [inspectorFocusRequestProvider].
class InspectorFocusRequest extends Notifier<String?> {
  @override
  String? build() => null;

  /// Asks the section for [key] to take focus.
  // ignore: use_setters_to_change_properties
  void request(String key) => state = key;

  /// Consumes the request for [key]; true when it was pending.
  bool take(String key) {
    if (state != key) return false;
    state = null;
    return true;
  }
}

/// The Pro overlay's Inspector sections, after open core's own.
///
/// Empty in open core. The overlay overrides it in its `proOverrides` list
/// (its cell inspector's "Custom symbol" section).
final proInspectorSectionsProvider =
    Provider<List<CruxInspectorSectionBuilder<SelectedElement>>>(
      (_) => const <CruxInspectorSectionBuilder<SelectedElement>>[],
      name: 'proInspectorSectionsProvider',
    );

/// Selects [element] on this tab's schematic and opens the Inspector with
/// focus. [container] is the tab's container.
void openInspectorFor(ProviderContainer container, SelectedElement element) {
  if (!element.isNone) {
    container.read(selectedElementProvider.notifier).select(element);
  }
  container.read(inspectorControllerProvider).open();
}

/// Returns keyboard focus from the Inspector to this tab's schematic canvas.
/// [canvasKey] is the tab's [schematicCanvasKeyProvider] key; the canvas's
/// focus node is the nearest `Focus` above the keyed repaint boundary.
void focusSchematicCanvas(GlobalKey canvasKey) {
  final canvas = canvasKey.currentContext;
  if (canvas == null) return;
  Focus.maybeOf(canvas)?.requestFocus();
}
