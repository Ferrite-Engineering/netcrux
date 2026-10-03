// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/collaboration/collab_presence_publisher.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/viewer/providers/canvas_fit_target_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/selection/schematic_hit_test.dart';
import 'package:netcrux/features/viewer/selection/schematic_keyboard_navigator.dart';
import 'package:netcrux/features/viewer/services/trace_overlay_controller.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_controller.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/net_name_lookup.dart';

/// Wraps [child] with pointer and keyboard handling for the schematic
/// canvas.
///
/// Behavior:
///
/// | Input                                  | Effect                          |
/// |----------------------------------------|---------------------------------|
/// | Cmd/Ctrl + scroll wheel                | Zoom around the pointer         |
/// | Two-finger trackpad scroll             | Pan in screen-space             |
/// | Middle-mouse drag                      | Pan                             |
/// | Left-click (release without dragging)  | Select the element under it     |
/// | Left-double-click                      | Push into / pop out of a scope  |
/// | Left-click + drag on empty canvas      | Pan (drag cancels the select)   |
/// | Arrow keys                             | Pan by a fixed step             |
/// | `+` / `-`                              | Zoom in / out around the center |
/// | `0`                                    | Reset (fit-to-screen surrogate) |
///
/// Touch gestures (pinch zoom, two-finger pan) are wired through
/// Flutter's [GestureDetector.onScale*] callbacks for future-proofing
/// — NetCrux targets desktop and desktop-class browsers (see
/// `CLAUDE.md`), but the same widget runs cleanly on a touch screen.
///
/// The handler talks to [ViewportTransformNotifier] only — the
/// painter watches the same notifier and repaints. No direct
/// communication with the render object; this keeps the gesture
/// layer testable in a `ProviderContainer` without pumping a
/// `RenderObject`.
class SchematicGestureHandler extends ConsumerStatefulWidget {
  /// Creates a gesture handler that wraps [child].
  const SchematicGestureHandler({
    required this.child,
    this.autofocus = true,
    super.key,
  });

  /// The canvas content — usually a [SchematicCanvas] widget.
  final Widget child;

  /// When true (the default) the handler requests focus on mount so
  /// keyboard shortcuts work without an explicit click first. Tests
  /// can pass `false` to keep focus deterministic.
  final bool autofocus;

  /// How many canvas pixels each arrow-key press pans by. Constant so
  /// the panning feels predictable; high-DPI tweaks belong in a
  /// dedicated settings batch.
  static const double keyboardPanStep = 40;

  /// Wheel-zoom sensitivity coefficient applied to scroll delta. Set
  /// so a single notch produces about ±5% change.
  static const double wheelZoomCoefficient = 1.0015;

  /// Keyboard zoom factor (the +/- shortcut).
  static const double keyboardZoomFactor = 1.15;

  /// Whether the pointer entering the canvas may take keyboard focus from
  /// [primary], the node that holds it now.
  ///
  /// False while [primary] is inside an editable text field or a menu, so
  /// typing in the hierarchy filter and walking a menu with the keyboard are
  /// never interrupted by the pointer passing over the schematic. True
  /// otherwise, including when nothing has focus.
  static bool hoverMayTakeFocus(FocusNode? primary) {
    final focusContext = primary?.context;
    if (focusContext == null) return true;
    bool holdsFocus(Widget widget) =>
        widget is EditableText ||
        widget is MenuItemButton ||
        widget is SubmenuButton ||
        widget is MenuAnchor;
    if (holdsFocus(focusContext.widget)) return false;
    var mayTake = true;
    focusContext.visitAncestorElements((element) {
      if (holdsFocus(element.widget)) {
        mayTake = false;
        return false;
      }
      return true;
    });
    return mayTake;
  }

  @override
  ConsumerState<SchematicGestureHandler> createState() =>
      _SchematicGestureHandlerState();
}

class _SchematicGestureHandlerState
    extends ConsumerState<SchematicGestureHandler> {
  late final FocusNode _focusNode;

  // Scale-gesture session bookkeeping. `_scaleStartZoom` is the zoom
  // factor at gesture start; `_scaleFocalStart` is the focal point in
  // canvas-local pixels. We apply zoomAt + pan deltas relative to
  // these so a scale-and-pan compound gesture (pinch with a drift)
  // stays under control.
  double _scaleStartZoom = 1;
  Offset _scaleFocalStart = Offset.zero;
  Offset _scaleStartOffset = Offset.zero;

  // Drag bookkeeping for plain left/middle drag (no scale). We use
  // explicit pointer tracking so middle-button drag works even on
  // platforms where GestureDetector swallows it under a regular
  // PanGestureRecognizer.
  Offset? _lastPointerPosition;
  int? _activeDragPointer;

  // Click bookkeeping for primary-button selection.
  //
  // Selection runs off these raw pointer events instead of
  // `GestureDetector.onTapUp` on purpose: `onTapUp` cannot fire until the
  // tap recognizer WINS the gesture arena, and the sibling `onDoubleTap`
  // (push into / pop out of a scope) HOLDS that arena for the whole
  // `kDoubleTapTimeout` (~300 ms). Clicking a cell therefore left the
  // inspector and the trace overlay frozen for a third of a second, and a
  // second click inside that window was swallowed as a double-tap. The
  // `Listener` sits outside the arena, so it is immediate.
  //
  // Selection still fires on pointer-UP, not pointer-down: a left-drag
  // pans this canvas, so press-and-drag must not select — `_pressAborted`
  // reproduces the tap recognizer's slop rejection (and bails out entirely
  // once a second pointer joins, e.g. a trackpad pinch).
  Offset? _pressOrigin;
  int? _pressPointer;
  bool _pressAborted = false;
  int _activePointerCount = 0;

  // Bounds of the scope last auto-fitted to. Guards the auto-fit so it
  // fires once per scope (when the layout's bounds change) rather than on
  // every provider re-emit.
  BoundingBox? _lastFittedBounds;

  // Canvas viewport size last seen during layout. Null until the first
  // layout — see [_onViewportConstraints].
  Size? _lastViewportSize;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'SchematicGestureHandler');
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Warm the CXP server the moment the schematic view mounts (rather than
    // lazily on the first cross-probe right-click). Starting it here gives
    // the discovery + outbound connector time to complete peer handshakes
    // before the user opens the context menu, so the FIRST "Send to peer"
    // submenu already reflects connected peers instead of showing an empty
    // "no connected peers" state that only fills in on a second open.
    // Cheap when disabled: the provider resolves to a null server.
    ref.watch(cxpServerHostProvider);
    // Auto-fit the camera whenever the scope's layout changes, so a large
    // design opens fit-to-view instead of at the identity transform's
    // top-left corner (where a 15 000 × 43 000 px core showed only a sliver
    // of overlapping labels).
    //
    // This must `watch` — not `listen` — the layout: the handler is only
    // built once the layout has loaded (the loading state shows a different
    // widget), so the value is already present when this widget first
    // mounts, and a `ref.listen` would never fire for it. The `_lastFitted`
    // bounds guard makes the post-frame fit run once per scope and never
    // fight manual pan/zoom (the laid-out graph only changes on scope /
    // model change).
    final laidOut = ref.watch(currentLaidOutGraphProvider).value;
    // A pending "reveal this cell" request (from search / jump-to-element).
    // Resolve it against THIS layout: only once the target's scope is laid
    // out does `findNode` return non-null. While a cross-scope switch is
    // still re-laying-out, the target is absent and the request stays
    // parked for a later build.
    final pendingReveal = ref.watch(revealRequestProvider);
    final revealTarget = (laidOut != null && pendingReveal != null)
        ? laidOut.layout.findNode(pendingReveal)
        : null;
    if (laidOut != null && !laidOut.isEmpty) {
      final bounds = laidOut.layout.bounds;
      if (bounds != _lastFittedBounds) {
        _lastFittedBounds = bounds;
        // Defer to post-frame so the canvas RenderBox has its size. Skip
        // the whole-design auto-fit when we're about to reveal a specific
        // element in this (freshly laid-out) scope — otherwise the fit
        // would frame everything and immediately clobber the reveal.
        if (revealTarget == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // A restored session's camera wins over the fit, but only for
            // the layout of the scope it was saved in.
            final scopePath =
                ref.read(hierarchyTreeProvider).selected?.path ??
                const <String>[];
            final restored = ref
                .read(viewportTransformProvider.notifier)
                .takePendingRestore(scopePath);
            if (restored != null) {
              _publishFitTarget(bounds);
              ref.read(viewportTransformProvider.notifier).restore(restored);
            } else {
              _fitToView(bounds);
            }
          });
        }
      }
    }
    if (revealTarget != null) {
      final targetBounds = revealTarget.bounds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealBounds(targetBounds);
        ref.read(revealRequestProvider.notifier).clear();
      });
    }
    // Republish the fit target every frame (post-layout) so the
    // toolbar-fit action tracks window / pane resizes even when the
    // laid-out bounds — and thus the auto-fit above — don't change.
    if (laidOut != null && !laidOut.isEmpty) {
      final bounds = laidOut.layout.bounds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _publishFitTarget(bounds);
      });
    }
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: MouseRegion(
        // Presence only. Hover is the one pointer signal the raw `Listener`
        // below does not carry a callback for, and a collaborative cursor
        // that only moves while a button is held is not a cursor.
        //
        // `onExit` matters as much as `onHover`: without it the last position
        // inside the canvas sticks, so a colleague who walked away is drawn
        // pointing at whatever they passed over on the way out — presence
        // that is confidently wrong rather than absent.
        opaque: false,
        // Focus follows the pointer onto the canvas, so the bare zoom and pan
        // keys work whenever the pointer is over the schematic, even after a
        // panel took focus. Never mid-edit: see [_takeFocusOnHover].
        onEnter: (_) => _takeFocusOnHover(),
        onHover: (event) => _publishCollabCursor(event.localPosition),
        onExit: (_) => _publishCollabCursor(null),
        child: Listener(
          // Opaque, not the default deferToChild: nothing below this Listener
          // reports a self-hit — `SchematicCanvasRenderObject` is a pure
          // painter with no `hitTestSelf` override, and both GestureDetectors
          // in between are `HitTestBehavior.translucent` (they add themselves
          // to the hit path but return "not hit" to their parent). Under
          // deferToChild this Listener therefore dropped OUT of the hit path
          // entirely — scale/double-tap callbacks still fired (translucent
          // self-registration) while every raw-pointer feature routed here
          // (left/middle drag-pan, click-select, scroll pan, Cmd/Ctrl+scroll
          // zoom) silently died. Opaque makes the canvas region a real
          // pointer target; ancestors (e.g. PaneHost's translucent
          // activate-on-tap detector) still see the events as before.
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _onPointerSignal,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: PlatformContextMenu(
            onContextMenu: _onContextMenu,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              // NOTE: no `onTapUp` here — selection runs from the raw
              // `Listener` above so `onDoubleTap` can't hold it hostage in
              // the gesture arena. See `_selectAt`.
              onDoubleTapDown: _onDoubleTapDown,
              onDoubleTap: _onDoubleTap,
              // The canvas viewport is this subtree's box, and a window or
              // splitter resize changes it through layout alone — no rebuild
              // is scheduled, so nothing else here would notice.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.hasBoundedWidth &&
                      constraints.hasBoundedHeight) {
                    _onViewportConstraints(constraints.biggest);
                  }
                  return widget.child;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Handles a secondary-button tap (right-click). Hit-tests at the
  /// pointer location, promotes the hit element to the primary
  /// selection (so the inspector and the context-menu actions agree
  /// on what was clicked), and shows the menu.
  Future<void> _onContextMenu(Offset globalPosition) async {
    // The PlatformContextMenu callback supplies the global position;
    // we need the canvas-local position for hit testing. Convert via
    // the render object so the conversion stays correct after the
    // pane has been resized or scrolled.
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final localPosition = box.globalToLocal(globalPosition);
    final hit = _hitTestAt(localPosition);
    if (hit is SelectedElementNone) return;
    // Promote the right-clicked element to the primary selection so
    // the inspector follows the menu (mirrors how a desktop file
    // manager updates the selection on right-click).
    ref.read(selectedElementProvider.notifier).select(hit);
    final controller = SchematicContextMenuController(
      ref: ref,
      traceController: TraceOverlayController(ref),
    );
    await controller.showAt(
      context: context,
      globalPosition: globalPosition,
      target: hit,
    );
  }

  Offset? _pendingDoubleTapPosition;

  /// Applies the primary-button click at [localPosition] to the selection.
  ///
  /// Called from the raw `Listener`'s pointer-up (see the `_pressPointer`
  /// bookkeeping above), never from a tap recognizer.
  void _selectAt(Offset localPosition) {
    final hit = _hitTestAt(localPosition);
    final notifier = ref.read(selectedElementProvider.notifier);
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final isShift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    // Cmd on macOS, Ctrl elsewhere. Both fire `toggleInSelection`.
    final isMeta =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (hit is SelectedElementNone && !isShift && !isMeta) {
      // Plain click on empty canvas clears the selection.
      notifier.clear();
    } else if (isShift) {
      notifier.addToSelection(hit);
    } else if (isMeta) {
      notifier.toggleInSelection(hit);
    } else {
      notifier.select(hit);
    }
    // Selection changes invalidate the trace overlay — drop any existing
    // overlay so the canvas doesn't dim against a stale anchor.
    ref.read(traceOverlayProvider.notifier).clear();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _pendingDoubleTapPosition = details.localPosition;
  }

  void _onDoubleTap() {
    final position = _pendingDoubleTapPosition;
    _pendingDoubleTapPosition = null;
    if (position == null) return;
    final hit = _hitTestAt(position);
    final hierarchy = ref.read(hierarchyTreeProvider.notifier);
    if (hit is SelectedElementCell) {
      hierarchy.pushInto(hit.cellId);
    } else if (hit is SelectedElementNone) {
      hierarchy.popOut();
    }
    // Reset selection / overlay on scope change so we don't carry
    // stale ids into the new scope's id namespace.
    ref.read(selectedElementProvider.notifier).clear();
    ref.read(traceOverlayProvider.notifier).clear();
  }

  SelectedElement _hitTestAt(Offset localPosition) {
    final laidOutAsync = ref.read(currentLaidOutGraphProvider);
    final laidOut = laidOutAsync.value;
    if (laidOut == null || laidOut.isEmpty) {
      return const SelectedElement.none();
    }
    final transform = ref.read(viewportTransformProvider);
    final tester = SchematicHitTester(laidOut: laidOut, transform: transform);
    return tester.hitTest(localPosition);
  }

  /// Gives the canvas keyboard focus as the pointer enters it, unless focus
  /// is somewhere it must stay: an editable text field (the hierarchy
  /// filter, the inspector, a dialog field), which would lose the user's
  /// edit, or an open menu, whose arrow keys would stop navigating it.
  void _takeFocusOnHover() {
    if (_focusNode.hasFocus) return;
    if (!SchematicGestureHandler.hoverMayTakeFocus(
      FocusManager.instance.primaryFocus,
    )) {
      return;
    }
    _focusNode.requestFocus();
  }

  // ── Pointer signal (scroll wheel / trackpad scroll) ─────────────

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final notifier = ref.read(viewportTransformProvider.notifier);
    if (_isModifierPressed) {
      // Cmd/Ctrl + scroll = zoom around pointer.
      // dy < 0 → zoom in (factor > 1).
      final factor = _zoomFactorForScroll(event.scrollDelta.dy);
      notifier.zoomAt(event.localPosition, factor);
    } else {
      // Plain scroll = pan in screen-space. Two-finger trackpad scroll
      // produces small dx + dy values; mouse wheel mostly dy. We pass
      // both through unchanged so the gesture feels native.
      notifier.pan(-event.scrollDelta);
    }
  }

  bool get _isModifierPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  double _zoomFactorForScroll(double dy) {
    // Power-of-coefficient mapping: continuous scrolling produces a
    // smooth zoom because the deltas compound. A coefficient slightly
    // above 1 keeps single-notch wheel events from snapping past the
    // user.
    return _pow(SchematicGestureHandler.wheelZoomCoefficient, -dy);
  }

  static double _pow(double base, double exponent) {
    // Avoids importing dart:math just for a single call. For our
    // wheel deltas (|dy| ≲ 200), expand via exp/log on the JS side
    // would be overkill; the built-in `pow` is fine but we keep the
    // helper to centralize the call site.
    var result = 1.0;
    final n = exponent.abs();
    final whole = n.toInt();
    for (var i = 0; i < whole; i++) {
      result *= base;
    }
    final frac = n - whole;
    if (frac > 0) {
      // Linear interpolation between base^whole and base^(whole+1)
      // — accurate enough for sub-notch deltas; the visible zoom
      // step is small.
      result *= 1 + (base - 1) * frac;
    }
    return exponent.isNegative ? 1 / result : result;
  }

  // ── Pointer drag (middle-button or left-button pan) ─────────────

  void _onPointerDown(PointerDownEvent event) {
    // Any press on the canvas, right-click and middle-drag included, hands
    // keyboard focus to it. A click is a deliberate move away from whatever
    // had focus, a text field included. Deferred to a microtask: a focused
    // text field unfocuses itself on the same press (its tap-outside
    // handler runs after this one), and an earlier request would lose to
    // that unfocus.
    if (!_focusNode.hasFocus) {
      scheduleMicrotask(() {
        if (mounted) _focusNode.requestFocus();
      });
    }
    _activePointerCount++;
    // A second pointer (trackpad pinch, second finger) means this is not a
    // click any more — cancel the pending selection.
    if (_activePointerCount > 1) _pressAborted = true;
    // Middle button → pan. Left button → a click that selects, unless the
    // pointer moves past the tap slop, in which case it pans.
    final isMiddle = event.buttons & kMiddleMouseButton != 0;
    final isLeft = event.buttons & kPrimaryMouseButton != 0;
    if (!isMiddle && !isLeft) return;
    if (isLeft && _pressPointer == null) {
      _pressPointer = event.pointer;
      _pressOrigin = event.localPosition;
      _pressAborted = _activePointerCount > 1;
    }
    _activeDragPointer = event.pointer;
    _lastPointerPosition = event.localPosition;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _pressPointer && !_pressAborted) {
      final origin = _pressOrigin;
      if (origin != null &&
          (event.localPosition - origin).distance > kTouchSlop) {
        // Moved past the tap slop — this is a pan, not a click.
        _pressAborted = true;
      }
    }
    if (event.pointer != _activeDragPointer) return;
    final last = _lastPointerPosition;
    if (last == null) return;
    final delta = event.localPosition - last;
    _lastPointerPosition = event.localPosition;
    ref.read(viewportTransformProvider.notifier).pan(delta);
    // Publish from the pan path too: `onHover` stops firing the moment a
    // button goes down, and somebody dragging the design around is exactly
    // when the room most wants to see where they are.
    _publishCollabCursor(event.localPosition);
  }

  /// Publishes the local pointer to a collaborative session, or clears it when
  /// [localPosition] is `null`.
  ///
  /// A no-op with no session running — [NoopSchematicCollaborationService]
  /// discards it — so this costs one provider read per hover event in an
  /// open-core build and nothing else. Throttling to the wire rate is the
  /// service's job, not the gesture handler's: the handler should not have to
  /// know what a frame budget is.
  void _publishCollabCursor(Offset? localPosition) {
    publishCollabCursor(
      ref,
      designPoint: localPosition == null
          ? null
          : collabDesignPoint(
              localPosition,
              ref.read(viewportTransformProvider),
            ),
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointerCount > 0) _activePointerCount--;
    if (event.pointer == _pressPointer) {
      final aborted = _pressAborted;
      final origin = _pressOrigin;
      _clearPress();
      if (!aborted && origin != null) _selectAt(event.localPosition);
    }
    if (event.pointer != _activeDragPointer) return;
    _activeDragPointer = null;
    _lastPointerPosition = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointerCount > 0) _activePointerCount--;
    if (event.pointer == _pressPointer) _clearPress();
    if (event.pointer != _activeDragPointer) return;
    _activeDragPointer = null;
    _lastPointerPosition = null;
  }

  void _clearPress() {
    _pressPointer = null;
    _pressOrigin = null;
    _pressAborted = false;
  }

  // ── Scale gesture (pinch zoom / two-finger pan on touch) ────────

  void _onScaleStart(ScaleStartDetails details) {
    final current = ref.read(viewportTransformProvider);
    _scaleStartZoom = current.zoom;
    _scaleStartOffset = current.offset;
    _scaleFocalStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Single-pointer scale events fire with `scale == 1`; treat
    // those as pure pans via the dedicated pointer-drag path above
    // (the ScaleGestureRecognizer also surfaces deltas, but we
    // already handled them).
    if (details.pointerCount < 2) return;
    final notifier = ref.read(viewportTransformProvider.notifier);
    final targetZoom = SchematicViewportLimits.clampZoom(
      _scaleStartZoom * details.scale,
    );
    final ratio = targetZoom / _scaleStartZoom;
    // Keep the focal start point pinned: invert the same math used by
    // zoomAt() but apply it to the gesture-start offset so the user's
    // fingers stay over the same design coordinate as they pinch.
    final focal = _scaleFocalStart;
    final newOffset =
        focal -
        (focal - _scaleStartOffset) * ratio +
        (details.localFocalPoint - _scaleFocalStart);
    notifier
      ..setZoom(targetZoom)
      ..pan(newOffset - ref.read(viewportTransformProvider).offset);
  }

  // ── Keyboard ──────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    // Everything the pointer does on an element has a key: Alt+Arrow selects
    // (the mouse click), Enter pushes into an instance (the double-click),
    // and Shift+F10 or the Menu key opens the element's menu (the
    // right-click) — the only route to Copy Path and to the Pro entries such
    // as cross-probing a signal to a peer.
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.contextMenu ||
            (key == LogicalKeyboardKey.f10 &&
                HardwareKeyboard.instance.isShiftPressed))) {
      unawaited(_openContextMenuFromKeyboard());
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isAltPressed && _stepSelection(key)) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final primary = ref.read(selectedElementProvider).primary;
      if (primary is! SelectedElementCell) return KeyEventResult.ignored;
      ref.read(hierarchyTreeProvider.notifier).pushInto(primary.cellId);
      ref.read(selectedElementProvider.notifier).clear();
      ref.read(traceOverlayProvider.notifier).clear();
      return KeyEventResult.handled;
    }
    final notifier = ref.read(viewportTransformProvider.notifier);
    const step = SchematicGestureHandler.keyboardPanStep;
    if (key == LogicalKeyboardKey.arrowLeft) {
      notifier.pan(const Offset(step, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      notifier.pan(const Offset(-step, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      notifier.pan(const Offset(0, step));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      notifier.pan(const Offset(0, -step));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      notifier.zoomAt(
        _viewportCenter(),
        SchematicGestureHandler.keyboardZoomFactor,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      notifier.zoomAt(
        _viewportCenter(),
        1 / SchematicGestureHandler.keyboardZoomFactor,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _fitToView();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        (key == LogicalKeyboardKey.bracketLeft && _isModifierPressed)) {
      ref.read(hierarchyTreeProvider.notifier).popOut();
      ref.read(selectedElementProvider.notifier).clear();
      ref.read(traceOverlayProvider.notifier).clear();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      ref.read(selectedElementProvider.notifier).clear();
      ref.read(traceOverlayProvider.notifier).clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Applies an Alt+Arrow selection step and announces the result. Returns
  /// false for keys that are not a step, so they fall through.
  ///
  /// Alt+Down / Alt+Up walk the scope's cells and module ports in reading
  /// order; Alt+Right / Alt+Left walk the pins of the cell the walk is on,
  /// each followed by the net on it (a module port: its net). Shift adds to
  /// the selection instead of replacing it, as a Shift-click does. See
  /// [SchematicKeyboardNavigator].
  bool _stepSelection(LogicalKeyboardKey key) {
    final byElement =
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp;
    final byConnection =
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft;
    if (!byElement && !byConnection) return false;
    final l10n = L10N.of(context);
    final navigator = SchematicKeyboardNavigator(
      ref.read(currentLaidOutGraphProvider).value ?? LaidOutGraph.empty,
    );
    final current = ref.read(selectedElementProvider).primary;
    final SelectedElement next;
    if (byElement) {
      next = navigator.stepElement(
        current,
        forward: key == LogicalKeyboardKey.arrowDown,
      );
      if (next.isNone) {
        announceCrux(context, l10n.schematicKeyboardNoElements);
        return true;
      }
      _walkAnchor = next;
    } else {
      // Stay on the element the walk started from while stepping through its
      // pins and nets (a net's driver may be another element); a pin or wire
      // selected some other way anchors on its cell or its driver.
      final anchor =
          SchematicKeyboardNavigator.indexIn(
                navigator.connectionsOf(_walkAnchor),
                current,
              ) !=
              -1
          ? _walkAnchor
          : navigator.anchorFor(current);
      if (anchor.isNone) {
        announceCrux(context, l10n.schematicKeyboardNothingSelected);
        return true;
      }
      next = navigator.stepConnection(
        current,
        anchor,
        forward: key == LogicalKeyboardKey.arrowRight,
      );
      if (next.isNone) {
        announceCrux(
          context,
          l10n.schematicKeyboardNoConnections(_nameOf(anchor)),
        );
        return true;
      }
      _walkAnchor = anchor;
    }
    final selection = ref.read(selectedElementProvider.notifier);
    if (HardwareKeyboard.instance.isShiftPressed) {
      selection.addToSelection(next);
    } else {
      selection.select(next);
    }
    ref.read(traceOverlayProvider.notifier).clear();
    final bounds = navigator.boundsOf(next);
    if (bounds != null) _ensureVisible(bounds);
    announceCrux(context, _describe(next, navigator));
    return true;
  }

  /// The element a keyboard pin-and-net walk is on; see [_stepSelection].
  SelectedElement _walkAnchor = const SelectedElement.none();

  /// What a screen reader hears for a keyboard-selected [element].
  String _describe(SelectedElement element, SchematicKeyboardNavigator nav) {
    final l10n = L10N.of(context);
    return switch (element) {
      SelectedElementCell(:final cellId) => l10n.schematicKeyboardCell(
        cellId,
        nav.laidOut.graph.cells
                .where((cell) => cell.id == cellId)
                .firstOrNull
                ?.type ??
            '',
      ),
      SelectedElementWire(:final netId) => l10n.schematicKeyboardNet(
        netNameForId(_currentModule(), netId) ?? '$netId',
      ),
      SelectedElementPort(:final portName, :final cellId) =>
        l10n.schematicKeyboardPin(portName, cellId),
      _ => l10n.schematicKeyboardBoundaryPort(_nameOf(element)),
    };
  }

  String _nameOf(SelectedElement element) => switch (element) {
    SelectedElementCell(:final cellId) => cellId,
    SelectedElementBoundaryPort(:final portName) => portName,
    SelectedElementPort(:final portName) => portName,
    SelectedElementWire(:final netId) => '$netId',
    SelectedElementNone() => '',
  };

  Module? _currentModule() {
    final tree = ref.read(hierarchyTreeProvider);
    final model = tree.model;
    return model == null ? null : tree.selected?.resolve(model);
  }

  /// Brings [bounds] into view when any part of it lies outside the canvas,
  /// leaving the camera alone while the keyboard walks what is already
  /// visible.
  void _ensureVisible(BoundingBox bounds) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final transform = ref.read(viewportTransformProvider);
    Offset toView(double x, double y) =>
        Offset(x, y) * transform.zoom + transform.offset;
    final view = Offset.zero & box.size;
    final visible =
        view.contains(toView(bounds.x, bounds.y)) &&
        view.contains(
          toView(bounds.x + bounds.width, bounds.y + bounds.height),
        );
    if (!visible) _revealBounds(bounds);
  }

  /// Opens the element menu for the primary selection, anchored on the
  /// element when it is on screen and on the middle of the canvas otherwise.
  Future<void> _openContextMenuFromKeyboard() async {
    final target = ref.read(selectedElementProvider).primary;
    if (target.isNone) {
      announceCrux(context, L10N.of(context).schematicKeyboardNothingSelected);
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final bounds = SchematicKeyboardNavigator(
      ref.read(currentLaidOutGraphProvider).value ?? LaidOutGraph.empty,
    ).boundsOf(target);
    var anchor = box.size.center(Offset.zero);
    if (bounds != null) {
      final transform = ref.read(viewportTransformProvider);
      final center =
          Offset(
                bounds.x + bounds.width / 2,
                bounds.y + bounds.height / 2,
              ) *
              transform.zoom +
          transform.offset;
      if ((Offset.zero & box.size).contains(center)) anchor = center;
    }
    await SchematicContextMenuController(
      ref: ref,
      traceController: TraceOverlayController(ref),
    ).showAt(
      context: context,
      globalPosition: box.localToGlobal(anchor),
      target: target,
    );
  }

  /// Records the canvas viewport size seen during layout and re-aims the
  /// camera when it changes.
  ///
  /// Called from a [LayoutBuilder], so the transform mutation is deferred to
  /// a post-frame callback — writing provider state during layout would
  /// rebuild a tree that is already being laid out. The first size seen is
  /// only recorded: there is no previous viewport to preserve anything
  /// relative to, and the auto-fit already frames the design on open.
  void _onViewportConstraints(Size size) {
    final previous = _lastViewportSize;
    if (previous == size) return;
    _lastViewportSize = size;
    if (previous == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(viewportTransformProvider.notifier)
          .handleViewportResize(previous, size);
    });
  }

  Offset _viewportCenter() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return Offset(box.size.width / 2, box.size.height / 2);
    }
    return Offset.zero;
  }

  /// Fits the current scope's layout into the canvas — the real "Fit All"
  /// (the `0` key) and the auto-fit on scope change. [bounds] is supplied by
  /// the auto-fit path (it already has them); the key path reads the current
  /// laid-out graph.
  void _fitToView([BoundingBox? bounds]) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final b =
        bounds ?? ref.read(currentLaidOutGraphProvider).value?.layout.bounds;
    if (b == null) return;
    // Keep the shared fit target current so the toolbar / palette "Fit to
    // screen" action (dispatched outside this render tree) fits against
    // the real viewport without reaching into the async layout provider.
    ref.read(canvasFitTargetProvider.notifier).set(box.size, b);
    ref.read(viewportTransformProvider.notifier).fitToBounds(box.size, b);
  }

  /// Centers the camera on [target] design-space bounds and zooms it to a
  /// readable scale — the "reveal element" path consumed from
  /// [revealRequestProvider] (a search-result jump). Reads the live canvas
  /// size straight off the render object so it frames against the real
  /// viewport.
  void _revealBounds(BoundingBox target) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    ref.read(viewportTransformProvider.notifier).revealBounds(box.size, target);
  }

  /// Publishes the canvas [RenderBox] size + [bounds] to
  /// [canvasFitTargetProvider]. Runs post-frame (the size is only known
  /// after layout) on every build so a window / pane resize keeps the
  /// toolbar-fit target accurate.
  void _publishFitTarget(BoundingBox bounds) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    ref.read(canvasFitTargetProvider.notifier).set(box.size, bounds);
  }
}
