// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/remote/cxp/cxp_design_names.dart';

/// Where a formal property is: a `property` element's path, `<file>:<line>`
/// or `<file>:<line>:<col>`, relative to the project root and 1-based (CXP
/// §8.2).
@immutable
class PropertyLocation {
  /// Creates a location.
  const PropertyLocation({required this.file, required this.line, this.column});

  /// The project-relative file, with `/` separators.
  final String file;

  /// The 1-based line the property starts on.
  final int line;

  /// The 1-based column, when the sender gave one.
  final int? column;

  /// Parses a `property` element's path, or returns null when it is not one
  /// NetCrux will look up: no line, a line below 1, an absolute file, a file
  /// that climbs out of the project (`..`), or a NUL. A peer chose the
  /// string, so the parse refuses anything a relative project path is not.
  static PropertyLocation? parse(String path) {
    if (path.isEmpty || path.contains('\u0000')) return null;
    final match = _location.firstMatch(path);
    if (match == null) return null;
    final file = match.group(1)!.replaceAll(r'\', '/');
    final line = int.tryParse(match.group(2)!);
    final column = match.group(3) == null
        ? null
        : int.tryParse(match.group(3)!);
    if (line == null || line < 1) return null;
    if (file.isEmpty || file.startsWith('/') || _drive.hasMatch(file)) {
      return null;
    }
    final segments = file.split('/');
    if (segments.any((s) => s == '..' || s.isEmpty)) return null;
    return PropertyLocation(file: file, line: line, column: column);
  }

  static final RegExp _location = RegExp(r'^(.+?):(\d+)(?::(\d+))?$');
  static final RegExp _drive = RegExp('^[A-Za-z]:');
}

/// The one file of [sourceFiles] (the open design's own source list) that
/// [location] names, matched on whole trailing path segments. Null when none
/// or more than one does.
///
/// This is the containment rule for a property: NetCrux reads only a file
/// the user already opened as part of the design in the tab, never a path a
/// peer made up.
String? designSourceFor(List<String> sourceFiles, PropertyLocation location) {
  final wanted = location.file.split('/');
  String? found;
  for (final source in sourceFiles) {
    final parts = source.replaceAll(r'\', '/').split('/');
    if (parts.length < wanted.length) continue;
    final tail = parts.sublist(parts.length - wanted.length);
    var same = true;
    for (var i = 0; i < wanted.length; i++) {
      if (tail[i] != wanted[i]) {
        same = false;
        break;
      }
    }
    if (!same) continue;
    if (found != null && found != source) return null;
    found = source;
  }
  return found;
}

/// The longest property text read: a property is one statement, and a
/// statement longer than this is not one a person wrote by hand.
const int kPropertyTextMaxChars = 4096;

/// The most lines a property statement is read across.
const int kPropertyTextMaxLines = 40;

/// Reads the statement that starts on [line] of [file]: from that line up
/// to and including the first `;`, bounded by [kPropertyTextMaxLines] and
/// [kPropertyTextMaxChars]. Streams the file a line at a time, so a large
/// source is never held whole. Null when the file cannot be read or has
/// fewer lines.
Future<String?> readPropertyStatement(String file, int line) async {
  final buffer = StringBuffer();
  var number = 0;
  var taken = 0;
  try {
    final lines = File(
      file,
    ).openRead().transform(utf8.decoder).transform(const LineSplitter());
    await for (final text in lines) {
      number++;
      if (number < line) continue;
      buffer.writeln(text);
      taken++;
      if (text.contains(';') ||
          taken >= kPropertyTextMaxLines ||
          buffer.length >= kPropertyTextMaxChars) {
        break;
      }
    }
  } on Object {
    return null;
  }
  if (number < line) return null;
  final text = buffer.toString();
  return text.length > kPropertyTextMaxChars
      ? text.substring(0, kPropertyTextMaxChars)
      : text;
}

/// SystemVerilog words that read like identifiers in a property but are not
/// signals.
const Set<String> _kPropertyKeywords = <String>{
  'assert', 'assume', 'cover', 'restrict', 'property', 'endproperty', //
  'sequence', 'endsequence', 'disable', 'iff', 'posedge', 'negedge',
  'edge', 'and', 'or', 'not', 'if', 'else', 'always', 'always_ff',
  'always_comb', 'initial', 'final', 'begin', 'end', 'intersect', 'within',
  'throughout', 'first_match', 'strong', 'weak', 'until', 'until_with',
  's_until', 's_until_with', 'implies', 'nexttime', 's_nexttime',
  'eventually', 's_eventually', 'accept_on', 'reject_on', 'sync_accept_on',
  'sync_reject_on', 'case', 'endcase', 'default', 'logic', 'wire', 'reg',
  'bit', 'int', 'integer', 'unique', 'priority', 'inside', 'dist', 'with',
  'expect', 'let', 'module', 'endmodule',
};

/// Identifiers in a property statement that may name signals: plain
/// (`full`), escaped (`\cnt.q `, returned without the `\`) and hierarchical
/// (`u_sub.state`), in first-seen order and without repeats. System
/// functions (`$past`), keywords, numbers, and a statement label before a
/// `:` are not signals and are left out; the caller still keeps only the
/// names the design has.
List<String> propertyIdentifiers(String statement) {
  // Comments carry words that are not code.
  final code = statement
      .replaceAll(RegExp(r'//[^\n]*'), ' ')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  final out = <String>[];
  final seen = <String>{};
  for (final match in _identifier.allMatches(code)) {
    final escaped = match.group(1);
    final plain = match.group(2);
    final name = escaped ?? plain!;
    if (escaped == null) {
      // A label (`p_full: assert ...`), never a `::` scope operator.
      final after = code.substring(match.end).trimLeft();
      if (after.startsWith(':') && !after.startsWith('::')) {
        final before = code.substring(0, match.start).trimRight();
        if (before.isEmpty || before.endsWith(';')) continue;
      }
      if (_kPropertyKeywords.contains(name)) continue;
    }
    if (seen.add(name)) out.add(name);
  }
  return out;
}

/// An escaped identifier (group 1) or a plain, possibly hierarchical one
/// (group 2) that is not part of a `$` system name or a number literal.
final RegExp _identifier = RegExp(
  r"\\(\S+)|(?<![\w$'])([A-Za-z_][\w$]*(?:\.[A-Za-z_][\w$]*)*)",
);

/// The signals a property reads, placed in the design.
@immutable
class PropertyReads {
  /// Creates the reads.
  const PropertyReads({
    required this.scope,
    required this.local,
    required this.otherScopes,
  });

  /// The scope the property's module is shown in.
  final HierarchyNode scope;

  /// The property's names that are nets of [scope]'s module.
  final List<String> local;

  /// The property's hierarchical names (`u_sub.state`), which live in
  /// another scope: named, and traced only where they are the same net as
  /// one in [scope].
  final List<String> otherScopes;

  /// Whether the property names nothing this design has.
  bool get isEmpty => local.isEmpty && otherScopes.isEmpty;
}

/// Places a property's [identifiers] in [model]: finds the module whose
/// source span holds [location] (Yosys's `src` attribute on the module),
/// the scope to show it in ([current] when that is an instance of the
/// module, else the first instance in hierarchy order), and the names that
/// module has as nets.
///
/// Null when no module of the elaborated design was read from that line.
PropertyReads? placePropertyReads({
  required NetlistModel model,
  required HierarchyNode? current,
  required PropertyLocation location,
  required List<String> identifiers,
}) {
  final moduleName = _moduleAt(model, location);
  if (moduleName == null) return null;
  HierarchyNode? scope;
  if (current != null && current.moduleName == moduleName) {
    scope = current;
  } else {
    for (final node in hierarchyPreOrder(model)) {
      if (node.moduleName == moduleName) {
        scope = node;
        break;
      }
    }
  }
  if (scope == null) return null;
  final module = model.modules[moduleName]!;
  final local = <String>[];
  final other = <String>[];
  for (final name in identifiers) {
    if (findNetNamed(module, name) != null) {
      local.add(name);
    } else if (name.contains('.')) {
      other.add(name);
    }
  }
  return PropertyReads(scope: scope, local: local, otherScopes: other);
}

/// The module whose `src` span covers [location]'s line in its file.
String? _moduleAt(NetlistModel model, PropertyLocation location) {
  final wanted = location.file.split('/');
  for (final module in model.modules.values) {
    final src = module.attributes['src'];
    if (src == null) continue;
    for (final part in src.split('|')) {
      final match = _srcSpan.firstMatch(part.trim());
      if (match == null) continue;
      final file = match.group(1)!.replaceAll(r'\', '/').split('/');
      if (file.length < wanted.length) continue;
      final tail = file.sublist(file.length - wanted.length);
      if (tail.join('/') != wanted.join('/')) continue;
      final from = int.parse(match.group(2)!);
      final to = int.parse(match.group(3)!);
      if (location.line >= from && location.line <= to) return module.name;
    }
  }
  return null;
}

/// A Yosys `src` span, `file.v:3.1-20.10`.
final RegExp _srcSpan = RegExp(r'^(.+):(\d+)\.\d+-(\d+)\.\d+$');
