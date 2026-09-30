// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_conflicts.dart';

void main() {
  group('resolveShortcutConflicts', () {
    test('a customized remap wins the chord over the default owner', () {
      // showFanin holds '[' by default; the user remaps showFanout onto '['.
      const bracketLeft = SingleActivator(LogicalKeyboardKey.bracketLeft);
      final r = resolveShortcutConflicts({
        NetcruxAction.showFanin: bracketLeft, // == its default → owner
        NetcruxAction.showFanout: bracketLeft, // != its default → interloper
      });
      // Runtime precedence: the interloper fires; the owner is shadowed.
      expect(
        r.effectiveBindings.containsKey(NetcruxAction.showFanout),
        isTrue,
      );
      expect(
        r.effectiveBindings.containsKey(NetcruxAction.showFanin),
        isFalse,
      );
      // Asymmetric UI view: both rows agree showFanout is the winner.
      expect(
        r.conflicts[NetcruxAction.showFanin]!.winner,
        NetcruxAction.showFanout,
      );
      expect(
        r.conflicts[NetcruxAction.showFanout]!.winner,
        NetcruxAction.showFanout,
      );
      expect(r.conflictChordCount, 1);
    });

    test('no collisions: no conflicts and a zero count', () {
      const a = SingleActivator(LogicalKeyboardKey.bracketLeft);
      const b = SingleActivator(LogicalKeyboardKey.bracketRight);
      final r = resolveShortcutConflicts({
        NetcruxAction.showFanin: a,
        NetcruxAction.showFanout: b,
      });
      expect(r.conflicts, isEmpty);
      expect(r.conflictChordCount, 0);
    });
  });
}
