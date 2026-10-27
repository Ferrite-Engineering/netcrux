// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show announceCrux;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Whether annotation callouts are drawn on the schematic. One switch for the
/// whole app, on by default: a user sees their notes on the canvas until they
/// turn them off with View > Show Annotation Callouts.
final NotifierProvider<AnnotationCalloutsVisible, bool>
annotationCalloutsVisibleProvider =
    NotifierProvider<AnnotationCalloutsVisible, bool>(
      AnnotationCalloutsVisible.new,
      name: 'annotationCalloutsVisibleProvider',
    );

/// The switch behind [annotationCalloutsVisibleProvider].
class AnnotationCalloutsVisible extends Notifier<bool> {
  @override
  bool build() => true;

  /// Shows the callouts when hidden and hides them when shown.
  void toggle() => state = !state;
}

/// View > Show Annotation Callouts and its palette entry: shows or hides the
/// callouts and says which, since the change can happen with nothing on the
/// canvas to see. Available at every tier.
void toggleAnnotationCallouts(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(annotationCalloutsVisibleProvider.notifier).toggle();
  final l10n = L10N.of(context);
  announceCrux(
    context,
    container.read(annotationCalloutsVisibleProvider)
        ? l10n.annotationCalloutsShownAnnouncement
        : l10n.annotationCalloutsHiddenAnnouncement,
  );
}
