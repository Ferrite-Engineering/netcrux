// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: every Dart file under `lib/` is reachable from an entry point
// of this package, or is listed below with the reason it is not.
//
// ## The defect class this closes
//
// A file nothing imports still compiles, still analyzes clean, and keeps its
// own unit tests green: the tests import it directly, so they cannot notice
// that the application does not. `action_reachability_guard_test.dart` checks
// that an action DECLARES a surface; nothing checked that the code behind a
// surface is MOUNTED. A text tripwire (`expect(source, contains('Foo('))`)
// stays green after the file holding `Foo(` loses its last importer, and a
// doc comment asserting "the open-core build renders this pane" survives the
// same loss. This guard reads the import graph instead.
//
// ## What counts as reached
//
// The walk starts at every `lib/main*.dart` and `bin/*.dart` and follows
// `import`, `export` and `part` directives through this package — every
// branch of a conditional import (`if (dart.library.io) …`), because each
// branch is compiled on some platform. Directives are read from a parsed
// syntax tree, so an import inside a comment or a string does not count.
// Generated outputs (`*.g.dart`, `lib/l10n/generated/`) are not candidates:
// they are reached through the sources that generate them, and they do not
// exist until codegen has run.
//
// ## Why a file may be unreached, and how an exemption stays honest
//
// Exactly two consumers outside this package's entry point are legitimate,
// and every exemption names one. The guard then checks the consumer is real,
// so an exemption cannot outlive its reason:
//
//  * `_Consumer.proOverlay` — an open-core file the Pro overlay mounts or
//    implements against (a pane widget behind a no-op opener seam, a seam
//    provider only the overlay reads). Verified whenever this repository is
//    checked out as the overlay's submodule (`../lib/overrides.dart` exists),
//    which is how the overlay's CI runs these guards: the walk is repeated
//    from the overlay's own `lib/main*.dart`, and each such file must be
//    reached from there.
//  * `_Consumer.testsAndTools` — support code shared by tests or a fixture
//    regenerator that must import it through `package:` (the overlay's tests
//    among them). Verified by walking `test/`, `integration_test/` and
//    `tool/`.
//
// An exemption whose file is now reached from an entry point, whose file is
// gone, or whose consumer no longer imports it fails the guard: delete it.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Which consumer, other than this package's entry points, uses a file.
enum _Consumer {
  /// Imported by the Pro overlay's `lib/`.
  proOverlay,

  /// Imported only by tests, integration tests or tools.
  testsAndTools,
}

/// A `lib/` file no entry point of this package reaches, and why that is
/// correct.
class _Exemption {
  const _Exemption(this.file, this.consumer, this.reason);

  /// Package-relative path, forward slashes.
  final String file;

  /// Who imports it instead; the guard verifies this.
  final _Consumer consumer;

  /// Why the open-core entry point does not reach it.
  final String reason;
}

const _overlayPane =
    'A pane body for a Pro-tier analysis. The open core ships the widget and '
    'the no-op opener seam; the open-core build refuses the action with '
    '"requires NetCrux Pro", so only the Pro overlay mounts the pane, inside '
    'its docked panel.';

const _overlayActivitySeam =
    'Part of the switching-activity seam: the analysis interface, its value '
    'types and the per-tab state the Pro heat-map panel reads. The open core '
    'declares the seam; no open-core code reads it, because the only '
    'activity surface is the Pro panel.';

const _overlayNetlistShim =
    'A re-export shim for `crux_netlist`, kept so existing import paths '
    'resolve. The open core imports the sibling shims; the Pro overlay '
    'still imports this one.';

const _exemptions = <_Exemption>[
  // The switching-activity seam.
  _Exemption(
    'lib/domain/interfaces/activity_analysis_service.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/domain/models/activity/activity_analysis_options.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/domain/models/activity/activity_analysis_result.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/domain/models/activity/activity_color_scheme.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/domain/models/activity/activity_normalization.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/domain/models/activity/net_activity.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/domain/models/activity/waveform_time_range.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/features/activity/providers/activity_heatmap_state_provider.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),
  _Exemption(
    'lib/services/activity/activity_analysis_service_provider.dart',
    _Consumer.proOverlay,
    _overlayActivitySeam,
  ),

  // Pane bodies the Pro overlay's docked panels wrap.
  _Exemption(
    'lib/features/activity/widgets/activity_heatmap_pane.dart',
    _Consumer.proOverlay,
    _overlayPane,
  ),
  _Exemption(
    'lib/features/cdc/widgets/cdc_analysis_pane.dart',
    _Consumer.proOverlay,
    _overlayPane,
  ),
  _Exemption(
    'lib/features/diff/widgets/diff_pane.dart',
    _Consumer.proOverlay,
    _overlayPane,
  ),
  _Exemption(
    'lib/features/diff/widgets/diff_row_label.dart',
    _Consumer.proOverlay,
    'What a Netlist Diff View row shows, imported by the diff pane body, '
        'which only the Pro overlay mounts.',
  ),
  _Exemption(
    'lib/features/fsm/widgets/fsm_bubble_diagram_pane.dart',
    _Consumer.proOverlay,
    _overlayPane,
  ),
  _Exemption(
    'lib/features/reset_domain/widgets/reset_domain_analysis_pane.dart',
    _Consumer.proOverlay,
    _overlayPane,
  ),
  _Exemption(
    'lib/shared/widgets/revealing_list_view.dart',
    _Consumer.proOverlay,
    'The scroll-to-row list the CDC and reset-domain pane bodies are built '
        'on, so it is reachable only through those panes, which only the Pro '
        'overlay mounts.',
  ),
  _Exemption(
    'lib/features/source_pane/widgets/source_pane.dart',
    _Consumer.proOverlay,
    _overlayPane,
  ),

  // Other open-core API only the Pro overlay calls.
  _Exemption(
    'lib/features/viewer/services/analysis_selection_probe.dart',
    _Consumer.proOverlay,
    'The row-click bridge from an analysis panel to the schematic '
        'selection. Every analysis panel that has rows is a Pro panel.',
  ),
  _Exemption(
    'lib/domain/models/diff/diff_element_address.dart',
    _Consumer.proOverlay,
    'Parses a diff row path into module and element name for the diff '
        'pane and the Pro diff panel that routes Show in Schematic.',
  ),
  _Exemption(
    'lib/services/telemetry/netcrux_telemetry_vocabulary.dart',
    _Consumer.proOverlay,
    'Closed vocabularies for events recorded by Pro call sites. Declared in '
        'the open core so the event catalog and its conformance test, which '
        'cannot see the overlay, own the one declaration both sides use.',
  ),
  _Exemption(
    'lib/services/workspace/active_project_file_path_provider.dart',
    _Consumer.proOverlay,
    'The active tab project-file path, read by the Pro custom-symbol '
        'registry for its per-project store. No open-core feature keeps '
        'per-project state.',
  ),
  _Exemption(
    'lib/shared/widgets/netcrux_edition_badge.dart',
    _Consumer.proOverlay,
    'States the edition in force and renders nothing at open core, so the '
        'open core does not mount it; the Pro overlay mounts it last in the '
        'status bar trailing slot.',
  ),
  _Exemption(
    'lib/domain/models/netlist/cell.dart',
    _Consumer.proOverlay,
    _overlayNetlistShim,
  ),
  _Exemption(
    'lib/domain/models/netlist/port.dart',
    _Consumer.proOverlay,
    _overlayNetlistShim,
  ),

  // Support code for tests and tools.
  _Exemption(
    'lib/services/telemetry/telemetry_event_catalog.dart',
    _Consumer.testsAndTools,
    'The pinned event catalog, read only by the conformance and emission '
        'tests. It lives under lib/ because the Pro overlay tests check '
        'their events against it through `package:`, which cannot reach '
        'test/.',
  ),
  _Exemption(
    'lib/services/yosys/netlist_golden.dart',
    _Consumer.testsAndTools,
    'Computes the structural golden companion of a parsed netlist, shared '
        'by the golden test and tool/generate_netlist_fixtures.dart, which '
        'regenerates the companions.',
  ),
];

void main() {
  final self = _packageName('.');
  final entries = _entryPoints('.');
  final reached = _relativeTo(
    '.',
    _reachable(entries, <String, String>{self: 'lib'}),
  );
  final candidates = _libFiles('.');
  final exempt = <String, _Exemption>{
    for (final e in _exemptions) e.file: e,
  };

  test('the walk is not vacuous', () {
    expect(entries, isNotEmpty, reason: 'no lib/main*.dart entry point');
    expect(
      candidates.where(reached.contains).length,
      greaterThan(300),
      reason: 'the walk reached almost nothing — directive parsing broke',
    );
    expect(reached, contains('lib/app.dart'));
    // A conditional-import branch is compiled on some platform, so it counts.
    expect(reached, contains('lib/services/layout/elk_web_solver_web.dart'));
    expect(reached, contains('lib/shared/platform/reveal_tab_file_io.dart'));
  });

  test('every lib file is reachable from an entry point, or says why not', () {
    final offenders = <String>[
      for (final file in candidates)
        if (!reached.contains(file) && !exempt.containsKey(file))
          '$file (${_lineCount(file)} lines)',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'No entry point of this package imports these files, directly or '
          'transitively:\n  ${offenders.join('\n  ')}\n\n'
          'A file nothing imports is built, tested and shipped by nobody — '
          'its tests import it directly, so they stay green. Delete it, '
          'wire it, or, when another consumer genuinely owns it, add an '
          '_Exemption naming that consumer and the reason.',
    );
  });

  test('every exemption is still needed, and its consumer still uses it', () {
    final stale = <String>[];
    final seen = <String>{};
    for (final e in _exemptions) {
      if (!seen.add(e.file)) stale.add('${e.file}: listed twice');
      if (!File(e.file).existsSync()) {
        stale.add('${e.file}: no longer exists');
      } else if (reached.contains(e.file)) {
        stale.add('${e.file}: now reached from an entry point');
      }
    }

    // Tests, integration tests and tools, as one more set of entry points.
    final supportRoots = <String>[
      for (final dir in const <String>['test', 'integration_test', 'tool'])
        ..._dartFilesUnder(dir),
    ];
    final supportReached = _relativeTo(
      '.',
      _reachable(supportRoots, <String, String>{self: 'lib'}),
    );
    for (final e in _exemptions) {
      if (e.consumer == _Consumer.testsAndTools &&
          !supportReached.contains(e.file)) {
        stale.add('${e.file}: no test, integration test or tool imports it');
      }
    }

    // Checked out as the Pro overlay's submodule — which is how the overlay's
    // CI runs these guards — the overlay-owned exemptions are verified
    // against the overlay's own entry points. A standalone checkout cannot
    // see the overlay, so there the check above is the whole of it.
    final overlay = _overlayCheckout();
    if (overlay != null) {
      final overlayReached = _relativeTo(
        '.',
        _reachable(_entryPoints(overlay.root), <String, String>{
          self: 'lib',
          overlay.package: p.join(overlay.root, 'lib'),
        }),
      );
      for (final e in _exemptions) {
        if (e.consumer == _Consumer.proOverlay &&
            !overlayReached.contains(e.file)) {
          stale.add('${e.file}: the Pro overlay no longer reaches it');
        }
      }
    }

    expect(
      stale,
      isEmpty,
      reason:
          'An exemption has outlived its reason; delete it (and the file, '
          'when nothing uses it any more):\n  ${stale.join('\n  ')}',
    );
  });

  group('the walk resolves the shapes it must', () {
    late Directory root;
    late Set<String> fixtureReached;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('import_walk_shapes_');
      void write(String path, String body) {
        File(p.join(root.path, 'lib', path))
          ..createSync(recursive: true)
          ..writeAsStringSync(body);
      }

      write('main.dart', '''
import 'package:demo/a.dart';
import 'package:other/unrelated.dart';
import 'dart:io';
// import 'package:demo/commented_out.dart';
/* import 'package:demo/block_commented.dart'; */
const text = "import 'package:demo/in_a_string.dart';";
void main() {}
''');
      write('a.dart', '''
export 'b.dart' show B;
import 'c_stub.dart'
    if (dart.library.io) 'c_io.dart'
    if (dart.library.js_interop) 'c_web.dart';
part 'a_part.dart';
''');
      write('a_part.dart', "part of 'a.dart';\n");
      write('b.dart', "import 'sub/d.dart';\nclass B {}\n");
      write('sub/d.dart', "import '../e.dart';\n");
      for (final leaf in const <String>[
        'c_stub.dart',
        'c_io.dart',
        'c_web.dart',
        'e.dart',
        'orphan.dart',
        'commented_out.dart',
        'block_commented.dart',
        'in_a_string.dart',
      ]) {
        write(leaf, '');
      }
      fixtureReached = _relativeTo(
        root.path,
        _reachable(
          <String>[p.join(root.path, 'lib', 'main.dart')],
          <String, String>{'demo': p.join(root.path, 'lib')},
        ),
      );
    });

    tearDownAll(() => root.deleteSync(recursive: true));

    test('imports, exports, parts and every conditional branch', () {
      expect(
        fixtureReached,
        unorderedEquals(<String>[
          'lib/main.dart',
          'lib/a.dart',
          'lib/a_part.dart',
          'lib/b.dart',
          'lib/c_stub.dart',
          'lib/c_io.dart',
          'lib/c_web.dart',
          'lib/sub/d.dart',
          'lib/e.dart',
        ]),
      );
    });

    test('commented-out, quoted and unimported files stay unreached', () {
      for (final unreached in const <String>[
        'lib/orphan.dart',
        'lib/commented_out.dart',
        'lib/block_commented.dart',
        'lib/in_a_string.dart',
      ]) {
        expect(fixtureReached, isNot(contains(unreached)));
      }
    });
  });
}

/// Every file reachable from [entries] through `import`, `export` and `part`,
/// following every branch of a conditional directive.
///
/// [packageRoots] maps a package name to its `lib/` directory; a `package:`
/// URI naming any other package is external and not followed. Returns
/// absolute, normalized paths. A target that does not exist (generated output
/// before codegen) is recorded but not read.
Set<String> _reachable(
  Iterable<String> entries,
  Map<String, String> packageRoots,
) {
  final roots = <String, String>{
    for (final e in packageRoots.entries)
      e.key: p.normalize(p.absolute(e.value)),
  };
  final reached = <String>{};
  final pending = <String>[
    for (final e in entries) p.normalize(p.absolute(e)),
  ];
  while (pending.isNotEmpty) {
    final file = pending.removeLast();
    if (!reached.add(file)) continue;
    final source = File(file);
    if (!source.existsSync()) continue;
    final unit = parseString(
      content: source.readAsStringSync(),
      path: file,
      throwIfDiagnostics: false,
    ).unit;
    for (final directive in unit.directives) {
      final uris = <String?>[
        if (directive is NamespaceDirective) ...<String?>[
          directive.uri.stringValue,
          for (final c in directive.configurations) c.uri.stringValue,
        ],
        if (directive is PartDirective) directive.uri.stringValue,
      ];
      for (final uri in uris.nonNulls) {
        final target = _resolve(uri, file, roots);
        if (target != null) pending.add(target);
      }
    }
  }
  return reached;
}

/// The file [uri] names when written in [from], or null when it lies outside
/// every package in [roots].
String? _resolve(String uri, String from, Map<String, String> roots) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final root = roots[rest.substring(0, slash)];
    if (root == null) return null;
    return p.normalize(p.join(root, rest.substring(slash + 1)));
  }
  return p.normalize(p.join(p.dirname(from), uri));
}

/// Every `lib/main*.dart` and `bin/*.dart` under [packageRoot].
List<String> _entryPoints(String packageRoot) => <String>[
  for (final f in _dartFilesUnder(p.join(packageRoot, 'lib'), recursive: false))
    if (p.basename(f).startsWith('main')) f,
  ..._dartFilesUnder(p.join(packageRoot, 'bin'), recursive: false),
];

/// Every hand-written `lib/**.dart` file, package-relative.
List<String> _libFiles(String packageRoot) => <String>[
  for (final f in _relativeTo(
    packageRoot,
    _dartFilesUnder(p.join(packageRoot, 'lib')),
  ))
    if (!_isGenerated(f)) f,
]..sort();

bool _isGenerated(String relative) =>
    relative.endsWith('.g.dart') ||
    relative.endsWith('.freezed.dart') ||
    relative.startsWith('lib/l10n/generated/');

List<String> _dartFilesUnder(String dir, {bool recursive = true}) {
  final d = Directory(dir);
  if (!d.existsSync()) return const <String>[];
  return <String>[
    for (final e in d.listSync(recursive: recursive))
      if (e is File && e.path.endsWith('.dart')) e.path,
  ];
}

/// [paths] relative to [root], with forward slashes, for paths inside it.
Set<String> _relativeTo(String root, Iterable<String> paths) {
  final base = p.normalize(p.absolute(root));
  return <String>{
    for (final path in paths)
      if (p.isWithin(base, p.normalize(p.absolute(path))))
        p.posix.joinAll(p.split(p.relative(p.absolute(path), from: base))),
  };
}

String _packageName(String packageRoot) {
  final match = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync());
  if (match == null) fail('$packageRoot/pubspec.yaml declares no name');
  return match.group(1)!;
}

/// The Pro overlay this repository is checked out inside, if any.
({String root, String package})? _overlayCheckout() {
  const root = '..';
  if (!File(p.join(root, 'lib', 'overrides.dart')).existsSync() ||
      !File(p.join(root, 'pubspec.yaml')).existsSync()) {
    return null;
  }
  return (root: root, package: _packageName(root));
}

int _lineCount(String file) => File(file).readAsLinesSync().length;
