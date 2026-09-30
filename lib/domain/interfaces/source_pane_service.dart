// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:netcrux/domain/models/source_file_content.dart';
import 'package:netcrux/domain/models/source_load_exception.dart';
import 'package:netcrux/domain/models/source_location.dart';

/// Extension-point service powering the RTL source pane.
///
/// The pane is a read-only viewer that displays an RTL source file
/// with the line corresponding to the user's current schematic
/// selection highlighted. Two bidirectional mappings drive it:
///
/// 1. **Forward** (schematic → source): given the [ElementId] of a
///    selected cell / port / net / scope, return the source-file
///    location(s) that define it. Powers the auto-scroll + highlight
///    flow when the user clicks an element in the schematic.
///
/// 2. **Reverse** (source → schematic): given a `(filePath, line)`
///    pair, return the set of schematic elements whose definitions
///    live there. Powers the click-token-in-source → emit-selection
///    flow.
///
/// The interface is intentionally read-as-snapshot — there is no
/// "scroll to" or "highlight" method on the service. The Pro panel
/// keeps the active source file and current selection in its own
/// Riverpod state and treats this service as a pure lookup layer.
///
/// **Open-core ships [NoopSourcePaneService]** as the registered
/// default. It throws [SourceLoadException] with reason `notFound`
/// from [loadSource] and returns empty results from both lookup
/// methods. The Pro overlay registers a `ProSourcePaneService` via
/// `proOverrides` that reads files from disk, parses Yosys `src`
/// attributes from the elaborated netlist, and runs a small
/// Verilog/SystemVerilog/VHDL lexer to populate [SourceToken]s.
abstract interface class SourcePaneService {
  /// Loads the source file at [filePath].
  ///
  /// Returns a [SourceFileContent] with [SourceFileContent.lines]
  /// populated. [SourceFileContent.tokens] is empty under the
  /// open-core default; the Pro overlay populates it via a lexer.
  ///
  /// Throws [SourceLoadException] on a missing / unreadable / decode
  /// failure.
  Future<SourceFileContent> loadSource(String filePath);

  /// Returns the schematic elements whose definitions are recorded
  /// at `filePath:line` (or `filePath:line:column` when [column] is
  /// supplied). Empty when the service has no source-attribution
  /// data for the location.
  Iterable<ElementId> elementsAtSourceLocation(
    String filePath,
    int line, {
    int? column,
  });

  /// Returns the source-file location(s) where the schematic element
  /// identified by [elementId] is defined. Empty when the service
  /// has no source-attribution data for the element (synthetic
  /// Yosys-emitted nodes carry no `src` attribute).
  Iterable<SourceLocation> sourceLocationsForElement(ElementId elementId);

  /// Stream that emits when the underlying source-attribution index
  /// becomes stale (e.g. re-elaboration after a user edit). The Pro
  /// panel listens to this stream and re-resolves the active
  /// selection's source location so the highlighted line stays
  /// correct.
  ///
  /// Open-core's no-op default never emits.
  Stream<void> get indexInvalidated;
}

/// Open-core default: no source-attribution data, no file loading.
///
/// Every read returns the empty / not-found result. The open-core build
/// registers this implementation and mounts nothing over it: the
/// `SourcePane` is mounted only by the Pro overlay, and
/// [NetcruxAction.openSourceForElement] stays discoverable in the menu /
/// palette while an open-core build refuses it with a "requires NetCrux
/// Pro" notice. The Pro overlay swaps this out via `proOverrides`.
class NoopSourcePaneService implements SourcePaneService {
  /// Creates the no-op service.
  const NoopSourcePaneService();

  @override
  Future<SourceFileContent> loadSource(String filePath) async {
    throw SourceLoadException(
      filePath: filePath,
      reason: SourceLoadFailure.notFound,
      detail: 'Open-core build has no source-attribution data.',
    );
  }

  @override
  Iterable<ElementId> elementsAtSourceLocation(
    String filePath,
    int line, {
    int? column,
  }) => const <ElementId>[];

  @override
  Iterable<SourceLocation> sourceLocationsForElement(ElementId elementId) =>
      const <SourceLocation>[];

  @override
  Stream<void> get indexInvalidated => const Stream<void>.empty();
}
