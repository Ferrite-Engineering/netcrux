// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the license texts that MUST travel inside the shipped binary.
///
/// NetCrux vendors elkjs (`assets/elk/elk.bundled.js`) under EPL-2.0, and
/// EPL-2.0 §3.1(b) requires a copy of the Agreement to accompany the Program
/// when it is distributed in object-code form. Vendoring the engine is a
/// deliberate act; shipping the Agreement alongside it is not optional.
///
/// This exists because the obligation was already missed once. The EPL text
/// and its `pubspec.yaml` asset entry landed in `9340319` (2026-07-23) — one
/// day AFTER the 0.1.0 binary was built — so the published 0.1.0 shipped
/// `elk.bundled.js` with an attribution notice but no copy of the Agreement.
/// Nothing failed, because nothing checked. The gap was only found by
/// unpacking the released `.app` by hand.
///
/// So the assertions below are deliberately about the things that would have
/// caught it: the text is present, it is the FULL agreement rather than a stub
/// or a link, and it is declared as an asset so the bundler actually ships it.
/// A declaration without the file, or a file without the declaration, both
/// produce a binary that is out of compliance while the tree looks fine.
void main() {
  final root = _repoRoot();

  group('bundled third-party license texts', () {
    final licenseFile = File('${root.path}/assets/elk/LICENSE.epl-2.0.txt');

    test('the elkjs EPL-2.0 text is present in the tree', () {
      expect(
        licenseFile.existsSync(),
        isTrue,
        reason:
            'assets/elk/LICENSE.epl-2.0.txt must exist — elkjs ships in every '
            'NetCrux build and EPL-2.0 §3.1(b) requires the Agreement to '
            'accompany it',
      );
    });

    test('it is the full Agreement, not a stub or a link', () {
      final text = licenseFile.readAsStringSync();

      // Structural markers spread across the whole document. A truncated file,
      // a "see https://…" placeholder, or the short header banner copied out
      // of the bundle would satisfy none of these.
      const required = <String, String>{
        'Eclipse Public License - v 2.0': 'the title',
        '1. DEFINITIONS': 'the definitions section',
        '3. REQUIREMENTS':
            'the EPL §3 requirements — the clause this file exists for',
        '5. NO WARRANTY': 'the warranty section',
        '6. DISCLAIMER OF LIABILITY': 'the liability disclaimer',
        '7. GENERAL': 'the general section',
        'Secondary Licenses': 'the EPL-2.0-specific secondary-licenses notice',
      };
      for (final entry in required.entries) {
        expect(
          text,
          contains(entry.key),
          reason:
              'the EPL-2.0 text is missing ${entry.value} — this looks like a '
              'partial copy, and a partial licence does not discharge §3.1(b)',
        );
      }
      expect(
        text.length,
        greaterThan(10000),
        reason:
            'the EPL-2.0 Agreement is ~14 KB; anything much smaller is not '
            'the whole document',
      );
    });

    test('it is declared as a Flutter asset so the bundler ships it', () {
      final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();

      // Match a real list entry, not a passing mention in a comment: the
      // rationale for this file is itself written in pubspec.yaml comments,
      // so a naive `contains` would pass even with the entry deleted.
      final declared = pubspec
          .split('\n')
          .map((line) => line.trim())
          .any((line) => line == '- assets/elk/LICENSE.epl-2.0.txt');
      expect(
        declared,
        isTrue,
        reason:
            'pubspec.yaml must list "- assets/elk/LICENSE.epl-2.0.txt" under '
            'flutter/assets. Without the declaration the file sits in the repo '
            'but never reaches the app bundle — which is exactly how the '
            'published 0.1.0 came to ship elkjs without the Agreement',
      );
    });

    test('the in-app license list points at the same asset', () {
      // `kNetcruxVendoredLicenses` is what puts elkjs into LicenseRegistry,
      // and therefore into the Acknowledgments page. It reads the shipped
      // file rather than an inline copy, so the page and the redistributed
      // text cannot disagree — but only if the path still matches. A
      // renamed asset with a stale entry would silently drop elkjs from the
      // list while every other assertion here still passed.
      final source = File(
        '${root.path}/lib/core/about/netcrux_vendored_licenses.dart',
      ).readAsStringSync();
      expect(
        source,
        contains("'assets/elk/LICENSE.epl-2.0.txt'"),
        reason:
            'kNetcruxVendoredLicenses must reference the same asset this '
            'guard checks, or the Acknowledgments page silently omits elkjs',
      );
    });

    test('the registration actually runs at startup', () {
      // A list nothing registers is a list nobody sees.
      final source = File('${root.path}/lib/app.dart').readAsStringSync();
      expect(
        source,
        contains('registerCruxVendoredLicenses(kNetcruxVendoredLicenses)'),
        reason:
            'bootstrap must register the vendored licenses; without the call '
            'the Acknowledgments page shows only pub packages',
      );
    });

    test('the engine it licenses is itself still bundled', () {
      // If elk.bundled.js were ever dropped, the obligation would go away and
      // this whole group would be dead weight. Pin the pairing so the two move
      // together in either direction.
      expect(
        File('${root.path}/assets/elk/elk.bundled.js').existsSync(),
        isTrue,
        reason:
            'elk.bundled.js is the reason the EPL text must ship; if it is '
            'genuinely gone, retire this guard deliberately rather than '
            'letting it rot',
      );
    });
  });
}

/// Walks up from the test file to the package root (the directory holding
/// `pubspec.yaml`), so this passes regardless of the working directory the
/// runner is invoked from — including from the Pro overlay, where this package
/// is consumed as a path dependency.
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/assets/elk').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate the netcrux package root from ${Directory.current}');
}
