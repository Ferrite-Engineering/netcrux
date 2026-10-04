// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

/// Builds row [index]; [flashing] is true while that row answers a
/// reveal request and should draw its brief highlight.
typedef RevealingItemBuilder =
    Widget Function(
      BuildContext context,
      int index, {
      required bool flashing,
    });

/// A lazily-built list that can scroll one row into view on request and
/// flash it briefly.
///
/// Set [revealIndex] to ask for row `revealIndex` to be revealed; the
/// list scrolls until that row is built and centred, flashes it for
/// [flashDuration], and calls [onRevealed]. The owner clears the request
/// in [onRevealed] (a new non-null [revealIndex] after a null one is a new
/// request, even for the same row).
///
/// Rows are built lazily, so a row far off screen has no element to scroll
/// to. The list first jumps to the row's estimated offset, using the
/// average row extent the scroll position reports, then centres the row
/// once it is built, retrying a few frames while the estimate converges.
class RevealingListView extends StatefulWidget {
  /// Creates the list.
  const RevealingListView({
    required this.itemCount,
    required this.itemBuilder,
    this.revealIndex,
    this.onRevealed,
    this.flashDuration = const Duration(milliseconds: 900),
    super.key,
  });

  /// Number of rows.
  final int itemCount;

  /// Builds each row.
  final RevealingItemBuilder itemBuilder;

  /// The row to reveal, or null when no request is pending.
  final int? revealIndex;

  /// Called once the pending reveal has been answered (or abandoned
  /// because the row could not be reached).
  final VoidCallback? onRevealed;

  /// How long a revealed row stays flashed.
  final Duration flashDuration;

  @override
  State<RevealingListView> createState() => _RevealingListViewState();
}

class _RevealingListViewState extends State<RevealingListView> {
  /// Frames spent converging on an unbuilt row before giving up.
  static const int _maxAttempts = 8;

  final ScrollController _controller = ScrollController();
  final GlobalKey _targetKey = GlobalKey(debugLabel: 'revealTarget');
  int? _targetIndex;
  int? _flashIndex;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _maybeStartReveal(null);
  }

  @override
  void didUpdateWidget(RevealingListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartReveal(oldWidget.revealIndex);
  }

  void _maybeStartReveal(int? previous) {
    final index = widget.revealIndex;
    if (index == null || index == previous || _targetIndex == index) return;
    _targetIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) => _step(index, 0));
  }

  void _step(int index, int attempt) {
    if (!mounted || _targetIndex != index) return;
    if (index < 0 || index >= widget.itemCount) {
      _finish(index, flash: false);
      return;
    }
    // Scrolls this list's own position only: the panes sit inside a
    // horizontal scroll on a narrow dock, and `Scrollable.ensureVisible`
    // would centre the row on that axis too.
    final target = _targetKey.currentContext?.findRenderObject();
    if (target != null && _controller.hasClients) {
      _controller.position.ensureVisible(
        target,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      _finish(index, flash: true);
      return;
    }
    if (attempt >= _maxAttempts || !_controller.hasClients) {
      _finish(index, flash: false);
      return;
    }
    final position = _controller.position;
    final average =
        (position.maxScrollExtent + position.viewportDimension) /
        widget.itemCount;
    final estimate =
        index * average - (position.viewportDimension - average) / 2;
    _controller.jumpTo(
      estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _step(index, attempt + 1),
    );
  }

  void _finish(int index, {required bool flash}) {
    _targetIndex = null;
    if (flash) {
      _flashTimer?.cancel();
      setState(() => _flashIndex = index);
      _flashTimer = Timer(widget.flashDuration, () {
        if (mounted) setState(() => _flashIndex = null);
      });
    }
    widget.onRevealed?.call();
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        final row = widget.itemBuilder(
          context,
          index,
          flashing: index == _flashIndex,
        );
        if (index != _targetIndex) return row;
        return KeyedSubtree(key: _targetKey, child: row);
      },
    );
  }
}
