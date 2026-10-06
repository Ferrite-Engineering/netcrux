// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A cell drawn with a custom symbol is laid out in the symbol's shape: its
// node takes the drawing's aspect, and each pin an anchor names sits on the
// anchor's face at the anchor's position. Cells without a symbol, and
// designs without any, keep exactly the ELK input they had before.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/flutter_js_host_vm.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

import '../../helpers/elk_ffi_library_gate.dart';

/// The demo SoC's top, reduced to the UART instance: `u_uart` of type
/// `uart_tx`, with the eight pins of the real module, wired to module ports
/// so every pin has an edge.
const _socJson = <String, Object?>{
  'creator': 'Yosys test',
  'modules': <String, Object?>{
    'soc_top': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'clk': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'rst_n': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[3],
        },
        'sel': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[4],
        },
        'we': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[5],
        },
        'addr': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[6, 7],
        },
        'wdata': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[8, 9],
        },
        'rdata': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[10, 11],
        },
        'tx': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[12],
        },
      },
      'cells': <String, Object?>{
        'u_uart': <String, Object?>{
          'hide_name': 0,
          'type': 'uart_tx',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'clk': 'input',
            'rst_n': 'input',
            'sel': 'input',
            'we': 'input',
            'reg_addr': 'input',
            'wdata': 'input',
            'rdata': 'output',
            'tx': 'output',
          },
          'connections': <String, Object?>{
            'clk': <Object>[2],
            'rst_n': <Object>[3],
            'sel': <Object>[4],
            'we': <Object>[5],
            'reg_addr': <Object>[6, 7],
            'wdata': <Object>[8, 9],
            'rdata': <Object>[10, 11],
            'tx': <Object>[12],
          },
        },
        'u_and': <String, Object?>{
          'hide_name': 0,
          'type': r'$and',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'A': 'input',
            'B': 'input',
            'Y': 'output',
          },
          'connections': <String, Object?>{
            'A': <Object>[4],
            'B': <Object>[5],
            'Y': <Object>[13],
          },
        },
      },
      'netnames': <String, Object?>{},
    },
  },
};

Module _soc() => NetlistModel.fromJson(_socJson).modules['soc_top']!;

/// The `uart_tx.svg` the issue reports: a 160 by 120 viewBox.
const _uartSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 120" '
    'width="160" height="120"><rect x="4" y="4" width="152" height="112"/> '
    '</svg>';

/// The symbol as the issue describes it: six pins anchored on the left and
/// `rdata` and `tx` on the right, at distinct heights. The declared size is
/// the editor's 120 by 80 default, which is not the drawing's aspect.
CustomCellSymbol _uartSymbol({Map<String, PortAnchor>? anchors}) =>
    CustomCellSymbol(
      id: 'uart',
      moduleType: 'uart_tx',
      kind: CustomCellSymbolKind.svg,
      content: _uartSvg,
      width: 120,
      height: 80,
      portAnchors:
          anchors ??
          const <String, PortAnchor>{
            'clk': PortAnchor(x: 0, y: 0.15, side: PortAnchorSide.left),
            'rst_n': PortAnchor(x: 0, y: 0.3, side: PortAnchorSide.left),
            'sel': PortAnchor(x: 0, y: 0.45, side: PortAnchorSide.left),
            'we': PortAnchor(x: 0, y: 0.6, side: PortAnchorSide.left),
            'reg_addr': PortAnchor(x: 0, y: 0.75, side: PortAnchorSide.left),
            'wdata': PortAnchor(x: 0, y: 0.9, side: PortAnchorSide.left),
            'rdata': PortAnchor(x: 1, y: 0.3, side: PortAnchorSide.right),
            'tx': PortAnchor(x: 1, y: 0.7, side: PortAnchorSide.right),
          },
      createdAt: '',
      updatedAt: '',
    );

CellSymbolGeometries _symbols([CustomCellSymbol? symbol]) =>
    CellSymbolGeometries.fromSnapshot(<String, CustomCellSymbol>{
      'uart_tx': symbol ?? _uartSymbol(),
    });

Map<String, Object?> _node(Map<String, Object?> input, String id) =>
    (input['children']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere(
          (n) => n['id'] == id,
        );

/// Checks that every pin of `u_uart` in [layout] sits on the face and at the
/// height its anchor in [symbol] names, within [tolerance].
void _expectPinsAtAnchors(
  NetlistLayout layout,
  CustomCellSymbol symbol, {
  double tolerance = 0.01,
}) {
  final node = layout.findNode('u_uart')!;
  final width = node.bounds.width;
  final height = node.bounds.height;
  for (final entry in symbol.portAnchors.entries) {
    final box = node.ports['u_uart:${entry.key}']!;
    final cy = box.y + box.height / 2;
    switch (entry.value.side) {
      case PortAnchorSide.left:
        expect(box.x + box.width, closeTo(0, tolerance), reason: entry.key);
      case PortAnchorSide.right:
        expect(box.x, closeTo(width, tolerance), reason: entry.key);
      case PortAnchorSide.top:
      case PortAnchorSide.bottom:
        fail('no top or bottom anchors in this symbol');
    }
    expect(cy, closeTo(entry.value.y * height, tolerance), reason: entry.key);
  }
}

void main() {
  group('svgIntrinsicSize', () {
    test('reads the viewBox, which wins over width and height', () {
      expect(svgIntrinsicSize(_uartSvg), const SymbolArtworkSize(160, 120));
      expect(
        svgIntrinsicSize(
          '<svg width="10" height="10" viewBox="0,0,300 100"></svg>',
        ),
        const SymbolArtworkSize(300, 100),
      );
    });

    test('falls back to numeric width and height', () {
      expect(
        svgIntrinsicSize("<svg width='40px' height='20'/>"),
        const SymbolArtworkSize(40, 20),
      );
    });

    test('is null without a usable size', () {
      expect(svgIntrinsicSize('<svg width="100%" height="50%"/>'), isNull);
      expect(svgIntrinsicSize('<g/>'), isNull);
      expect(svgIntrinsicSize('<svg viewBox="0 0 0 10"/>'), isNull);
    });
  });

  group('CellSymbolGeometry', () {
    test("takes the drawing's aspect, not the declared size", () {
      final geometry = CellSymbolGeometry.fromSymbol(_uartSymbol());
      expect(geometry.aspect, closeTo(160 / 120, 1e-9));
    });

    test('falls back to the declared size when the SVG has none', () {
      final geometry = CellSymbolGeometry.fromSymbol(
        _uartSymbol().copyWith(content: '<svg><rect/></svg>'),
      );
      expect(geometry.aspect, closeTo(120 / 80, 1e-9));
    });

    test('clamps a degenerate aspect', () {
      final geometry = CellSymbolGeometry.fromSymbol(
        _uartSymbol().copyWith(content: '<svg viewBox="0 0 1000 1"/>'),
      );
      expect(geometry.aspect, CellSymbolGeometry.maxAspect);
    });

    test('geometries are value-equal', () {
      expect(_symbols(), _symbols());
      expect(_symbols(), isNot(CellSymbolGeometries.none));
      expect(
        CellSymbolGeometries.fromSnapshot(const <String, CustomCellSymbol>{}),
        CellSymbolGeometries.none,
      );
    });
  });

  group('spreadAlongFace', () {
    test('leaves well-spaced points where they asked to be', () {
      expect(spreadAlongFace(<double>[20, 50, 80], 100, 10), <double>[
        20,
        50,
        80,
      ]);
    });

    test('spreads coincident points around their place in input order', () {
      final placed = spreadAlongFace(<double>[50, 50, 50], 100, 10);
      expect(placed, <double>[40, 50, 60]);
    });

    test('keeps points clear of the ends', () {
      final placed = spreadAlongFace(<double>[0, 0, 100], 100, 10);
      expect(placed, <double>[5, 15, 95]);
    });

    test('spaces evenly when the points cannot fit at the pitch', () {
      final placed = spreadAlongFace(<double>[1, 2, 3], 20, 10);
      expect(placed, <double>[5, 10, 15]);
    });
  });

  group('buildElkInput with symbols', () {
    test('a design without symbols has exactly the input it had before', () {
      final module = _soc();
      final before = jsonEncode(buildElkInput(module));
      expect(
        // Passing the default explicitly is the point: an empty set of
        // symbols must be the same input as none at all.
        // ignore: avoid_redundant_argument_values
        jsonEncode(buildElkInput(module, symbols: CellSymbolGeometries.none)),
        before,
      );
      // A symbol for a type the scope does not use changes nothing either.
      final elsewhere = CellSymbolGeometries.fromSnapshot(
        <String, CustomCellSymbol>{
          'spi_master': _uartSymbol().copyWith(moduleType: 'spi_master'),
        },
      );
      expect(jsonEncode(buildElkInput(module, symbols: elsewhere)), before);
      // And the built-in node is the one it always was.
      final uart = _node(buildElkInput(module), 'u_uart');
      expect(uart['width'], 80);
      expect(uart['height'], 32 + 8 * 10);
      expect(
        (uart['layoutOptions']! as Map<String, Object?>)['elk.portConstraints'],
        'FIXED_SIDE',
      );
    });

    test("a symbol cell's node takes the drawing's aspect", () {
      final input = buildElkInput(_soc(), symbols: _symbols());
      final uart = _node(input, 'u_uart');
      final width = uart['width']! as double;
      final height = uart['height']! as double;
      // Six pins on the busier (west) face need 32 + 6 × 10.
      expect(height, 92);
      expect(width / height, closeTo(160 / 120, 0.001));
      expect(
        (uart['layoutOptions']! as Map<String, Object?>)['elk.portConstraints'],
        'FIXED_POS',
      );
      // The other cell keeps its built-in node.
      final and = _node(input, 'u_and');
      expect(and['width'], 80);
      expect(and['height'], 32 + 3 * 10);
    });

    test('the anchors set the faces and positions of the ports', () {
      final input = buildElkInput(_soc(), symbols: _symbols());
      final uart = _node(input, 'u_uart');
      final height = uart['height']! as double;
      final ports = <String, Map<String, Object?>>{
        for (final p
            in (uart['ports']! as List<Object?>).cast<Map<String, Object?>>())
          p['id']! as String: p,
      };
      final rdata = ports['u_uart:rdata']!;
      expect(
        (rdata['layoutOptions']! as Map<String, Object?>)['elk.port.side'],
        'EAST',
      );
      expect(rdata['x'], uart['width']);
      expect((rdata['y']! as double) + 2, closeTo(0.3 * height, 0.01));
      final clk = ports['u_uart:clk']!;
      expect(clk['x'], -4.0);
      expect((clk['y']! as double) + 2, closeTo(0.15 * height, 0.01));
    });

    test('an output anchored on the left goes west, and a pin with no '
        'anchor keeps its direction face', () {
      final anchors = Map<String, PortAnchor>.of(_uartSymbol().portAnchors)
        ..['tx'] = const PortAnchor(x: 0, y: 0.5, side: PortAnchorSide.left)
        ..remove('rdata');
      final symbol = _uartSymbol(anchors: anchors);
      final faces = symbolPortFaces(
        _soc().cells['u_uart']!,
        CellSymbolGeometry.fromSymbol(symbol),
      );
      expect(faces['tx'], 'WEST');
      expect(faces['rdata'], 'EAST');
    });

    test('anchors that all ask for the same place are spread apart', () {
      // The symbol as first saved in the rehearsal: every anchor at the
      // editor's default height of 0.5.
      final anchors = <String, PortAnchor>{
        for (final name in <String>[
          'clk',
          'rst_n',
          'sel',
          'we',
          'reg_addr',
          'wdata',
          'tx',
        ])
          name: const PortAnchor(x: 0, y: 0.5, side: PortAnchorSide.left),
        'rdata': const PortAnchor(x: 0, y: 0.5, side: PortAnchorSide.right),
      };
      final input = buildElkInput(
        _soc(),
        symbols: _symbols(_uartSymbol(anchors: anchors)),
      );
      final uart = _node(input, 'u_uart');
      final ys = <double>[
        for (final p
            in (uart['ports']! as List<Object?>).cast<Map<String, Object?>>())
          if ((p['layoutOptions']! as Map<String, Object?>)['elk.port.side'] ==
              'WEST')
            p['y']! as double,
      ];
      expect(ys, hasLength(7));
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i] - ys[i - 1], closeTo(symbolPinPitch, 1e-9));
      }
      // Centred on the anchor they share.
      final mid = (ys.first + ys.last) / 2 + 2;
      expect(mid, closeTo((uart['height']! as double) / 2, 0.01));
    });

    test('symbolCellAnchoredPorts lists exactly the pins an anchor names', () {
      final anchors = Map<String, PortAnchor>.of(_uartSymbol().portAnchors)
        ..remove('we')
        ..['no_such_pin'] = const PortAnchor(
          x: 0,
          y: 0.5,
          side: PortAnchorSide.left,
        );
      final result = symbolCellAnchoredPorts(
        _soc(),
        _symbols(_uartSymbol(anchors: anchors)),
      );
      expect(result.keys, <String>['u_uart']);
      expect(result['u_uart'], <String>{
        'clk',
        'rst_n',
        'sel',
        'reg_addr',
        'wdata',
        'rdata',
        'tx',
      });
      expect(
        symbolCellAnchoredPorts(_soc(), CellSymbolGeometries.none),
        isEmpty,
      );
    });
  });

  group('ElkLayoutService with symbols', () {
    test('a symbol changes the cache key; the same symbol hits it', () async {
      var solves = 0;
      final service = ElkLayoutService(
        solverFactory: () => _CountingSolver(() => solves++),
        assetLoader: (_) async => '',
      );
      addTearDown(service.dispose);
      final module = _soc();
      await service.layout(module);
      await service.layout(module, symbols: _symbols());
      expect(solves, 2);
      await service.layout(module, symbols: _symbols());
      await service.layout(module);
      expect(solves, 2);
    });

    test('the native engine puts every anchored pin on its face at its '
        'anchor, and the node keeps the aspect', () async {
      if (!requireElkFfiLibrary()) return;
      final service = ElkLayoutService(
        solverFactory: NativeElkSolver.open,
        assetLoader: (_) async => throw StateError('elkjs must not load'),
      );
      addTearDown(service.dispose);
      final symbol = _uartSymbol();
      final layout = await service.layout(_soc(), symbols: _symbols(symbol));
      final node = layout.findNode('u_uart')!;
      expect(
        node.bounds.width / node.bounds.height,
        closeTo(160 / 120, 0.001),
      );
      _expectPinsAtAnchors(layout, symbol);
      // Every pin has a wire ending on it: the routing honours the pins.
      for (final entry in node.ports.entries) {
        final box = entry.value;
        final cx = node.bounds.x + box.x + box.width / 2;
        final cy = node.bounds.y + box.y + box.height / 2;
        final ends = <LayoutPoint>[
          for (final edge in layout.edges)
            if (edge.points.isNotEmpty) ...<LayoutPoint>[
              edge.points.first,
              edge.points.last,
            ],
        ];
        expect(
          ends.any((p) => (p.x - cx).abs() <= 3 && (p.y - cy).abs() <= 3),
          isTrue,
          reason: '${entry.key} has no wire ending on it',
        );
      }
    });

    // elkjs runs under `flutter test` on JavaScriptCore only; elsewhere the
    // test is not registered rather than skipped (the CI skip guard).
    if (Platform.isMacOS) {
      test('elkjs places the pins where the native engine does', () {
        if (!requireElkFfiLibrary()) return;
        final input = jsonEncode(buildElkInput(_soc(), symbols: _symbols()));
        final ElkJsHost host;
        try {
          host = createDefaultElkJsHost();
          initElkRuntime(
            host,
            File('assets/elk/elk.bundled.js').readAsStringSync(),
          );
        } on Object catch (e) {
          markTestSkipped('no JavaScript engine here: $e');
          return;
        }
        addTearDown(host.dispose);
        final js = NetlistLayout.fromJson(
          jsonDecode(runElkLayoutOnHost(host, input)) as Map<String, Object?>,
        );
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final native = NetlistLayout.fromJson(
          jsonDecode(solver.solve(input)) as Map<String, Object?>,
        );
        _expectPinsAtAnchors(js, _uartSymbol());
        final a = js.findNode('u_uart')!;
        final b = native.findNode('u_uart')!;
        expect(a.bounds.width, b.bounds.width);
        expect(a.bounds.height, b.bounds.height);
        for (final id in a.ports.keys) {
          expect(a.ports[id]!.x, closeTo(b.ports[id]!.x, 1e-6), reason: id);
          expect(a.ports[id]!.y, closeTo(b.ports[id]!.y, 1e-6), reason: id);
        }
      });
    }
  });
}

/// A solver that answers every input with an empty layout and counts calls.
class _CountingSolver implements ElkSolver {
  _CountingSolver(this._onSolve);

  final void Function() _onSolve;

  @override
  String get engineDescription => 'counting';

  @override
  String solve(String inputJson) {
    _onSolve();
    return '{"id":"root","x":0,"y":0,"width":10,"height":10,'
        '"children":[],"edges":[]}';
  }

  @override
  void dispose() {}
}
