// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// One line of [text] that, when it does not fit, drops characters from the
/// **start** and shows an ellipsis there (`…alu.add_cy_r_SB_LUT4_I3_1`), so
/// the tail always shows.
///
/// For names whose distinguishing part is at the end: in a flat
/// post-synthesis netlist every cell name carries the full dotted path, so
/// the shared prefix is the part worth losing. Flutter's
/// [TextOverflow.ellipsis] only cuts the end, so the fitting suffix is
/// measured with a [TextPainter] ([startElidedText]).
class StartEllipsisText extends StatelessWidget {
  /// Creates a start-elided line of [text] in [style].
  const StartEllipsisText(this.text, {this.style, super.key});

  /// The full text.
  final String text;

  /// The text style, merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = startElidedText(
          text,
          style: effective,
          maxWidth: constraints.maxWidth,
          textScaler: scaler,
          textDirection: direction,
        );
        return Text(
          shown,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        );
      },
    );
  }
}

/// The ellipsis [startElidedText] puts in front of a cut name.
const String startEllipsis = '…';

/// [text] when it fits in [maxWidth] on one line, otherwise [startEllipsis]
/// followed by the longest tail of [text] that fits with it. Cuts on
/// character (grapheme) boundaries. An unbounded [maxWidth] returns [text].
String startElidedText(
  String text, {
  required TextStyle style,
  required double maxWidth,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (text.isEmpty || !maxWidth.isFinite) return text;
  final painter = TextPainter(
    maxLines: 1,
    textDirection: textDirection,
    textScaler: textScaler,
  );
  bool fits(String candidate) {
    painter
      ..text = TextSpan(text: candidate, style: style)
      ..layout();
    return painter.width <= maxWidth;
  }

  try {
    if (fits(text)) return text;
    final chars = text.characters.toList();
    // The fewest characters to drop so the rest fits behind the ellipsis.
    var low = 1;
    var high = chars.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (fits(startEllipsis + chars.sublist(mid).join())) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return startEllipsis + chars.sublist(low).join();
  } finally {
    painter.dispose();
  }
}
