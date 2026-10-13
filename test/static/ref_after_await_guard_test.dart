// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: a widget's `ref` is never used after an `await` without a
// `mounted` check in between.
//
// A `ConsumerState`'s `ref`, and a `WidgetRef` handed to a function, die with
// their widget. Read after an `await`, when the widget may be gone, the read
// throws "Using ref when a widget is about to or has been unmounted" and the
// rest of the handler never runs: an audit record not written, a flag that
// blocks input for the session. The suite has fixed this class several times;
// `crux_guards`' `cruxAuditRefAfterAwait` is what stops it coming back. The
// fix is to read what the handler needs from `ref` before the `await`, or to
// check `mounted` (`ref.mounted`, `context.mounted`) after it and return.
//
// The scanner reads syntax in source order and resolves no types; its own
// documentation lists what it cannot see. An exemption names a file and a
// function where the use is safe, with the reason, and one that matches
// nothing is a finding, so the list cannot outlive the code.
//
// Scope: this repository's hand-written `lib/`.

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ref is never used after an await without a mounted check', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'lib/ must exist; run from the repository root',
    );
    final sources = <CruxGuardSource>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            !entity.uri.pathSegments.contains('generated'))
          CruxGuardSource(
            path: entity.path.replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];

    final result = cruxAuditRefAfterAwait(
      sources: sources,
    );

    expect(
      result.filesScanned,
      greaterThan(100),
      reason: 'the source walk collected implausibly few files',
    );
    expect(result.isClean, isTrue, reason: result.describe());
  });
}
