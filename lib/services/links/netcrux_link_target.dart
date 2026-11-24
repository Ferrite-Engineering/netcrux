// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart' show CxpPathContainment;
import 'package:crux_io/crux_io.dart' show canonicalPathKey;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The design files a link may open.
///
/// Verilog, SystemVerilog and VHDL sources, which NetCrux elaborates with its
/// own fixed Yosys (or GHDL) invocation exactly as File > Open Source Files
/// does, and a pre-built Yosys JSON netlist, which it reads in-process. The
/// link chooses the file and nothing about how it is read: no engine, no
/// argument, no script.
///
/// Left out on purpose: `.netcrux-project` (it carries extra Yosys commands,
/// defines and include paths, so opening one runs what the file says),
/// `.netcrux` sessions, `.netcrux-workspace` files, `.crux-project` manifests
/// and `.f` filelists, which name further files the confirmation never shows,
/// and a compressed `.v.gz` netlist.
const Set<String> kNetCruxLinkExtensions = {
  '.v',
  '.sv',
  '.vh',
  '.svh',
  '.vhd',
  '.vhdl',
  '.json',
};

/// Why the file a link names was not opened.
enum NetCruxLinkTargetRefusal {
  /// The path is not an absolute, well-formed local path: the CXP receive
  /// floor refused it (relative, empty, padded, carrying a NUL, or a network
  /// or device path on Windows), or it names a Windows device or stream.
  pathRefused,

  /// Not one of [kNetCruxLinkExtensions], as named or once links resolve.
  notADesign,

  /// Nothing is there, or it is not a regular file.
  fileNotFound,

  /// Links are not handled on this platform.
  unsupportedPlatform,
}

/// The result of [vetNetCruxLinkTarget].
sealed class NetCruxLinkTargetResult {
  const NetCruxLinkTargetResult();
}

/// The file may be opened, subject to the user's consent.
final class NetCruxLinkTargetAccepted extends NetCruxLinkTargetResult {
  /// Wraps the resolved [path].
  const NetCruxLinkTargetAccepted(this.path);

  /// The file to open: the link's path with every symbolic link resolved.
  /// This is the value checked, shown to the user, and opened.
  final String path;
}

/// The file may not be opened.
final class NetCruxLinkTargetRefused extends NetCruxLinkTargetResult {
  /// Wraps the [refusal].
  const NetCruxLinkTargetRefused(this.refusal);

  /// Why not.
  final NetCruxLinkTargetRefusal refusal;
}

/// The rule a link's path is held to before the filesystem is asked anything.
///
/// The CXP receive floor, unrooted: absolute, well-formed, no NUL, no padding,
/// and on Windows no `\\server\share`, `\\?\` or `\\.\` path (judging one of
/// those would open an SMB connection to a server the link chose). It is the
/// same rule `crux_mcp`'s `Confinement` applies, without a root.
///
/// Why the floor and not a rooted rule: a link exists to open a design NetCrux
/// has not opened yet, so a rooted rule would refuse what the feature is for.
/// What a CXP peer proves with its per-process token, a link cannot prove at
/// all, so a file the user has not opened before is confirmed by the user
/// instead (see `openNetCruxLink`).
const CxpPathContainment kNetCruxLinkContainment = CxpPathContainment();

/// Windows device names, which open a device rather than a file whatever the
/// extension after them.
const Set<String> _windowsDeviceNames = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Decides whether the file a link names may be opened, and which file that
/// is once symbolic links resolve.
///
/// In order, and stopping at the first refusal:
///
/// 1. [kNetCruxLinkContainment] judges the path as spelled, before anything
///    reads the filesystem.
/// 2. On Windows, an alternate data stream (`top.v:x`) or a device name
///    (`NUL.v`) is refused, also by spelling.
/// 3. The extension, as spelled, must be a [kNetCruxLinkExtensions] one.
/// 4. The path must exist and resolve, every link followed, to a regular file
///    whose own extension is one of them too: `top.v` linking to
///    `~/.ssh/id_ed25519` is refused, not opened.
///
/// [windows] defaults to the host; tests pin it.
NetCruxLinkTargetResult vetNetCruxLinkTarget(String file, {bool? windows}) {
  if (_kIsWeb) {
    return const NetCruxLinkTargetRefused(
      NetCruxLinkTargetRefusal.unsupportedPlatform,
    );
  }
  if (kNetCruxLinkContainment.refuse(file) != null) {
    return const NetCruxLinkTargetRefused(NetCruxLinkTargetRefusal.pathRefused);
  }
  if ((windows ?? Platform.isWindows) && _isWindowsDeviceOrStream(file)) {
    return const NetCruxLinkTargetRefused(NetCruxLinkTargetRefusal.pathRefused);
  }
  if (!isNetCruxLinkExtension(file)) {
    return const NetCruxLinkTargetRefused(NetCruxLinkTargetRefusal.notADesign);
  }
  final String resolved;
  try {
    if (FileSystemEntity.typeSync(file) != FileSystemEntityType.file) {
      return const NetCruxLinkTargetRefused(
        NetCruxLinkTargetRefusal.fileNotFound,
      );
    }
    resolved = File(file).resolveSymbolicLinksSync();
    if (FileSystemEntity.typeSync(resolved, followLinks: false) !=
        FileSystemEntityType.file) {
      return const NetCruxLinkTargetRefused(
        NetCruxLinkTargetRefusal.fileNotFound,
      );
    }
  } on FileSystemException {
    return const NetCruxLinkTargetRefused(
      NetCruxLinkTargetRefusal.fileNotFound,
    );
  }
  if (!isNetCruxLinkExtension(resolved)) {
    return const NetCruxLinkTargetRefused(NetCruxLinkTargetRefusal.notADesign);
  }
  // The resolved path is opened, so it is held to the same rule as the path
  // the link spelled.
  if (kNetCruxLinkContainment.refuse(resolved) != null) {
    return const NetCruxLinkTargetRefused(NetCruxLinkTargetRefusal.pathRefused);
  }
  return NetCruxLinkTargetAccepted(resolved);
}

/// Whether this is a browser build. Spelled out rather than taken from
/// Flutter's `kIsWeb`, so the headless `netcrux` binary, which has no Flutter,
/// can ask [isNetCruxLinkExtension] which files a link may name.
const bool _kIsWeb = bool.fromEnvironment('dart.library.js_interop');

/// Whether [path]'s extension is one a link may open, ignoring case.
bool isNetCruxLinkExtension(String path) =>
    kNetCruxLinkExtensions.contains(p.extension(path).toLowerCase());

/// Whether [path], a Windows path, names an alternate data stream or a
/// device.
@visibleForTesting
bool isWindowsDeviceOrStreamForTest(String path) =>
    _isWindowsDeviceOrStream(path);

bool _isWindowsDeviceOrStream(String path) {
  // A drive-letter path has its one legitimate colon at index 1.
  final afterDrive = path.length > 2 ? path.substring(2) : '';
  if (afterDrive.contains(':')) return true;
  final base = p.windows.basenameWithoutExtension(path).toLowerCase();
  final stem = base.split('.').first.trimRight();
  return _windowsDeviceNames.contains(stem);
}

/// Whether the user has opened [resolvedPath] in NetCrux before: it is a file
/// of an open tab (one of its sources, or the project it came from), or an
/// entry in a recent-files list.
///
/// Compared by file identity (crux_io's [canonicalPathKey]: absolute,
/// normalized, symbolic links resolved, case folded where the filesystem
/// folds it), so a tab opened through one spelling matches a link through
/// another.
///
/// Only the user's own opens count. A design a link opened is not added to
/// the recent lists, so consenting once is not remembered: the next link to
/// that file asks again unless its tab is still open or the user has since
/// opened it themselves.
bool wasOpenedBefore(
  String resolvedPath, {
  required Iterable<String?> openTabPaths,
  required Iterable<String> recentPaths,
}) {
  final key = canonicalPathKey(resolvedPath);
  if (key.isEmpty) return false;
  for (final path in [...openTabPaths, ...recentPaths]) {
    if (path == null || path.isEmpty) continue;
    if (canonicalPathKey(path) == key) return true;
  }
  return false;
}
