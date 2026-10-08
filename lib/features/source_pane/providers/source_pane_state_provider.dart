// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/interfaces/source_pane_service.dart';
import 'package:netcrux/domain/models/source_file_content.dart';
import 'package:netcrux/domain/models/source_load_exception.dart';
import 'package:netcrux/services/source_pane/source_pane_service_provider.dart';

/// State held by [SourcePaneStateNotifier] for a single tab's RTL
/// source pane.
///
/// Encapsulates: the currently-loaded file content, the set of
/// 1-based line numbers to highlight, the line to scroll the
/// viewport to centre on (or null when scroll has already been
/// applied), the [ElementId] of the schematic element that drove
/// the most recent navigation (used by the "Jump to element" status
/// button), and the most recent loader error (cleared on next
/// successful load).
@immutable
class SourcePaneState {
  /// Creates a source-pane state snapshot.
  const SourcePaneState({
    this.currentContent = SourceFileContent.empty,
    this.highlightedLines = const <int>{},
    this.scrollToLine,
    this.currentElementId,
    this.error,
  });

  /// Canonical empty state — the initial value before any selection
  /// has been routed into the pane.
  static const SourcePaneState empty = SourcePaneState();

  /// File content currently displayed by the pane.
  final SourceFileContent currentContent;

  /// 1-based line numbers to render with the highlight background.
  final Set<int> highlightedLines;

  /// 1-based line the viewport should centre on. Cleared to null
  /// once the renderer has applied the scroll so subsequent
  /// rebuilds don't re-jump.
  final int? scrollToLine;

  /// [ElementId] of the schematic element that drove the most
  /// recent navigation. Null when the pane was loaded without a
  /// driving selection (e.g. user dragged in a file directly).
  final ElementId? currentElementId;

  /// Most recent loader error, or null. Cleared on the next
  /// successful load.
  final SourceLoadException? error;

  /// True when [currentContent] holds a real file (non-empty).
  bool get hasContent => currentContent.lines.isNotEmpty;

  /// True when [currentContent.filePath] is non-empty.
  bool get hasFilePath => currentContent.filePath.isNotEmpty;

  /// Convenience accessor — the currently-loaded file path, or null
  /// when the pane is empty.
  String? get currentFilePath => hasFilePath ? currentContent.filePath : null;

  /// Copies the state with selective overrides. Pass `clearError`,
  /// `clearScrollToLine`, or `clearElementId` to explicitly reset a
  /// field rather than just leaving the old value.
  SourcePaneState copyWith({
    SourceFileContent? currentContent,
    Set<int>? highlightedLines,
    int? scrollToLine,
    ElementId? currentElementId,
    SourceLoadException? error,
    bool clearError = false,
    bool clearScrollToLine = false,
    bool clearElementId = false,
  }) {
    return SourcePaneState(
      currentContent: currentContent ?? this.currentContent,
      highlightedLines: highlightedLines ?? this.highlightedLines,
      scrollToLine: clearScrollToLine
          ? null
          : (scrollToLine ?? this.scrollToLine),
      currentElementId: clearElementId
          ? null
          : (currentElementId ?? this.currentElementId),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SourcePaneState) return false;
    if (other.currentContent != currentContent) return false;
    if (other.scrollToLine != scrollToLine) return false;
    if (other.currentElementId != currentElementId) return false;
    if (other.error != error) return false;
    if (other.highlightedLines.length != highlightedLines.length) return false;
    for (final line in highlightedLines) {
      if (!other.highlightedLines.contains(line)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    currentContent,
    scrollToLine,
    currentElementId,
    error,
    Object.hashAll(highlightedLines),
  );
}

/// Notifier owning the per-tab [SourcePaneState].
///
/// Lives in a per-tab `ProviderContainer` (mirrors how
/// [annotationStateProvider] / [xTraceResultProvider] are
/// scoped) so each open tab keeps its own source-pane viewport,
/// highlighted lines, and scroll position. The hosting [PaneHost]
/// is responsible for routing schematic selection changes from the
/// active tab into [setActiveFile] / [setActiveElement].
class SourcePaneStateNotifier extends Notifier<SourcePaneState> {
  @override
  SourcePaneState build() => SourcePaneState.empty;

  /// Loads [filePath] via the active [SourcePaneService] and updates
  /// state on completion. Drops any prior content and highlighted
  /// lines; sets [SourcePaneState.error] on failure (preserves the
  /// previous content so the user can keep reading the last
  /// successfully-loaded file).
  Future<void> setActiveFile(
    String filePath, {
    Set<int> highlightedLines = const <int>{},
    int? scrollToLine,
    ElementId? elementId,
  }) async {
    final service = ref.read(sourcePaneServiceProvider);
    try {
      final content = await service.loadSource(filePath);
      state = SourcePaneState(
        currentContent: content,
        highlightedLines: highlightedLines,
        scrollToLine: scrollToLine,
        currentElementId: elementId,
      );
    } on SourceLoadException catch (e) {
      state = state.copyWith(
        error: e,
        clearScrollToLine: true,
      );
    }
  }

  /// Resolves [elementId] through the active [SourcePaneService]
  /// and, on a hit, calls [setActiveFile] for the first returned
  /// location. Returns true when navigation succeeded.
  ///
  /// When the element has no source attribution this is a no-op
  /// (returns false); the pane keeps its previous content.
  Future<bool> setActiveElement(ElementId elementId) async {
    final service = ref.read(sourcePaneServiceProvider);
    final locations = service.sourceLocationsForElement(elementId).toList();
    if (locations.isEmpty) return false;
    final loc = locations.first;
    await setActiveFile(
      loc.filePath,
      highlightedLines: <int>{loc.line},
      scrollToLine: loc.line,
      elementId: elementId,
    );
    return state.error == null;
  }

  /// Clears the pane back to its empty state.
  void clearActiveFile() {
    state = SourcePaneState.empty;
  }

  /// Replaces the highlighted-lines set.
  void setHighlightedLines(Set<int> lines) {
    state = state.copyWith(highlightedLines: lines);
  }

  /// Asks the renderer to centre the viewport on [line]. Cleared
  /// automatically when [acknowledgeScroll] is called by the
  /// renderer post-frame.
  void scrollToLineCenter(int line) {
    state = state.copyWith(scrollToLine: line);
  }

  /// Called by the renderer once it has applied the scroll. Clears
  /// [SourcePaneState.scrollToLine] so re-builds don't re-jump.
  void acknowledgeScroll() {
    if (state.scrollToLine == null) return;
    state = state.copyWith(clearScrollToLine: true);
  }
}

/// Riverpod provider exposing the per-tab [SourcePaneStateNotifier].
///
/// Scoped per-tab via the workspace's [TabContainerManager], same
/// pattern as annotations / X-trace.
final sourcePaneStateProvider =
    NotifierProvider<SourcePaneStateNotifier, SourcePaneState>(
      SourcePaneStateNotifier.new,
      name: 'sourcePaneStateProvider',
    );
