// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether somebody here is writing a note: an annotation draft in the
/// Inspector holds unapplied edits.
///
/// A collaborative session tells the room so ("…is writing a note…") instead
/// of streaming the keystrokes: the note travels when it is saved, so nobody
/// watches it appear letter by letter and the protocol needs no collaborative
/// text editing. Root-scoped: the session is app-wide, while each tab's
/// drafts raise it through their own writer (`annotationDraftsProvider`).
final annotationWritingProvider =
    NotifierProvider<AnnotationWritingNotifier, bool>(
      AnnotationWritingNotifier.new,
      name: 'annotationWritingProvider',
    );

/// Notifier behind [annotationWritingProvider]. Counts writers (one per tab
/// with a dirty draft), so one tab finishing cannot clear the flag while
/// another is still writing.
class AnnotationWritingNotifier extends Notifier<bool> {
  int _open = 0;

  @override
  bool build() => false;

  /// A writer started.
  void start() {
    _open++;
    state = true;
  }

  /// A writer finished.
  void stop() {
    if (_open > 0) _open--;
    state = _open > 0;
  }

  /// [stop], after the current provider life-cycle callback: for a writer
  /// that ends inside one (a tab container disposing with a draft open),
  /// where another provider may not be modified. Does nothing once this
  /// provider is gone.
  void stopLater() {
    scheduleMicrotask(() {
      if (ref.mounted) stop();
    });
  }
}
