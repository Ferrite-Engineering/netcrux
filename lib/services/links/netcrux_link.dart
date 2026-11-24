// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The URL scheme NetCrux registers with the operating system.
///
/// A link is `netcrux://open?file=<path>&cell=<name>`, or `&net=<name>`. It
/// can arrive from anywhere: a chat message, a CI log, a lint report, a coding
/// agent's answer. Everything in this file treats it as hostile input, and
/// nothing here touches the filesystem. Whether the file it names may be
/// opened is decided afterwards by `vetNetCruxLinkTarget`, and whether the
/// user agrees by the link handler.
///
/// The grammar, the encoding and the bounds are WaveCrux's
/// (`wavecrux/lib/services/links/wavecrux_link.dart`), so one convention
/// covers both products: the same key style, `+` as a literal plus, the same
/// length limits and the same refusals.
const String kNetCruxLinkScheme = 'netcrux';

/// The longest link accepted, in UTF-16 code units, before any decoding.
const int kNetCruxLinkMaxLength = 8192;

/// The longest decoded `file` value accepted.
const int kNetCruxLinkMaxFileLength = 4096;

/// The longest decoded `cell` or `net` value accepted.
const int kNetCruxLinkMaxNameLength = 1024;

/// Why a link was refused before anything was opened.
///
/// Every value but [relativePath] is reported to the user the same way ("not
/// a valid NetCrux link"): the distinctions are for tests and diagnostics, not
/// for the sender.
enum NetCruxLinkRefusal {
  /// Longer than [kNetCruxLinkMaxLength], or a value longer than its bound.
  tooLong,

  /// The scheme is not `netcrux`.
  notANetCruxLink,

  /// Not of the form `netcrux://open?…`: another action, a user name, a
  /// port, a path, a fragment, or no query at all.
  malformed,

  /// A query key this build does not know. Unknown keys are refused rather
  /// than ignored, so a link written for a later build fails visibly instead
  /// of half-working.
  unknownKey,

  /// The same key twice. One link names one file and one element.
  duplicateKey,

  /// Both `cell` and `net`. One link names one element.
  cellAndNet,

  /// No `file`, or an empty value for any key.
  missingValue,

  /// A broken percent-escape, or bytes that are not UTF-8.
  badEncoding,

  /// White space, a control character or a bidirectional-text control in the
  /// link or in a decoded value.
  forbiddenCharacter,

  /// A `file` that is not an absolute path as written: `/…`, `\\…`, `C:\…`
  /// or `C:/…`. A relative path would be resolved against whatever directory
  /// the app happened to start in, which the sender cannot know.
  relativePath,

  /// More than one link on the command line. Only one is honoured per launch.
  tooManyLinks,
}

/// What a link's element names: a cell or a net.
enum NetCruxLinkElementKind {
  /// A cell: an instance of a module or a primitive.
  cell,

  /// A net.
  net,
}

/// A link that parsed: the file it names, and optionally a cell or a net.
@immutable
class NetCruxLink {
  /// Creates a parsed link.
  const NetCruxLink({required this.file, this.kind, this.name})
    : assert((kind == null) == (name == null), 'a kind needs a name');

  /// The local path, exactly as decoded from the link. Absolute as text; not
  /// yet checked against the filesystem.
  final String file;

  /// Whether [name] is a cell or a net; null when the link names neither.
  final NetCruxLinkElementKind? kind;

  /// The hierarchical name to select, if any.
  final String? name;
}

/// The result of [parseNetCruxLink].
sealed class NetCruxLinkParseResult {
  const NetCruxLinkParseResult();
}

/// The link parsed.
final class NetCruxLinkParsed extends NetCruxLinkParseResult {
  /// Wraps the parsed [link].
  const NetCruxLinkParsed(this.link);

  /// The parsed link.
  final NetCruxLink link;
}

/// The link was refused.
final class NetCruxLinkRejected extends NetCruxLinkParseResult {
  /// Wraps the [refusal].
  const NetCruxLinkRejected(this.refusal);

  /// Why it was refused.
  final NetCruxLinkRefusal refusal;
}

const String _keyFile = 'file';
const String _keyCell = 'cell';
const String _keyNet = 'net';
const Set<String> _knownKeys = {_keyFile, _keyCell, _keyNet};

/// Whether [raw] is spelled as a NetCrux link: it begins with the scheme and a
/// colon, in any case. Says nothing about whether it is a valid one.
bool looksLikeNetCruxLink(String raw) =>
    raw.length > kNetCruxLinkScheme.length &&
    raw.substring(0, kNetCruxLinkScheme.length + 1).toLowerCase() ==
        '$kNetCruxLinkScheme:';

/// Whether [path] is absolute as written, on any host: `/…`, `\\…`, `C:\…` or
/// `C:/…`. A link made on one host is read on another, so this never asks the
/// reading host. The same rule `crux_mcp` holds a link's `file` to when it
/// writes one.
bool isAbsolutePathText(String path) {
  if (path.startsWith('/') || path.startsWith(r'\\')) return true;
  if (path.length < 3) return false;
  final c = path.codeUnitAt(0) | 0x20;
  final letter = c >= 0x61 && c <= 0x7A;
  final sep = path.codeUnitAt(2);
  return letter && path.codeUnitAt(1) == 0x3A && (sep == 0x5C || sep == 0x2F);
}

/// Parses [raw] strictly. Never throws, never touches the filesystem.
///
/// Accepted: `netcrux://open?file=…` with an optional `cell` or `net` (not
/// both), in any order, each at most once, each percent-encoded. The
/// authority is exactly `open` (any case), optionally followed by a single
/// `/`. Nothing else is accepted: no user name, port, other path, fragment or
/// other key. The file must be absolute as written ([isAbsolutePathText]).
///
/// `+` is a literal plus, not a space: a path such as `/work/c++/top.v` must
/// survive, and a space is written `%20`.
///
/// [isAbsolute] is the absolute-path rule, replaceable only so a test can show
/// that a parser which accepts a relative path is caught.
NetCruxLinkParseResult parseNetCruxLink(
  String raw, {
  @visibleForTesting bool Function(String path) isAbsolute = isAbsolutePathText,
}) {
  if (raw.length > kNetCruxLinkMaxLength) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.tooLong);
  }
  if (!looksLikeNetCruxLink(raw)) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.notANetCruxLink);
  }
  if (_hasForbiddenCharacter(raw)) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.forbiddenCharacter);
  }
  if (raw.contains('#')) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.malformed);
  }
  final rest = raw.substring(kNetCruxLinkScheme.length + 1);
  if (!rest.startsWith('//')) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.malformed);
  }
  final afterSlashes = rest.substring(2);
  final queryAt = afterSlashes.indexOf('?');
  final head = queryAt == -1
      ? afterSlashes
      : afterSlashes.substring(0, queryAt);
  if (head.toLowerCase() != 'open' && head.toLowerCase() != 'open/') {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.malformed);
  }
  if (queryAt == -1) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.missingValue);
  }
  final query = afterSlashes.substring(queryAt + 1);
  if (query.isEmpty) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.missingValue);
  }

  final values = <String, String>{};
  for (final pair in query.split('&')) {
    final eq = pair.indexOf('=');
    if (eq <= 0) {
      return const NetCruxLinkRejected(NetCruxLinkRefusal.malformed);
    }
    final key = pair.substring(0, eq);
    if (!_knownKeys.contains(key)) {
      return const NetCruxLinkRejected(NetCruxLinkRefusal.unknownKey);
    }
    if (values.containsKey(key)) {
      return const NetCruxLinkRejected(NetCruxLinkRefusal.duplicateKey);
    }
    final String decoded;
    try {
      decoded = Uri.decodeComponent(pair.substring(eq + 1));
    } on Object {
      return const NetCruxLinkRejected(NetCruxLinkRefusal.badEncoding);
    }
    if (decoded.isEmpty) {
      return const NetCruxLinkRejected(NetCruxLinkRefusal.missingValue);
    }
    if (decoded.contains('\uFFFD')) {
      // A malformed UTF-8 sequence decodes to the replacement character,
      // which would name a different file than the sender's bytes did.
      return const NetCruxLinkRejected(NetCruxLinkRefusal.badEncoding);
    }
    final limit = key == _keyFile
        ? kNetCruxLinkMaxFileLength
        : kNetCruxLinkMaxNameLength;
    if (decoded.length > limit) {
      return const NetCruxLinkRejected(NetCruxLinkRefusal.tooLong);
    }
    if (_hasForbiddenCharacter(decoded, allowSpace: key == _keyFile)) {
      return const NetCruxLinkRejected(NetCruxLinkRefusal.forbiddenCharacter);
    }
    values[key] = decoded;
  }

  final file = values[_keyFile];
  if (file == null) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.missingValue);
  }
  if (!isAbsolute(file)) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.relativePath);
  }
  final cell = values[_keyCell];
  final net = values[_keyNet];
  if (cell != null && net != null) {
    return const NetCruxLinkRejected(NetCruxLinkRefusal.cellAndNet);
  }
  return NetCruxLinkParsed(
    NetCruxLink(
      file: file,
      kind: cell != null
          ? NetCruxLinkElementKind.cell
          : net != null
          ? NetCruxLinkElementKind.net
          : null,
      name: cell ?? net,
    ),
  );
}

/// Whether [value] holds a character no link or link value may carry: a C0 or
/// C1 control, DEL, a bidirectional-text control (which can make a file name
/// read differently from the file it is), a line or paragraph separator, or
/// white space (allowed only as a plain U+0020 inside a decoded path when
/// [allowSpace]).
bool _hasForbiddenCharacter(String value, {bool allowSpace = false}) {
  for (final unit in value.runes) {
    if (unit == 0x20) {
      if (allowSpace) continue;
      return true;
    }
    if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F)) return true;
    if (unit == 0x200E || unit == 0x200F) return true;
    if (unit >= 0x202A && unit <= 0x202E) return true;
    if (unit >= 0x2066 && unit <= 0x2069) return true;
    if (unit == 0x061C || unit == 0x2028 || unit == 0x2029) return true;
    if (unit == 0x00A0 || unit == 0x1680 || unit == 0x3000) return true;
    if (unit >= 0x2000 && unit <= 0x200B) return true;
    if (unit == 0x202F || unit == 0x205F || unit == 0xFEFF) return true;
  }
  return false;
}

/// The command line a launch received, with any NetCrux link taken out.
///
/// On Windows and Linux the operating system opens a link by starting the
/// application with the link as an argument. A link that carries a quote can
/// break out of the registered command's quoting on Windows and smuggle
/// further arguments in after it (`--reset` or `--yosys-path` among them), so
/// when any argument is a link **every other argument is dropped**: a launch
/// is either a link or an ordinary command line, never both.
@immutable
class NetCruxLaunchArgs {
  const NetCruxLaunchArgs._(this.args, this.links);

  /// Splits [argv]. An argument is a link when it begins with `netcrux:` in
  /// any case.
  factory NetCruxLaunchArgs.split(List<String> argv) {
    final links = <String>[
      for (final a in argv)
        if (looksLikeNetCruxLink(a)) a,
    ];
    if (links.isEmpty) return NetCruxLaunchArgs._(argv, const <String>[]);
    return NetCruxLaunchArgs._(const <String>[], links);
  }

  /// The arguments to parse as a command line. Empty when [links] is not.
  final List<String> args;

  /// Every argument that looked like a link. More than one is refused as a
  /// whole ([NetCruxLinkRefusal.tooManyLinks]).
  final List<String> links;
}
