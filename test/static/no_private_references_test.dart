// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: nothing in this public repository points at a private one.
//
// NetCrux open core is published; the planning documents, the Pro overlay,
// the websites and the release infrastructure are not. A reference into any of
// them resolves for exactly one reader — someone who already has access — and
// for everyone else it is a dead end that also advertises what they cannot
// see. Such references accumulate naturally while a project is planned in one
// place and built in another, so a sweep that removes them decays the first
// time someone writes "per the plan §5.2" again. This guard makes the sweep
// permanent.
//
// Every tracked text file is scanned (`git ls-files`), except generated
// localizations, build output, the vendored elkjs bundle, the `crux-shared`
// submodule, captured third-party RTL, and this file. Four classes fail:
//
//  1. Private repository names — the planning repository, the Pro overlay
//     repositories, the websites, the update and commerce services.
//  2. Plan citations — named plans, plan phases, consistency rulings and
//     campaigns: vocabulary that only means something inside those documents.
//  3. Tracking identifiers — work-stream, prompt, audit-finding and issue
//     numbers from trackers this repository cannot link to.
//  4. Unattributed section marks. A `§` must name the document it points
//     into, and a mark into one of this repository's own numbered documents
//     must name a section that exists. A bare `§5.2.6` is exactly what a
//     private plan citation looks like once its document name is deleted.
//
// The replacement for a reference is the reason itself, stated inline; a
// document in this repository cited by name and section; or a public page
// (`https://edacrux.app/…`, `https://docs.netcrux.app/…`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One failing class: a name for the report and the pattern that detects it.
class _Rule {
  const _Rule(this.name, this.pattern, this.advice);

  final String name;
  final RegExp pattern;
  final String advice;
}

final _rules = <_Rule>[
  _Rule(
    'private repository',
    RegExp(
      r'(?<![\w.-])edacrux(?![\w-]|\.app)'
      r'|\b(?:wavecrux|netcrux|lintcrux|simcrux)-pro\b'
      r'|\b(?:wavecrux|netcrux|lintcrux|simcrux|edacrux|ferrite)-website\b'
      r'|\*-website\b'
      r'|\b(?:crux-updates|crux-commerce|wavecrux-updates|vcd_parser)\b'
      r'|\b(?:pulsecrux|PulseCrux|[Aa]nneal)\b'
      // The beta repos close at the open-core flip (L4), so a
      // reference to one is a link that dies on flip day.
      r'|\b(?:wavecrux|netcrux|lintcrux|simcrux)-beta\b'
      r'|\b(?:private planning|planning|docs) repo(?:sitory)?\b',
    ),
    'Name the Pro overlay as "the Pro overlay" and link public pages; a '
        'private repository is not referenced at all.',
  ),
  _Rule(
    'plan citation',
    RegExp(
      r'\b(?:[Pp]roject|[Ss]uite|[Ss]trategic|[Ee]cosystem|[Rr]obustness|'
      r'[Ll]aunch|[Bb]usiness)[- ][Pp]lan\b'
      r'|-project-plan\b|-and-performance-plan\b|ECOSYSTEM_PLAN|SUITE_PLAN'
      r'|\b[Cc]onsistency[- ](?:charter|rulings?|pass)\b'
      r'|\bruling [A-Z]\d+\b|\bR-[A-Z]+\d*-\d+\b'
      r'|\b[Pp]lan\s*§|\b[Cc]ampaign\b'
      r'|\b[Pp]hase[ -]?\d',
    ),
    'State the reason the plan gave, in present tense; plan phases and '
        'sections mean nothing to a reader of this repository.',
  ),
  _Rule(
    'tracking identifier',
    RegExp(
      r'\bWS-?\d+\b|\bWS-[A-Z]\b|\bP\d{2}\b|\bF-\d{2}\b|\bR\d-\d+\b'
      r'|\bCS\d{1,2}\b|\bR-CS\w*|\bPR \d+\b|\b[Ii]ssue[- ]#?\d+\b'
      r'|\baudit [A-Z]-\d+',
    ),
    'Describe the behaviour or defect instead of citing the tracker row.',
  ),
];

/// A `§` followed by the section it names.
final _sectionMark = RegExp(r'§+\s?([A-Z]?\d+(?:\.\d+)*)');

/// A numbered Markdown heading: `## 4.1 …`, `### 9.2. …`.
final _numberedHeading = RegExp(r'^#{1,6}\s+(\d+(?:\.\d+)*)\.?\s');

const _architecture = 'docs/ARCHITECTURE.md';
const _guide = 'verification/VERIFICATION_GUIDE.md';

/// A document a `§` may point into, recognized by the words just before it.
/// [headingsOf] is the repository document whose numbered headings the mark
/// must resolve against, or null for a document outside this repository.
class _Qualifier {
  const _Qualifier(this.pattern, this.headingsOf);

  final RegExp pattern;
  final String? headingsOf;
}

final _qualifiers = <_Qualifier>[
  // A sibling product's document. Listed first so that "WaveCrux
  // ARCHITECTURE.md §8" is read as WaveCrux's manual, not this one.
  _Qualifier(
    RegExp(
      r"\b(?:WaveCrux|LintCrux|SimCrux|wavecrux|lintcrux|simcrux)(?:'s)?"
      r'(?:[\s`/]*[\w./-]*(?:ARCHITECTURE|VERIFICATION_\w+)(?:\.md)?'
      r'|\s+(?:manual|checklist|guide))?',
    ),
    null,
  ),
  _Qualifier(RegExp(r'\bARCHITECTURE(?:\.md)?'), _architecture),
  _Qualifier(
    RegExp(r'\bVERIFICATION_GUIDE(?:\.md)?|\b[Vv]erification [Gg]uide\b'),
    _guide,
  ),
  _Qualifier(RegExp(r'\bGuide\b'), _guide),
  _Qualifier(RegExp(r'\bNOTICES\b'), null),
  _Qualifier(RegExp(r'\bCXP\b|edacrux\.app/cxp'), null),
  _Qualifier(
    RegExp(
      r'\b(?:EPL|MPL|L?GPL|AGPL|BSD|MIT|Apache|EAR|CFR|RFC|IEEE|ISO|'
      r'Agreement|[Ll]icen[cs]e)\b',
    ),
    null,
  ),
];

/// Documents whose own `§` marks point into a numbered repository document
/// without naming it: the document itself, or the guide a companion follows.
/// A null value means the marks are the document's own, with headings in a
/// format this guard does not parse.
const Map<String, String?> _selfNumberedDocs = {
  _architecture: _architecture,
  _guide: _guide,
  'verification/VERIFICATION_CHECKLIST.md': _guide,
  'integration_test/PENDING.md': _guide,
  'NOTICES': null,
};

/// Path prefixes that are not first-party prose.
const _excludedPrefixes = <String>[
  'crux-shared/', // the submodule: public, with its own guard
  'lib/l10n/generated/', // gen-l10n output
  'build/',
  'docs-site/site/', // mkdocs output
  'assets/elk/', // the vendored elkjs bundle
  // The vendored elkrs port: ELK Layered's "Phase 1" to "Phase 5" in its
  // comments are the algorithm's phases, not sections of a private plan.
  'native/vendor/',
];

/// Captured fixtures are third-party RTL and the netlists elaborated from it;
/// only their provenance notes are ours.
bool _isCapturedThirdParty(String path) =>
    path.contains('/captured/') && !path.endsWith('PROVENANCE.md');

const _thisFile = 'test/static/no_private_references_test.dart';

const _binaryExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.ico',
  '.icns',
  '.webp',
  '.gz',
  '.zip',
  '.ttf',
  '.otf',
  '.woff',
  '.woff2',
  '.riv',
  '.pdf',
  '.jar',
  '.so',
  '.dylib',
  '.dll',
  '.exe',
  '.bin',
  '.a',
  '.o',
  '.car',
  '.keystore',
};

/// A finding that is correct as written, and why. Keyed by the exact file and
/// the exact matched text, so an entry cannot silence anything else.
class _Allowance {
  const _Allowance(this.path, this.match, this.reason);

  final String path;
  final String match;
  final String reason;
}

// Empty. The allowance exists for a shipped executable or app whose name
// happens to look like a repository name — the `lintcrux-pro` CLI, say.
// NetCrux's own Pro binary is `netcrux_pro`, which no rule matches, so nothing
// here needs one. An entry that stops matching fails the stale-entry test.
const _allowlist = <_Allowance>[];

/// One offending occurrence.
class _Finding {
  const _Finding(this.path, this.line, this.rule, this.match);

  final String path;
  final int line;
  final String rule;
  final String match;

  @override
  String toString() => '$path:$line — $rule: "$match"';
}

/// Section numbers of the numbered headings in [source].
Set<String> _headingNumbers(String source) => {
  for (final line in const LineSplitter().convert(source))
    if (_numberedHeading.firstMatch(line) case final m?) m.group(1)!,
};

/// The qualifier nearest the end of [window], preferring the earlier-listed
/// qualifier on a tie, or null when [window] names no document.
_Qualifier? _nearestQualifier(String window) {
  _Qualifier? best;
  var bestEnd = -1;
  for (final qualifier in _qualifiers) {
    for (final m in qualifier.pattern.allMatches(window)) {
      if (m.end > bestEnd) {
        best = qualifier;
        bestEnd = m.end;
      }
    }
  }
  return best;
}

/// Scans one file's [content]. [headings] maps each numbered repository
/// document to its heading numbers.
List<_Finding> _scan(
  String path,
  String content,
  Map<String, Set<String>> headings,
) {
  final findings = <_Finding>[];
  final lines = const LineSplitter().convert(content);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final rule in _rules) {
      for (final m in rule.pattern.allMatches(line)) {
        findings.add(_Finding(path, i + 1, rule.name, m.group(0)!));
      }
    }
    for (final m in _sectionMark.allMatches(line)) {
      final number = m.group(1)!;
      final window =
          '${i == 0 ? '' : lines[i - 1]}\n'
          '${line.substring(0, m.start)}';
      final qualifier = _nearestQualifier(window);
      final String? resolveAgainst;
      if (qualifier != null) {
        resolveAgainst = qualifier.headingsOf;
      } else if (_selfNumberedDocs.containsKey(path)) {
        resolveAgainst = _selfNumberedDocs[path];
      } else {
        findings.add(
          _Finding(path, i + 1, 'unattributed section mark', m.group(0)!),
        );
        continue;
      }
      if (resolveAgainst == null) continue;
      if (headings[resolveAgainst]?.contains(number) ?? false) continue;
      findings.add(
        _Finding(
          path,
          i + 1,
          'section mark with no such heading in $resolveAgainst',
          m.group(0)!,
        ),
      );
    }
  }
  return findings;
}

List<String> _trackedTextFiles() {
  final result = Process.runSync('git', ['ls-files', '-z']);
  if (result.exitCode != 0) {
    fail('git ls-files failed: ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\x00')
      .where((p) => p.isNotEmpty)
      .where((p) => !_excludedPrefixes.any(p.startsWith))
      .where((p) => !_isCapturedThirdParty(p))
      .where((p) => p != _thisFile)
      .where((p) => !_binaryExtensions.any(p.toLowerCase().endsWith))
      .toList()
    ..sort();
}

Map<String, Set<String>> _repositoryHeadings() => {
  for (final doc in {_architecture, _guide})
    doc: _headingNumbers(File(doc).readAsStringSync()),
};

bool _isAllowed(_Finding f) =>
    _allowlist.any((a) => a.path == f.path && a.match == f.match);

List<_Finding> _scanRepository() {
  final headings = _repositoryHeadings();
  final findings = <_Finding>[];
  for (final path in _trackedTextFiles()) {
    final file = File(path);
    if (!file.existsSync()) continue; // a deleted but still-indexed file
    final bytes = file.readAsBytesSync();
    if (bytes.contains(0)) continue;
    final String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      continue;
    }
    findings.addAll(_scan(path, content, headings));
  }
  return findings;
}

void main() {
  test('no tracked file references a private repository, plan or tracker', () {
    final offenders = _scanRepository()
        .where((f) => !_isAllowed(f))
        .map((f) => f.toString())
        .toList();
    expect(
      offenders,
      isEmpty,
      reason:
          'A public file points at something only the private side can see. '
          "State the reason inline, cite this repository's own documents by "
          'name and section, or link a public page.\n'
          '${_rules.map((r) => '  ${r.name}: ${r.advice}').join('\n')}\n'
          '  section marks: name the document — `docs/ARCHITECTURE.md` §6.2, '
          'Verification Guide §4.1.3, CXP §6.2.\n'
          '${offenders.join('\n')}',
    );
  });

  test('every allowlist entry still suppresses a finding', () {
    final findings = _scanRepository();
    final stale = _allowlist
        .where(
          (a) => !findings.any((f) => f.path == a.path && f.match == a.match),
        )
        .map((a) => '${a.path}: "${a.match}" (${a.reason})')
        .toList();
    expect(
      stale,
      isEmpty,
      reason:
          'An allowance outlived the text it excused; delete it.\n'
          '${stale.join('\n')}',
    );
  });

  group('the scanner catches each class', () {
    final headings = {
      _architecture: {'6', '6.2', '10'},
      _guide: {'4', '4.1', '4.1.3'},
    };
    List<String> rulesFor(String line, {String path = 'lib/x.dart'}) =>
        _scan(path, line, headings).map((f) => f.rule).toList();

    test('private repository names', () {
      for (final line in [
        'see edacrux/docs/plans/netcrux/plan.md',
        'lives in the `netcrux-pro` overlay',
        'copied into netcrux-website/img/',
        'the ingestion Worker (crux-updates/telemetry)',
        'in the private planning repo',
        'filed as netcrux-beta issue #12',
      ]) {
        expect(rulesFor(line), contains('private repository'), reason: line);
      }
    });

    test('plan citations', () {
      for (final line in [
        'per the NetCrux project plan',
        'a Phase 4 seam',
        'forward-compatible with pre-Phase-4 sessions',
        'suite consistency pass, ruling D3',
        'see the plan §8.10',
      ]) {
        expect(rulesFor(line), contains('plan citation'), reason: line);
      }
    });

    test('tracking identifiers', () {
      for (final line in [
        'the WS4 isolate-offload seam',
        'Cross-Probe Increment WS-E',
        'the P47 regression',
        'audit F-17',
        'fixed in PR 4',
        'the issue #38 recovery path',
      ]) {
        expect(rulesFor(line), contains('tracking identifier'), reason: line);
      }
    });

    test('section marks must name a document that has the section', () {
      expect(rulesFor('powering the §5.3.4 heatmap'), [
        'unattributed section mark',
      ]);
      expect(
        rulesFor('the layer matrix (`docs/ARCHITECTURE.md` §6.2)'),
        <String>[],
      );
      expect(rulesFor('see `docs/ARCHITECTURE.md` §7'), [
        'section mark with no such heading in docs/ARCHITECTURE.md',
      ]);
      expect(rulesFor("(Guide §4.1.3)'"), <String>[]);
      expect(rulesFor('WaveCrux ARCHITECTURE.md §8.8'), <String>[]);
      expect(rulesFor('EPL-2.0 §3.1(b)'), <String>[]);
      expect(rulesFor('CXP §6.2'), <String>[]);
      expect(
        rulesFor('- [x] §4.1.3', path: 'integration_test/PENDING.md'),
        <String>[],
      );
      expect(rulesFor('- [x] §5.2.6', path: 'integration_test/PENDING.md'), [
        'section mark with no such heading in $_guide',
      ]);
    });

    test('public names and URLs pass', () {
      for (final line in [
        'https://edacrux.app/telemetry',
        'the `.netcrux-project` file',
        'the edacrux-edu-packs repo',
        'the Pro overlay registers a controller',
        'NetCrux Pro',
        'crux-shared/packages/crux_yosys',
        'simulated annealing',
      ]) {
        expect(rulesFor(line), isEmpty, reason: line);
      }
    });
  });
}
