// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard for the `netcrux://` URL scheme: the macOS bundle declares it,
// the native half forwards it on the channel the Dart half listens on, the
// AppImage identity claims it, a launch carrying a link hands it to the
// running instance, and the app actually reaches the handler. A scheme that is
// registered and then dropped is worse than none: the link looks like it
// should work, and the failure is indistinguishable from the app hanging.
//
// The Windows registration (the installer and the MSI) and the .deb and .rpm
// entries live with the release packaging and are guarded there.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/platform/netcrux_linux_desktop_app.dart';
import 'package:netcrux/services/links/netcrux_link.dart';

/// The `CFBundleURLSchemes` strings declared in [plist].
List<String> declaredSchemes(File plist) {
  final src = plist.readAsStringSync();
  final at = src.indexOf('<key>CFBundleURLTypes</key>');
  if (at == -1) return const [];
  final schemesAt = src.indexOf('<key>CFBundleURLSchemes</key>', at);
  if (schemesAt == -1) return const [];
  final end = src.indexOf('</array>', schemesAt);
  return RegExp(
    '<string>([^<]*)</string>',
  ).allMatches(src.substring(schemesAt, end)).map((m) => m.group(1)!).toList();
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the macOS bundle declares the netcrux scheme', () {
    expect(declaredSchemes(File('macos/Runner/Info.plist')), [
      kNetCruxLinkScheme,
    ]);
    expect(kNetCruxLinkScheme, 'netcrux');
  });

  test('the macOS app delegate forwards links on the channel Dart reads', () {
    final delegate = _read('macos/Runner/AppDelegate.swift');
    final window = _read('macos/Runner/MainFlutterWindow.swift');
    final dart = _read('lib/services/links/incoming_link_service.dart');
    expect(delegate, contains('IncomingLinkPlugin.shared.handle(urls: urls)'));
    expect(
      delegate,
      contains(r'!$0.isFileURL && !IncomingLinkPlugin.isLink($0)'),
      reason: 'a link must not also reach super as a deep link',
    );
    expect(delegate, contains('url.scheme?.lowercased() == "netcrux"'));
    expect(delegate, contains('invokeMethod("openLink"'));
    expect(window, contains('IncomingLinkPlugin.shared.register('));
    const channel = 'com.netcrux/incoming_link';
    expect(delegate, contains('"$channel"'));
    expect(dart, contains("'$channel'"));
    expect(dart, contains("call.method == 'openLink'"));
  });

  test('the AppImage identity declares the scheme it hands to the app', () {
    expect(netcruxLinuxDesktopApp.urlSchemes, [kNetCruxLinkScheme]);
    final identity = _read('lib/core/platform/netcrux_linux_desktop_app.dart');
    expect(identity, contains("urlSchemes: const ['netcrux']"));
  });

  test('Windows and Linux hand a link to the running instance', () {
    final app = _read('lib/app.dart');
    expect(app, contains('claimSingleInstance('));
    expect(app, contains('is SingleInstanceDelivered'));
    expect(app, contains('IncomingLinkService.attachForwardedLinks('));
    expect(app, contains('bringWindowForward()'));
    expect(app, contains('releaseSingleInstanceOnExit(claim)'));
    final handoff = _read('lib/services/links/single_instance_handoff.dart');
    expect(handoff, contains('schemes: const [kNetCruxLinkScheme]'));
    expect(handoff, contains('maxLinkBytes: kNetCruxLinkMaxLength'));
    expect(handoff, contains('desktopApp.appId'));
  });

  test('the app reaches the link handler from every delivery route', () {
    final app = _read('lib/app.dart');
    final screen = _read(
      'lib/features/workspace/screens/workspace_screen.dart',
    );
    // Windows and Linux: the command line, split before anything reads it.
    expect(app, contains('NetCruxLaunchArgs.split(args)'));
    expect(app, contains('initialNetCruxLinksProvider.overrideWithValue('));
    expect(screen, contains('ref.read(initialNetCruxLinksProvider)'));
    // macOS, and links forwarded by later launches: the link stream.
    expect(screen, contains('.read(incomingLinkServiceProvider)'));
    // Both reach one inbox, which reaches the handler and the confirmation.
    expect(screen, contains('NetCruxLinkInbox(_openLink)'));
    expect(screen, contains('await openNetCruxLink('));
    expect(screen, contains('OpenLinkConfirmDialog.show('));
    expect(screen, contains('_linkInbox.markReady()'));
    // Nothing downstream of the split may read the raw arguments: a link
    // launch drops them all.
    const marker = 'final argv = launch.args;';
    expect(app, contains(marker));
    final body = app.substring(app.indexOf(marker) + marker.length);
    final rest = body.substring(0, body.indexOf('\nclass NetcruxApp '));
    expect(
      RegExp(r'(?<![.\w])args\b').hasMatch(rest),
      isFalse,
      reason: 'bootstrap must read argv, not args, after the split',
    );
  });
}
