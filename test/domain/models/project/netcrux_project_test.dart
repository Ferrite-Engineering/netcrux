// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';

void main() {
  group('NetcruxProject', () {
    test('empty has expected defaults', () {
      expect(NetcruxProject.empty.version, kNetcruxProjectVersion);
      expect(NetcruxProject.empty.sourceFiles, isEmpty);
      expect(NetcruxProject.empty.topModule, '');
      expect(NetcruxProject.empty.defines, isEmpty);
      expect(NetcruxProject.empty.includePaths, isEmpty);
      expect(NetcruxProject.empty.extraYosysCommands, isEmpty);
      expect(NetcruxProject.empty.lowerToStructural, isFalse);
    });

    test('create produces a v1 project with the supplied fields', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['a.v', 'b.sv'],
        topModule: 'top',
        defines: const <String, String>{'WIDTH': '32', 'FAST': ''},
        includePaths: const ['inc'],
        extraYosysCommands: const ['flatten'],
        lowerToStructural: true,
      );
      expect(project.version, kNetcruxProjectVersion);
      expect(project.sourceFiles, ['a.v', 'b.sv']);
      expect(project.topModule, 'top');
      expect(project.defines, {'WIDTH': '32', 'FAST': ''});
      expect(project.includePaths, ['inc']);
      expect(project.extraYosysCommands, ['flatten']);
      expect(project.lowerToStructural, isTrue);
    });

    test('equality compares every field', () {
      final a = NetcruxProject.create(
        sourceFiles: const <String>['a.v'],
        topModule: 'top',
      );
      final b = NetcruxProject.create(
        sourceFiles: const <String>['a.v'],
        topModule: 'top',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on a single field difference', () {
      final a = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      final b = NetcruxProject.create(sourceFiles: const <String>['b.v']);
      expect(a == b, isFalse);
    });

    test('copyWith leaves other fields untouched', () {
      final original = NetcruxProject.create(
        sourceFiles: const <String>['a.v'],
        topModule: 'top',
        defines: const <String, String>{'X': '1'},
        includePaths: const ['inc'],
        lowerToStructural: true,
      );
      final next = original.copyWith(topModule: 'cpu');
      expect(next.topModule, 'cpu');
      expect(next.sourceFiles, original.sourceFiles);
      expect(next.defines, original.defines);
      expect(next.includePaths, original.includePaths);
      expect(next.lowerToStructural, isTrue);
    });

    test('resolveLanguage uses an explicit override when present', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v'],
        sourceFileLanguages: const <String, NetcruxSourceLanguage>{
          'top.v': NetcruxSourceLanguage.systemVerilog,
        },
      );
      expect(
        project.resolveLanguage('top.v'),
        NetcruxSourceLanguage.systemVerilog,
      );
    });

    test('resolveLanguage falls back to extension auto-detect', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.vhd', 'core.sv', 'legacy.v'],
      );
      expect(
        project.resolveLanguage('top.vhd'),
        NetcruxSourceLanguage.vhdl,
      );
      expect(
        project.resolveLanguage('core.sv'),
        NetcruxSourceLanguage.systemVerilog,
      );
      expect(
        project.resolveLanguage('legacy.v'),
        NetcruxSourceLanguage.verilog,
      );
    });

    test('inferLanguageFromExtension is case-insensitive', () {
      expect(
        NetcruxProject.inferLanguageFromExtension('Top.VHD'),
        NetcruxSourceLanguage.vhdl,
      );
      expect(
        NetcruxProject.inferLanguageFromExtension('CORE.SV'),
        NetcruxSourceLanguage.systemVerilog,
      );
    });

    test('inferLanguageFromExtension falls back to SystemVerilog', () {
      expect(
        NetcruxProject.inferLanguageFromExtension('mystery'),
        NetcruxSourceLanguage.systemVerilog,
      );
    });

    test('equality includes the sourceFileLanguages map', () {
      final a = NetcruxProject.create(
        sourceFiles: const <String>['t.v'],
        sourceFileLanguages: const <String, NetcruxSourceLanguage>{
          't.v': NetcruxSourceLanguage.systemVerilog,
        },
      );
      final b = NetcruxProject.create(
        sourceFiles: const <String>['t.v'],
        sourceFileLanguages: const <String, NetcruxSourceLanguage>{
          't.v': NetcruxSourceLanguage.systemVerilog,
        },
      );
      final c = NetcruxProject.create(
        sourceFiles: const <String>['t.v'],
        sourceFileLanguages: const <String, NetcruxSourceLanguage>{
          't.v': NetcruxSourceLanguage.vhdl,
        },
      );
      expect(a, b);
      expect(a == c, isFalse);
    });
  });

  group('NetcruxProject.isPrebuiltNetlist', () {
    test('a single .json source is a pre-built netlist', () {
      expect(
        NetcruxProject.create(
          sourceFiles: const <String>['/d/top.netlist.JSON'],
        ).isPrebuiltNetlist,
        isTrue,
      );
    });

    test('HDL sources, several sources, or no source are not', () {
      expect(
        NetcruxProject.create(
          sourceFiles: const <String>['/d/top.v'],
        ).isPrebuiltNetlist,
        isFalse,
      );
      expect(
        NetcruxProject.create(
          sourceFiles: const <String>['/d/a.json', '/d/b.json'],
        ).isPrebuiltNetlist,
        isFalse,
      );
      expect(NetcruxProject.empty.isPrebuiltNetlist, isFalse);
    });

    test('a URL is judged by its path, not its query or fragment', () {
      expect(
        NetcruxProject.isNetlistJsonPath('https://h/top.json?rev=3#x'),
        isTrue,
      );
      expect(
        NetcruxProject.isNetlistJsonPath('https://h/get?file=top.json'),
        isFalse,
      );
    });
  });

  group('NetcruxProject.locationLabel', () {
    test('a path shows its base name, on either separator', () {
      expect(NetcruxProject.locationLabel('/d/rtl/top.v'), 'top.v');
      expect(NetcruxProject.locationLabel(r'C:\rtl\top.v'), 'top.v');
      expect(NetcruxProject.locationLabel('top.v'), 'top.v');
    });

    test('a URL shows its last path segment, ignoring the query', () {
      expect(
        NetcruxProject.locationLabel('https://h/n/top.json?rev=3'),
        'top.json',
      );
    });

    test('a URL fragment is the name a browser upload carries', () {
      expect(
        NetcruxProject.locationLabel(
          'blob:https://app.netcrux.app/5b0c#a%20b.json',
        ),
        'a b.json',
      );
    });
  });
}
