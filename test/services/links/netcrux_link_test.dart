// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:crux_mcp/crux_mcp.dart'
    show
        McpElementKind,
        McpElementLocation,
        McpLocationException,
        kMcpMaxLinkFileLength,
        kMcpMaxLinkLength,
        kMcpMaxLinkNameLength,
        kNetCruxLinkPrefix,
        netCruxLink;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/links/netcrux_link.dart';

/// The link parser is the first thing a link from anywhere (a chat, a CI log,
/// a coding agent's answer) reaches. These hold it to its grammar, which is
/// WaveCrux's: one action, known keys, each once, bounded, percent-decoded
/// with `+` left alone, an absolute file, and no character that could disguise
/// a file name. The round-trip group parses every link the suite's builder
/// (`crux_mcp`'s `netCruxLink`) writes, so the writer and the reader cannot
/// drift apart. The fuzz group asserts only what must hold for every input:
/// the parser never throws, and whatever it accepts satisfies the invariants
/// a caller relies on.

NetCruxLink _ok(String raw) => switch (parseNetCruxLink(raw)) {
  NetCruxLinkParsed(:final link) => link,
  NetCruxLinkRejected(:final refusal) => fail(
    'expected $raw to parse, got $refusal',
  ),
};

NetCruxLinkRefusal _refused(String raw) => switch (parseNetCruxLink(raw)) {
  NetCruxLinkRejected(:final refusal) => refusal,
  NetCruxLinkParsed(:final link) => fail(
    'expected $raw to be refused, got file=${link.file}',
  ),
};

/// Relative paths a link may not name, each written the way a sender would.
const List<String> _relativeFiles = <String>[
  'top.v',
  'rtl/top.v',
  './top.v',
  '../top.v',
  r'rtl\top.v',
  'C:top.v',
  '~/top.v',
];

/// The relative-path oracle: the links of [_relativeFiles] that [parse]
/// accepted. A correct parser accepts none.
List<String> _acceptedRelative(
  NetCruxLinkParseResult Function(String raw) parse,
) => <String>[
  for (final file in _relativeFiles)
    if (parse('netcrux://open?file=${Uri.encodeComponent(file)}&cell=top.u')
        is NetCruxLinkParsed)
      file,
];

void main() {
  group('the bounds are the builder bounds', () {
    test('one convention with crux_mcp and WaveCrux', () {
      expect(kNetCruxLinkMaxLength, kMcpMaxLinkLength);
      expect(kNetCruxLinkMaxFileLength, kMcpMaxLinkFileLength);
      expect(kNetCruxLinkMaxNameLength, kMcpMaxLinkNameLength);
      expect(kNetCruxLinkPrefix, '$kNetCruxLinkScheme://open?');
    });
  });

  group('accepted links', () {
    test('file only', () {
      final link = _ok('netcrux://open?file=/home/me/rtl/top.v');
      expect(link.file, '/home/me/rtl/top.v');
      expect(link.kind, isNull);
      expect(link.name, isNull);
    });

    test('a cell, a net, in any order', () {
      final cell = _ok('netcrux://open?cell=top.u_cpu.pc_reg&file=/w/a.json');
      expect(cell.file, '/w/a.json');
      expect(cell.kind, NetCruxLinkElementKind.cell);
      expect(cell.name, 'top.u_cpu.pc_reg');
      final net = _ok('netcrux://open?file=/w/a.sv&net=top.u_cpu.pc_q');
      expect(net.kind, NetCruxLinkElementKind.net);
      expect(net.name, 'top.u_cpu.pc_q');
    });

    test('percent-escapes decode; + stays a plus', () {
      final link = _ok(
        'netcrux://open?file=/work/c++/my%20rtl/d%C3%A9j%C3%A0.v'
        '&cell=top.%5Cesc%2Bname',
      );
      expect(link.file, '/work/c++/my rtl/déjà.v');
      expect(link.name, r'top.\esc+name');
      expect(_ok('netcrux://open?file=/a.v&net=a+b').name, 'a+b');
    });

    test('scheme and action ignore case; one trailing slash is allowed', () {
      expect(_ok('NetCrux://OPEN?file=/a.v').file, '/a.v');
      expect(_ok('netcrux://open/?file=/a.v').file, '/a.v');
    });

    test('a Windows path survives, encoded or not', () {
      expect(_ok(r'netcrux://open?file=C:\work\a.v').file, r'C:\work\a.v');
      expect(_ok('netcrux://open?file=C%3A%5Cwork%5Ca.v').file, r'C:\work\a.v');
      expect(_ok('netcrux://open?file=C:/work/a.v').file, 'C:/work/a.v');
    });

    test('a name with a bit range and a Yosys name are kept whole', () {
      expect(
        _ok('netcrux://open?file=/a.v&net=top.data%5B7%3A0%5D').name,
        'top.data[7:0]',
      );
      expect(
        _ok('netcrux://open?file=/a.v&cell=top.%24and%24top.v%3A3%2412').name,
        r'top.$and$top.v:3$12',
      );
    });
  });

  group('refused links', () {
    test('another scheme is not a NetCrux link', () {
      expect(
        _refused('https://open?file=/a.v'),
        NetCruxLinkRefusal.notANetCruxLink,
      );
      expect(
        _refused('wavecrux://open?file=/a.vcd'),
        NetCruxLinkRefusal.notANetCruxLink,
      );
      expect(
        _refused('netcruxx://open?file=/a.v'),
        NetCruxLinkRefusal.notANetCruxLink,
      );
      expect(_refused(''), NetCruxLinkRefusal.notANetCruxLink);
    });

    test('anything but //open is malformed', () {
      for (final raw in [
        'netcrux:open?file=/a.v',
        'netcrux:/open?file=/a.v',
        'netcrux://close?file=/a.v',
        'netcrux://run?file=/a.v',
        'netcrux://user@open?file=/a.v',
        'netcrux://open:80?file=/a.v',
        'netcrux://open/x?file=/a.v',
        'netcrux://open//?file=/a.v',
        'netcrux://open?file=/a.v#frag',
        'netcrux://open?file=/a.v&',
        'netcrux://open?&file=/a.v',
        'netcrux://open?file',
        'netcrux://open?=x&file=/a.v',
      ]) {
        expect(_refused(raw), NetCruxLinkRefusal.malformed, reason: raw);
      }
    });

    test('no query, an empty query or no file is a missing value', () {
      expect(_refused('netcrux://open'), NetCruxLinkRefusal.missingValue);
      expect(_refused('netcrux://open?'), NetCruxLinkRefusal.missingValue);
      expect(
        _refused('netcrux://open?cell=top.u'),
        NetCruxLinkRefusal.missingValue,
      );
      expect(
        _refused('netcrux://open?file='),
        NetCruxLinkRefusal.missingValue,
      );
      expect(
        _refused('netcrux://open?file=/a.v&net='),
        NetCruxLinkRefusal.missingValue,
      );
    });

    test('unknown keys are refused, not ignored', () {
      for (final key in [
        'File',
        'signal',
        't',
        'path',
        'cmd',
        'yosys',
        'top',
        'scope',
      ]) {
        expect(
          _refused('netcrux://open?file=/a.v&$key=x'),
          NetCruxLinkRefusal.unknownKey,
          reason: key,
        );
      }
    });

    test('one file and one element per link', () {
      expect(
        _refused('netcrux://open?file=/a.v&file=/b.v'),
        NetCruxLinkRefusal.duplicateKey,
      );
      expect(
        _refused('netcrux://open?file=/a.v&cell=x&cell=y'),
        NetCruxLinkRefusal.duplicateKey,
      );
      expect(
        _refused('netcrux://open?file=/a.v&cell=x&net=y'),
        NetCruxLinkRefusal.cellAndNet,
      );
    });

    test('broken escapes and invalid UTF-8 are refused', () {
      for (final raw in [
        'netcrux://open?file=/a%ZZ.v',
        'netcrux://open?file=/a%.v',
        'netcrux://open?file=/a%C3.v',
        'netcrux://open?file=/a%EF%BF%BD.v',
      ]) {
        expect(_refused(raw), NetCruxLinkRefusal.badEncoding, reason: raw);
      }
    });

    test('controls, raw white space and bidi controls are refused', () {
      for (final raw in [
        'netcrux://open?file=/a.v ',
        'netcrux://open?file=/a b.v',
        'netcrux://open?file=/a.v\n',
        'netcrux://open?file=/a%00.v',
        'netcrux://open?file=/a%0A.v',
        'netcrux://open?file=/a%7F.v',
        'netcrux://open?file=/evil%E2%80%AEv.json',
        'netcrux://open?file=/x%E2%81%A6.v',
        'netcrux://open?file=/a.v&cell=top.%20u',
        'netcrux://open?file=/a%C2%A0b.v',
      ]) {
        expect(
          _refused(raw),
          NetCruxLinkRefusal.forbiddenCharacter,
          reason: raw,
        );
      }
    });

    test('lengths are bounded', () {
      final longLink = 'netcrux://open?file=/${'a' * kNetCruxLinkMaxLength}';
      expect(_refused(longLink), NetCruxLinkRefusal.tooLong);
      final longFile =
          'netcrux://open?file=/${'a' * kNetCruxLinkMaxFileLength}.v';
      expect(_refused(longFile), NetCruxLinkRefusal.tooLong);
      final longName =
          'netcrux://open?file=/a.v&cell=${'s' * (kNetCruxLinkMaxNameLength + 1)}';
      expect(_refused(longName), NetCruxLinkRefusal.tooLong);
    });

    test('a relative file is refused by the parser', () {
      expect(_acceptedRelative(parseNetCruxLink), isEmpty);
      for (final file in _relativeFiles) {
        expect(
          _refused('netcrux://open?file=${Uri.encodeComponent(file)}'),
          NetCruxLinkRefusal.relativePath,
          reason: file,
        );
      }
    });

    test('mutation proof: a parser that accepts a relative path is caught', () {
      // The parser with its absolute-path rule replaced by one that accepts
      // everything: the oracle above must see it.
      NetCruxLinkParseResult broken(String raw) =>
          parseNetCruxLink(raw, isAbsolute: (_) => true);
      expect(_acceptedRelative(broken), isNotEmpty);
      expect(_acceptedRelative(broken), containsAll(_relativeFiles));
    });
  });

  group('absolute path text', () {
    test('every host spelling of an absolute path', () {
      for (final path in [
        '/a.v',
        r'\\server\share\a.v',
        r'C:\a.v',
        'c:/a.v',
        'Z:/a.v',
      ]) {
        expect(isAbsolutePathText(path), isTrue, reason: path);
      }
      for (final path in ['', 'a', 'C:', 'C:a.v', r'\a.v', '1:/a.v']) {
        expect(isAbsolutePathText(path), isFalse, reason: path);
      }
    });
  });

  group('round trip with the crux_mcp builder', () {
    void roundTrip(String file, McpElementKind kind, String name) {
      final link = netCruxLink(file, kind: kind, name: name);
      final parsed = _ok(link);
      expect(parsed.file, file, reason: link);
      expect(parsed.name, name, reason: link);
      expect(
        parsed.kind,
        kind == McpElementKind.cell
            ? NetCruxLinkElementKind.cell
            : NetCruxLinkElementKind.net,
        reason: link,
      );
    }

    test('the links crux_mcp documents', () {
      final cell = _ok('netcrux://open?file=%2Fw%2Ftop.json&cell=u%2Fa%241');
      expect(cell.file, '/w/top.json');
      expect(cell.kind, NetCruxLinkElementKind.cell);
      expect(cell.name, r'u/a$1');
      final net = _ok('netcrux://open?file=C%3A%5Cw%5Ct.json&net=n1');
      expect(net.file, r'C:\w\t.json');
      expect(net.kind, NetCruxLinkElementKind.net);
      expect(net.name, 'n1');
    });

    test('every awkward file and name the builder accepts', () {
      const files = <String>[
        '/w/top.json',
        '/home/me/my rtl/top.v',
        '/work/c++/top.sv',
        '/données/schéma.v',
        '/a/b%20c/d.vhd',
        r'C:\work\top.v',
        'C:/work/top.vhdl',
        r'\\server\share\top.v',
        '/tmp/a&b=c?d#e.json',
        '/漢字/トップ.sv',
      ];
      const names = <String>[
        'top',
        'top.u_cpu.pc_reg',
        r'top.$and$top.v:3$12',
        r'top.\esc+name',
        'top.data[7:0]',
        r'u/a$1',
        'a&b=c?d#e',
        'top.%41',
        'セル.ネット',
      ];
      for (final file in files) {
        for (final name in names) {
          roundTrip(file, McpElementKind.cell, name);
          roundTrip(file, McpElementKind.net, name);
        }
      }
    });

    test('a location the builder links parses back to its members', () {
      final location = McpElementLocation(
        file: '/w/design/top.json',
        kind: McpElementKind.net,
        name: 'top.u_cpu.pc_q',
        module: 'cpu',
        linked: true,
      );
      final parsed = _ok(location.link!);
      expect(parsed.file, location.file);
      expect(parsed.kind, NetCruxLinkElementKind.net);
      expect(parsed.name, location.name);
    });

    test('at the length bounds the builder and the parser agree', () {
      final longFile = '/${'f' * (kMcpMaxLinkFileLength - 3)}.v';
      final longName = 'n' * kMcpMaxLinkNameLength;
      roundTrip(longFile, McpElementKind.cell, longName);
    });

    test('random files and names: whatever the builder writes parses back', () {
      final random = Random(0x5EED67);
      const pool =
          'abcXYZ019_-.~ /\\:+%&=?#\$[]()@!*,;\'"éü漢\u00A0\u200B\u202E\t';
      String draw(int max) => List<String>.generate(
        1 + random.nextInt(max),
        (_) => pool[random.nextInt(pool.length)],
      ).join();
      var built = 0;
      for (var i = 0; i < 4000; i++) {
        final file = random.nextBool() ? '/${draw(40)}' : 'C:\\${draw(40)}';
        final name = draw(30);
        final kind = random.nextBool()
            ? McpElementKind.cell
            : McpElementKind.net;
        final String link;
        try {
          link = netCruxLink(file, kind: kind, name: name);
        } on McpLocationException {
          continue;
        }
        built++;
        roundTrip(file, kind, name);
        expect(link, startsWith(kNetCruxLinkPrefix));
      }
      // The pool holds characters the builder refuses, so most draws are
      // refused; the seed is fixed, so the count of built links is too.
      expect(built, greaterThan(150), reason: 'the draw must exercise links');
    });
  });

  group('launch arguments', () {
    test('an ordinary command line passes through untouched', () {
      final split = NetCruxLaunchArgs.split(const ['--reset', 'top.v']);
      expect(split.args, ['--reset', 'top.v']);
      expect(split.links, isEmpty);
    });

    test('a link drops every other argument, whatever its position', () {
      // The Windows quoting break-out: "%1" closed early by a quote in the
      // link, so the rest arrives as extra arguments.
      final split = NetCruxLaunchArgs.split(const [
        'netcrux://open?file=C:/a.v',
        '--yosys-path=C:/evil.exe',
        '--reset',
        r'C:\other.v',
      ]);
      expect(split.args, isEmpty);
      expect(split.links, ['netcrux://open?file=C:/a.v']);
      final before = NetCruxLaunchArgs.split(const [
        '--symbol-library',
        '/x.lib',
        'NETCRUX://open?file=/a.v',
      ]);
      expect(before.args, isEmpty);
      expect(before.links, ['NETCRUX://open?file=/a.v']);
    });

    test('two links are both kept so the launch can refuse them', () {
      final split = NetCruxLaunchArgs.split(const [
        'netcrux://open?file=/a.v',
        'netcrux://open?file=/b.v',
      ]);
      expect(split.args, isEmpty);
      expect(split.links, hasLength(2));
    });

    test('a WaveCrux link is not a NetCrux link', () {
      final split = NetCruxLaunchArgs.split(const [
        'wavecrux://open?file=/a.vcd',
      ]);
      expect(split.links, isEmpty);
      expect(split.args, ['wavecrux://open?file=/a.vcd']);
    });
  });

  group('fuzz', () {
    const seed = 0x5EED2;
    const valid =
        'netcrux://open?file=/home/me/rtl/top.v&cell=top.u_cpu.pc_reg';
    const letters =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const punctuation = r'%&=?#/:\.+-_ ~@!$*()[];,';
    const awkward =
        '\u0000\u0009\u000A\u007F\u00A0\u00E9\u202E\u2066\uFEFF\u{1F600}';
    const alphabet = '$letters$punctuation$awkward';

    void checkInvariants(String raw) {
      final NetCruxLinkParseResult result;
      try {
        result = parseNetCruxLink(raw);
      } on Object catch (e) {
        fail('parseNetCruxLink threw $e on ${Uri.encodeFull(raw)}');
      }
      if (result case NetCruxLinkParsed(:final link)) {
        expect(raw.length, lessThanOrEqualTo(kNetCruxLinkMaxLength));
        expect(looksLikeNetCruxLink(raw), isTrue);
        expect(link.file, isNotEmpty);
        expect(isAbsolutePathText(link.file), isTrue);
        expect(link.file.length, lessThanOrEqualTo(kNetCruxLinkMaxFileLength));
        expect(
          RegExp(
            r'[\u0000-\u001F\u007F\u202A-\u202E\u2066-\u2069]',
          ).hasMatch(link.file),
          isFalse,
        );
        final name = link.name;
        expect(link.kind == null, name == null);
        if (name != null) {
          expect(name, isNotEmpty);
          expect(name.contains(' '), isFalse);
          expect(name.length, lessThanOrEqualTo(kNetCruxLinkMaxNameLength));
        }
      }
    }

    test('mutations of a valid link never throw and keep the invariants', () {
      final random = Random(seed);
      for (var i = 0; i < 5000; i++) {
        final chars = valid.split('');
        final edits = 1 + random.nextInt(6);
        for (var e = 0; e < edits; e++) {
          final op = random.nextInt(3);
          final at = random.nextInt(chars.length + 1);
          final ch = alphabet[random.nextInt(alphabet.length)];
          if (op == 0 && at < chars.length) {
            chars[at] = ch;
          } else if (op == 1) {
            chars.insert(at, ch);
          } else if (at < chars.length) {
            chars.removeAt(at);
          }
        }
        checkInvariants(chars.join());
      }
    });

    test('random query strings never throw', () {
      final random = Random(seed + 1);
      for (var i = 0; i < 5000; i++) {
        final length = random.nextInt(80);
        final query = List.generate(
          length,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
        checkInvariants('netcrux://open?$query');
        checkInvariants('netcrux://open?file=$query');
      }
    });
  });
}
