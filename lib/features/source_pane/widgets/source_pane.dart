// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/source_file_content.dart';
import 'package:netcrux/domain/models/source_load_exception.dart';
import 'package:netcrux/domain/models/source_token.dart';
import 'package:netcrux/features/source_pane/providers/source_pane_state_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Open-core RTL source pane widget.
///
/// Renders the source file currently held by
/// [sourcePaneStateProvider]: line numbers + token-classified text in
/// monospace, with the active line highlighted and the viewport
/// auto-scrolled when [SourcePaneState.scrollToLine] is set. A remount
/// with no pending scroll centres the highlighted line again, and lines
/// longer than the pane is wide scroll sideways inside the code view
/// rather than being clipped.
///
/// Tokens that carry an [SourceToken.associatedElementId] render as
/// tappable; the tap callback fires [onTokenTap]. The hosting Pro
/// panel wires that into the active-tab selection provider so
/// clicking a source-side identifier highlights the corresponding
/// element in the schematic.
///
/// The widget itself is layout-agnostic and tier-agnostic: the Pro
/// overlay's `SourcePanePanel` wraps it in panel chrome + tier badge,
/// and is the only place it is mounted — the open-core build refuses the
/// source-pane actions with a "requires NetCrux Pro" notice and mounts no
/// pane. Empty state copy and error
/// messages come from open-core ARB; the Pro chrome strings are
/// supplied separately by the Pro overlay's L10NPro.
class SourcePane extends ConsumerWidget {
  /// Creates the source-pane widget.
  const SourcePane({this.onTokenTap, this.onCursorPositionChanged, super.key});

  /// Invoked when the user taps a token that carries an associated
  /// [ElementId]. The caller typically emits a selection into the
  /// schematic via the active-tab selection provider.
  final void Function(ElementId)? onTokenTap;

  /// Invoked with the (line, column) of the token under the user's
  /// most recent tap. The Pro panel uses this to populate the
  /// "Jump to element" status-bar button.
  final void Function(int line, int? column, ElementId? underToken)?
  onCursorPositionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(sourcePaneStateProvider);

    if (state.error != null) {
      return _ErrorState(l10n: l10n, error: state.error!);
    }
    if (!state.hasContent) {
      return CruxPanelEmptyState(
        icon: Icons.code_off,
        message:
            '${l10n.sourcePaneEmptyTitle}\n'
            '${l10n.sourcePaneEmptyHint}',
      );
    }
    return _LoadedView(
      content: state.currentContent,
      highlightedLines: state.highlightedLines,
      scrollToLine: state.scrollToLine,
      onScrollAcknowledged: () =>
          ref.read(sourcePaneStateProvider.notifier).acknowledgeScroll(),
      onTokenTap: onTokenTap,
      onCursorPositionChanged: onCursorPositionChanged,
    );
  }
}

// ── error state ───────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.l10n, required this.error});

  final L10N l10n;
  final SourceLoadException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = _bodyFor(l10n, error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 28, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.filePath,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _bodyFor(L10N l10n, SourceLoadException e) {
    switch (e.reason) {
      case SourceLoadFailure.notFound:
        return l10n.sourcePaneErrorNotFound;
      case SourceLoadFailure.accessDenied:
        return l10n.sourcePaneErrorAccessDenied;
      case SourceLoadFailure.encodingFailure:
        return l10n.sourcePaneErrorEncoding;
      case SourceLoadFailure.oversized:
        return l10n.sourcePaneErrorOversized;
      case SourceLoadFailure.ioError:
        return l10n.sourcePaneErrorGeneric;
    }
  }
}

// ── loaded view ──────────────────────────────────────────────────────

class _LoadedView extends StatefulWidget {
  const _LoadedView({
    required this.content,
    required this.highlightedLines,
    required this.scrollToLine,
    required this.onScrollAcknowledged,
    required this.onTokenTap,
    required this.onCursorPositionChanged,
  });

  final SourceFileContent content;
  final Set<int> highlightedLines;
  final int? scrollToLine;
  final VoidCallback onScrollAcknowledged;
  final void Function(ElementId)? onTokenTap;
  final void Function(int line, int? column, ElementId? underToken)?
  onCursorPositionChanged;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  // Tokens grouped by 1-based line number for cheap per-line lookup.
  late Map<int, List<SourceToken>> _tokensByLine;
  // Character count of the file's longest line, tabs counted wide, so the
  // code can be laid out at its own width and scroll sideways in a pane
  // narrower than it.
  late int _longestLineChars;

  static const double _lineHeight = 18;

  // `_SourceLineRow`'s fixed chrome: horizontal padding on both sides, the
  // line-number gutter and the gap after it.
  static const double _rowChromeWidth = 8 + 44 + 8 + 8;

  // A tab renders narrower than the column it advances to in an editor; it
  // is counted as this many characters so a tab-indented line is not
  // clipped at its end.
  static const int _tabWidthChars = 4;

  @override
  void initState() {
    super.initState();
    _rebuildTokenIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyScroll());
  }

  @override
  void didUpdateWidget(_LoadedView old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _rebuildTokenIndex();
    }
    if (widget.scrollToLine != null &&
        widget.scrollToLine != old.scrollToLine) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyScroll());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _rebuildTokenIndex() {
    final map = <int, List<SourceToken>>{};
    for (final t in widget.content.tokens) {
      map.putIfAbsent(t.line, () => <SourceToken>[]).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.columnStart.compareTo(b.columnStart));
    }
    _tokensByLine = map;
    var longest = 0;
    for (final line in widget.content.lines) {
      final tabs = '\t'.allMatches(line).length;
      final chars = line.length + tabs * (_tabWidthChars - 1);
      if (chars > longest) longest = chars;
    }
    _longestLineChars = longest;
  }

  void _applyScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final pending = widget.scrollToLine;
    // With no pending jump, the highlight still marks the line the reader was
    // taken to. A docked pane is rebuilt each time its tab comes back to the
    // front, so centring the highlight again keeps that line in view instead
    // of starting the file at line 1.
    final target = pending ?? _firstHighlightedLine();
    if (target == null) return;
    final lineTop = (target - 1) * _lineHeight;
    final viewport = _scrollController.position.viewportDimension;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final goal = (lineTop - viewport / 2).clamp(
      0.0,
      maxExtent < 0 ? 0.0 : maxExtent,
    );
    _scrollController.jumpTo(goal);
    if (pending == null) return;
    // A new navigation starts at the line numbers, not wherever an earlier
    // read left the sideways scroll.
    if (_horizontalController.hasClients) _horizontalController.jumpTo(0);
    widget.onScrollAcknowledged();
  }

  int? _firstHighlightedLine() {
    final lines = widget.highlightedLines;
    if (lines.isEmpty) return null;
    return lines.reduce((a, b) => a < b ? a : b);
  }

  /// The width the longest line needs, measured with the code font.
  double _codeWidth(BuildContext context) {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final charWidth = painter.width;
    painter.dispose();
    return _rowChromeWidth + _longestLineChars * charWidth;
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.content.lines;
    final list = ListView.builder(
      controller: _scrollController,
      itemCount: lines.length,
      itemExtent: _lineHeight,
      itemBuilder: (context, index) {
        final lineNumber = index + 1;
        final isHighlighted = widget.highlightedLines.contains(lineNumber);
        return _SourceLineRow(
          lineNumber: lineNumber,
          rawText: lines[index],
          tokens: _tokensByLine[lineNumber] ?? const <SourceToken>[],
          isHighlighted: isHighlighted,
          onTokenTap: widget.onTokenTap,
          onTokenSelected: widget.onCursorPositionChanged,
        );
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return list;
        }
        // The code lays out at its own width and scrolls sideways when the
        // pane is narrower, so a docked pane at its default width still
        // shows a long line in full instead of clipping it. Only the code
        // scrolls: the panel chrome around it stays at the pane's width.
        final codeWidth = _codeWidth(context);
        final width = codeWidth > constraints.maxWidth
            ? codeWidth
            : constraints.maxWidth;
        // Both bars are explicit: the vertical one sits on the pane's edge
        // (it hears the list one level down), where the list's own default
        // bar would sit on the far edge of the wide code, out of view.
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Scrollbar(
            controller: _scrollController,
            notificationPredicate: (n) => n.depth == 1,
            child: Scrollbar(
              controller: _horizontalController,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: list,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SourceLineRow extends StatelessWidget {
  const _SourceLineRow({
    required this.lineNumber,
    required this.rawText,
    required this.tokens,
    required this.isHighlighted,
    required this.onTokenTap,
    required this.onTokenSelected,
  });

  final int lineNumber;
  final String rawText;
  final List<SourceToken> tokens;
  final bool isHighlighted;
  final void Function(ElementId)? onTokenTap;
  final void Function(int line, int? column, ElementId? underToken)?
  onTokenSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final spans = _buildSpans(cs);

    return Container(
      color: isHighlighted ? cs.primary.withValues(alpha: 0.18) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: spans),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _buildSpans(ColorScheme cs) {
    if (tokens.isEmpty) {
      return <InlineSpan>[
        TextSpan(
          text: rawText,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: cs.onSurface,
          ),
        ),
      ];
    }
    final children = <InlineSpan>[];
    var cursor = 1; // 1-based column cursor through rawText
    for (final token in tokens) {
      if (token.columnStart > cursor) {
        // Gap of unclassified text (whitespace or unknown).
        final gap = _substringByColumn(rawText, cursor, token.columnStart);
        if (gap.isNotEmpty) {
          children.add(
            TextSpan(
              text: gap,
              style: _styleFor(SourceTokenKind.whitespace, cs),
            ),
          );
        }
      }
      final text = _substringByColumn(
        rawText,
        token.columnStart,
        token.columnEnd,
      );
      if (token.associatedElementId != null) {
        final elementId = token.associatedElementId!;
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _TappableTokenSpan(
              text: text,
              style: _styleFor(token.kind, cs).copyWith(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
                color: cs.primary,
              ),
              onTap: () {
                onTokenTap?.call(elementId);
                onTokenSelected?.call(token.line, token.columnStart, elementId);
              },
            ),
          ),
        );
      } else {
        children.add(TextSpan(text: text, style: _styleFor(token.kind, cs)));
      }
      cursor = token.columnEnd;
    }
    // Trailing tail past the last token.
    if (cursor <= rawText.length) {
      final tail = _substringByColumn(rawText, cursor, rawText.length + 1);
      if (tail.isNotEmpty) {
        children.add(
          TextSpan(text: tail, style: _styleFor(SourceTokenKind.unknown, cs)),
        );
      }
    }
    return children;
  }

  String _substringByColumn(String text, int startCol1, int endCol1) {
    // 1-based, inclusive start, exclusive end.
    final start = (startCol1 - 1).clamp(0, text.length);
    final end = (endCol1 - 1).clamp(start, text.length);
    return text.substring(start, end);
  }

  TextStyle _styleFor(SourceTokenKind kind, ColorScheme cs) {
    const base = TextStyle(fontSize: 12, fontFamily: 'monospace');
    switch (kind) {
      case SourceTokenKind.keyword:
        return base.copyWith(color: cs.primary, fontWeight: FontWeight.w600);
      case SourceTokenKind.identifier:
        return base.copyWith(color: cs.onSurface);
      case SourceTokenKind.number:
        return base.copyWith(color: cs.secondary);
      case SourceTokenKind.string:
        return base.copyWith(color: cs.tertiary);
      case SourceTokenKind.comment:
        return base.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        );
      case SourceTokenKind.operator:
        return base.copyWith(color: cs.onSurface);
      case SourceTokenKind.whitespace:
        return base.copyWith(color: cs.onSurface);
      case SourceTokenKind.unknown:
        return base.copyWith(color: cs.onSurface);
    }
  }
}

/// Inline tappable span — a tiny stateless wrapper around an
/// [InkWell] sized to a token. Kept private to this file.
class _TappableTokenSpan extends StatelessWidget {
  const _TappableTokenSpan({
    required this.text,
    required this.style,
    required this.onTap,
  });

  final String text;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      child: Text(text, style: style),
    );
  }
}
