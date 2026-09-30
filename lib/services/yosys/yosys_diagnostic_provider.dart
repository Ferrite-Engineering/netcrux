// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'yosys_diagnostic_provider.g.dart';

/// The [YosysDiagnosticParser] used to turn yosys stderr into structured
/// diagnostics. Stateless; the provider exists so tests can substitute
/// an instrumented parser if needed.
@Riverpod(keepAlive: true)
YosysDiagnosticParser yosysDiagnosticParser(Ref ref) =>
    const YosysDiagnosticParser();

/// Family-style provider that turns a raw yosys stderr string into a list
/// of [YosysDiagnostic]s. Consumers (`elaborationFailureNotifier`, the
/// future diagnostics panel) watch this provider keyed by the stderr
/// captured from a [YosysRunFailure] and re-render when the input
/// changes.
///
/// The provider is *not* `keepAlive`: each new stderr string is a fresh
/// computation and we don't want to retain stale diagnostic lists in
/// memory after the user dismisses an elaboration failure.
@riverpod
List<YosysDiagnostic> yosysErrorDiagnostic(Ref ref, String stderr) {
  return ref.watch(yosysDiagnosticParserProvider).parse(stderr);
}
