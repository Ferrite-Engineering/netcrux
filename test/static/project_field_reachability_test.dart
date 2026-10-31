// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Every field of a `.netcrux-project` must change what NetCrux does with the
// design. A field the file codec reads and writes but nothing else acts on
// looks configurable and is not, so each field is accounted for here: either
// changing it changes the Yosys request the elaboration sends, or it names
// the source that acts on it. A new field fails the first test until it is
// added to one of the two tables.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';

const String _modelPath = 'lib/domain/models/project/netcrux_project.dart';

/// The fields the Yosys request is built from, each with a change that must
/// change the request.
final Map<String, NetcruxProject Function(NetcruxProject)> _requestFields =
    <String, NetcruxProject Function(NetcruxProject)>{
      'sourceFiles': (p) =>
          p.copyWith(sourceFiles: <String>[...p.sourceFiles, 'sub.v']),
      'topModule': (p) => p.copyWith(topModule: 'top'),
      'defines': (p) => p.copyWith(defines: <String, String>{'WIDTH': '8'}),
      'includePaths': (p) => p.copyWith(includePaths: <String>['inc']),
      'extraYosysCommands': (p) =>
          p.copyWith(extraYosysCommands: <String>['flatten']),
      'lowerToStructural': (p) => p.copyWith(lowerToStructural: true),
      'sourceFileLanguages': (p) => p.copyWith(
        sourceFileLanguages: <String, NetcruxSourceLanguage>{
          'top.v': NetcruxSourceLanguage.systemVerilog,
        },
      ),
      'blackBoxMissingModules': (p) => p.copyWith(blackBoxMissingModules: true),
    };

/// The fields that act somewhere other than the Yosys request, with the
/// source that reads each one.
const Map<String, String> _otherFields = <String, String>{
  // The schema stamp: the codec writes it and rejects a file of another one.
  'version': 'lib/services/project/netcrux_project_file.dart',
  // Turned into a file of black-box stubs read ahead of the sources, and
  // given to the native reader.
  'libertyFiles': 'lib/features/project/providers/loaded_netlist_provider.dart',
  // Read by the native gate-level reader only.
  'cellModelFiles': 'lib/services/verilog/native_read_pipeline.dart',
  // Picks the reader.
  'netlistReader':
      'lib/features/project/providers/loaded_netlist_provider.dart',
};

void main() {
  test('every project field is accounted for', () {
    final source = File(_modelPath).readAsStringSync();
    final fields = RegExp(
      r'^  final [^=(]+? (\w+);$',
      multiLine: true,
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(fields, isNotEmpty, reason: 'no fields found in $_modelPath');
    expect(
      fields,
      <String>{..._requestFields.keys, ..._otherFields.keys},
      reason:
          'a NetcruxProject field must change the elaboration request or name '
          'the source that acts on it',
    );
  });

  group('changing a request field changes the Yosys request', () {
    final base = NetcruxProject.create(sourceFiles: const <String>['top.v']);
    for (final MapEntry(key: field, value: vary) in _requestFields.entries) {
      test(field, () {
        final varied = vary(base);
        expect(varied, isNot(base), reason: 'the change must change $field');
        expect(
          LoadedNetlist.buildRequest(varied),
          isNot(LoadedNetlist.buildRequest(base)),
          reason: '$field is saved in the project but never reaches Yosys',
        );
      });
    }
  });

  group('a field outside the request is read where it acts', () {
    for (final MapEntry(key: field, value: path) in _otherFields.entries) {
      test(field, () {
        expect(
          File(path).readAsStringSync(),
          contains('project.$field'),
          reason: '$path no longer reads $field',
        );
      });
    }
  });
}
