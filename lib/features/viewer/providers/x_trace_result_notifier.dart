// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'x_trace_result_notifier.g.dart';

/// Per-tab notifier holding the latest [XTraceResult] computed by the
/// active [XTraceService]. Pro feature surface — the open-core
/// [NoopXTraceService] always writes [XTraceResult.empty] here, so a
/// running open-core build silently shows the empty state in the
/// X-trace result panel.
///
/// Scoped per tab via the tab-container parent / overrides pattern
/// (mirrors `traceOverlayProvider`, `selectedElementProvider`, …).
@Riverpod(keepAlive: true)
class XTraceResultNotifier extends _$XTraceResultNotifier {
  @override
  XTraceResult build() => XTraceResult.empty;

  /// Replaces the result with [result]. No-op when nothing changed —
  /// the result panel listens via `ref.watch`, so identical results
  /// must avoid re-painting downstream widgets.
  void set(XTraceResult result) {
    if (state == result) return;
    state = result;
  }

  /// Resets to the canonical empty result — paint normally on the
  /// next frame.
  void clear() {
    if (state.isEmpty &&
        state.termination == XTraceTermination.noTraceableSelection) {
      return;
    }
    state = XTraceResult.empty;
  }
}
