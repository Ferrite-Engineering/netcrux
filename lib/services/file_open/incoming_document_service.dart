// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _log = Logger('netcrux.file_open');

/// Documents macOS opens on NetCrux's behalf: a Finder double-click, "Open
/// With", `open -a NetCrux <file>`, or a file dropped on the Dock icon.
///
/// `Info.plist` registers NetCrux as the handler for its project, session and
/// workspace files, HDL sources, filelists and suite design manifests, so
/// Finder offers it and a double-click launches it. The file itself arrives
/// as an Apple Event, and until the runner's `AppDelegate.swift` implemented
/// `application(_:open:)` nothing delivered that event to Dart: the app
/// opened empty. The runner forwards each path on [channel]; this is the
/// Dart half.
///
/// A path from here is routed exactly as the same path on the command line
/// would be — see `CliArgParser.parseOpenedDocument` — so it goes through the
/// same open flow and the same checks on the file's contents.
///
/// - **Cold start**: [initialDocument], asked once by `bootstrap` when the
///   command line names nothing. The runner holds a document that arrived
///   before Dart was running.
/// - **Warm start**: [documents], subscribed by the workspace screen once
///   its launch intent has been applied. Subscribing sends `listen`, and the
///   runner answers with everything it is still holding — a second file from
///   the same Finder selection — then each later document as it arrives, as
///   an `openDocument` call.
///
/// One method channel carries both directions, where the WaveCrux runner
/// uses an event channel for the second. An event channel with no native
/// half reports the failed subscription as a `FlutterError` rather than an
/// error on the stream, which every widget test that mounts the workspace on
/// a macOS host would then trip over. A missing handler here is a
/// [MissingPluginException] this class catches: nobody opened anything.
///
/// Elsewhere this is a no-op: Windows and Linux hand documents over as
/// command-line arguments, and the browser has no file associations.
class IncomingDocumentService {
  /// Creates the service. [isSupported] decides whether a platform delivers
  /// documents this way; tests inject it.
  const IncomingDocumentService({this.isSupported = _platformDelivers});

  /// Whether this platform delivers documents on [channel].
  final bool Function() isSupported;

  static bool _platformDelivers() => !kIsWeb && Platform.isMacOS;

  /// The channel the runner's `IncomingDocumentPlugin` answers on.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'com.netcrux/incoming_document',
  );

  /// The absolute path of the document that launched the app, or null.
  ///
  /// Never throws: this runs in `bootstrap`, where a throw is a failure to
  /// start.
  Future<String?> initialDocument() async {
    if (!isSupported()) return null;
    try {
      final path = await channel.invokeMethod<String>('getInitialDocument');
      return path == null || path.isEmpty ? null : path;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      _log.warning('Could not read the document macOS opened: ${e.message}');
      return null;
    }
  }

  /// The absolute path of each document opened while the app is running.
  ///
  /// Single-subscription: the workspace screen is its one listener, and the
  /// runner delivers each document once.
  Stream<String> get documents {
    if (!isSupported()) return const Stream<String>.empty();
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () async {
        // The handler goes in before `listen` is sent, so nothing the runner
        // delivers in reply can arrive with no one to take it.
        channel.setMethodCallHandler((call) async {
          final path = call.arguments;
          if (call.method == 'openDocument' && path is String) {
            if (path.isNotEmpty) controller.add(path);
            return null;
          }
          throw MissingPluginException('${call.method} is not handled');
        });
        await _send('listen');
      },
      onCancel: () async {
        // The runner stops delivering before the handler goes, for the
        // same reason.
        await _send('cancel');
        channel.setMethodCallHandler(null);
      },
    );
    return controller.stream;
  }

  Future<void> _send(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No runner behind the channel: nothing will be delivered.
    } on PlatformException catch (e) {
      _log.warning('Document delivery: $method failed: ${e.message}');
    }
  }
}
