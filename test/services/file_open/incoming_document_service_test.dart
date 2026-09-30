// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/file_open/incoming_document_service.dart';

/// The Dart half of the macOS document delivery. The runner's side of the
/// channel is played here by a mock handler; the real one is Swift, in
/// `macos/Runner/AppDelegate.swift`, and is proven by building the runner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = IncomingDocumentService.channel;
  const service = IncomingDocumentService(isSupported: _yes);

  late List<String> calls;

  /// Plays the runner: answers `getInitialDocument` with [initial] and
  /// records every call Dart makes.
  void runner({String? initial}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'getInitialDocument' ? initial : null;
    });
  }

  /// Delivers [path] from the runner as an `openDocument` call.
  Future<void> deliver(Object? path) => messenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(MethodCall('openDocument', path)),
    (_) {},
  );

  setUp(() => calls = <String>[]);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  group('initialDocument', () {
    test('is the document the runner was holding', () async {
      runner(initial: '/d/demo.netcrux-project');
      expect(await service.initialDocument(), '/d/demo.netcrux-project');
      expect(calls, <String>['getInitialDocument']);
    });

    test('is null when the runner holds nothing', () async {
      for (final initial in <String?>[null, '']) {
        runner(initial: initial);
        expect(await service.initialDocument(), isNull);
      }
    });

    test('is null, not a failure to start, with no runner behind it', () async {
      expect(await service.initialDocument(), isNull);
    });

    test('is null when the runner fails', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      expect(await service.initialDocument(), isNull);
    });

    test('asks nothing where documents do not arrive this way', () async {
      runner(initial: '/d/demo.netcrux-project');
      const elsewhere = IncomingDocumentService(isSupported: _no);
      expect(await elsewhere.initialDocument(), isNull);
      expect(calls, isEmpty);
    });
  });

  group('documents', () {
    test('listening asks the runner for what it holds, then each '
        'document arrives in order', () async {
      runner();
      final received = <String>[];
      final sub = service.documents.listen(received.add);
      await pumpEventQueue();
      expect(calls, <String>['listen']);

      await deliver('/d/one.netcrux-project');
      await deliver('/d/two.sv');
      await pumpEventQueue();
      expect(received, <String>['/d/one.netcrux-project', '/d/two.sv']);

      await sub.cancel();
      expect(calls, <String>['listen', 'cancel']);
    });

    test('an empty or malformed delivery is dropped', () async {
      runner();
      final received = <String>[];
      final sub = service.documents.listen(received.add);
      await pumpEventQueue();
      await deliver('');
      await deliver(42);
      await deliver('/d/top.v');
      await pumpEventQueue();
      expect(received, <String>['/d/top.v']);
      await sub.cancel();
    });

    test('with no runner behind it, listening is quiet — no error on the '
        'stream and none reported', () async {
      final errors = <Object>[];
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final sub = service.documents.listen((_) {}, onError: errors.add);
      await pumpEventQueue();
      await sub.cancel();
      expect(errors, isEmpty);
      expect(reported, isEmpty);
    });

    test('is empty where documents do not arrive this way', () async {
      runner();
      const elsewhere = IncomingDocumentService(isSupported: _no);
      expect(await elsewhere.documents.isEmpty, isTrue);
      expect(calls, isEmpty);
    });
  });
}

bool _yes() => true;

bool _no() => false;
