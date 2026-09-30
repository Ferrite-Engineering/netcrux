// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/wait_for.dart';

/// Malformed inbound CXP traffic (bad JSON, non-object root, missing
/// fields, unknown verb, oversized payload) must be rejected with a protocol
/// error reply and must never crash the server: a valid client can still
/// connect and handshake afterward.
void main() {
  late Directory tmp;
  late NetcruxCxpServer server;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('netcrux_cxp_fuzz_');
    server = NetcruxCxpServer(
      productVersion: '0.0.0-test',
      manifestDirectory: p.join(tmp.path, 'peers'),
    );
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  /// Opens a raw socket, sends [line] + newline, and returns the server's
  /// first reply line (newline-framed JSON). Fails if no complete reply
  /// line arrives within the poll timeout — every fuzz case expects a
  /// protocol error back, so "no reply" is itself a failure.
  Future<String> sendRaw(String line) async {
    final socket = await Socket.connect('127.0.0.1', server.boundPort!);
    final replies = <int>[];
    final sub = socket.listen(replies.addAll);
    socket.add(utf8.encode('$line\n'));
    await socket.flush();
    // The reply is newline-framed: poll until a full line has arrived.
    await waitFor(
      () => replies.contains(0x0A),
      reason: 'no newline-framed reply to: $line',
    );
    await sub.cancel();
    socket.destroy();
    return utf8.decode(replies, allowMalformed: true).split('\n').first;
  }

  String envelope(String kind, Object? payload) => jsonEncode(<String, Object?>{
    'cxp_version': '1.0',
    'message_id': 'fuzz-1',
    'from': 'fuzzer',
    'kind': kind,
    'payload': payload,
  });

  test('every malformed message gets an error reply, not a crash', () async {
    final cases = <String, String>{
      'garbage bytes': 'this is not json at all',
      'non-object root': '[1, 2, 3]',
      'bare number': '42',
      'missing envelope fields': '{}',
      'unknown verb': envelope('totally_bogus_verb', <String, Object?>{}),
      'oversized payload': envelope('totally_bogus_verb', <String, Object?>{
        'blob': 'x' * 200000,
      }),
    };
    for (final entry in cases.entries) {
      final reply = await sendRaw(entry.value);
      expect(
        reply,
        isNotEmpty,
        reason: '${entry.key}: server must reply with a protocol error',
      );
      // The reply is itself a well-formed envelope (the server stays in
      // protocol), and it signals an error.
      final decoded = jsonDecode(reply) as Map<String, Object?>;
      expect(
        decoded['kind'].toString().toLowerCase(),
        contains('error'),
        reason: '${entry.key}: reply should be an error envelope',
      );
    }
  });

  test(
    'an unknown verb is named in the error reply (verb-allow-list anchor)',
    () async {
      // Mutation anchor: dropping the unknown-kind check in crux_cxp lets an
      // unknown verb fall through without an "Unknown message kind" reply.
      final reply = await sendRaw(
        envelope('definitely_not_a_verb', <String, Object?>{}),
      );
      expect(reply.toLowerCase(), contains('unknown'));
    },
  );

  test(
    'a malformed payload of a KNOWN kind yields malformed_payload, not a '
    'crash (decodeCxpMessage must not let a FormatException escape the '
    'read loop for a recognised verb with a bad body)',
    () async {
      // "hello" is a known kind; "identity" must be a JSON object. A
      // number is decodable JSON but fails Hello.fromJson; the server's
      // dispatch point wraps decodeCxpMessage in a try/catch so that
      // failure becomes an error reply rather than a dead read loop.
      final reply = await sendRaw(
        envelope('hello', <String, Object?>{'identity': 5}),
      );
      final decoded = jsonDecode(reply) as Map<String, Object?>;
      expect(decoded['kind'].toString().toLowerCase(), contains('error'));
      final payload = decoded['payload']! as Map<String, Object?>;
      expect(payload['code'], 'malformed_payload');
    },
  );

  test('the server is still alive after the fuzz barrage', () async {
    await sendRaw('garbage');
    await sendRaw(envelope('bogus', null));
    // A real Hello still earns a HelloAck — the server never died.
    final reply = await sendRaw(
      envelope('hello', <String, Object?>{
        'identity': <String, Object?>{
          'peer_id': 'live-client',
          'product_name': 'wavecrux',
          'product_version': '0.0.0-test',
        },
      }),
    );
    expect(server.isRunning, isTrue);
    expect(reply.toLowerCase(), contains('hello'));
  });
}
