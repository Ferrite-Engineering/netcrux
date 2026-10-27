// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// The line a panel row leads with: the annotation's title, the first line
/// of its body when untitled, or its element id when it has neither.
String annotationRowHeading(Annotation annotation) {
  final heading = annotation.heading;
  return heading.isEmpty ? annotation.targetId : heading;
}

/// The Markdown a panel row shows under its heading: the whole body for a
/// titled annotation, and the body after its first line for an untitled
/// one, whose first line is already the heading.
String annotationRowDetails(Annotation annotation) {
  final body = annotation.body.trim();
  if (annotation.title != null) return body;
  final firstBreak = body.indexOf('\n');
  return firstBreak < 0 ? '' : body.substring(firstBreak + 1).trim();
}

/// [markdown] as a screen reader should read it: emphasis and code marks,
/// heading and quote markers and list bullets dropped, lines joined.
String annotationSpokenText(String markdown) => markdown
    .split('\n')
    .map(
      (line) => line
          .replaceFirst(RegExp(r'^\s*(#{1,6}\s+|>\s?|[-*+]\s+)'), '')
          .replaceAll(RegExp('[*`~]'), '')
          .trim(),
    )
    .where((line) => line.isNotEmpty)
    .join(' ');

/// The localized name of an annotation target kind, as the panel and the
/// screen-reader labels show it.
String annotationTargetKindLabel(L10N l10n, AnnotationTargetKind kind) {
  switch (kind) {
    case AnnotationTargetKind.cell:
      return l10n.annotationTargetKindCell;
    case AnnotationTargetKind.port:
      return l10n.annotationTargetKindPort;
    case AnnotationTargetKind.boundaryPort:
      return l10n.annotationTargetKindBoundaryPort;
    case AnnotationTargetKind.net:
      return l10n.annotationTargetKindNet;
    case AnnotationTargetKind.scope:
      return l10n.annotationTargetKindScope;
  }
}
