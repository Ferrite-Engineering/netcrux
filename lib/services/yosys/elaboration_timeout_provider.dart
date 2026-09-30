// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'elaboration_timeout_provider.g.dart';

/// Open-core default [ElaborationTimeoutPolicy]: a size-aware budget with a
/// 30 s floor and a 10 min cap.
///
/// Pre-elaboration we only know the source byte size, so the budget scales
/// linearly with it at [_bytesPerSecond] (a deliberately generous read +
/// elaborate throughput floor — well below real Yosys speed, so honest
/// designs never trip it; a wedged Yosys still gets killed). The floor
/// keeps tiny designs from being killed on a slow cold start; the cap
/// bounds the worst case so even a 1 GB include can't wait forever.
class DefaultElaborationTimeoutPolicy implements ElaborationTimeoutPolicy {
  /// Creates the default policy.
  const DefaultElaborationTimeoutPolicy();

  /// Minimum budget — covers subprocess startup + a small design on a cold,
  /// loaded CI box.
  static const Duration floor = Duration(seconds: 30);

  /// Maximum budget — the hard ceiling on any single elaboration.
  static const Duration cap = Duration(minutes: 10);

  /// Throughput floor used to scale the budget by input size. Conservative
  /// on purpose: ~512 KB/s means even a slow box comfortably beats it, so
  /// the budget only bites a genuinely stuck process.
  static const int _bytesPerSecond = 512 * 1024;

  @override
  Duration timeoutFor(ElaborationSizeEstimate estimate) {
    final scaledMs = estimate.totalSourceBytes / _bytesPerSecond * 1000;
    final scaled = Duration(milliseconds: scaledMs.round());
    if (scaled < floor) return floor;
    if (scaled > cap) return cap;
    return scaled;
  }

  @override
  bool get killOnTimeout => true;
}

/// The [ElaborationTimeoutPolicy] consulted by the elaboration pipeline
/// before each Yosys run. Open-core registers [DefaultElaborationTimeoutPolicy];
/// a Pro tier may override this in `lib/overrides.dart` to expose a
/// user-configurable per-design budget. Bounding elaboration needs
/// no Pro override — the default policy is sufficient on its own.
@Riverpod(keepAlive: true)
ElaborationTimeoutPolicy elaborationTimeoutPolicy(Ref ref) =>
    const DefaultElaborationTimeoutPolicy();
