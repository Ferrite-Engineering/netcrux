// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Vertical + horizontal scrollbars flanking the schematic canvas, synced
/// bidirectionally to the per-tab [viewportTransformProvider] pan/zoom
/// state (navigation must never *require* a trackpad gesture; off-screen cells are always reachable by scrollbar).
///
/// - The **track** represents the design's laid-out bounds along that axis
///   (in design units); the **thumb** represents the visible design window
///   (`viewport-extent / zoom`, positioned at `-offset / zoom`).
/// - Dragging the thumb pans the canvas (writes a new offset through
///   [ViewportTransformNotifier.pan]); tapping the track jumps there.
/// - Mouse/trackpad pans and zooms move/resize the thumbs live, because
///   the widget watches the same transform provider the gesture handler
///   writes.
///
/// The scroll bands are always reserved (8 dp visual, 14 dp band) so the
/// canvas size — and therefore Fit-All's viewport — stays stable; when the
/// whole design fits along an axis the band renders an empty track.
/// Mirrors WaveCrux's `WaveformHorizontalScrollbar` interaction model,
/// extended to both axes for the 2-D schematic.
class SchematicScrollbars extends ConsumerWidget {
  /// Wraps [child] (the schematic canvas region) with the two scrollbars.
  const SchematicScrollbars({
    required this.bounds,
    required this.child,
    super.key,
  });

  /// The laid-out design's bounding box, in design coordinates. An empty
  /// box renders both bands as empty tracks.
  final BoundingBox bounds;

  /// The canvas region the scrollbars flank.
  final Widget child;

  /// Total reserved band thickness (visual thumb is thinner).
  static const double bandThickness = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transform = ref.watch(viewportTransformProvider);
    final l10n = L10N.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportW = math
            .max(0, constraints.maxWidth - bandThickness)
            .toDouble();
        final viewportH = math
            .max(0, constraints.maxHeight - bandThickness)
            .toDouble();
        final zoom = transform.zoom;

        // Visible design window along each axis: screen = design*zoom +
        // offset, so designStart = -offset/zoom and extent = viewport/zoom.
        final visibleW = zoom > 0 ? viewportW / zoom : 0.0;
        final visibleH = zoom > 0 ? viewportH / zoom : 0.0;
        final visibleX = zoom > 0 ? -transform.offset.dx / zoom : 0.0;
        final visibleY = zoom > 0 ? -transform.offset.dy / zoom : 0.0;

        void jumpToX(double newVisibleX) {
          final newOffsetDx = -newVisibleX * zoom;
          ref
              .read(viewportTransformProvider.notifier)
              .pan(Offset(newOffsetDx - transform.offset.dx, 0));
        }

        void jumpToY(double newVisibleY) {
          final newOffsetDy = -newVisibleY * zoom;
          ref
              .read(viewportTransformProvider.notifier)
              .pan(Offset(0, newOffsetDy - transform.offset.dy));
        }

        return Column(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(child: child),
                  SizedBox(
                    width: bandThickness,
                    child: _AxisScrollbar(
                      axis: Axis.vertical,
                      semanticsLabel: l10n.schematicVerticalScrollbarLabel,
                      fullStart: bounds.y,
                      fullExtent: bounds.height,
                      visibleStart: visibleY,
                      visibleExtent: visibleH,
                      onJump: jumpToY,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: bandThickness,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _AxisScrollbar(
                      axis: Axis.horizontal,
                      semanticsLabel: l10n.schematicHorizontalScrollbarLabel,
                      fullStart: bounds.x,
                      fullExtent: bounds.width,
                      visibleStart: visibleX,
                      visibleExtent: visibleW,
                      onJump: jumpToX,
                    ),
                  ),
                  // Corner square where the two bands meet.
                  const SizedBox(width: bandThickness),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One axis of [SchematicScrollbars]: track = full design extent, thumb =
/// visible window. Drag pans; track-tap jumps. All values are in design
/// units; [onJump] receives the desired visible-window start.
class _AxisScrollbar extends StatefulWidget {
  const _AxisScrollbar({
    required this.axis,
    required this.semanticsLabel,
    required this.fullStart,
    required this.fullExtent,
    required this.visibleStart,
    required this.visibleExtent,
    required this.onJump,
  });

  final Axis axis;
  final String semanticsLabel;
  final double fullStart;
  final double fullExtent;
  final double visibleStart;
  final double visibleExtent;
  final ValueChanged<double> onJump;

  @override
  State<_AxisScrollbar> createState() => _AxisScrollbarState();
}

class _AxisScrollbarState extends State<_AxisScrollbar> {
  /// Visible-window start (design units) when the drag began; new
  /// positions derive from cumulative drag pixels rather than per-frame
  /// deltas, avoiding rounding drift (mirrors WaveCrux).
  double? _dragStartVisibleStart;
  double? _dragStartTrackLength;
  double? _dragStartPointer;

  static const double _visualThickness = 8;
  static const double _minThumbLength = 24;

  bool get _scrollable =>
      widget.fullExtent > 0 &&
      widget.visibleExtent > 0 &&
      widget.visibleExtent < widget.fullExtent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_scrollable) {
      // Keep the reserved band; nothing to scroll along this axis.
      return const SizedBox.expand();
    }
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      value: _semanticValue(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackLength = widget.axis == Axis.horizontal
              ? constraints.maxWidth
              : constraints.maxHeight;
          if (trackLength <= 0) return const SizedBox.shrink();

          final thumbFraction = widget.visibleExtent / widget.fullExtent;
          final thumbLength = math.min(
            trackLength,
            math.max(_minThumbLength, trackLength * thumbFraction),
          );
          final maxThumbStart = math.max<double>(0, trackLength - thumbLength);
          final scrollableExtent = widget.fullExtent - widget.visibleExtent;
          final fractionAlong = scrollableExtent <= 0
              ? 0.0
              : (widget.visibleStart - widget.fullStart) / scrollableExtent;
          final thumbStart = (fractionAlong * maxThumbStart).clamp(
            0.0,
            maxThumbStart,
          );

          final isHorizontal = widget.axis == Axis.horizontal;
          double localPos(Offset p) => isHorizontal ? p.dx : p.dy;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _handleTrackTap(
              tapPos: localPos(details.localPosition),
              trackLength: trackLength,
              thumbLength: thumbLength,
              thumbStart: thumbStart,
            ),
            onPanStart: (details) {
              _dragStartVisibleStart = widget.visibleStart;
              _dragStartTrackLength = trackLength;
              _dragStartPointer = localPos(details.localPosition);
            },
            onPanUpdate: (details) =>
                _handleDragUpdate(pointer: localPos(details.localPosition)),
            onPanEnd: (_) {
              _dragStartVisibleStart = null;
              _dragStartTrackLength = null;
              _dragStartPointer = null;
            },
            child: Stack(
              alignment: isHorizontal
                  ? Alignment.centerLeft
                  : Alignment.topCenter,
              children: <Widget>[
                // Track.
                Align(
                  child: Container(
                    width: isHorizontal ? null : _visualThickness,
                    height: isHorizontal ? _visualThickness : null,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(_visualThickness / 2),
                    ),
                  ),
                ),
                // Thumb.
                Positioned(
                  left: isHorizontal ? thumbStart : null,
                  top: isHorizontal ? null : thumbStart,
                  width: isHorizontal ? thumbLength : _visualThickness,
                  height: isHorizontal ? _visualThickness : thumbLength,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(_visualThickness / 2),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Tap-on-track: jump so the thumb centre sits at the tap, unless the
  /// tap is already inside the thumb (the follow-up drag handles it).
  void _handleTrackTap({
    required double tapPos,
    required double trackLength,
    required double thumbLength,
    required double thumbStart,
  }) {
    if (tapPos >= thumbStart && tapPos <= thumbStart + thumbLength) return;
    final maxThumbStart = trackLength - thumbLength;
    if (maxThumbStart <= 0) return;
    final desiredThumbStart = (tapPos - thumbLength / 2).clamp(
      0.0,
      maxThumbStart,
    );
    final fractionAlong = desiredThumbStart / maxThumbStart;
    widget.onJump(
      widget.fullStart +
          fractionAlong * (widget.fullExtent - widget.visibleExtent),
    );
  }

  void _handleDragUpdate({required double pointer}) {
    final startVisible = _dragStartVisibleStart;
    final startTrack = _dragStartTrackLength;
    final startPointer = _dragStartPointer;
    if (startVisible == null || startTrack == null || startPointer == null) {
      return;
    }
    if (!_scrollable) return;
    final thumbFraction = widget.visibleExtent / widget.fullExtent;
    final thumbLength = math.max(_minThumbLength, startTrack * thumbFraction);
    final maxThumbStart = startTrack - thumbLength;
    if (maxThumbStart <= 0) return;
    final fractionDelta = (pointer - startPointer) / maxThumbStart;
    widget.onJump(
      startVisible + fractionDelta * (widget.fullExtent - widget.visibleExtent),
    );
  }

  String _semanticValue() {
    if (widget.fullExtent <= 0) return '';
    final percent =
        ((widget.visibleStart - widget.fullStart) / widget.fullExtent * 100)
            .clamp(0, 100)
            .round();
    return '$percent%';
  }
}
