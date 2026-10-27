// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart' show CruxFocusRing;
import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/features/annotation_callouts/annotation_callouts_toggle.dart';
import 'package:netcrux/features/annotation_callouts/callout_projection.dart';
import 'package:netcrux/features/annotations/providers/annotation_statuses_provider.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/features/annotations/services/annotation_openers.dart';
import 'package:netcrux/features/annotations/services/annotation_row_text.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/annotation_badge_layout.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/schematic/annotation_callout_seams.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';

/// The pointer target a callout's dot and controls are given, in logical
/// pixels: the fold control is 0.6 of it (24 × 24), and a dot is centred in
/// a 24 × 24 target although it is drawn 18 across.
const double kCalloutTouchTarget = 40;

/// The side of the square a numbered dot answers the pointer in.
const double kCalloutDotTarget = 24;

/// The annotation callouts drawn over the schematic: each note on an element
/// of the scope on screen, as a balloon with a leader to the element, or a
/// numbered dot.
///
/// Mounted by the canvas's tab content, inside the canvas gesture handler and
/// over the canvas, so a pointer that
/// misses every callout still pans, zooms and selects; a callout claims the
/// pointer it takes through `canvasOverlayGestureClaimProvider`. Outside the
/// canvas's export boundary: callouts are an on-screen aid and never appear in
/// a PNG or SVG export.
///
/// Everything a callout is made of is the suite's shared layer
/// (`crux_annotations`): the balloon, the dot, the leaders, the fold rule, the
/// drag model and the drift styling, as WaveCrux draws them. What is
/// NetCrux's here is the projection of an element to the screen
/// ([calloutAnchorInDesign]), the level of detail ([calloutDetailFor]), the
/// scope (only notes the shared status table calls drawable), and the keys.
///
/// Available at every tier: nothing here reads the licence.
class SchematicCalloutLayer extends ConsumerStatefulWidget {
  /// Creates the layer.
  const SchematicCalloutLayer({super.key});

  @override
  ConsumerState<SchematicCalloutLayer> createState() =>
      _SchematicCalloutLayerState();
}

class _SchematicCalloutLayerState extends ConsumerState<SchematicCalloutLayer> {
  /// The label travel of the drag in progress, by note id, applied on top of
  /// the stored placement and written to the note once, when the drag ends.
  /// One store write per drag rather than one per frame: in a collaborative
  /// session every write of your own note goes over the wire.
  final Map<String, Offset> _dragging = <String, Offset>{};

  void _commitDrag(Annotation note) {
    final travel = _dragging.remove(note.id);
    if (travel == null || travel == Offset.zero) {
      setState(() {});
      return;
    }
    ref
        .read(annotationStoreProvider)
        .updateAnnotation(
          note.copyWith(placement: note.placement.nudged(travel.dx, travel.dy)),
        );
  }

  void _setFolded(Annotation note, {required bool folded}) {
    ref
        .read(annotationStoreProvider)
        .updateAnnotation(
          note.copyWith(placement: note.placement.copyWith(collapsed: folded)),
        );
  }

  void _openInPanel(Annotation note) {
    ref.read(showAnnotationForTargetOpenerProvider)(context, ref, note.anchor);
  }

  void _editInInspector(Annotation note) {
    openAnnotationInInspector(
      ProviderScope.containerOf(context, listen: false),
      note,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(annotationCalloutsVisibleProvider)) {
      return const SizedBox.shrink();
    }
    final laidOut = ref.watch(currentLaidOutGraphProvider).value;
    if (laidOut == null || laidOut.isEmpty) return const SizedBox.shrink();
    final transform = ref.watch(viewportTransformProvider);
    if (transform.zoom <= 0) return const SizedBox.shrink();
    final detail = calloutDetailFor(LodBandRouter.bandFor(transform.zoom));
    if (detail == CruxCalloutDetail.hidden) return const SizedBox.shrink();

    final notes = ref.watch(annotationSnapshotProvider).annotations;
    final statuses = ref.watch(annotationStatusesProvider);
    if (notes.isEmpty || statuses.isEmpty) return const SizedBox.shrink();
    final me = ref.watch(schematicCollabSessionProvider).value?.myParticipantId;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10N.of(context);
    final defaultColor = AnnotationBadgeColors.of(theme).fill;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Offset.zero & constraints.biggest;
        final leaders = <CruxCalloutLeader>[];
        final anchors = <Widget>[];
        final labels = <Widget>[];
        var expanded = 0;

        for (var i = 0; i < notes.length; i++) {
          final note = notes[i];
          final status = statuses[note.id];
          // Only a note on an element of the scope on screen is drawn: one
          // outside the scope, missing from the design, or on a whole scope
          // is the Annotations panel's to list.
          if (note.hidden ||
              status == null ||
              status == CruxAnnotationStatus.unanchoredToRow ||
              !status.isDrawable) {
            continue;
          }
          final design = calloutAnchorInDesign(laidOut, note);
          if (design == null) continue;
          final anchor = design * transform.zoom + transform.offset;
          if (!anchor.dx.isFinite || !anchor.dy.isFinite) continue;
          if (!viewport.inflate(kCruxCalloutBalloonWidth).contains(anchor)) {
            continue;
          }

          final number = i + 1;
          final drifted = status == CruxAnnotationStatus.drifted;
          final readOnly = note.authorId != null && note.authorId != me;
          final color = drifted
              ? kCruxAnnotationDriftedColor
              : (note.colorArgb == null
                    ? defaultColor
                    : Color(note.colorArgb!));
          final heading = annotationRowHeading(note);
          final excerpt = calloutExcerpt(
            heading,
            annotationSpokenText(annotationRowDetails(note)),
          );
          final collapsed =
              detail == CruxCalloutDetail.dot ||
              CruxCalloutGeometry.isCollapsed(
                isEditing: false,
                collapsed: note.placement.collapsed,
                hasText: excerpt.trim().isNotEmpty,
                expandedSoFar: expanded,
              );
          if (!collapsed) expanded++;

          final travel = _dragging[note.id] ?? Offset.zero;
          final origin = CruxCalloutGeometry.labelOrigin(
            anchor,
            labelDx: note.placement.labelDx + travel.dx,
            labelDy: note.placement.labelDy + travel.dy,
          );
          leaders.add(
            CruxCalloutLeader(
              from: anchor,
              to: CruxCalloutGeometry.leaderEnd(origin, collapsed: collapsed),
              color: color,
              dashed: drifted,
            ),
          );
          anchors.add(
            Positioned(
              left: anchor.dx - CruxCalloutAnchorDot.size / 2,
              top: anchor.dy - CruxCalloutAnchorDot.size / 2,
              child: CruxCalloutAnchorDot(color: color),
            ),
          );

          final kind = annotationTargetKindLabel(l10n, note.targetKind);
          final spoken = l10n.annotationCalloutSemantics(
            number,
            heading,
            kind,
            note.targetId,
          );
          final draggable = CruxCalloutDraggable(
            onClaim: (value) =>
                ref.read(canvasOverlayGestureClaimProvider.notifier).active =
                    value,
            onDragStart: readOnly
                ? null
                : () => setState(() => _dragging[note.id] = Offset.zero),
            onDragUpdate: readOnly
                ? null
                : (delta) => setState(
                    () => _dragging[note.id] =
                        (_dragging[note.id] ?? Offset.zero) + delta,
                  ),
            onDragEnd: readOnly ? null : () => _commitDrag(note),
            // A dot opens to its balloon; at middle zoom, where every note
            // is a dot, a tap opens the note in the Annotations panel.
            onTap: !collapsed
                ? null
                : (detail == CruxCalloutDetail.dot ||
                      readOnly ||
                      !note.placement.collapsed)
                ? () => _openInPanel(note)
                : () => _setFolded(note, folded: false),
            child: collapsed
                ? SizedBox.square(
                    dimension: kCalloutDotTarget,
                    child: Center(
                      child: CruxCalloutNumberDot(
                        number: number,
                        color: color,
                        onColor: scheme.surface,
                      ),
                    ),
                  )
                : Tooltip(
                    // The whole note, on hover. The balloon shows a few
                    // lines; the panel row and this show all of it.
                    message: excerpt,
                    excludeFromSemantics: true,
                    waitDuration: const Duration(milliseconds: 500),
                    child: CruxCalloutBalloon(
                      text: excerpt,
                      number: number,
                      color: color,
                      surface: scheme.surface,
                      onSurface: scheme.onSurface,
                      drifted: drifted,
                      touchTarget: kCalloutTouchTarget,
                      isEditing: false,
                      onCollapse: readOnly
                          ? null
                          : () => _setFolded(note, folded: true),
                      onDelete: null,
                      onCommit: (_) {},
                      onBeginEdit: readOnly
                          ? null
                          : () => _editInInspector(note),
                      collapseTooltip: l10n.annotationCalloutFoldTooltip,
                      deleteTooltip: '',
                      editHint: '',
                      maxLength: 1,
                      maxLines: 3,
                    ),
                  ),
          );
          labels.add(
            Positioned(
              key: ValueKey<String>('annotationCallout-${note.id}'),
              left: collapsed ? origin.dx - kCalloutDotTarget / 2 : origin.dx,
              top: collapsed ? origin.dy - kCalloutDotTarget / 2 : origin.dy,
              width: collapsed ? null : kCruxCalloutBalloonWidth,
              child: _CalloutKeys(
                label: spoken,
                drifted: drifted,
                driftedLabel: l10n.annotationStatusDrifted,
                onActivate: () => _openInPanel(note),
                onToggleFold: readOnly || detail == CruxCalloutDetail.dot
                    ? null
                    : () => _setFolded(note, folded: !collapsed),
                child: draggable,
              ),
            ),
          );
        }

        if (labels.isEmpty) return const SizedBox.shrink();
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: CruxCalloutLeadersPainter(leaders)),
              ),
            ),
            ...anchors,
            ...labels,
          ],
        );
      },
    );
  }
}

/// Makes one callout a keyboard stop with one spoken name: Enter opens the
/// note in the Annotations panel, Space folds or unfolds it. The keys are
/// handled here, so they never reach the canvas underneath (where Enter would
/// push into the selected cell).
class _CalloutKeys extends StatefulWidget {
  const _CalloutKeys({
    required this.label,
    required this.drifted,
    required this.driftedLabel,
    required this.onActivate,
    required this.onToggleFold,
    required this.child,
  });

  final String label;
  final bool drifted;
  final String driftedLabel;
  final VoidCallback onActivate;
  final VoidCallback? onToggleFold;
  final Widget child;

  @override
  State<_CalloutKeys> createState() => _CalloutKeysState();
}

class _CalloutKeysState extends State<_CalloutKeys> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      widget.onToggleFold?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: widget.drifted
        ? '${widget.label}. ${widget.driftedLabel}'
        : widget.label,
    onTap: widget.onActivate,
    child: Focus(
      onKeyEvent: _onKey,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: CruxFocusRing(
        focused: _focused,
        child: ExcludeSemantics(child: widget.child),
      ),
    ),
  );
}
