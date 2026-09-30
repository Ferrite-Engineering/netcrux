// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/crux_linux_integration.dart';

// The overlay builds its own identity with this type and passes it to
// `bootstrap`, without depending on crux_linux_integration itself.
export 'package:crux_linux_integration/crux_linux_integration.dart'
    show LinuxDesktopApp;

/// Open-core NetCrux's freedesktop identity, for the AppImage desktop entry
/// `bootstrap` writes on first run.
///
/// [LinuxDesktopApp.appId] and [LinuxDesktopApp.execName] are the
/// `APPLICATION_ID` and `BINARY_NAME` in `linux/CMakeLists.txt`: the GTK
/// runner stamps that id on the window, and the entry has to carry the same
/// one for a dock to match the window to its icon. The Pro overlay passes its
/// own identity to `bootstrap`.
/// Not `const`: a declared MIME type validates its arguments, so
/// [LinuxMimeType.declared] is a factory and the list it builds is `final`.
/// `bootstrap` therefore takes a nullable identity and falls back to this one
/// rather than naming it as a default argument.
final netcruxLinuxDesktopApp = LinuxDesktopApp(
  appId: 'com.ferriteengineering.netcrux',
  name: 'NetCrux',
  comment: 'Netlist schematic browser for Verilog, SystemVerilog, and VHDL',
  execName: 'netcrux',
  fileTypes: kNetcruxFileTypes,
);

/// The files NetCrux opens, as a Linux desktop has to be told about them —
/// the Linux half of the document types `macos/Runner/Info.plist` registers.
///
/// A desktop entry only matches a type the system can derive from the file,
/// so NetCrux's own formats are **declared**: the installed
/// `shared-mime-info` package gives each one its extension and the "Kind"
/// text a file manager shows, and each sub-classes the format it is written
/// in, so a desktop that has never heard of it still opens it in a text
/// editor and searches it as text.
///
/// The HDL sources are **registered**: named in the entry and never declared,
/// because a distro already maps them. Declaring one would replace the
/// description every Verilog, SystemVerilog or VHDL file on the machine
/// shows, including files NetCrux has never opened.
///
/// `.f` is **unmapped on purpose**. A Vivado filelist has no registered type,
/// and `.f` belongs to Fortran on a Linux desktop: a glob for it either loses
/// to `text/x-fortran` at the default weight, or outranks it and takes the
/// extension from Fortran editors for everyone who installs NetCrux. Import a
/// filelist from inside NetCrux instead.
///
/// `test/static/linux_desktop_identity_test.dart` holds this list against the
/// macOS document types, so the two platforms cannot drift.
final List<LinuxMimeType> kNetcruxFileTypes = List<LinuxMimeType>.unmodifiable(
  <LinuxMimeType>[
    LinuxMimeType.declared(
      name: 'application/x-netcrux-project',
      comment: 'NetCrux project',
      extensions: const <String>['netcrux-project'],
      subClassOf: 'application/json',
    ),
    LinuxMimeType.declared(
      name: 'application/x-netcrux-session',
      comment: 'NetCrux session',
      extensions: const <String>['netcrux'],
      subClassOf: 'application/json',
    ),
    LinuxMimeType.declared(
      name: 'application/x-netcrux-workspace',
      comment: 'NetCrux workspace',
      extensions: const <String>['netcrux-workspace'],
      subClassOf: 'application/json',
    ),
    // The suite manifest, which all four products open: one file, one name,
    // matching the macOS UTI `app.edacrux.project`.
    LinuxMimeType.declared(
      name: 'application/x-edacrux-project',
      comment: 'EDACrux design manifest',
      extensions: const <String>['crux-project'],
      subClassOf: 'application/x-yaml',
    ),
    // All three are in freedesktop's database, so they are named and never
    // declared. Two consequences of leaving them alone, both accepted:
    // upstream gives `.vh` to SystemVerilog rather than Verilog, which costs
    // nothing here because the entry names both types and a `.vh` typed
    // either way reaches NetCrux; and a distro whose database predates the
    // SystemVerilog addition maps `.sv` to nothing, so NetCrux is not
    // offered for it. Declaring the type would fix that one machine and
    // retype every SystemVerilog file on every other.
    const LinuxMimeType.registered('text/x-verilog'),
    const LinuxMimeType.registered('text/x-systemverilog'),
    const LinuxMimeType.registered('text/x-vhdl'),
    LinuxMimeType.unmapped(
      extensions: const <String>['f'],
      reason:
          'a Vivado filelist has no registered type, and .f is Fortran to '
          'every Linux desktop: a glob for it either loses to text/x-fortran '
          'or takes .f from Fortran editors. Filelists are imported from '
          'inside NetCrux.',
    ),
  ],
);
