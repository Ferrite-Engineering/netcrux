// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:path/path.dart' as p;

/// Guards for the shipped `examples/` projects.
///
/// The examples exist because NetCrux had nothing a new user could open:
/// the only `.netcrux-project` in the repository lived under
/// `test/fixtures/project/`, which reads as internal scaffolding, and it
/// names source files that were never committed. Something a person is
/// told to open must actually open.
///
/// **Existence is not loadability.** Every assertion below runs through
/// the real [NetcruxProjectFileReader], the real [resolveProjectPaths] and
/// the real [LoadedNetlist.buildRequest] — the same three the desktop open
/// flow uses between the file picker and the Yosys subprocess. A guard
/// that asserted `File(...).existsSync()` on the `.netcrux-project` would
/// pass on a project naming RTL nobody committed, which is exactly the
/// failure a first-run user would hit.
///
/// What is deliberately *not* asserted here is elaboration itself: that
/// needs a Yosys binary, which CI does not have. The boundary this suite
/// defends is everything up to the subprocess — that the request handed to
/// Yosys names real files, in the right language, with a top module that
/// exists in them.
void main() {
  final examplesRoot = Directory(p.join(Directory.current.path, 'examples'));

  List<File> discover() =>
      examplesRoot
          .listSync()
          .whereType<Directory>()
          .expand((d) => d.listSync().whereType<File>())
          .where((f) => f.path.endsWith('.$kNetcruxProjectExtension'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  group('examples/', () {
    test('ships the documented openable projects, plus a README', () {
      expect(examplesRoot.existsSync(), isTrue);
      expect(File(p.join(examplesRoot.path, 'README.md')).existsSync(), isTrue);
      final found = discover()
          .map((f) => p.basename(p.dirname(f.path)))
          .toSet();
      expect(found, containsAll(<String>['adder4', 'cdc-capture']));
    });

    for (final file in discover()) {
      final name = p.basename(p.dirname(file.path));
      group(name, () {
        late final NetcruxProject authored;
        late final NetcruxProject resolved;
        late final YosysRunRequest request;

        setUpAll(() {
          // Decoding is the first thing the open flow does with a picked
          // file; anchoring is the second.
          authored = const NetcruxProjectFileReader().parse(
            file.readAsStringSync(),
          );
          resolved = resolveProjectPaths(authored, p.dirname(file.path));
          request = LoadedNetlist.buildRequest(resolved);
        });

        test('is authored portably — every path relative', () {
          // A committed example must not carry the author's checkout
          // layout. Relative paths are the only form that survives being
          // cloned somewhere else.
          expect(authored.sourceFiles, isNotEmpty);
          for (final f in authored.sourceFiles) {
            expect(
              p.isAbsolute(f),
              isFalse,
              reason: '$f must be relative so the example travels',
            );
          }
          for (final d in authored.includePaths) {
            expect(p.isAbsolute(d), isFalse, reason: '$d must be relative');
          }
        });

        test('declares the schema version this build reads', () {
          // A version bump that forgot the examples surfaces to the user
          // as "Project file version N is not supported" on the one file
          // they were told to open.
          expect(authored.version, kNetcruxProjectVersion);
        });

        test('every declared source resolves to a committed file', () {
          for (final f in resolved.sourceFiles) {
            expect(
              File(f).existsSync(),
              isTrue,
              reason:
                  '$name declares a source that is not committed at "$f" — '
                  'the example would open to an empty schematic',
            );
            expect(
              p.isAbsolute(f),
              isTrue,
              reason: 'anchoring must absolutize',
            );
          }
          for (final d in resolved.includePaths) {
            expect(Directory(d).existsSync(), isTrue, reason: d);
          }
        });

        test('names a top module that the sources actually define', () {
          // The gap this closes: a `topModule` that no source declares
          // makes Yosys fail `hierarchy -check` with "module not found",
          // which reads to a new user as "NetCrux cannot open this".
          expect(
            authored.topModule,
            isNotEmpty,
            reason:
                'an example should pin its top module rather than leave '
                'the choice to auto-detection',
          );
          final declaration = RegExp(
            r'^\s*module\s+' + RegExp.escape(authored.topModule) + r'\b',
            multiLine: true,
          );
          final declaringSources = resolved.sourceFiles.where(
            (f) => declaration.hasMatch(File(f).readAsStringSync()),
          );
          expect(
            declaringSources,
            isNotEmpty,
            reason:
                '$name sets topModule "${authored.topModule}", which none of '
                'its sources declares',
          );
        });

        test('builds a Yosys request naming each source in its language', () {
          expect(request.topModule, authored.topModule);
          expect(
            request.sources.map((s) => s.path),
            resolved.sourceFiles,
            reason: 'the anchored paths are what reach the subprocess',
          );
          for (final source in request.sources) {
            final expected = switch (p.extension(source.path).toLowerCase()) {
              '.vhd' || '.vhdl' => YosysSourceLanguage.vhdl,
              '.sv' || '.svh' => YosysSourceLanguage.systemVerilog,
              _ => YosysSourceLanguage.verilog,
            };
            expect(
              source.language,
              expected,
              reason:
                  '${source.path} would be handed to the wrong Yosys reader',
            );
          }
        });

        test('stays inside the toolchain the example README promises', () {
          // Every shipped example claims `yosys` alone is enough. A VHDL
          // source would silently add a GHDL requirement — and worse, the
          // project schema cannot express GHDL's top *unit* separately
          // from the Verilog top *module*, so a mixed-language project
          // authored here fails in `ghdl --synth` before Yosys ever runs.
          for (final source in request.sources) {
            expect(
              source.language,
              isNot(YosysSourceLanguage.vhdl),
              reason:
                  '$name ships VHDL: `vhdlTopUnit` is derived from '
                  'topModule, so GHDL is asked to elaborate an entity that '
                  'does not exist',
            );
          }
        });
      });
    }
  });
}
