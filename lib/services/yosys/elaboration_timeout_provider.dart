// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/enums/elaboration_time_limit.dart';
import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';

/// Open-core default [ElaborationTimeoutPolicy]: a budget that scales with the
/// size of the sources, between a 30 s floor and a 12 h ceiling, times the
/// factor of the user's [ElaborationTimeLimit].
///
/// Pre-elaboration we only know the source byte size, so the budget scales
/// linearly with it at [bytesPerSecond]: a throughput well below what Yosys
/// reaches, so a design that is merely large is never stopped, while a
/// wedged Yosys still is. Measured on a fast desktop, Yosys read and
/// elaborated a 660 MB structural netlist of five million gates in 403 s
/// (1.6 MB/s); at 256 KB/s that source is given 44 minutes, six and a half
/// times as long, which leaves room for a machine several times slower. The
/// floor keeps tiny designs from being killed on a slow cold start. The
/// ceiling is a sanity bound far above any design NetCrux is asked to open;
/// the user can remove the limit altogether, and Cancel always stops a run.
class DefaultElaborationTimeoutPolicy implements ElaborationTimeoutPolicy {
  /// Creates the default policy for the user's [limit].
  const DefaultElaborationTimeoutPolicy({
    this.limit = ElaborationTimeLimit.automatic,
  });

  /// The user's choice: the automatic budget, a multiple of it, or none.
  final ElaborationTimeLimit limit;

  /// Minimum budget: covers subprocess startup and a small design on a cold,
  /// loaded CI box.
  static const Duration floor = Duration(seconds: 30);

  /// Largest automatic budget. A source this large would be about 11 GB.
  static const Duration ceiling = Duration(hours: 12);

  /// Throughput the budget is computed from.
  static const int bytesPerSecond = 256 * 1024;

  @override
  Duration timeoutFor(ElaborationSizeEstimate estimate) {
    final scaledMs = estimate.totalSourceBytes / bytesPerSecond * 1000;
    var base = Duration(milliseconds: scaledMs.round());
    if (base < floor) base = floor;
    if (base > ceiling) base = ceiling;
    // A factor of 0 is "no limit"; the budget is still finite, and
    // [killOnTimeout] says it is not enforced.
    return base * (limit.factor == 0 ? 1 : limit.factor);
  }

  @override
  bool get killOnTimeout => limit != ElaborationTimeLimit.none;
}
