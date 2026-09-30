// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/platform/netcrux_linux_desktop_app.dart';

/// The AppImage desktop entry names the running binary. The GTK runner
/// stamps `APPLICATION_ID` on the window, and the entry's file name, icon and
/// `StartupWMClass` must equal it or the dock shows a generic icon; an entry
/// carrying another tier's id also overwrites that tier's installed entry.
void main() {
  String cmakeValue(String name) {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    final match = RegExp('set\\($name "([^"]+)"\\)').firstMatch(cmake);
    if (match == null) throw StateError('linux/CMakeLists.txt sets no $name');
    return match.group(1)!;
  }

  test('the open-core identity matches the Linux runner', () {
    expect(netcruxLinuxDesktopApp.appId, cmakeValue('APPLICATION_ID'));
    expect(netcruxLinuxDesktopApp.execName, cmakeValue('BINARY_NAME'));
    expect(netcruxLinuxDesktopApp.name, 'NetCrux');
  });

  // The Linux half of the macOS document types: a file manager offers an
  // application only for types the system can derive from the file, and the
  // entry claimed none, so a double-clicked project went elsewhere. The
  // shared checker holds the two platforms to each other; what belongs here
  // is NetCrux's own answer for each extension.
  group('the files NetCrux opens', () {
    /// Every extension `CFBundleDocumentTypes` registers, without the dot.
    Set<String> registeredOnMacOS() {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      final documentTypes = RegExp(
        r'<key>CFBundleDocumentTypes</key>\s*<array>(.*)</array>\s*<key>'
        'UTImportedTypeDeclarations</key>',
        dotAll: true,
      ).firstMatch(plist)!.group(1)!;
      return RegExp(
            r'<key>CFBundleTypeExtensions</key>\s*<array>(.*?)</array>',
            dotAll: true,
          )
          .allMatches(documentTypes)
          .expand(
            (m) => RegExp(
              '<string>([^<]+)</string>',
            ).allMatches(m.group(1)!).map((e) => e.group(1)!),
          )
          .toSet();
    }

    test('every extension macOS registers is answered for on Linux', () {
      final registered = registeredOnMacOS();
      expect(registered, isNotEmpty);

      final coverage = checkLinuxMimeCoverage(
        netcruxLinuxDesktopApp,
        registeredExtensions: registered,
        // A registered type carries no extensions of its own, so the HDL
        // sources are accounted for by the types the system already maps.
        registeredExtensionsOf: const <String, List<String>>{
          'text/x-verilog': <String>['v', 'vh'],
          'text/x-systemverilog': <String>['sv', 'svh'],
          'text/x-vhdl': <String>['vhd', 'vhdl'],
        },
        // NetCrux's own trade: the HDL source types a distro maps, which are
        // not in the shared generic set.
        additionalSystemTypes: const <String>{
          'text/x-verilog',
          'text/x-systemverilog',
          'text/x-vhdl',
        },
      );

      expect(coverage.problems, isEmpty, reason: '$coverage');
      // `.f` is the one extension left to other applications, and the record
      // is the decision: a glob for it either loses to text/x-fortran or
      // takes .f from Fortran editors.
      expect(coverage.deliberatelyUnmapped.keys, <String>['f']);
    });

    test("NetCrux declares its own formats and re-declares nobody else's", () {
      final declared = netcruxLinuxDesktopApp.fileTypes.where(
        (t) => t.isDeclared,
      );
      expect(
        declared.map((t) => t.name),
        <String>[
          'application/x-netcrux-project',
          'application/x-netcrux-session',
          'application/x-netcrux-workspace',
          // The suite manifest, named as the macOS UTI names it.
          'application/x-edacrux-project',
        ],
      );
      for (final type in declared) {
        expect(type.extensions, isNotEmpty, reason: type.name);
        expect(type.comment, isNotNull, reason: type.name);
        // A desktop that has never heard of the type still opens the file as
        // what it is written in.
        expect(type.subClassOf, isNotNull, reason: type.name);
      }
      // The types a distro maps are named and never declared: declaring one
      // would replace the description every such file on the machine shows.
      expect(
        netcruxLinuxDesktopApp.fileTypes
            .where((t) => t.isNamed && !t.isDeclared)
            .map((t) => t.name),
        <String>['text/x-verilog', 'text/x-systemverilog', 'text/x-vhdl'],
      );
      final xml = buildMimePackage(netcruxLinuxDesktopApp)!;
      for (final registered in const <String>[
        'text/x-verilog',
        'text/x-systemverilog',
        'text/x-vhdl',
      ]) {
        expect(xml, isNot(contains(registered)), reason: registered);
      }
      expect(xml, contains('EDACrux design manifest'));
    });

    test('the desktop entry names every type, declared and registered', () {
      final entry = buildDesktopEntry(
        netcruxLinuxDesktopApp,
        appImagePath: '/home/e/Apps/NetCrux-1.0.0-x86_64.AppImage',
      );
      expect(
        entry,
        contains(
          'MimeType=application/x-netcrux-project;'
          'application/x-netcrux-session;'
          'application/x-netcrux-workspace;'
          'application/x-edacrux-project;'
          'text/x-verilog;text/x-systemverilog;text/x-vhdl;\n',
        ),
      );
    });
  });

  test('bootstrap integrates the identity it is given, not a fixed one', () {
    final app = File('lib/app.dart').readAsStringSync();
    // Open core's is the fallback, never the answer when a host supplies
    // one: the Pro overlay passes its own, and an entry carrying the wrong
    // tier's id overwrites that tier's installed entry.
    expect(
      app,
      contains(
        'maybeIntegrateDesktopEntry(linuxDesktopApp ?? netcruxLinuxDesktopApp)',
      ),
    );
    expect(app, isNot(contains('netcrux_pro')));
  });
}
