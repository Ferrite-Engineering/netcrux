// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';

/// Kills every Yosys subprocess still running when the app detaches.
///
/// `crux_yosys` registers each process it spawns in a [ProcessRegistry]
/// but deliberately does not depend on Flutter's lifecycle, so the host
/// has to drain the registry. Nothing fails without this: elaboration
/// keeps working and no test goes red. The cost is paid only by the
/// user — a hard quit or a parent crash mid-elaboration orphans a
/// `yosys` process that keeps consuming a core until it is killed by
/// hand.
///
/// Only `detached` drains. `paused` is a mobile background transition
/// where the process is expected to resume; killing a running
/// elaboration there would discard work the user is coming back to.
class YosysProcessReaper extends StatefulWidget {
  /// Wraps [child] with the detach-time process drain.
  const YosysProcessReaper({
    required this.child,
    this.registry,
    super.key,
  });

  /// Registry to drain. Defaults to the process-wide
  /// [ProcessRegistry.instance] that `DefaultProcessRunner` uses.
  final ProcessRegistry? registry;

  /// Subtree rendered unchanged.
  final Widget child;

  @override
  State<YosysProcessReaper> createState() => _YosysProcessReaperState();
}

class _YosysProcessReaperState extends State<YosysProcessReaper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) return;
    (widget.registry ?? ProcessRegistry.instance).killAll();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
