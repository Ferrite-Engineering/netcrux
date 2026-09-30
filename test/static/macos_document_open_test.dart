// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/file_open/incoming_document_service.dart';

/// `Info.plist` registers NetCrux as the handler for its document types, so
/// Finder launches it on a double-click. The file then arrives as an Apple
/// Event, and a runner that registers the types without handling that event
/// opens empty — no error, because nothing failed; the event was never
/// delivered. That is how NetCrux shipped until the handler was written.
///
/// The handler is Swift, which `flutter test` cannot run, so these check the
/// runner still carries both halves of the handoff, on the channel and
/// methods the Dart side uses.
void main() {
  String read(String path) => File(path).readAsStringSync();
  final plist = read('macos/Runner/Info.plist');
  final appDelegate = read('macos/Runner/AppDelegate.swift');
  final window = read('macos/Runner/MainFlutterWindow.swift');

  test('the runner registers document types for Finder to route here', () {
    expect(plist, contains('<key>CFBundleDocumentTypes</key>'));
  });

  // Where a document type names `LSItemContentTypes`, macOS ignores its
  // extensions and claims every file of those types. `public.source-code`
  // on the HDL entry offered NetCrux for every C, Python and Swift file, and
  // `public.plain-text` on the filelist entry for every text file. A type
  // NetCrux owns, or the suite's own manifest type, names only its files.
  test('no document type claims a system-wide content type', () {
    final claimed =
        RegExp(
              r'<key>LSItemContentTypes</key>\s*<array>(.*?)</array>',
              dotAll: true,
            )
            .allMatches(plist)
            .expand(
              (m) => RegExp(
                '<string>([^<]+)</string>',
              ).allMatches(m.group(1)!).map((s) => s.group(1)!),
            );
    expect(claimed, isNotEmpty);
    expect(claimed.where((type) => type.startsWith('public.')), isEmpty);
  });

  test('the app delegate hands every opened file to the plugin', () {
    expect(
      appDelegate,
      contains(
        'override func application(_ application: NSApplication, '
        'open urls: [URL])',
      ),
    );
    expect(
      appDelegate,
      contains('IncomingDocumentPlugin.shared.handle(urls: urls)'),
    );
  });

  test('the plugin answers on the channel and methods Dart uses', () {
    expect(appDelegate, contains('"${IncomingDocumentService.channel.name}"'));
    for (final method in <String>[
      'getInitialDocument',
      'listen',
      'cancel',
      'openDocument',
    ]) {
      expect(appDelegate, contains('"$method"'), reason: method);
    }
  });

  test('the main window registers the plugin once the engine exists', () {
    expect(window, contains('IncomingDocumentPlugin.shared.register('));
  });
}
