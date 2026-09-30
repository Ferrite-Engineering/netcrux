// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';

/// Kind of artwork a [CustomCellSymbol] carries. Drives how the
/// renderer interprets [CustomCellSymbol.content].
enum CustomCellSymbolKind {
  /// [CustomCellSymbol.content] is a full SVG document (XML).
  svg,

  /// [CustomCellSymbol.content] is a path-data string (SVG `d`
  /// attribute) describing a single closed shape that the renderer
  /// strokes and fills using the active [SymbolPaintContext]. Useful
  /// for lightweight overrides that should adopt the project's theme
  /// colors.
  path,

  /// [CustomCellSymbol.content] names a built-in glyph from a small
  /// curated set (e.g. `ieeeAlu`, `ieeeAdder`). Reserved for future
  /// use; v1 implementations may reject unknown names with a
  /// fallback rendering.
  builtinGlyph,
}

/// User-authored symbol override that replaces the default
/// rectangular cell rendering for a specific Yosys module type.
///
/// Custom cell symbols live in the open-core [CustomCellSymbolRegistry]
/// extension point. The open-core build ships
/// [NoopCustomCellSymbolRegistry] as the registered default; the
/// closed-source Pro overlay registers a persistent
/// `ProCustomCellSymbolRegistry` that loads symbols from per-project
/// (`<project>/.netcrux-symbols/`) and per-user
/// (`<appSupportDir>/netcrux/symbols/`) directories.
///
/// Symbol binding is by [moduleType] — when the schematic renderer
/// paints an instance whose [moduleType] matches a registered symbol,
/// it uses the symbol's [content] in place of the built-in painter for
/// that cell's [CellKind].
@immutable
class CustomCellSymbol {
  /// Creates a custom cell symbol.
  const CustomCellSymbol({
    required this.id,
    required this.moduleType,
    required this.kind,
    required this.content,
    required this.width,
    required this.height,
    required this.portAnchors,
    required this.createdAt,
    required this.updatedAt,
    this.author,
    this.notes,
  });

  /// Round-trips a [CustomCellSymbol] from its JSON shape.
  factory CustomCellSymbol.fromJson(Map<String, Object?> json) {
    final anchors = <String, PortAnchor>{};
    final rawAnchors = json['portAnchors'];
    if (rawAnchors is Map) {
      rawAnchors.forEach((key, value) {
        if (key is String && value is Map) {
          anchors[key] = PortAnchor.fromJson(
            value.cast<String, Object?>(),
          );
        }
      });
    }
    return CustomCellSymbol(
      id: (json['id'] as String?) ?? '',
      moduleType: (json['moduleType'] as String?) ?? '',
      kind: CustomCellSymbolKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => CustomCellSymbolKind.svg,
      ),
      content: (json['content'] as String?) ?? '',
      width: (json['width'] as num?)?.toDouble() ?? 100,
      height: (json['height'] as num?)?.toDouble() ?? 60,
      portAnchors: anchors,
      createdAt: (json['createdAt'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
      author: json['author'] as String?,
      notes: json['notes'] as String?,
    );
  }

  /// Stable identifier (UUID). Persists across renames of
  /// [moduleType] so editor flows can update the binding without
  /// orphaning the file.
  final String id;

  /// Yosys cell-type / module-type string this symbol binds to.
  /// Compared against `SchematicCell.type` at render time.
  final String moduleType;

  /// Kind of artwork stored in [content].
  final CustomCellSymbolKind kind;

  /// Artwork payload — SVG XML, SVG path data, or a glyph name
  /// (interpretation driven by [kind]).
  final String content;

  /// Declared canvas width (in symbol-local units). The renderer
  /// scales-to-fit so the actual rendered width is governed by the
  /// schematic layout engine, but this width drives port-anchor
  /// normalization in the editor.
  final double width;

  /// Declared canvas height (in symbol-local units).
  final double height;

  /// Map from port name → [PortAnchor]. Port names come from the
  /// bound module's port list. Anchors with no matching cell port
  /// are silently ignored at render time; cell ports with no
  /// matching anchor fall back to the default port stub position
  /// computed by the layout engine.
  final Map<String, PortAnchor> portAnchors;

  /// ISO-8601 timestamp recorded when the symbol was first saved.
  final String createdAt;

  /// ISO-8601 timestamp recorded on the most recent save.
  final String updatedAt;

  /// Optional author name. Free-form; not validated.
  final String? author;

  /// Optional free-form notes (purpose, intended usage, attribution).
  final String? notes;

  /// Returns a copy with the given fields overridden. Use
  /// [clearAuthor] / [clearNotes] to explicitly null out the
  /// optional fields (passing `null` to the named parameter
  /// preserves the existing value, per Dart's `copyWith` idiom).
  CustomCellSymbol copyWith({
    String? id,
    String? moduleType,
    CustomCellSymbolKind? kind,
    String? content,
    double? width,
    double? height,
    Map<String, PortAnchor>? portAnchors,
    String? createdAt,
    String? updatedAt,
    String? author,
    String? notes,
    bool clearAuthor = false,
    bool clearNotes = false,
  }) {
    return CustomCellSymbol(
      id: id ?? this.id,
      moduleType: moduleType ?? this.moduleType,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      width: width ?? this.width,
      height: height ?? this.height,
      portAnchors: portAnchors ?? this.portAnchors,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      author: clearAuthor ? null : (author ?? this.author),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  /// Serializes the symbol into its JSON shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'moduleType': moduleType,
    'kind': kind.name,
    'content': content,
    'width': width,
    'height': height,
    'portAnchors': <String, Object?>{
      for (final entry in portAnchors.entries) entry.key: entry.value.toJson(),
    },
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (author != null) 'author': author,
    if (notes != null) 'notes': notes,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomCellSymbol) return false;
    if (other.id != id) return false;
    if (other.moduleType != moduleType) return false;
    if (other.kind != kind) return false;
    if (other.content != content) return false;
    if (other.width != width) return false;
    if (other.height != height) return false;
    if (other.createdAt != createdAt) return false;
    if (other.updatedAt != updatedAt) return false;
    if (other.author != author) return false;
    if (other.notes != notes) return false;
    if (other.portAnchors.length != portAnchors.length) return false;
    for (final entry in portAnchors.entries) {
      if (other.portAnchors[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    moduleType,
    kind,
    content,
    width,
    height,
    createdAt,
    updatedAt,
    author,
    notes,
    Object.hashAllUnordered(
      portAnchors.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'CustomCellSymbol(id=$id, moduleType=$moduleType, kind=${kind.name}, '
      'size=${width}x$height, ports=${portAnchors.length})';
}
