// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';

/// Every action must be reachable, or be listed here with the reason it is not.
///
/// ## The defect class this closes
///
/// The most expensive defect a suite-wide audit found was work that shipped
/// and then had no way in. An action's `surfaces` set is one line, it is silent
/// when empty, and nothing checked it:
///
///  * LintCrux Pro's entire multi-project feature set (project switcher,
///    reopen recent, cross-project search) was built, tier-badged,
///    telemetry-instrumented, and reachable by nobody: it shipped as done,
///    and a later "hide the stub actions" pass emptied the surface sets.
///    Neither side saw the other.
///  * SimCrux's `dispatchPrAnnotations` had a working dispatcher
///    and no menu entry, while the website described the menu entry's
///    behaviour in detail.
///  * NetCrux's X-Trace engine computed a correct result into a provider
///    nothing rendered, while it was recorded as shipped.
///
/// Each was found by a human reading code. This makes the machine read it.
///
/// ## Why an allowlist rather than a blanket ban
///
/// A surfaceless action is sometimes correct — a focus command bound only to a
/// chord, or an engine whose UI genuinely has not been built. What is never
/// correct is an *unexplained* one. The allowlist is a map so every entry
/// carries its reason: an allowance without one is indistinguishable from an
/// oversight six months later, which is precisely how the LintCrux case
/// survived.
///
/// When a surface lands, delete the entry. When one is emptied, this fails.
const _allowedSurfaceless = <NetcruxAction, String>{
  // Empty, and worth keeping empty. The X-Trace pair was
  // the only entry this list ever held: the Pro back-cone walker computed a
  // correct result into `xTraceResultProvider` and no widget rendered it, so
  // surfacing the two openers would have offered commands that ran a
  // computation with no visible output. `XTraceResultPanel` ships, both
  // openers declare `_menuPalette`, and the allowance is deleted rather than
  // weakened — the first test below now DEMANDS their surfaces.
  //
  // The bar for adding an entry is an action whose reachability is genuinely
  // meant to be zero, not one someone has not got round to surfacing.
};

void main() {
  test('every action is reachable, or explains why not', () {
    final offenders = <String>[];

    for (final action in NetcruxAction.values) {
      final hasSurface = descriptorFor(action).surfaces.isNotEmpty;
      if (hasSurface) {
        // A surfaced action that is ALSO on the allowlist means the allowance
        // outlived the problem. Fail, so the list cannot rot.
        if (_allowedSurfaceless.containsKey(action)) {
          offenders.add(
            '${action.name}: now has a surface but is still allowlisted — '
            'delete its entry from _allowedSurfaceless',
          );
        }
        continue;
      }
      if (_allowedSurfaceless.containsKey(action)) continue;
      offenders.add(
        '${action.name}: declares no ActionSurface, so it appears in no menu, '
        'no palette and no toolbar. If that is deliberate, add it to '
        '_allowedSurfaceless with the reason. If not, give it a surface — '
        'this is the shipped-but-unreachable defect class.',
      );
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the allowlisted actions are reachable by nothing, deliberately', () {
    // Unlike a chord-only focus command, an engine whose UI does not exist
    // should be reachable by NO route — offering a command that runs a
    // computation with no visible output is worse than offering nothing. If
    // one of these grows a binding, either the panel landed (delete the
    // allowance and give it a surface) or someone made it half-reachable.
    for (final action in _allowedSurfaceless.keys) {
      expect(
        defaultBindings().containsKey(action),
        isFalse,
        reason:
            '${action.name} is allowlisted as having no UI, but has a default '
            'keybinding — so a user can run it and see nothing happen.',
      );
    }
  });

  test('the guard is not vacuous', () {
    // If the enum or the descriptor table moved, every check above would pass
    // trivially.
    expect(NetcruxAction.values.length, greaterThan(10));
    expect(
      NetcruxAction.values.where(
        (a) => descriptorFor(a).surfaces.isNotEmpty,
      ),
      isNotEmpty,
      reason: 'no action has any surface — the descriptor table is not loading',
    );
  });
}
