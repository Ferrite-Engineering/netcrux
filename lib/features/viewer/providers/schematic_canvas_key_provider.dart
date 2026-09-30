// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-tab [`GlobalKey`] attached to the `RepaintBoundary` that wraps
/// each tab's [`SchematicCanvas`]. The PNG-export pipeline reads the
/// key off the active tab's container and calls
/// `findRenderObject()` to grab the boundary's render object, which it
/// hands to [`RenderRepaintBoundary.toImage`].
///
/// The provider must be in [`netcruxTabOverridesFactory`] so each tab
/// gets a distinct key; otherwise a PNG export from tab B would
/// rasterise tab A's canvas (or vice versa) under split-pane.
final Provider<GlobalKey> schematicCanvasKeyProvider = Provider<GlobalKey>(
  (_) => GlobalKey(debugLabel: 'schematicCanvasKey'),
);
