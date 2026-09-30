// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/layout_engine_selection.dart';

void main() {
  bool none(String _) => false;
  bool all(String _) => true;

  group('selectLayoutEngine', () {
    test('macOS uses the system JavaScriptCore without probing', () {
      var probed = 0;
      final choice = selectLayoutEngine(
        platform: LayoutHostPlatform.macOS,
        environment: const <String, String>{},
        probe: (_) {
          probed++;
          return true;
        },
      );
      expect(choice.engine, LayoutJsEngine.javaScriptCore);
      expect(choice.library, isNull);
      expect(choice.forced, isFalse);
      expect(probed, 0);
    });

    test('Windows uses QuickJS', () {
      final choice = selectLayoutEngine(
        platform: LayoutHostPlatform.windows,
        environment: const <String, String>{},
        probe: all,
      );
      expect(choice.engine, LayoutJsEngine.quickJs);
      expect(choice.note, isNull);
    });

    test('Linux takes the first library that probes, newest ABI first', () {
      final probed = <String>[];
      final choice = selectLayoutEngine(
        platform: LayoutHostPlatform.linux,
        environment: const <String, String>{},
        probe: (name) {
          probed.add(name);
          return name == 'libjavascriptcoregtk-4.1.so.0';
        },
      );
      expect(choice.engine, LayoutJsEngine.javaScriptCore);
      expect(choice.library, 'libjavascriptcoregtk-4.1.so.0');
      expect(probed, <String>[
        'libjavascriptcoregtk-6.0.so.1',
        'libjavascriptcoregtk-4.1.so.0',
      ]);
    });

    test('Linux falls back to QuickJS when no library probes', () {
      final choice = selectLayoutEngine(
        platform: LayoutHostPlatform.linux,
        environment: const <String, String>{},
        probe: none,
      );
      expect(choice.engine, LayoutJsEngine.quickJs);
      expect(choice.library, isNull);
      expect(choice.note, isNull);
    });

    test('$kLayoutEngineEnvVar=quickjs forces the interpreter everywhere', () {
      for (final platform in LayoutHostPlatform.values) {
        final choice = selectLayoutEngine(
          platform: platform,
          environment: const <String, String>{kLayoutEngineEnvVar: ' QuickJS '},
          probe: all,
        );
        expect(choice.engine, LayoutJsEngine.quickJs, reason: '$platform');
        expect(choice.forced, isTrue, reason: '$platform');
      }
    });

    test('$kLayoutEngineEnvVar=jsc on Linux still needs a library', () {
      final honoured = selectLayoutEngine(
        platform: LayoutHostPlatform.linux,
        environment: const <String, String>{kLayoutEngineEnvVar: 'jsc'},
        probe: all,
      );
      expect(honoured.engine, LayoutJsEngine.javaScriptCore);
      expect(honoured.forced, isTrue);

      final refused = selectLayoutEngine(
        platform: LayoutHostPlatform.linux,
        environment: const <String, String>{kLayoutEngineEnvVar: 'jsc'},
        probe: none,
      );
      expect(refused.engine, LayoutJsEngine.quickJs);
      expect(refused.forced, isFalse);
      expect(refused.note, contains(kLayoutEngineEnvVar));
    });

    test('$kLayoutEngineEnvVar=jsc on Windows explains the refusal', () {
      final choice = selectLayoutEngine(
        platform: LayoutHostPlatform.windows,
        environment: const <String, String>{
          kLayoutEngineEnvVar: 'javascriptcore',
        },
        probe: all,
      );
      expect(choice.engine, LayoutJsEngine.quickJs);
      expect(choice.note, contains('does not provide'));
    });

    test('an unknown value is ignored', () {
      final choice = selectLayoutEngine(
        platform: LayoutHostPlatform.linux,
        environment: const <String, String>{kLayoutEngineEnvVar: 'v8'},
        probe: none,
      );
      expect(choice.engine, LayoutJsEngine.quickJs);
      expect(choice.forced, isFalse);
      expect(choice.note, isNull);
    });
  });

  group('LayoutEngineChoice.describe', () {
    test('names the engine, the library, the override and the note', () {
      expect(
        const LayoutEngineChoice(LayoutJsEngine.javaScriptCore).describe(),
        'JavaScriptCore',
      );
      expect(
        const LayoutEngineChoice(
          LayoutJsEngine.javaScriptCore,
          library: 'libjavascriptcoregtk-6.0.so.1',
          forced: true,
        ).describe(),
        'JavaScriptCore (libjavascriptcoregtk-6.0.so.1), forced by '
        '$kLayoutEngineEnvVar',
      );
      expect(
        const LayoutEngineChoice(
          LayoutJsEngine.quickJs,
          note: 'no library',
        ).describe(),
        'QuickJS; no library',
      );
    });
  });
}
