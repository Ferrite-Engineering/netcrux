// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the Add / Edit Annotation dialog is open — somebody here is
/// writing a note.
///
/// A collaborative session tells the room so ("…is writing a note…") instead
/// of streaming the keystrokes: the note travels when it is saved, so nobody
/// watches it appear letter by letter and the protocol needs no collaborative
/// text editing. Root-scoped: the dialog is app chrome, not a tab's state.
final annotationWritingProvider =
    NotifierProvider<AnnotationWritingNotifier, bool>(
      AnnotationWritingNotifier.new,
      name: 'annotationWritingProvider',
    );

/// Notifier behind [annotationWritingProvider]. Counts open dialogs, so a
/// nested open and close cannot clear the flag while one is still open.
class AnnotationWritingNotifier extends Notifier<bool> {
  int _open = 0;

  @override
  bool build() => false;

  /// A dialog opened.
  void start() {
    _open++;
    state = true;
  }

  /// A dialog closed.
  void stop() {
    if (_open > 0) _open--;
    state = _open > 0;
  }
}
