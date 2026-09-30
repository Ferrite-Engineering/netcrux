// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';

/// Tuning knobs passed to [ResetDomainAnalysisService.analyze].
///
/// All knobs are optional; the defaults give a sensible behavior for
/// typical netlists (a few hundred to a few thousand registers across
/// 1–8 reset domains).
@immutable
class ResetDomainAnalysisOptions {
  /// Creates an options bundle. All fields are optional.
  const ResetDomainAnalysisOptions({
    this.scopeFilter,
    this.userSynchronizerPatterns = const <String>[],
    this.minSeverityToReport = ResetSeverity.info,
    this.maxPathDepth = 10,
  });

  /// Canonical "use all defaults" instance.
  static const ResetDomainAnalysisOptions defaults =
      ResetDomainAnalysisOptions();

  /// Optional canonical hierarchical-path prefix that restricts the
  /// walk to a sub-tree of the design (e.g. `"top.cpu"`). Null walks
  /// the entire design.
  final ElementId? scopeFilter;

  /// User-asserted module-name patterns (substring match on cell
  /// `type`) that should be treated as custom reset synchronizers.
  /// When a crossing's path runs through an instance whose `type`
  /// matches any of these patterns, the analyzer classifies it as
  /// [ResetSynchronizerStatus.customSynchronizer] regardless of the
  /// instance's structural shape.
  final List<String> userSynchronizerPatterns;

  /// Crossings with severity strictly below this level are still
  /// detected but omitted from the returned result. The default of
  /// [ResetSeverity.info] returns everything; raise to
  /// [ResetSeverity.warning] or [ResetSeverity.critical] to filter at
  /// analysis time.
  final ResetSeverity minSeverityToReport;

  /// Upper bound on the number of cells the synchronizer-classification
  /// walker traverses from source-domain driver to destination-domain
  /// consumer. Deeper paths are classified as [ResetConfidence.low].
  /// Default of 10 covers nearly every real reset synchronizer; raise
  /// on designs that buffer their sync chains heavily.
  final int maxPathDepth;

  /// Returns a copy with the given fields replaced. Pass
  /// `clearScopeFilter` to reset the scope to null explicitly.
  ResetDomainAnalysisOptions copyWith({
    ElementId? scopeFilter,
    List<String>? userSynchronizerPatterns,
    ResetSeverity? minSeverityToReport,
    int? maxPathDepth,
    bool clearScopeFilter = false,
  }) => ResetDomainAnalysisOptions(
    scopeFilter: clearScopeFilter ? null : (scopeFilter ?? this.scopeFilter),
    userSynchronizerPatterns:
        userSynchronizerPatterns ?? this.userSynchronizerPatterns,
    minSeverityToReport: minSeverityToReport ?? this.minSeverityToReport,
    maxPathDepth: maxPathDepth ?? this.maxPathDepth,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ResetDomainAnalysisOptions) return false;
    if (scopeFilter != other.scopeFilter) return false;
    if (userSynchronizerPatterns.length !=
        other.userSynchronizerPatterns.length) {
      return false;
    }
    for (var i = 0; i < userSynchronizerPatterns.length; i++) {
      if (userSynchronizerPatterns[i] != other.userSynchronizerPatterns[i]) {
        return false;
      }
    }
    if (minSeverityToReport != other.minSeverityToReport) return false;
    if (maxPathDepth != other.maxPathDepth) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    scopeFilter,
    Object.hashAll(userSynchronizerPatterns),
    minSeverityToReport,
    maxPathDepth,
  );

  @override
  String toString() =>
      'ResetDomainAnalysisOptions('
      'scope: ${scopeFilter?.path ?? "all"}, '
      'customPatterns: ${userSynchronizerPatterns.length}, '
      'minSeverity: ${minSeverityToReport.name}, '
      'maxDepth: $maxPathDepth)';
}
