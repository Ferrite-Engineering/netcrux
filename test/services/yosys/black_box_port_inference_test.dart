// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';

const PortDirection _in = PortDirection.input;
const PortDirection _out = PortDirection.output;

/// A cell as `write_json` writes an instance of a module nothing defines:
/// connections, no `port_directions`.
Map<String, Object?> _bb(String type, Map<String, List<Object>> connections) =>
    <String, Object?>{
      'hide_name': 0,
      'type': type,
      'parameters': <String, Object?>{},
      'attributes': <String, Object?>{},
      'connections': connections,
    };

/// A cell whose ports Yosys knows.
Map<String, Object?> _known(
  String type,
  Map<String, String> directions,
  Map<String, List<Object>> connections,
) => <String, Object?>{
  'hide_name': 0,
  'type': type,
  'parameters': <String, Object?>{},
  'attributes': <String, Object?>{},
  'port_directions': directions,
  'connections': connections,
};

Map<String, Object?> _port(String direction, List<Object> bits) =>
    <String, Object?>{'direction': direction, 'bits': bits};

NetlistModel _model(
  Map<String, Map<String, Object?>> ports,
  Map<String, Map<String, Object?>> cells, {
  Map<String, Object?> extraModules = const <String, Object?>{},
}) => NetlistModel.fromJson(<String, Object?>{
  'creator': 'test',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': const <String, Object?>{'top': '1'},
      'ports': ports,
      'cells': cells,
      'netnames': const <String, Object?>{},
    },
    ...extraModules,
  },
});

Map<String, PortDirection> _dirs(NetlistModel model, String cell) =>
    model.modules['top']!.cells[cell]!.portDirections;

void main() {
  group('inferBlackBoxPorts', () {
    test('named ports: driven is an input, sole driver is an output', () {
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'a': _port('input', <Object>[2]),
            'y': _port('output', <Object>[3]),
          },
          <String, Map<String, Object?>>{
            'u1': _bb('INV', <String, List<Object>>{
              'A': <Object>[2],
              'Y': <Object>[3],
            }),
          },
        ),
      );
      expect(_dirs(result.model, 'u1'), <String, PortDirection>{
        'A': _in,
        'Y': _out,
      });
      expect(result.report.types, <String>['INV']);
      expect(result.report.pinCount, 2);
      expect(result.report.guessedPinCount, 0);
    });

    test('a known cell is both evidence and untouched', () {
      final model = _model(
        <String, Map<String, Object?>>{
          'a': _port('input', <Object>[2]),
          'y': _port('output', <Object>[5]),
        },
        <String, Map<String, Object?>>{
          // u1 reads the black box's output and drives the module output.
          'u_not': _known(
            r'$not',
            <String, String>{'A': 'input', 'Y': 'output'},
            <String, List<Object>>{
              'A': <Object>[4],
              'Y': <Object>[5],
            },
          ),
          'bb': _bb('MYSTERY', <String, List<Object>>{
            'I': <Object>[2],
            'O': <Object>[4],
          }),
        },
      );
      final result = inferBlackBoxPorts(model);
      expect(_dirs(result.model, 'bb'), <String, PortDirection>{
        'I': _in,
        'O': _out,
      });
      expect(
        result.model.modules['top']!.cells['u_not'],
        model.modules['top']!.cells['u_not'],
      );
    });

    test('positional ports are numbered in instance order', () {
      // Yosys sorts connection names as strings: $1, $10, $11, $2, ...
      final connections = <String, List<Object>>{
        for (final n in <int>[1, 10, 11, 2, 3, 4, 5, 6, 7, 8, 9])
          '\$$n': <Object>[if (n == 11) 30 else 2],
      };
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'a': _port('input', <Object>[2]),
            'y': _port('output', <Object>[30]),
          },
          <String, Map<String, Object?>>{'u': _bb('WIDE', connections)},
        ),
      );
      final cell = result.model.modules['top']!.cells['u']!;
      expect(cell.connections.keys, <String>[
        for (var n = 1; n <= 11; n++) '\$$n',
      ]);
      expect(cell.portDirections.keys, cell.connections.keys);
      expect(cell.portDirections[r'$11'], _out);
      expect(cell.portDirections[r'$1'], _in);
    });

    test('multi-bit pins decide on every bit that has evidence', () {
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'd': _port('input', <Object>[2, 3]),
            'q': _port('output', <Object>[6, 7]),
            'clk': _port('input', <Object>[8]),
          },
          <String, Map<String, Object?>>{
            'm': _bb('MACRO', <String, List<Object>>{
              'CLK': <Object>[8],
              // One bit from a port, one from a constant.
              'D': <Object>[2, '0'],
              'Q': <Object>[6, 7],
              // One bit driven, one with nothing else on it: still an input.
              'S': <Object>[3, 9],
            }),
          },
        ),
      );
      expect(_dirs(result.model, 'm'), <String, PortDirection>{
        'CLK': _in,
        'D': _in,
        'Q': _out,
        'S': _in,
      });
      expect(result.report.guessedPinCount, 0);
    });

    test('a chain of black boxes resolves end to end', () {
      // a -> INV u1 -> n1 -> NAND2 u2 (B=b) -> n2 -> DFF u3 ($1 clk) -> y
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'a': _port('input', <Object>[2]),
            'b': _port('input', <Object>[3]),
            'clk': _port('input', <Object>[4]),
            'y': _port('output', <Object>[5]),
          },
          <String, Map<String, Object?>>{
            'u1': _bb('INV', <String, List<Object>>{
              'A': <Object>[2],
              'Y': <Object>[9],
            }),
            'u2': _bb('NAND2', <String, List<Object>>{
              'A': <Object>[9],
              'B': <Object>[3],
              'Y': <Object>[10],
            }),
            'u3': _bb('DFF', <String, List<Object>>{
              r'$1': <Object>[4],
              r'$2': <Object>[10],
              r'$3': <Object>[5],
            }),
          },
        ),
      );
      expect(_dirs(result.model, 'u1'), <String, PortDirection>{
        'A': _in,
        'Y': _out,
      });
      expect(_dirs(result.model, 'u2'), <String, PortDirection>{
        'A': _in,
        'B': _in,
        'Y': _out,
      });
      expect(_dirs(result.model, 'u3'), <String, PortDirection>{
        r'$1': _in,
        r'$2': _in,
        r'$3': _out,
      });
      expect(result.report.types, <String>['DFF', 'INV', 'NAND2']);
      expect(result.report.pinCount, 8);
      // u1.Y and u2.Y were picked as their cells' outputs to break the tie
      // between two undecided black-box pins; everything else followed from
      // the wiring.
      expect(result.report.guessedPinCount, 2);
    });

    test('a black-box output feeding other black boxes drives them', () {
      // TIE drives n, which two black boxes read and a module output reads.
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'y': _port('output', <Object>[7]),
          },
          <String, Map<String, Object?>>{
            'tie': _bb('TIEHI', <String, List<Object>>{
              'Y': <Object>[7],
            }),
            'r1': _bb('LOAD', <String, List<Object>>{
              'A': <Object>[7],
            }),
            'r2': _bb('LOAD', <String, List<Object>>{
              'A': <Object>[7],
            }),
          },
        ),
      );
      // Three black-box pins share net 7 and nothing else drives it, so the
      // wiring alone decides none of them; TIEHI's lone pin is picked as its
      // output, which makes the two loads inputs.
      expect(_dirs(result.model, 'tie')['Y'], _out);
      expect(_dirs(result.model, 'r1')['A'], _in);
      expect(_dirs(result.model, 'r2')['A'], _in);
      expect(result.report.types, <String>['LOAD', 'TIEHI']);
      expect(result.report.guessedPinCount, 1);
    });

    test('power pins on constants and supply ports read as inputs', () {
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'a': _port('input', <Object>[2]),
            'y': _port('output', <Object>[3]),
            'VDDA': _port('inout', <Object>[4]),
          },
          <String, Map<String, Object?>>{
            'u1': _bb('INV', <String, List<Object>>{
              'A': <Object>[2],
              'VDD': <Object>['1'],
              'VNW': <Object>[4],
              'VSS': <Object>['0'],
              'Y': <Object>[3],
            }),
          },
        ),
      );
      expect(_dirs(result.model, 'u1'), <String, PortDirection>{
        'A': _in,
        'VDD': _in,
        'VNW': _in,
        'VSS': _in,
        'Y': _out,
      });
      expect(result.report.guessedPinCount, 0);
    });

    test('undecided pins default to inputs and count as guesses', () {
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'a': _port('input', <Object>[2]),
            'y': _port('output', <Object>[3]),
          },
          <String, Map<String, Object?>>{
            'u1': _bb('ODD', <String, List<Object>>{
              'A': <Object>[2],
              'Y': <Object>[3],
              // Nothing else on net 20.
              'NC': <Object>[20],
              // Driven on one bit, sole driver of a module output on the
              // other: conflicting evidence.
              'X': <Object>[2, 21],
              // A floating constant is no evidence.
              'Z': <Object>['z'],
            }),
            'u_buf': _known(
              r'$_BUF_',
              <String, String>{'A': 'input', 'Y': 'output'},
              <String, List<Object>>{
                'A': <Object>[21],
                'Y': <Object>[22],
              },
            ),
          },
        ),
      );
      expect(_dirs(result.model, 'u1'), <String, PortDirection>{
        'A': _in,
        'Y': _out,
        'NC': _in,
        'X': _in,
        'Z': _in,
      });
      expect(result.report.pinCount, 5);
      expect(result.report.guessedPinCount, 3);
    });

    test('directions Yosys gave are kept and used as evidence', () {
      final cell = _bb('HALF', <String, List<Object>>{
        'A': <Object>[2],
        'Y': <Object>[3],
      })..['port_directions'] = <String, String>{'Y': 'output'};
      final result = inferBlackBoxPorts(
        _model(
          <String, Map<String, Object?>>{
            'y': _port('output', <Object>[4]),
          },
          <String, Map<String, Object?>>{
            'h': cell,
            'r': _bb('LOAD', <String, List<Object>>{
              'A': <Object>[3],
              'Y': <Object>[4],
            }),
          },
        ),
      );
      expect(_dirs(result.model, 'h'), <String, PortDirection>{
        'A': _in,
        'Y': _out,
      });
      expect(_dirs(result.model, 'r'), <String, PortDirection>{
        'A': _in,
        'Y': _out,
      });
      // h.A is the only pin inferred for h; r's two pins.
      expect(result.report.pinCount, 3);
    });

    test('module types and internal cells are not black boxes', () {
      final model = _model(
        <String, Map<String, Object?>>{
          'a': _port('input', <Object>[2]),
          'y': _port('output', <Object>[3]),
        },
        <String, Map<String, Object?>>{
          's': _known(
            'sub',
            <String, String>{'i': 'input', 'o': 'output'},
            <String, List<Object>>{
              'i': <Object>[2],
              'o': <Object>[3],
            },
          ),
        },
        extraModules: <String, Object?>{
          'sub': <String, Object?>{
            'attributes': <String, Object?>{},
            'ports': <String, Object?>{
              'i': _port('input', <Object>[2]),
              'o': _port('output', <Object>[3]),
            },
            'cells': <String, Object?>{},
            'netnames': <String, Object?>{},
          },
        },
      );
      expect(isUndefinedModuleType(model, 'sub'), isFalse);
      expect(isUndefinedModuleType(model, r'$dff'), isFalse);
      expect(isUndefinedModuleType(model, 'INV'), isTrue);
      final result = inferBlackBoxPorts(model);
      expect(identical(result.model, model), isTrue);
      expect(result.report, BlackBoxReport.none);
      expect(result.report.warningLines, isEmpty);
    });

    test('black boxes in a submodule are inferred there', () {
      final model = NetlistModel.fromJson(<String, Object?>{
        'creator': 'test',
        'modules': <String, Object?>{
          'top': const <String, Object?>{
            'attributes': <String, Object?>{'top': '1'},
            'ports': <String, Object?>{},
            'cells': <String, Object?>{},
            'netnames': <String, Object?>{},
          },
          'leaf': <String, Object?>{
            'attributes': const <String, Object?>{},
            'ports': <String, Object?>{
              'i': _port('input', <Object>[2]),
              'o': _port('output', <Object>[3]),
            },
            'cells': <String, Object?>{
              'g': _bb('BUF', <String, List<Object>>{
                'A': <Object>[2],
                'Y': <Object>[3],
              }),
            },
            'netnames': const <String, Object?>{},
          },
        },
      });
      final result = inferBlackBoxPorts(model);
      expect(result.model.modules['leaf']!.cells['g']!.portDirections, {
        'A': _in,
        'Y': _out,
      });
      expect(result.model.modules['top'], model.modules['top']);
    });
  });

  group('BlackBoxReport.warningLines', () {
    test('names the types and the guesses', () {
      const report = BlackBoxReport(
        types: <String>['DFF', 'INV'],
        pinCount: 7,
        guessedPinCount: 2,
      );
      const drawn =
          'Warning: No definition found for 2 module types, drawn as black '
          'boxes with pin directions inferred from the wiring: DFF, INV.';
      const guessed =
          'Warning: 2 of 7 black-box pins had no direction the wiring decided '
          'and were guessed. Add a cell library (Liberty) for exact pins.';
      expect(report.warningLines, <String>[drawn, guessed]);
    });

    test('leaves out the guess line when nothing was guessed', () {
      const report = BlackBoxReport(
        types: <String>['INV'],
        pinCount: 2,
        guessedPinCount: 0,
      );
      expect(report.warningLines, hasLength(1));
      expect(report.warningLines.single, contains('1 module type,'));
    });

    test('caps a long type list', () {
      final report = BlackBoxReport(
        types: <String>[for (var i = 0; i < 25; i++) 'C$i'],
        pinCount: 25,
        guessedPinCount: 0,
      );
      expect(report.warningLines.single, endsWith('C19 and 5 more.'));
    });
  });
}
