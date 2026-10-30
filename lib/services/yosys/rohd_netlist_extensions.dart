// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show File;

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';

/// The `creator` a netlist written by ROHD's `NetlistSynthesizer` carries.
///
/// ROHD (the hardware framework written in Dart) exports a superset of
/// Yosys JSON. The extensions are only meaningful for a document with this
/// creator, and none of them is required to read the netlist: a file
/// without them, or with fields this reader does not know, opens as plain
/// Yosys JSON.
const String rohdNetlistCreator = 'NetlistSynthesizer (rohd)';

/// Cell types ROHD writes for a procedural block (`Combinational` and
/// `Sequential`). They are cells with their own pins and no module
/// definition in the document, which in any other netlist would be an
/// instance of a missing module.
const Set<String> rohdBlockCellTypes = <String>{'Combinational', 'Sequential'};

/// The module attribute that holds the source trace in the document.
const String rohdSourceTraceKey = 'rohd.src_trace';

/// The net attribute [RohdNetlistReading] writes to describe a structured or
/// array type.
const String rohdTypeAttribute = 'rohd.type';

/// Whether [creator] names ROHD's netlist writer.
bool isRohdCreator(String creator) =>
    creator.startsWith('NetlistSynthesizer (rohd');

/// One entry of a ROHD source trace: the Dart file (an index into the
/// document's `files` array), line and column that created something.
@immutable
class RohdSourceFrame {
  /// Creates a frame.
  const RohdSourceFrame(this.file, this.line, this.column);

  /// Parses `fileIndex:line[:column]`, or returns `null` for anything else.
  static RohdSourceFrame? tryParse(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final file = int.tryParse(parts[0]);
    final line = int.tryParse(parts[1]);
    final column = parts.length == 3 ? int.tryParse(parts[2]) : null;
    if (file == null || file < 0 || line == null || line < 1) return null;
    if (parts.length == 3 && (column == null || column < 1)) return null;
    return RohdSourceFrame(file, line, column);
  }

  /// Index into the document's top-level `files` array.
  final int file;

  /// 1-based line.
  final int line;

  /// 1-based column, when the trace recorded one.
  final int? column;

  @override
  bool operator ==(Object other) =>
      other is RohdSourceFrame &&
      other.file == file &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(file, line, column);

  @override
  String toString() => 'RohdSourceFrame($file:$line:$column)';
}

/// The `rohd.src_trace` of one module: for each local signal and instance
/// name, the frames of the stack that created it, innermost first.
///
/// Only the first two frames of each are kept: the innermost is where the
/// thing was created, the next is who asked for it, which is where a
/// sub-module is instantiated.
@immutable
class RohdSourceTrace {
  /// Creates a trace.
  const RohdSourceTrace({required this.signals, required this.instances});

  /// Reads the attribute value, or returns `null` when it is not an object
  /// or holds no usable frame. A malformed entry is dropped, not an error.
  static RohdSourceTrace? tryParse(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final signals = _readFrames(raw['signals']);
    final instances = _readFrames(raw['instances']);
    if (signals.isEmpty && instances.isEmpty) return null;
    return RohdSourceTrace(signals: signals, instances: instances);
  }

  static Map<String, List<RohdSourceFrame>> _readFrames(Object? raw) {
    if (raw is! Map<Object?, Object?>) return const {};
    final out = <String, List<RohdSourceFrame>>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! List<Object?>) continue;
      final frames = <RohdSourceFrame>[];
      for (final item in value) {
        final frame = RohdSourceFrame.tryParse(item);
        if (frame != null) frames.add(frame);
        if (frames.length == 2) break;
      }
      if (frames.isNotEmpty) out[key] = frames;
    }
    return out;
  }

  /// Frames by signal (net or port) name.
  final Map<String, List<RohdSourceFrame>> signals;

  /// Frames by instance (cell) name.
  final Map<String, List<RohdSourceFrame>> instances;
}

/// Maps a source file as ROHD recorded it to the file to open.
typedef RohdSourceFileResolver = String Function(String recorded);

/// A [RohdSourceFileResolver] for a netlist read from [netlistPath].
///
/// ROHD records a path relative to the package root it was given, and the
/// netlist does not say where that was. The path is therefore looked for
/// beside the netlist and in each directory above it, and the first hit is
/// returned as an absolute path; a path that is absolute, or found nowhere,
/// is returned as it was recorded.
RohdSourceFileResolver rohdSourceResolverFor(
  String netlistPath, {
  bool Function(String path)? exists,
  int levels = 8,
}) {
  final found = exists ?? (String path) => File(path).existsSync();
  // Looked for from the directory the netlist is in, so it is made absolute
  // first; the path that is returned is then one to open as it stands.
  final absolute = exists == null
      ? File(netlistPath).absolute.path
      : netlistPath;
  final cache = <String, String>{};
  final separator = absolute.contains(r'\') && !absolute.contains('/')
      ? r'\'
      : '/';
  final start = _parentOf(absolute, separator);
  return (recorded) {
    if (_isAbsolute(recorded)) return recorded;
    return cache.putIfAbsent(recorded, () {
      var dir = start;
      for (var i = 0; i < levels && dir != null; i++) {
        final candidate = _join(dir, recorded, separator);
        if (found(candidate)) return candidate;
        dir = _parentOf(dir, separator);
      }
      return recorded;
    });
  };
}

bool _isAbsolute(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

String? _parentOf(String path, String separator) {
  final cut = path.lastIndexOf(separator);
  if (cut <= 0) return null;
  return path.substring(0, cut);
}

String _join(String dir, String relative, String separator) {
  var tail = relative;
  while (tail.startsWith('./')) {
    tail = tail.substring(2);
  }
  return '$dir$separator${separator == '/' ? tail : tail.replaceAll('/', separator)}';
}

/// What a reader collects from the ROHD extensions of one document, and the
/// last step that turns it into things the rest of NetCrux already reads.
///
/// A reader hands each module's `attributes`, each net's JSON and the
/// top-level `files` array to the matching method as it meets them, in
/// whatever order the document has them, then passes the finished model to
/// [finish]. Nothing here is needed to open the netlist, so every method
/// ignores what it does not recognise.
///
/// The extensions land as follows:
///
/// - `rohd.src_trace` becomes the standard `src` attribute
///   (`file.dart:line.column`) on the cells and nets it names, so the source
///   pane, search and cross-probing treat a Dart location as they treat a
///   Yosys one. The module attribute itself is dropped once it is read.
/// - `logic_type` on a net becomes a `rohd.type` attribute, a one-line
///   description of a structured or array type.
class RohdNetlistReading {
  /// Creates a collector. [resolveFile] maps a recorded source path to the
  /// path to open; without it the path is kept as recorded.
  RohdNetlistReading({this.resolveFile});

  /// See [rohdSourceResolverFor].
  final RohdSourceFileResolver? resolveFile;

  List<String> _files = const <String>[];
  final Map<String, RohdSourceTrace> _traces = <String, RohdSourceTrace>{};

  /// Records the document's top-level `files` array. Anything that is not a
  /// list of strings is ignored.
  void readFiles(Object? raw) {
    if (raw is! List<Object?>) return;
    _files = <String>[
      for (final item in raw)
        if (item is String) item else '',
    ];
  }

  /// Records the source trace in [attributes], the `attributes` object of
  /// module [module], and returns the attributes without it.
  Map<String, Object?> readModuleAttributes(
    String module,
    Map<String, Object?> attributes,
  ) {
    if (!attributes.containsKey(rohdSourceTraceKey)) return attributes;
    final trace = RohdSourceTrace.tryParse(attributes[rohdSourceTraceKey]);
    if (trace != null) _traces[module] = trace;
    return <String, Object?>{
      for (final entry in attributes.entries)
        if (entry.key != rohdSourceTraceKey) entry.key: entry.value,
    };
  }

  /// Adds a `rohd.type` attribute to [net], the JSON of one netname, when
  /// its `logic_type` describes a structure or an array.
  void readNet(Map<String, Object?> net) {
    final description = describeRohdLogicType(net['logic_type']);
    if (description == null) return;
    final attributes = net['attributes'];
    if (attributes == null) {
      net['attributes'] = <String, Object?>{rohdTypeAttribute: description};
    } else if (attributes is Map<String, Object?>) {
      attributes[rohdTypeAttribute] = description;
    }
  }

  /// [readModuleAttributes] and [readNet] over a whole decoded module, for a
  /// reader that holds one. Returns the module JSON to build the model from.
  Map<String, Object?> readModule(String module, Map<String, Object?> json) {
    final attributes = json['attributes'];
    final nets = json['netnames'];
    if (nets is Map<String, Object?>) {
      for (final net in nets.values) {
        if (net is Map<String, Object?>) readNet(net);
      }
    }
    if (attributes is! Map<String, Object?> ||
        !attributes.containsKey(rohdSourceTraceKey)) {
      return json;
    }
    return <String, Object?>{
      ...json,
      'attributes': readModuleAttributes(module, attributes),
    };
  }

  /// Whether a source trace has been read, so the `files` array is needed.
  bool get hasSourceTraces => _traces.isNotEmpty;

  /// Adds a `src` attribute, from the source traces read so far, to the
  /// cells and nets of [model] that have none.
  NetlistModel finish(NetlistModel model) {
    if (_traces.isEmpty || _files.isEmpty) return model;
    final resolved = <int, String?>{};
    String? fileOf(int index) => resolved.putIfAbsent(index, () {
      if (index >= _files.length || _files[index].isEmpty) return null;
      final recorded = _files[index];
      return resolveFile?.call(recorded) ?? recorded;
    });

    String? sourceOf(List<RohdSourceFrame>? frames, {bool callSite = false}) {
      if (frames == null || frames.isEmpty) return null;
      final frame = callSite && frames.length > 1 ? frames[1] : frames.first;
      final file = fileOf(frame.file);
      if (file == null) return null;
      final column = frame.column;
      return column == null
          ? '$file:${frame.line}'
          : '$file:${frame.line}.$column';
    }

    final modules = <String, Module>{};
    for (final entry in model.modules.entries) {
      final trace = _traces[entry.key];
      if (trace == null) {
        modules[entry.key] = entry.value;
        continue;
      }
      final module = entry.value;
      final cells = <String, Cell>{};
      for (final cellEntry in module.cells.entries) {
        final cell = cellEntry.value;
        var frames = trace.instances[cell.name];
        // A cell that instantiates another module of the document is
        // located by the line that instantiated it. The innermost frame is
        // inside the instantiated class.
        final callSite = model.modules.containsKey(cell.type);
        if (frames == null && cell.type.startsWith(r'$struct_')) {
          frames = trace.signals[cell.parameters['STRUCT_NAME']];
        }
        final src = cell.attributes.containsKey('src')
            ? null
            : sourceOf(frames, callSite: callSite);
        cells[cellEntry.key] = src == null
            ? cell
            : cell.copyWith(
                attributes: <String, String>{...cell.attributes, 'src': src},
              );
      }
      final nets = <String, Net>{};
      for (final netEntry in module.nets.entries) {
        final net = netEntry.value;
        final src = net.attributes.containsKey('src')
            ? null
            : sourceOf(trace.signals[net.name]);
        nets[netEntry.key] = src == null
            ? net
            : net.copyWith(
                attributes: <String, String>{...net.attributes, 'src': src},
              );
      }
      modules[entry.key] = module.copyWith(cells: cells, nets: nets);
    }
    return model.copyWith(modules: modules);
  }
}

/// A one-line description of a ROHD `logic_type`, or `null` for a plain bus.
///
/// A structure reads `Sample{data:16, valid:1}` (a nested one nests), an
/// array `array[4][2]x8`, and an array of structures
/// `array[4]xSample{data:16, valid:1}`. The output is bounded: a hostile
/// document cannot make it long.
String? describeRohdLogicType(Object? raw) {
  final text = _describe(raw, 0);
  if (text == null || text.isEmpty) return null;
  return text.length <= _maxDescription
      ? text
      : '${text.substring(0, _maxDescription)}…';
}

const int _maxDescription = 240;
const int _maxDepth = 6;

String? _describe(Object? raw, int depth) {
  if (raw is! Map<Object?, Object?> || depth > _maxDepth) return null;
  final typeName = raw['typeName'];
  final fields = raw['fields'];
  if (fields is List<Object?>) {
    final parts = <String>[];
    for (final field in fields) {
      if (field is! Map<Object?, Object?>) continue;
      final name = field['name'];
      if (name is! String) continue;
      final nested = _describe(field['type'], depth + 1);
      final width = field['width'];
      parts.add(
        nested != null
            ? '$name:$nested'
            : width is int
            ? '$name:$width'
            : name,
      );
    }
    final label = typeName is String ? typeName : 'struct';
    return '$label{${parts.join(', ')}}';
  }
  final dims = raw['arrayDims'];
  if (dims is List<Object?>) {
    final shape = dims.whereType<int>().map((d) => '[$d]').join();
    final element = _describe(raw['elementType'], depth + 1);
    final elementWidth = raw['elementWidth'];
    final tail = element ?? (elementWidth is int ? '$elementWidth' : '?');
    return 'array${shape}x$tail';
  }
  return null;
}
