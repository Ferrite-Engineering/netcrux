// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';
import 'package:netcrux/services/links/netcrux_link.dart';

Map<String, Object?> _open({Map<String, Object?> extra = const {}}) =>
    <String, Object?>{
      'type': kHostBridgeFrameType,
      'protocol': 1,
      'kind': kHostBridgeOpenNetlistKind,
      'name': 'top.json',
      'text': '{"modules":{}}',
      ...extra,
    };

void main() {
  group('names shared with the extension shim', () {
    // The page shim in crux-vscode publishes these globals and frame types by
    // string. A rename on either side is silent: the app reports "no host" or
    // drops every frame.
    test('are the strings the shim uses', () {
      expect(kEditorHostMarkerGlobal, 'cruxEditorHost');
      expect(kEditorHostSeamGlobal, 'cruxHostBridge');
      expect(kEditorHostLayoutWorkerGlobal, 'cruxLayoutWorkerUrl');
      expect(kEditorHostMarkerKindVscode, 'vscode');
      expect(kHostBridgeFrameType, 'crux.netcrux');
      expect(kHostBridgeOpenNetlistKind, 'open_netlist');
      expect(kHostBridgeThemeTokensKind, 'theme_tokens');
      expect(kHostBridgeReadyKind, 'ready');
      expect(kHostBridgeOpenSourceKind, 'open_source');
      expect(kHostBridgeStatusKind, 'status');
      expect(kHostBridgeSelectKind, 'select');
      expect(kHostBridgeSelectResultKind, 'select_result');
      expect(
        HostBridgeSelectOutcome.values.map((o) => o.wire),
        <String>['selected', 'not_found', 'no_design'],
      );
    });
  });

  group('select', () {
    Map<String, Object?> select(Map<String, Object?> fields) =>
        <String, Object?>{
          'type': kHostBridgeFrameType,
          'protocol': 1,
          'kind': kHostBridgeSelectKind,
          'element': 'cell',
          'name': 'top.u_cpu.pc_reg',
          ...fields,
        };

    test('reads a cell or a net, with the id a webview sends as a double', () {
      expect(
        parseHostBridgeFrame(select(const {'id': 7.0})),
        const HostBridgeSelect(
          element: NetCruxLinkElementKind.cell,
          name: 'top.u_cpu.pc_reg',
          id: 7,
        ),
      );
      expect(
        parseHostBridgeFrame(select(const {'element': 'net', 'name': 'y'})),
        const HostBridgeSelect(element: NetCruxLinkElementKind.net, name: 'y'),
      );
    });

    test('refuses an unknown element, a bad name or a bad id', () {
      for (final fields in <Map<String, Object?>>[
        {'element': 'signal'},
        {'element': null},
        {'name': ''},
        {'name': 3},
        {'name': 'a' * (kHostBridgeMaxSelectNameChars + 1)},
        {'id': 1.5},
        {'id': -1},
        {'id': 'one'},
        {'id': double.nan},
        {'id': double.infinity},
        {'id': kHostBridgeMaxSelectId + 1},
      ]) {
        expect(parseHostBridgeFrame(select(fields)), isNull, reason: '$fields');
      }
    });

    test('select_result carries the id, the outcome and a cone view', () {
      expect(
        hostBridgeSelectResultFrame(
          HostBridgeSelectOutcome.selected,
          id: 4,
          coneView: true,
        ),
        <String, Object?>{
          'type': 'crux.netcrux',
          'protocol': 1,
          'kind': 'select_result',
          'id': 4,
          'outcome': 'selected',
          'coneView': true,
        },
      );
      expect(
        hostBridgeSelectResultFrame(HostBridgeSelectOutcome.notFound),
        <String, Object?>{
          'type': 'crux.netcrux',
          'protocol': 1,
          'kind': 'select_result',
          'outcome': 'not_found',
        },
      );
    });
  });

  group('parseHostBridgeFrame', () {
    test('reads an open_netlist frame with its hints', () {
      final parsed = parseHostBridgeFrame(
        _open(extra: {'scope': 'top.cpu', 'signal': 'alu_y'}),
      );
      expect(
        parsed,
        const HostBridgeOpenNetlist(
          name: 'top.json',
          text: '{"modules":{}}',
          scope: 'top.cpu',
          signal: 'alu_y',
        ),
      );
    });

    test('drops empty hints', () {
      final parsed = parseHostBridgeFrame(
        _open(extra: {'scope': '', 'signal': 3}),
      );
      final open = parsed! as HostBridgeOpenNetlist;
      expect(open.scope, isNull);
      expect(open.signal, isNull);
    });

    test('refuses a frame of another type, version or kind', () {
      expect(parseHostBridgeFrame(_open(extra: {'type': 'other'})), isNull);
      expect(parseHostBridgeFrame(_open(extra: {'protocol': 0})), isNull);
      expect(parseHostBridgeFrame(_open(extra: {'protocol': 'x'})), isNull);
      expect(parseHostBridgeFrame(_open(extra: {'kind': 'nope'})), isNull);
    });

    test('refuses a netlist with a missing or oversized field', () {
      expect(parseHostBridgeFrame(_open(extra: {'name': ''})), isNull);
      expect(parseHostBridgeFrame(_open(extra: {'name': 7})), isNull);
      expect(parseHostBridgeFrame(_open(extra: {'text': ''})), isNull);
      expect(parseHostBridgeFrame(_open(extra: {'text': null})), isNull);
      expect(
        parseHostBridgeFrame(
          _open(extra: {'name': 'a' * (kHostBridgeMaxNameChars + 1)}),
        ),
        isNull,
      );
    });

    test('reads theme tokens and keeps only string pairs', () {
      final parsed = parseHostBridgeFrame(<String, Object?>{
        'type': kHostBridgeFrameType,
        'protocol': 1,
        'kind': kHostBridgeThemeTokensKind,
        'appearance': 'light',
        'tokens': <Object?, Object?>{
          'editor.background': '#ffffff',
          'bad': 3,
          4: '#000000',
        },
      });
      expect(parsed, isA<HostBridgeThemeTokens>());
      final theme = parsed! as HostBridgeThemeTokens;
      expect(theme.appearance, 'light');
      expect(theme.tokens, <String, String>{'editor.background': '#ffffff'});
    });

    test('refuses theme tokens with an unknown appearance', () {
      expect(
        parseHostBridgeFrame(<String, Object?>{
          'type': kHostBridgeFrameType,
          'protocol': 1,
          'kind': kHostBridgeThemeTokensKind,
          'appearance': 'sepia',
          'tokens': <String, Object?>{},
        }),
        isNull,
      );
    });
  });

  group('hostBridgeStringMap', () {
    test('accepts an object with string keys', () {
      expect(hostBridgeStringMap(<Object?, Object?>{'a': 1}), {'a': 1});
    });

    test('refuses anything else', () {
      expect(hostBridgeStringMap('x'), isNull);
      expect(hostBridgeStringMap(null), isNull);
      expect(hostBridgeStringMap(<Object?, Object?>{1: 2}), isNull);
    });
  });

  group('outbound frames', () {
    test('open_source carries the file, line and optional column', () {
      expect(
        hostBridgeOpenSourceFrame(file: 'rtl/top.v', line: 12, column: 3),
        <String, Object?>{
          'type': 'crux.netcrux',
          'protocol': 1,
          'kind': 'open_source',
          'file': 'rtl/top.v',
          'line': 12,
          'column': 3,
        },
      );
      expect(
        hostBridgeOpenSourceFrame(file: 'a.v', line: 1).containsKey('column'),
        isFalse,
      );
    });

    test('status names its phase and leaves unset fields out', () {
      expect(
        hostBridgeStatusFrame(HostBridgeStatusPhase.loaded, modules: 2),
        <String, Object?>{
          'type': 'crux.netcrux',
          'protocol': 1,
          'kind': 'status',
          'phase': 'loaded',
          'modules': 2,
        },
      );
    });

    test('ready is a bare frame', () {
      expect(hostBridgeReadyFrame(), <String, Object?>{
        'type': 'crux.netcrux',
        'protocol': 1,
        'kind': 'ready',
      });
    });
  });
}
