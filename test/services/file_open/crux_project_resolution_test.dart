// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/file_open/crux_project_resolution.dart';
import 'package:path/path.dart' as p;

/// NetCrux's half of the `<design>.crux-project` contract.
///
/// NetCrux is the one product that can act on **either** half of a manifest —
/// a pre-built netlist, or `design.sources` it elaborates itself — so its
/// resolution has a branch the other three do not, and most of these tests are
/// about getting that branch's precedence right.
void main() {
  const resolver = CruxProjectResolver();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('nc_crux_project'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Writes a design directory named [design] holding [files] and a manifest
  /// with [yaml]. The manifest is `<design>.crux-project` unless
  /// [manifestName] says otherwise.
  ({String manifest, String dir}) writeDesign(
    String yaml, {
    List<String> files = const <String>[],
    String design = 'cdc_capture',
    String? manifestName,
  }) {
    final dir = Directory(p.join(tmp.path, design))
      ..createSync(recursive: true);
    for (final f in files) {
      File(p.join(dir.path, f))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
    }
    final manifest = p.join(dir.path, manifestName ?? '$design.crux-project');
    File(manifest).writeAsStringSync(yaml);
    return (manifest: manifest, dir: dir.path);
  }

  const sourcesYaml = 'version: 1\nname: cdc\ndesign:\n  sources:\n    - a.v\n';

  group('pass-through', () {
    test('an ordinary project path is untouched', () {
      final r = resolver.resolve('/d/thing.netcrux-project');
      expect(r, isA<NotAManifest>());
      expect((r as NotAManifest).path, '/d/thing.netcrux-project');
    });

    test('a name that only contains the extension is not a manifest', () {
      final r = resolver.resolve('/d/notes.crux-project.txt');
      expect(r, isA<NotAManifest>());
    });
  });

  group('the manifest file name', () {
    test('any <name>.crux-project is a manifest, and is read as one', () {
      // Named by its extension, so a missing file is a manifest that cannot
      // be read, not a source file handed to Yosys.
      final r = resolver.resolve('/d/my.crux-project');
      expect(r, isA<ManifestUnusable>());
      expect((r as ManifestUnusable).reason, ManifestUnusableReason.invalid);
    });

    test('a named manifest opens with no legacy notice', () {
      final d = writeDesign(sourcesYaml, files: ['a.v']);
      final s = resolver.resolve(d.manifest) as ManifestSources;
      expect(p.basename(s.manifestPath), 'cdc_capture.crux-project');
      expect(s.legacyRenameTo, isNull);
      expect(s.warnings, isEmpty);
    });

    test('the extension matches without regard to case', () {
      final d = writeDesign(
        sourcesYaml,
        files: ['a.v'],
        manifestName: 'CDC.Crux-Project',
      );
      expect(resolver.resolve(d.manifest), isA<ManifestSources>());
    });

    test('the legacy bare .crux-project still opens, naming the new name', () {
      final d = writeDesign(
        sourcesYaml,
        files: ['a.v'],
        manifestName: '.crux-project',
      );
      final s = resolver.resolve(d.manifest) as ManifestSources;
      expect(s.legacyRenameTo, 'cdc_capture.crux-project');
      // The parser's English deprecation warning is carried as the typed
      // field, not left in the list for a caller to show untranslated.
      expect(s.warnings, isEmpty);
      expect(s.designId, cxpDesignIdForPath(d.dir));
    });

    test('the legacy notice rides on the netlist outcome too', () {
      final d = writeDesign(
        'version: 1\nartifacts:\n  netlist: n.json\n',
        files: ['n.json'],
        manifestName: '.crux-project',
      );
      final n = resolver.resolve(d.manifest) as ManifestNetlist;
      expect(n.legacyRenameTo, 'cdc_capture.crux-project');
    });

    test('renaming the manifest keeps the design id', () {
      final d = writeDesign(
        sourcesYaml,
        files: ['a.v'],
        manifestName: '.crux-project',
      );
      final legacyId =
          (resolver.resolve(d.manifest) as ManifestSources).designId;
      final named = File(
        d.manifest,
      ).renameSync(p.join(d.dir, 'cdc_capture.crux-project'));
      final namedId =
          (resolver.resolve(named.path) as ManifestSources).designId;
      expect(namedId, legacyId);
    });
  });

  group('a design directory', () {
    test('opens the one manifest inside it', () {
      final d = writeDesign(sourcesYaml, files: ['a.v']);
      final s = resolver.resolve(d.dir) as ManifestSources;
      expect(s.manifestPath, d.manifest);
      expect(s.designId, cxpDesignIdForPath(d.dir));
    });

    test('with no manifest says so, naming the directory', () {
      final dir = Directory(p.join(tmp.path, 'bare'))..createSync();
      final r = resolver.resolve(dir.path);
      expect(r, isA<ManifestUnusable>());
      final u = r as ManifestUnusable;
      expect(u.reason, ManifestUnusableReason.noManifestInDirectory);
      expect(u.detail, dir.path);
    });

    test('with two manifests refuses to guess', () {
      // The legacy file beside a named one counts as two.
      final d = writeDesign(sourcesYaml, files: ['a.v']);
      File(p.join(d.dir, '.crux-project')).writeAsStringSync(sourcesYaml);
      final r = resolver.resolve(d.dir);
      expect(r, isA<ManifestAmbiguous>());
      final a = r as ManifestAmbiguous;
      expect(a.directory, d.dir);
      expect(a.candidates.map(p.basename), <String>[
        '.crux-project',
        'cdc_capture.crux-project',
      ]);
    });
  });

  group('suggestedCruxProjectFileName', () {
    test("is the directory's name with the extension", () {
      expect(
        suggestedCruxProjectFileName(p.join(tmp.path, 'uart_tx')),
        'uart_tx.crux-project',
      );
    });

    test('names the working directory for a relative dot', () {
      expect(
        suggestedCruxProjectFileName('.'),
        '${p.basename(Directory.current.path)}.crux-project',
      );
    });

    test('falls back to design for a filesystem root', () {
      final root = p.rootPrefix(p.absolute(tmp.path));
      expect(suggestedCruxProjectFileName(root), 'design.crux-project');
    });
  });

  group('netlist wins when present', () {
    test('a pre-built netlist is used in preference to sources', () {
      final d = writeDesign(
        '''
version: 1
name: cdc
design:
  sources:
    - rtl/a.v
artifacts:
  netlist: build/cdc.json
''',
        files: ['rtl/a.v', 'build/cdc.json'],
      );
      final r = resolver.resolve(d.manifest);
      expect(r, isA<ManifestNetlist>());
      final n = r as ManifestNetlist;
      // p.join, not a POSIX literal: these are host-resolved absolute paths,
      // so on a Windows runner the tail legitimately uses backslashes. A
      // hardcoded `build/cdc.json` passes on macOS and Linux and fails on
      // Windows for a reason that has nothing to do with precedence, which is
      // what this test is actually about.
      expect(n.netlistPath, endsWith(p.join('build', 'cdc.json')));
      expect(n.designId, cxpDesignIdForPath(d.dir));
    });

    test('a named-but-missing netlist reports rather than falling back', () {
      // Silently elaborating instead would hide a stale build — the user asked
      // for that file.
      final d = writeDesign(
        '''
version: 1
design:
  sources:
    - rtl/a.v
artifacts:
  netlist: build/gone.json
''',
        files: ['rtl/a.v'],
      );
      final r = resolver.resolve(d.manifest);
      expect(r, isA<ManifestUnusable>());
      final u = r as ManifestUnusable;
      expect(u.reason, ManifestUnusableReason.netlistMissing);
      expect(u.detail, 'build/gone.json');
    });
  });

  group('sources are actionable on their own', () {
    test('a manifest with sources and no netlist elaborates', () {
      final d = writeDesign(
        '''
version: 1
name: uart
design:
  top: uart_tx
  sources:
    - rtl/uart_tx.v
    - rtl/fifo.v
''',
        files: ['rtl/uart_tx.v', 'rtl/fifo.v'],
      );
      final r = resolver.resolve(d.manifest);
      expect(r, isA<ManifestSources>());
      final s = r as ManifestSources;
      expect(s.sources, hasLength(2));
      expect(s.sources.first, endsWith(p.join('rtl', 'uart_tx.v')));
      expect(s.top, 'uart_tx');
      expect(s.displayName, 'uart');
      expect(s.designId, cxpDesignIdForPath(d.dir));
    });

    test('source order is preserved — elaboration order matters', () {
      final d = writeDesign(
        '''
version: 1
design:
  sources:
    - rtl/defs.vh
    - rtl/top.v
''',
        files: ['rtl/defs.vh', 'rtl/top.v'],
      );
      final s = resolver.resolve(d.manifest) as ManifestSources;
      expect(s.sources.first, endsWith('defs.vh'));
      expect(s.sources.last, endsWith('top.v'));
    });
  });

  group('refusals name the fix', () {
    test('a manifest with neither sources nor a netlist', () {
      final d = writeDesign(
        'version: 1\nname: cdc\nartifacts:\n  waveform: d.vcd\n',
      );
      final r = resolver.resolve(d.manifest);
      expect(r, isA<ManifestUnusable>());
      final u = r as ManifestUnusable;
      expect(u.reason, ManifestUnusableReason.nothingToOpen);
      expect(u.detail, 'cdc');
    });

    test('an invalid manifest says so', () {
      final d = writeDesign('name: no version\n');
      final r = resolver.resolve(d.manifest);
      expect(r, isA<ManifestUnusable>());
      final u = r as ManifestUnusable;
      expect(u.reason, ManifestUnusableReason.invalid);
      expect(u.detail, contains('version'));
    });
  });

  group('the design id is the manifest directory, always', () {
    test('same id whether the netlist or the sources branch is taken', () {
      // Both branches must agree, or a design would cross-probe differently
      // depending on whether someone had run synthesis.
      final withNetlist = writeDesign(
        'version: 1\ndesign:\n  sources:\n    - a.v\nartifacts:\n  netlist: n.json\n',
        files: ['a.v', 'n.json'],
        design: 'shared_design',
      );
      final netlistId =
          (resolver.resolve(withNetlist.manifest) as ManifestNetlist).designId;

      File(p.join(withNetlist.dir, 'n.json')).deleteSync();
      File(
        withNetlist.manifest,
      ).writeAsStringSync('version: 1\ndesign:\n  sources:\n    - a.v\n');
      final sourcesId =
          (resolver.resolve(withNetlist.manifest) as ManifestSources).designId;

      expect(netlistId, sourcesId);
      expect(netlistId, cxpDesignIdForPath(withNetlist.dir));
    });
  });
}
