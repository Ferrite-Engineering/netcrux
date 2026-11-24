// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_single_instance/crux_single_instance.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:netcrux/core/platform/netcrux_linux_desktop_app.dart';
import 'package:netcrux/services/links/incoming_link_service.dart';
import 'package:netcrux/services/links/netcrux_link.dart';
import 'package:netcrux/services/links/single_instance_handoff.dart';

/// A launch carrying a `netcrux://` link hands it to the running instance and
/// ends; the running instance receives it on the same stream macOS delivers
/// links on. Run over a real claim in a private directory, on the transport
/// this host has.

const _link = 'netcrux://open?file=/w/top.json&cell=top.u';

/// Links forwarded by later launches only, as on Windows and Linux.
const _byProcess = IncomingLinkService(
  isMacOS: _no,
  handsOverByProcess: _yes,
);

bool _no() => false;
bool _yes() => true;

/// A claim in a private directory of its own. The id is short because a Unix
/// socket path must fit `sun_path`.
SingleInstance _instance(String directory) => SingleInstance(
  appId: 'nc.test',
  policy: netCruxSingleInstancePolicy(),
  directory: directory,
  transport: Platform.isWindows
      ? SingleInstanceTransport.loopbackTcp
      : SingleInstanceTransport.unixSocket,
);

void main() {
  late Directory tmp;
  late String dir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ncsi');
    dir = '${tmp.path}${Platform.pathSeparator}d';
  });

  tearDown(() {
    IncomingLinkService.detachForwardedLinks();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A socket still closing; the directory is in the system temp.
    }
  });

  test('the policy is the scheme and the length the parser enforces', () {
    final policy = netCruxSingleInstancePolicy();
    expect(policy.schemes, {kNetCruxLinkScheme});
    expect(policy.maxLinkBytes, kNetCruxLinkMaxLength);
    expect(policy.accepts(_link), isTrue);
    expect(policy.accepts('wavecrux://open?file=/a.vcd'), isFalse);
    expect(policy.accepts('https://example.com/'), isFalse);
  });

  test('the rendezvous is named by the desktop identity', () {
    expect(netcruxLinuxDesktopApp.appId, 'com.ferriteengineering.netcrux');
  });

  test('a delivered claim ends the launch before a window, with the link '
      'handed over', () async {
    final running = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(running.close);
    final received = <String>[];
    final sub = running.links.listen(received.add);
    addTearDown(sub.cancel);

    int? exitedWith;
    await bootstrap(
      args: const [_link, '--reset'],
      singleInstance: _instance(dir),
      exitProcess: (code) => exitedWith = code,
    );

    expect(exitedWith, 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received, [_link], reason: 'the link alone; --reset was dropped');
  });

  test('a launch with no link is not delivered anywhere', () async {
    final running = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(running.close);

    final claim = await claimSingleInstance(
      desktopApp: netcruxLinuxDesktopApp,
      launchLinks: const [],
      singleInstance: _instance(dir),
    );

    expect(claim, isA<SingleInstanceStandalone>());
  });

  test('two links on one command line are not forwarded', () async {
    final running = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(running.close);

    final claim = await claimSingleInstance(
      desktopApp: netcruxLinuxDesktopApp,
      launchLinks: const [_link, _link],
      singleInstance: _instance(dir),
    );

    expect(claim, isA<SingleInstanceStandalone>());
  });

  test('macOS and the browser make no claim', () async {
    // On a Windows or Linux host the real claim would take this machine's
    // lock, so only a host that delivers links itself runs the check.
    if (handsLinksToRunningInstance) return;
    expect(
      await claimSingleInstance(
        desktopApp: netcruxLinuxDesktopApp,
        launchLinks: const [_link],
      ),
      isNull,
    );
  });

  test('a link forwarded to the running instance arrives on its link '
      'stream', () async {
    final primary = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(primary.close);
    IncomingLinkService.attachForwardedLinks(primary.links);
    final arrived = _byProcess.links.first;

    final second = await claimSingleInstance(
      desktopApp: netcruxLinuxDesktopApp,
      launchLinks: const [_link],
      singleInstance: _instance(dir),
    );

    expect(second, isA<SingleInstanceDelivered>());
    expect(await arrived.timeout(const Duration(seconds: 5)), _link);
  });

  test('a link forwarded before anyone listens is held, not lost', () async {
    final primary = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(primary.close);
    IncomingLinkService.attachForwardedLinks(primary.links);

    final delivered = await claimSingleInstance(
      desktopApp: netcruxLinuxDesktopApp,
      launchLinks: const [_link],
      singleInstance: _instance(dir),
    );

    expect(delivered, isA<SingleInstanceDelivered>());
    expect(
      await _byProcess.links.first.timeout(const Duration(seconds: 5)),
      _link,
    );
  });

  test('the link stream can be listened to again after the first listener '
      'goes, as a second mount of the app does', () async {
    final primary = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(primary.close);
    IncomingLinkService.attachForwardedLinks(primary.links);

    final first = _byProcess.links.listen((_) {});
    await first.cancel();

    final arrived = _byProcess.links.first;
    final delivered = await claimSingleInstance(
      desktopApp: netcruxLinuxDesktopApp,
      launchLinks: const [_link],
      singleInstance: _instance(dir),
    );

    expect(delivered, isA<SingleInstanceDelivered>());
    expect(await arrived.timeout(const Duration(seconds: 5)), _link);
  });

  test('a host with no scheme gets no links', () async {
    IncomingLinkService.attachForwardedLinks(Stream.value(_link));
    const none = IncomingLinkService(isMacOS: _no, handsOverByProcess: _no);
    expect(await none.links.toList(), isEmpty);
  });

  test('an exit request releases the running instance and lets the exit go '
      'ahead', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final primary = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(primary.close);
    final listener = releaseSingleInstanceOnExit(primary);
    addTearDown(listener.dispose);
    final advert = File('$dir${Platform.pathSeparator}nc.test.json');
    expect(advert.existsSync(), isTrue);

    // What the engine sends Dart when it is asked to quit.
    final reply = Completer<Object?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.platform.name,
          SystemChannels.platform.codec.encodeMethodCall(
            const MethodCall('System.requestAppExit'),
          ),
          (data) => reply.complete(
            data == null
                ? null
                : SystemChannels.platform.codec.decodeEnvelope(data),
          ),
        );

    expect(await reply.future, {'response': 'exit'});
    expect(advert.existsSync(), isFalse, reason: 'the advert left with it');
    // The lock is free again: the next launch becomes the running instance.
    final next = await _instance(dir).claim();
    expect(next, isA<SingleInstancePrimary>());
    await (next as SingleInstancePrimary).close();
  });

  group('macOS', () {
    const macOS = IncomingLinkService(isMacOS: _yes, handsOverByProcess: _no);

    test('reads the runner channel, never the forwarded stream', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(IncomingLinkService.channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          IncomingLinkService.channel,
          null,
        ),
      );
      IncomingLinkService.attachForwardedLinks(Stream.value(_link));

      final seen = <String>[];
      final sub = macOS.links.listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, ['listen']);
      expect(seen, isEmpty);

      // The runner delivering a link, as `IncomingLinkPlugin` does.
      await messenger.handlePlatformMessage(
        IncomingLinkService.channel.name,
        IncomingLinkService.channel.codec.encodeMethodCall(
          const MethodCall('openLink', _link),
        ),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        IncomingLinkService.channel.name,
        IncomingLinkService.channel.codec.encodeMethodCall(
          const MethodCall('openLink', ''),
        ),
        (_) {},
      );
      expect(seen, [_link], reason: 'an empty string is dropped');

      await sub.cancel();
      expect(calls, ['listen', 'cancel']);
    });

    test('with no runner behind the channel, nothing arrives and nothing '
        'throws', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final seen = <String>[];
      final sub = macOS.links.listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(seen, isEmpty);
    });
  });
}
