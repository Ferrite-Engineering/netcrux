// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/rohd_netlist_extensions.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// Netlists written by ROHD's `NetlistSynthesizer`, a superset of Yosys JSON,
/// read through every route NetCrux has. The fixtures are real ROHD output
/// (`test/fixtures/netlist/rohd/generated/PROVENANCE.md`); the hand-written documents
/// below pin the cases a real export does not happen to contain.
const String _dir = 'test/fixtures/netlist/rohd/generated';
const List<String> _fixtures = <String>[
  'sample_pipeline',
  'lane_reducer',
  'demo_top',
  'hcl_fifo',
];
const Map<String, String> _tops = <String, String>{
  'sample_pipeline': 'SamplePipeline',
  'lane_reducer': 'LaneReducer',
  'demo_top': 'DemoTop',
  'hcl_fifo': 'Fifo_D4_W8',
};

NetlistModel _chunked(String text, int chunk, {RohdSourceFileResolver? r}) =>
    ChunkedYosysJsonReader(
      MemoryChunkSource(Uint8List.fromList(utf8.encode(text)), maxChunk: chunk),
      chunkSize: chunk,
      sourceResolver: r,
    ).parse();

const StreamingYosysJsonReader _strings = StreamingYosysJsonReader();

/// A small document with one module `m`, a net `a`, a cell `c` and the given
/// extensions, with `files` written before or after `modules`.
String _doc({
  String creator = rohdNetlistCreator,
  Object? files = const <String>['lib/a.dart', 'lib/b.dart'],
  Object? trace = const <String, Object?>{
    'signals': {
      'a': ['0:10:5', '1:20:7'],
    },
    'instances': {
      'c': ['1:30:3', '0:40:9'],
    },
  },
  bool filesFirst = true,
  Map<String, Object?> extraTop = const <String, Object?>{},
  String cellType = r'$buf',
  Map<String, Object?>? netExtra,
}) {
  final module = <String, Object?>{
    'attributes': {'top': 1, 'src': 'generated', 'rohd.src_trace': ?trace},
    'ports': {
      'a': {
        'direction': 'input',
        'bits': [2],
      },
    },
    'cells': {
      'c': {
        'hide_name': 0,
        'type': cellType,
        'parameters': <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': {'A': 'input', 'Y': 'output'},
        'connections': {
          'A': [2],
          'Y': [3],
        },
      },
    },
    'netnames': {
      'a': {
        'bits': [2],
        'attributes': <String, Object?>{},
        ...?netExtra,
      },
    },
  };
  final top = <String, Object?>{
    'creator': creator,
    'version': '9.9.9',
    ...extraTop,
  };
  final modules = <String, Object?>{'m': module};
  final ordered = <String, Object?>{
    ...top,
    if (filesFirst && files != null) 'files': files,
    'modules': modules,
    if (!filesFirst && files != null) 'files': files,
  };
  return jsonEncode(ordered);
}

void main() {
  group('the ROHD fixtures', () {
    for (final name in _fixtures) {
      final path = '$_dir/$name.json';
      final text = File(path).readAsStringSync();

      group(name, () {
        test('open with the same model on every route', () async {
          final resolver = rohdSourceResolverFor(path);
          final file = ChunkedYosysJsonReader.parseFile(path);
          final cut = _chunked(text, 97, r: resolver);
          final string = _strings.parse(text, sourceResolver: resolver);
          expect(cut, file);
          expect(string, file);
          expect(file.creator, rohdNetlistCreator);
          expect(file.topModule?.name, _tops[name]);

          final onIsolate = await const PrebuiltNetlistLoader().load(path);
          expect(onIsolate, file);
          // The browser route: text in, parsed in place. No file system, so
          // a recorded path stays as ROHD wrote it.
          final browser = await PrebuiltNetlistLoader(
            read: (_) async => text,
            parseOnIsolate: false,
          ).load(path);
          expect(browser?.topModule?.name, _tops[name]);
          expect(browser?.modules.keys, file.modules.keys);
        });

        test('raise no black-box warning for ROHD procedural cells', () async {
          final loaded = await const PrebuiltNetlistLoader().loadWithReport(
            path,
          );
          expect(loaded!.report.isEmpty, isTrue);
          expect(loaded.report.warningLines, isEmpty);
        });

        test('keep the source trace out of the attributes', () {
          final model = ChunkedYosysJsonReader.parseFile(path);
          for (final module in model.modules.values) {
            expect(module.attributes, isNot(contains(rohdSourceTraceKey)));
          }
        });

        test('draw the top scope', () {
          final model = ChunkedYosysJsonReader.parseFile(path);
          final graph = const SchematicGraphBuilder().build(
            model,
            HierarchyNode.rootOf(model)!,
          );
          expect(graph.cells, isNotEmpty);
          expect(graph.boundaryPorts, isNotEmpty);
        });
      });
    }

    test('a source location points at the line that made the thing', () {
      const path = '$_dir/demo_top.json';
      final model = ChunkedYosysJsonReader.parseFile(path);
      final top = model.modules['DemoTop']!;

      // The instantiation of a sub-module is the line that instantiated it,
      // not the line inside the instantiated class.
      final pipeline = top.cells['sample_pipeline']!;
      final location = _location(pipeline.attributes['src']!);
      expect(File(location.file).existsSync(), isTrue, reason: location.file);
      expect(location.file, endsWith('generator/lib/designs.dart'));
      expect(
        _lineOf(location),
        contains('SamplePipeline(clk, reset, feed)'),
      );

      // A signal and a leaf cell inside a sub-module.
      final inner = model.modules['SamplePipeline']!;
      expect(
        _lineOf(_location(inner.nets['scaled']!.attributes['src']!)),
        contains("Logic(name: 'scaled'"),
      );
      expect(
        _lineOf(_location(inner.cells['lshift']!.attributes['src']!)),
        contains('scaled < inbound.data << 1'),
      );
      expect(
        _lineOf(_location(inner.cells['sequential']!.attributes['src']!)),
        contains('Sequential('),
      );
    });

    test('every location a design file is named at is a real line', () {
      const path = '$_dir/demo_top.json';
      final model = ChunkedYosysJsonReader.parseFile(path);
      var seen = 0;
      for (final module in model.modules.values) {
        final sources = <String>[
          for (final cell in module.cells.values) ?cell.attributes['src'],
          for (final net in module.nets.values) ?net.attributes['src'],
        ];
        for (final source in sources) {
          final location = _location(source);
          if (!location.file.endsWith('generator/lib/designs.dart')) continue;
          seen++;
          expect(_lineOf(location).trim(), isNotEmpty, reason: source);
        }
      }
      expect(seen, greaterThan(40));
    });

    test('a structure or array net carries a one-line type', () {
      final model = ChunkedYosysJsonReader.parseFile('$_dir/demo_top.json');
      final top = model.modules['DemoTop']!;
      expect(
        top.nets['item']!.attributes[rohdTypeAttribute],
        'TaggedSample{beat:Sample{data:16, valid:1}, tag:4}',
      );
      expect(
        top.nets['lane_array']!.attributes[rohdTypeAttribute],
        'array[4]x8',
      );
      expect(
        model
            .modules['SamplePipeline']!
            .nets['sample_in']!
            .attributes[rohdTypeAttribute],
        'Sample{data:16, valid:1}',
      );
      // A plain bus has none.
      expect(top.nets['clk']!.attributes, isNot(contains(rohdTypeAttribute)));
    });

    test('struct pack and unpack cells keep their fields as pins', () {
      final model = ChunkedYosysJsonReader.parseFile(
        '$_dir/sample_pipeline.json',
      );
      final module = model.modules['SamplePipeline']!;
      final unpack = module.cells.values.singleWhere(
        (c) => c.type == r'$struct_unpack',
      );
      expect(unpack.connections.keys, containsAll(['A', 'data', 'valid']));
      expect(unpack.connections['A']!.length, 17);
      expect(unpack.parameters['STRUCT_NAME'], 'sample_in');
      final pack = module.cells.values.singleWhere(
        (c) => c.type == r'$struct_pack',
      );
      expect(pack.connections.keys, containsAll(['data', 'valid', 'Y']));
      // Located by the signal they split or build.
      expect(unpack.attributes, contains('src'));
      expect(pack.attributes, contains('src'));
    });

    test('a file is found from the netlist directory upward', () {
      final model = ChunkedYosysJsonReader.parseFile(
        '$_dir/sample_pipeline.json',
      );
      final src =
          model.modules['SamplePipeline']!.nets['clk']!.attributes['src']!;
      expect(src, startsWith(Directory.current.absolute.path));
    });
  });

  group('the ROHD extensions in a document', () {
    for (final filesFirst in <bool>[true, false]) {
      final order = filesFirst ? 'files before modules' : 'files after modules';
      test('apply with $order, on both readers', () {
        final text = _doc(filesFirst: filesFirst);
        for (final model in <NetlistModel>[
          _strings.parse(text),
          _chunked(text, 5),
          _chunked(text, 4096),
        ]) {
          final m = model.modules['m']!;
          expect(m.nets['a']!.attributes['src'], 'lib/a.dart:10.5');
          // `c` is not a module of the document: the innermost frame.
          expect(m.cells['c']!.attributes['src'], 'lib/b.dart:30.3');
          expect(m.attributes, isNot(contains(rohdSourceTraceKey)));
          expect(m.attributes['src'], 'generated');
        }
      });
    }

    test(
      'a cell that instantiates a module is located by its second frame',
      () {
        final text = _doc(cellType: 'm');
        final m = _strings.parse(text).modules['m']!;
        expect(m.cells['c']!.attributes['src'], 'lib/a.dart:40.9');
        expect(_chunked(text, 7), _strings.parse(text));
      },
    );

    test('a file the document names no entry for gives no location', () {
      final text = _doc(
        trace: {
          'signals': {
            'a': ['7:10:5'],
          },
        },
      );
      final m = _strings.parse(text).modules['m']!;
      expect(m.nets['a']!.attributes, isNot(contains('src')));
    });

    test('a location with no column is kept without one', () {
      final text = _doc(
        trace: {
          'signals': {
            'a': ['0:12'],
          },
        },
      );
      expect(
        _chunked(text, 11).modules['m']!.nets['a']!.attributes['src'],
        'lib/a.dart:12',
      );
    });

    test('an existing src is never replaced', () {
      final text = _doc(
        netExtra: {
          'attributes': {'src': 'top.v:1.1-2.2'},
        },
      );
      expect(
        _strings.parse(text).modules['m']!.nets['a']!.attributes['src'],
        'top.v:1.1-2.2',
      );
    });

    test('a net called files is not the files array', () {
      // The first `"files": [` in the text is the cell's pin, not the
      // document's.
      final text = jsonEncode({
        'creator': rohdNetlistCreator,
        'modules': {
          'm': {
            'attributes': {
              'top': 1,
              rohdSourceTraceKey: {
                'signals': {
                  'a': ['0:3:4'],
                },
              },
            },
            'cells': {
              'c': {
                'type': r'$buf',
                'port_directions': {'files': 'input'},
                'connections': {
                  'files': [9, 9],
                },
              },
            },
            'netnames': {
              'a': {
                'bits': [2],
              },
            },
          },
        },
        'files': ['real.dart'],
      });
      expect(
        _strings.parse(text).modules['m']!.nets['a']!.attributes['src'],
        'real.dart:3.4',
      );
    });

    test('unknown fields, a newer version and bad shapes are ignored', () {
      final text = _doc(
        extraTop: {
          'future_section': {
            'a': [1, 2, 3],
          },
          'version': '99.0.0',
        },
        netExtra: {
          'logic_type': {'typeName': 5, 'fields': 'nope'},
          'newest_field': [
            1,
            {'x': null},
          ],
        },
        trace: {
          'signals': {
            'a': 'not a list',
            'b': ['x:y:z', 5, null],
          },
          'instances': [1, 2],
          'extra': true,
        },
      );
      for (final model in <NetlistModel>[
        _strings.parse(text),
        _chunked(text, 3),
      ]) {
        expect(model.topModule?.name, 'm');
        expect(
          model.modules['m']!.nets['a']!.attributes,
          isNot(contains('src')),
        );
      }
    });

    test('malformed trace and files do not stop the netlist opening', () {
      for (final files in <Object?>[
        'lib/a.dart',
        42,
        <Object?>[1, null, 'lib/a.dart'],
        <String, Object?>{},
      ]) {
        final text = _doc(files: files);
        expect(_strings.parse(text).topModule?.name, 'm');
        expect(_chunked(text, 9).topModule?.name, 'm');
      }
      expect(_strings.parse(_doc(trace: 'text')).topModule?.name, 'm');
      expect(_strings.parse(_doc(files: null)).topModule?.name, 'm');
    });

    test('plain Yosys JSON is read as before', () {
      final text = _doc(creator: 'Yosys 0.50', trace: null, files: null);
      final model = _strings.parse(text);
      expect(model.modules['m']!.nets['a']!.attributes, isEmpty);
      expect(_chunked(text, 13), model);
    });
  });

  group('ROHD procedural cell types', () {
    test('are not black boxes in a ROHD netlist', () {
      final model = _strings.parse(_doc(cellType: 'Sequential'));
      expect(isUndefinedModuleType(model, 'Sequential'), isFalse);
      expect(isUndefinedModuleType(model, 'Combinational'), isFalse);
      expect(isUndefinedModuleType(model, 'Other'), isTrue);
      expect(inferBlackBoxPorts(model).report.isEmpty, isTrue);
    });

    test('still are in any other netlist', () {
      final model = _strings.parse(
        _doc(creator: 'Yosys 0.50', cellType: 'Sequential', trace: null),
      );
      expect(isUndefinedModuleType(model, 'Sequential'), isTrue);
      expect(inferBlackBoxPorts(model).report.types, ['Sequential']);
    });
  });

  group('RohdSourceFrame', () {
    test('parses file, line and optional column', () {
      expect(
        RohdSourceFrame.tryParse('0:42:5'),
        const RohdSourceFrame(0, 42, 5),
      );
      expect(
        RohdSourceFrame.tryParse('3:7'),
        const RohdSourceFrame(3, 7, null),
      );
    });

    test('refuses anything else', () {
      for (final bad in <Object?>[
        null,
        4,
        '',
        '1',
        '1:2:3:4',
        'a:2',
        '1:b',
        '-1:2',
        '1:0',
        '1:2:0',
        '1:2:x',
      ]) {
        expect(RohdSourceFrame.tryParse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('describeRohdLogicType', () {
    test('describes a structure, a nested one and an array', () {
      expect(
        describeRohdLogicType({
          'typeName': 'Pair',
          'fields': [
            {'name': 'lo', 'width': 4},
            {
              'name': 'inner',
              'type': {
                'typeName': 'In',
                'fields': [
                  {'name': 'x', 'width': 1},
                ],
              },
            },
          ],
        }),
        'Pair{lo:4, inner:In{x:1}}',
      );
      expect(
        describeRohdLogicType({
          'width': 24,
          'arrayDims': [3, 2],
          'elementWidth': 4,
        }),
        'array[3][2]x4',
      );
      expect(
        describeRohdLogicType({
          'arrayDims': [2],
          'elementType': {
            'typeName': 'S',
            'fields': [
              {'name': 'v', 'width': 1},
            ],
          },
        }),
        'array[2]xS{v:1}',
      );
    });

    test('has nothing to say about a plain bus or anything else', () {
      expect(describeRohdLogicType({'width': 8}), isNull);
      expect(describeRohdLogicType(null), isNull);
      expect(describeRohdLogicType('Sample'), isNull);
      expect(describeRohdLogicType([1]), isNull);
    });

    test('is bounded, whatever the document nests or lists', () {
      Object? deep = {'width': 1};
      for (var i = 0; i < 5000; i++) {
        deep = {
          'typeName': 'T',
          'fields': [
            {'name': 'f', 'type': deep},
          ],
        };
      }
      expect(describeRohdLogicType(deep)?.length ?? 0, lessThan(300));
      final wide = {
        'typeName': 'W',
        'fields': [
          for (var i = 0; i < 5000; i++) {'name': 'field_$i', 'width': 1},
        ],
      };
      expect(describeRohdLogicType(wide)!.length, lessThanOrEqualTo(241));
    });
  });

  group('rohdSourceResolverFor', () {
    test('finds a relative path beside the netlist and above it', () {
      final present = <String>{'/p/lib/a.dart', '/p/out/b.dart'};
      final resolve = rohdSourceResolverFor(
        '/p/out/deep/n.json',
        exists: present.contains,
      );
      expect(resolve('lib/a.dart'), '/p/lib/a.dart');
      expect(resolve('b.dart'), '/p/out/b.dart');
      expect(resolve('./b.dart'), '/p/out/b.dart');
    });

    test('keeps an absolute path and one it cannot find', () {
      final resolve = rohdSourceResolverFor('/p/n.json', exists: (_) => false);
      expect(resolve('/pub-cache/x.dart'), '/pub-cache/x.dart');
      expect(resolve(r'C:\src\x.dart'), r'C:\src\x.dart');
      expect(resolve('lib/missing.dart'), 'lib/missing.dart');
    });

    test('reads a Windows netlist path', () {
      final resolve = rohdSourceResolverFor(
        r'C:\proj\out\n.json',
        exists: (p) => p == r'C:\proj\lib\a.dart',
      );
      expect(resolve('lib/a.dart'), r'C:\proj\lib\a.dart');
    });

    test('looks up a bounded number of directories', () {
      final resolve = rohdSourceResolverFor(
        '/a/b/c/d/n.json',
        exists: (p) => p == '/a/x.dart',
        levels: 2,
      );
      expect(resolve('x.dart'), 'x.dart');
    });
  });
}

({String file, int line}) _location(String src) {
  final colon = src.lastIndexOf(':');
  final line = int.parse(src.substring(colon + 1).split('.').first);
  return (file: src.substring(0, colon), line: line);
}

String _lineOf(({String file, int line}) location) =>
    File(location.file).readAsLinesSync()[location.line - 1];
