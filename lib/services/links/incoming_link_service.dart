// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:netcrux/services/links/netcrux_link.dart';

final _log = Logger('netcrux.links');

/// Receives `netcrux://` links the operating system delivers to the running
/// app.
///
/// **macOS** delivers a link as an Apple event, to the one running instance
/// or to the instance it launches for the link. The native half is
/// `IncomingLinkPlugin` in `macos/Runner/AppDelegate.swift`, which holds a
/// link that arrives before Dart listens (the cold-launch case) and hands it
/// over when [links] is first listened to. One method channel carries both
/// directions, as for documents (`IncomingDocumentService`): Dart sends
/// `listen` and `cancel`, the runner calls `openLink` with each link.
///
/// **Windows and Linux** start a new process per link, with the link as its
/// argument. `bootstrap` takes the link a launch carries off its command line
/// ([NetCruxLaunchArgs]) and, when another instance is already running, hands
/// it to that instance and exits (`crux_single_instance`). The running
/// instance's side of that hand-off is [attachForwardedLinks]: the links
/// later launches forward arrive on [links], held until first listened to.
///
/// The browser registers no scheme: [links] never emits there.
class IncomingLinkService {
  /// Creates the service. [isMacOS] and [handsOverByProcess] decide which
  /// route a platform delivers links on; tests inject them.
  const IncomingLinkService({
    this.isMacOS = _platformIsMacOS,
    this.handsOverByProcess = _platformHandsOverByProcess,
  });

  /// Whether links arrive on [channel] (macOS).
  final bool Function() isMacOS;

  /// Whether links arrive from later launches (Windows and Linux).
  final bool Function() handsOverByProcess;

  static bool _platformIsMacOS() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool _platformHandsOverByProcess() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// The channel the runner's `IncomingLinkPlugin` answers on.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'com.netcrux/incoming_link',
  );

  static Stream<String>? _forwarded;

  /// Takes the links other launches forward to this running instance
  /// (Windows and Linux). Called once, from `bootstrap`, with the stream the
  /// single-instance claim provides; a second call replaces the first.
  ///
  /// The claim's stream is single-subscription, but [links] may be listened
  /// to more than once in one process (the workspace screen is built again
  /// when the app is mounted again), so it is shared. The source is not
  /// listened to until the first listen, so a link that arrives before then
  /// is held, not lost.
  static void attachForwardedLinks(Stream<String> links) {
    _forwarded = links.isBroadcast ? links : links.asBroadcastStream();
  }

  /// Drops what [attachForwardedLinks] took. For tests.
  @visibleForTesting
  static void detachForwardedLinks() {
    _forwarded = null;
  }

  /// Links delivered while the app runs, and any that arrived before the
  /// first listen. Each event is the link exactly as the system delivered it;
  /// nothing here parses or trusts it. An empty string is dropped. A link
  /// over [kNetCruxLinkMaxLength] still arrives on macOS, so the parser can
  /// refuse it and the user is told; the runner drops anything over eight
  /// times that.
  Stream<String> get links {
    if (isMacOS()) return _channelLinks();
    final forwarded = _forwarded;
    if (handsOverByProcess() && forwarded != null) {
      return forwarded.where((link) => link.isNotEmpty);
    }
    return const Stream<String>.empty();
  }

  Stream<String> _channelLinks() {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () async {
        // The handler goes in before `listen` is sent, so nothing the runner
        // delivers in reply can arrive with no one to take it.
        channel.setMethodCallHandler((call) async {
          final link = call.arguments;
          if (call.method == 'openLink' && link is String) {
            if (link.isNotEmpty) controller.add(link);
            return null;
          }
          throw MissingPluginException('${call.method} is not handled');
        });
        await _send('listen');
      },
      onCancel: () async {
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
      _log.warning('Link delivery: $method failed: ${e.message}');
    }
  }
}
