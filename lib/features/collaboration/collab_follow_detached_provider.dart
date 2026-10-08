// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a follower may stay detached without touching the view before
/// the room snaps them back to the presenter.
///
/// The same window WaveCrux uses: long enough to read something off to the
/// side, short enough that a follower who glanced away and forgot does not sit
/// for the rest of the meeting on a view nobody is talking about.
const Duration kCollabFollowIdleResume = Duration(seconds: 12);

/// The idle window [CollabFollowDetachedNotifier] waits before resuming, or
/// `null` to resume only on the explicit "Resume following" action. Tests
/// shorten it.
final collabFollowIdleResumeProvider = Provider<Duration?>(
  (_) => kCollabFollowIdleResume,
  name: 'collabFollowIdleResumeProvider',
);

/// Whether the local follower has navigated away from the presenter's view.
///
/// Soft-follow: a follower who pans, zooms or changes scope is **detached**,
/// not dropped. The session goes on, the presenter is unchanged, and the
/// presenter's view stops being applied here until the follower resumes —
/// with the "Resume following" action, or by leaving the view alone for
/// [collabFollowIdleResumeProvider].
///
/// Local UI state: never broadcast, meaningless for the presenter, root-scoped
/// so every tab and the status bar read one value, and cleared when a session
/// ends or the local participant becomes the presenter.
final collabFollowDetachedProvider =
    NotifierProvider<CollabFollowDetachedNotifier, bool>(
      CollabFollowDetachedNotifier.new,
      name: 'collabFollowDetachedProvider',
    );

/// Notifier behind [collabFollowDetachedProvider].
class CollabFollowDetachedNotifier extends Notifier<bool> {
  Timer? _idle;

  @override
  bool build() {
    ref.onDispose(_cancelIdle);
    return false;
  }

  /// A local navigation gesture happened while following.
  ///
  /// Every call restarts the idle window, so continuous navigation keeps the
  /// follower detached and the snap-back fires only once they stop.
  void detach() {
    _cancelIdle();
    final idle = ref.read(collabFollowIdleResumeProvider);
    if (idle != null) _idle = Timer(idle, resume);
    if (!state) state = true;
  }

  /// Follows the presenter again.
  void resume() {
    _cancelIdle();
    if (state) state = false;
  }

  void _cancelIdle() {
    _idle?.cancel();
    _idle = null;
  }
}
