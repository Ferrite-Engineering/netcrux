// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  final projectDir = p.normalize(p.absolute(p.join('/tmp', 'designs', 'cpu')));

  NetcruxProject projectWith({
    List<String> sourceFiles = const <String>[],
    List<String> includePaths = const <String>[],
    Map<String, NetcruxSourceLanguage> languages =
        const <String, NetcruxSourceLanguage>{},
  }) => NetcruxProject.create(
    sourceFiles: sourceFiles,
    topModule: 'cpu',
    includePaths: includePaths,
    sourceFileLanguages: languages,
  );

  group('resolveProjectPaths', () {
    test('anchors relative source files to the project directory', () {
      final resolved = resolveProjectPaths(
        projectWith(sourceFiles: <String>['alu.v', 'rtl/regfile.v']),
        projectDir,
      );
      expect(resolved.sourceFiles, <String>[
        p.join(projectDir, 'alu.v'),
        p.join(projectDir, 'rtl', 'regfile.v'),
      ]);
    });

    test('collapses parent segments rather than passing them to Yosys', () {
      final resolved = resolveProjectPaths(
        projectWith(sourceFiles: <String>['../../test/fixtures/verilog/a.v']),
        projectDir,
      );
      expect(
        resolved.sourceFiles.single,
        p.normalize(p.absolute('/tmp/test/fixtures/verilog/a.v')),
      );
      expect(resolved.sourceFiles.single, isNot(contains('..')));
    });

    test('leaves absolute paths alone', () {
      // A project may legitimately point at a shared IP directory that
      // lives outside its own tree.
      final shared = p.normalize(p.absolute(p.join('/opt', 'ip', 'fifo.v')));
      final resolved = resolveProjectPaths(
        projectWith(sourceFiles: <String>[shared]),
        projectDir,
      );
      expect(resolved.sourceFiles.single, shared);
    });

    test('anchors include paths too', () {
      final resolved = resolveProjectPaths(
        projectWith(includePaths: <String>['inc']),
        projectDir,
      );
      expect(resolved.includePaths.single, p.join(projectDir, 'inc'));
    });

    test('rewrites language-override keys in step with the source list', () {
      // The overrides are keyed by the same strings that appear in
      // sourceFiles. Leaving the keys behind drops every override the
      // moment paths are anchored, sending VHDL through the Verilog
      // reader.
      final resolved = resolveProjectPaths(
        projectWith(
          sourceFiles: <String>['sub.vhd'],
          languages: <String, NetcruxSourceLanguage>{
            'sub.vhd': NetcruxSourceLanguage.vhdl,
          },
        ),
        projectDir,
      );
      final anchored = resolved.sourceFiles.single;
      expect(resolved.sourceFileLanguages, <String, NetcruxSourceLanguage>{
        anchored: NetcruxSourceLanguage.vhdl,
      });
      expect(resolved.resolveLanguage(anchored), NetcruxSourceLanguage.vhdl);
    });

    test('preserves the elaboration knobs it does not touch', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['alu.v'],
        topModule: 'alu',
        defines: const <String, String>{'WIDTH': '32', 'DEBUG': ''},
        extraYosysCommands: const <String>['proc', 'opt'],
        lowerToStructural: true,
      );
      final resolved = resolveProjectPaths(project, projectDir);
      expect(resolved.topModule, 'alu');
      expect(resolved.defines, project.defines);
      expect(resolved.extraYosysCommands, project.extraYosysCommands);
      expect(resolved.lowerToStructural, isTrue);
      expect(resolved.version, project.version);
    });

    test('is idempotent — anchoring an anchored project is a no-op', () {
      final once = resolveProjectPaths(
        projectWith(sourceFiles: <String>['alu.v']),
        projectDir,
      );
      expect(resolveProjectPaths(once, projectDir), once);
    });

    // `p.canonicalize` lowercases on Windows. These strings are the source
    // list the user sees and the workspace saves, so a Windows project must
    // come back spelled as the user spelled it. The Windows path style is
    // passed in, so this holds on every host.
    //
    // MUTATION: resolving through `canonicalize` makes this red.
    test('keeps the case of a Windows path, anchored or absolute', () {
      const dir = r'C:\Users\Dev\Designs\CPU';
      final resolved = resolveProjectPaths(
        projectWith(
          sourceFiles: <String>[r'RTL\Top.v', r'D:\Shared\IP\Fifo.v'],
          includePaths: <String>[r'..\Inc'],
          languages: <String, NetcruxSourceLanguage>{
            r'RTL\Top.v': NetcruxSourceLanguage.verilog,
          },
        ),
        dir,
        pathContext: p.windows,
      );
      expect(resolved.sourceFiles, <String>[
        r'C:\Users\Dev\Designs\CPU\RTL\Top.v',
        r'D:\Shared\IP\Fifo.v',
      ]);
      expect(resolved.includePaths, <String>[r'C:\Users\Dev\Designs\Inc']);
      expect(resolved.sourceFileLanguages.keys, <String>[
        r'C:\Users\Dev\Designs\CPU\RTL\Top.v',
      ]);
    });

    test('handles a project with no paths at all', () {
      final resolved = resolveProjectPaths(projectWith(), projectDir);
      expect(resolved.sourceFiles, isEmpty);
      expect(resolved.includePaths, isEmpty);
    });
  });

  group('relativizeProjectPaths', () {
    test('writes paths under the project directory relative to it', () {
      final portable = relativizeProjectPaths(
        projectWith(
          sourceFiles: <String>[
            p.join(projectDir, 'alu.v'),
            p.join(projectDir, 'rtl', 'regfile.v'),
          ],
          includePaths: <String>[p.join(projectDir, 'inc')],
          languages: <String, NetcruxSourceLanguage>{
            p.join(projectDir, 'alu.v'): NetcruxSourceLanguage.verilog,
          },
        ),
        projectDir,
      );
      expect(portable.sourceFiles, <String>['alu.v', 'rtl/regfile.v']);
      expect(portable.includePaths, <String>['inc']);
      expect(portable.sourceFileLanguages, <String, NetcruxSourceLanguage>{
        'alu.v': NetcruxSourceLanguage.verilog,
      });
    });

    test(
      'reaches a sibling directory with .. rather than an absolute path',
      () {
        final shared = p.normalize(p.join(projectDir, '..', 'ip', 'fifo.v'));
        final portable = relativizeProjectPaths(
          projectWith(sourceFiles: <String>[shared]),
          projectDir,
        );
        expect(portable.sourceFiles, <String>['../ip/fifo.v']);
      },
    );

    test('keeps a path already relative as written', () {
      final portable = relativizeProjectPaths(
        projectWith(sourceFiles: <String>['rtl/top.v']),
        projectDir,
      );
      expect(portable.sourceFiles, <String>['rtl/top.v']);
    });

    test('keeps a path on another Windows drive absolute', () {
      const dir = r'C:\Users\Dev\Designs\CPU';
      final portable = relativizeProjectPaths(
        projectWith(
          sourceFiles: <String>[
            r'C:\Users\Dev\Designs\CPU\RTL\Top.v',
            r'D:\Shared\IP\Fifo.v',
          ],
          includePaths: <String>[r'C:\Users\Dev\Designs\Inc'],
        ),
        dir,
        pathContext: p.windows,
      );
      expect(portable.sourceFiles, <String>[
        'RTL/Top.v',
        r'D:\Shared\IP\Fifo.v',
      ]);
      expect(portable.includePaths, <String>['../Inc']);
    });

    test('round-trips through resolveProjectPaths', () {
      final original = projectWith(
        sourceFiles: <String>[
          p.join(projectDir, 'alu.v'),
          p.normalize(p.join(projectDir, '..', 'ip', 'fifo.v')),
        ],
        includePaths: <String>[p.join(projectDir, 'inc')],
        languages: <String, NetcruxSourceLanguage>{
          p.join(projectDir, 'alu.v'): NetcruxSourceLanguage.systemVerilog,
        },
      );
      final back = resolveProjectPaths(
        relativizeProjectPaths(original, projectDir),
        projectDir,
      );
      expect(back, original);
    });
  });

  // A project is committed from one host and opened on another, so the file
  // has to read the same under both path styles. Each case names its style
  // through `pathContext`, so every host runs both.
  group('path separators in a shared project file', () {
    final windows = p.Context(style: p.Style.windows);
    final posix = p.posix;
    const winDir = r'C:\Users\Dev\Designs\CPU';
    const posixDir = '/home/dev/designs/cpu';

    NetcruxProject windowsDesign() => projectWith(
      sourceFiles: <String>[
        r'C:\Users\Dev\Designs\CPU\RTL\Top.v',
        r'C:\Users\Dev\Designs\IP\Fifo.v',
      ],
      includePaths: <String>[r'C:\Users\Dev\Designs\CPU\Inc'],
      languages: <String, NetcruxSourceLanguage>{
        r'C:\Users\Dev\Designs\CPU\RTL\Top.v': NetcruxSourceLanguage.verilog,
      },
    );

    // MUTATION: writing `context.relative` unchanged makes this red.
    test('saving on Windows writes every relative entry with /', () {
      final portable = relativizeProjectPaths(
        windowsDesign(),
        winDir,
        pathContext: windows,
      );
      expect(portable.sourceFiles, <String>['RTL/Top.v', '../IP/Fifo.v']);
      expect(portable.includePaths, <String>['Inc']);
      expect(portable.sourceFileLanguages.keys, <String>['RTL/Top.v']);
    });

    test('saving on POSIX writes /', () {
      final portable = relativizeProjectPaths(
        projectWith(
          sourceFiles: <String>['$posixDir/rtl/top.v', '/home/dev/ip/f.v'],
        ),
        posixDir,
        pathContext: posix,
      );
      expect(portable.sourceFiles, <String>['rtl/top.v', '../../ip/f.v']);
    });

    test('a relative entry typed with a backslash is saved with /', () {
      final portable = relativizeProjectPaths(
        projectWith(
          sourceFiles: <String>[r'RTL\Top.v'],
          languages: <String, NetcruxSourceLanguage>{
            r'RTL\Top.v': NetcruxSourceLanguage.vhdl,
          },
        ),
        winDir,
        pathContext: windows,
      );
      expect(portable.sourceFiles, <String>['RTL/Top.v']);
      expect(portable.sourceFileLanguages.keys, <String>['RTL/Top.v']);
    });

    test('saved Liberty and cell-model entries are written with /', () {
      final portable = relativizeProjectPaths(
        windowsDesign().copyWith(
          libertyFiles: <String>[r'C:\Users\Dev\Designs\CPU\Lib\fast.lib'],
          cellModelFiles: <String>[r'C:\Users\Dev\Designs\CPU\Lib\cells.v'],
        ),
        winDir,
        pathContext: windows,
      );
      expect(portable.libertyFiles, <String>['Lib/fast.lib']);
      expect(portable.cellModelFiles, <String>['Lib/cells.v']);
    });

    // MUTATION: dropping the POSIX rewrite in `resolveProjectPaths` makes
    // this red.
    test('a Windows-saved file opens its sources under POSIX rules', () {
      final saved =
          projectWith(
            sourceFiles: <String>[r'RTL\Top.v', r'..\IP\Fifo.v'],
            includePaths: <String>[r'Inc\Common'],
            languages: <String, NetcruxSourceLanguage>{
              r'RTL\Top.v': NetcruxSourceLanguage.verilog,
            },
          ).copyWith(
            libertyFiles: <String>[r'Lib\fast.lib'],
            cellModelFiles: <String>[r'Lib\cells.v'],
          );
      final resolved = resolveProjectPaths(saved, posixDir, pathContext: posix);
      expect(resolved.sourceFiles, <String>[
        '$posixDir/RTL/Top.v',
        '/home/dev/designs/IP/Fifo.v',
      ]);
      expect(resolved.includePaths, <String>['$posixDir/Inc/Common']);
      expect(resolved.libertyFiles, <String>['$posixDir/Lib/fast.lib']);
      expect(resolved.cellModelFiles, <String>['$posixDir/Lib/cells.v']);
      expect(resolved.sourceFileLanguages.keys, <String>[
        '$posixDir/RTL/Top.v',
      ]);
    });

    test('a file saved with / opens under both styles', () {
      final saved = projectWith(
        sourceFiles: <String>['RTL/Top.v', '../ip/f.v'],
      );
      expect(
        resolveProjectPaths(saved, winDir, pathContext: windows).sourceFiles,
        <String>[
          r'C:\Users\Dev\Designs\CPU\RTL\Top.v',
          r'C:\Users\Dev\Designs\ip\f.v',
        ],
      );
      expect(
        resolveProjectPaths(saved, posixDir, pathContext: posix).sourceFiles,
        <String>['$posixDir/RTL/Top.v', '/home/dev/designs/ip/f.v'],
      );
    });

    test('Windows-absolute entries are left alone under POSIX rules', () {
      // They cannot resolve on this host, so they keep the not-found
      // handling they had: anchored as an opaque relative name, never split.
      final resolved = resolveProjectPaths(
        projectWith(
          sourceFiles: <String>[r'C:\Shared\Fifo.v', r'\\srv\ip\f.v'],
        ),
        posixDir,
        pathContext: posix,
      );
      expect(resolved.sourceFiles, <String>[
        '$posixDir/C:\\Shared\\Fifo.v',
        '$posixDir/\\\\srv\\ip\\f.v',
      ]);
    });

    test('an absolute POSIX entry containing a backslash is untouched', () {
      final resolved = resolveProjectPaths(
        projectWith(sourceFiles: <String>[r'/opt/we\ird/f.v']),
        posixDir,
        pathContext: posix,
      );
      expect(resolved.sourceFiles, <String>[r'/opt/we\ird/f.v']);
    });

    test('Windows to POSIX round trip finds the same files', () {
      final onWindows = windowsDesign();
      final committed = relativizeProjectPaths(
        onWindows,
        winDir,
        pathContext: windows,
      );
      final onPosix = resolveProjectPaths(
        committed,
        posixDir,
        pathContext: posix,
      );
      expect(onPosix.sourceFiles, <String>[
        '$posixDir/RTL/Top.v',
        '/home/dev/designs/IP/Fifo.v',
      ]);
      expect(onPosix.includePaths, <String>['$posixDir/Inc']);
    });

    test('POSIX to Windows round trip finds the same files', () {
      final onPosix = projectWith(
        sourceFiles: <String>[
          '$posixDir/rtl/top.v',
          '/home/dev/designs/ip/f.v',
        ],
        includePaths: <String>['$posixDir/inc'],
      );
      final committed = relativizeProjectPaths(
        onPosix,
        posixDir,
        pathContext: posix,
      );
      final onWindows = resolveProjectPaths(
        committed,
        winDir,
        pathContext: windows,
      );
      expect(onWindows.sourceFiles, <String>[
        r'C:\Users\Dev\Designs\CPU\rtl\top.v',
        r'C:\Users\Dev\Designs\ip\f.v',
      ]);
      expect(onWindows.includePaths, <String>[r'C:\Users\Dev\Designs\CPU\inc']);
    });

    test('the file text a Windows save produces has no backslash', () {
      final text = const NetcruxProjectFileWriter().serialise(
        relativizeProjectPaths(windowsDesign(), winDir, pathContext: windows),
      );
      expect(text, contains('"RTL/Top.v"'));
      expect(text, isNot(contains(r'\\')));
      // And a POSIX host opens exactly what that text names.
      final opened = resolveProjectPaths(
        const NetcruxProjectFileReader().parse(text),
        posixDir,
        pathContext: posix,
      );
      expect(opened.sourceFiles.first, '$posixDir/RTL/Top.v');
    });

    test('saving twice is stable: relative entries stay as written', () {
      final once = relativizeProjectPaths(
        windowsDesign(),
        winDir,
        pathContext: windows,
      );
      expect(relativizeProjectPaths(once, winDir, pathContext: windows), once);
    });
  });
}
