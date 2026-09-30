// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point: widgets stacked above the schematic, below the
/// tab strip, for conditions the user has to act on rather than notice later.
///
/// Open core returns an empty list, so the workspace renders unchanged. The
/// closed-source Pro overlay overrides the binding to inject its own
/// notices without forking the open-core shell — the sibling of
/// [statusBarTrailingWidgetsProvider], and split from it on purpose: the status
/// bar reports *state* (how many people are collaborating) and this slot
/// reports *problems* (one of them is holding the wrong invite).
///
/// Injected widgets are responsible for rendering `SizedBox.shrink()` when they
/// have nothing to say, so the slot adds no visual weight when nothing is
/// wrong — which is almost always.
final workspaceBannerWidgetsProvider = Provider<List<Widget>>(
  (_) => const <Widget>[],
  name: 'workspaceBannerWidgetsProvider',
);
