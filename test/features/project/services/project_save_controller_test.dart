// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/services/project_save_controller.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:path/path.dart' as p;

/// Pumps a MaterialApp so the controller has a live [ScaffoldMessengerState]
/// (both outcomes snackbar) and captures a [ProjectSaveController] bound to
/// [container].
Future<ProjectSaveController> _controller(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late ProjectSaveController controller;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              controller = ProjectSaveController(
                container: container,
                messenger: ScaffoldMessenger.of(context),
                l10n: L10N.of(context),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('netcrux-project-save-');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// The project a filelist import leaves in a tab: absolute sources under
  /// the design directory, a define, an include directory, a per-file
  /// language.
  NetcruxProject designIn(String dir) => NetcruxProject.create(
    sourceFiles: <String>[
      p.join(dir, 'rtl', 'gpio.v'),
      p.join(dir, 'rtl', 'soc_top.sv'),
    ],
    topModule: 'soc_top',
    defines: const <String, String>{'WIDTH': '32'},
    includePaths: <String>[p.join(dir, 'inc')],
    sourceFileLanguages: <String, NetcruxSourceLanguage>{
      p.join(dir, 'rtl', 'soc_top.sv'): NetcruxSourceLanguage.systemVerilog,
    },
  );

  group('ProjectSaveController.saveToPath', () {
    testWidgets('writes a project the reader opens with the same design, '
        'with paths relative to the file', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final design = designIn(tempDir.path);
      container.read(currentProjectProvider.notifier).setProject(design);
      final controller = await _controller(tester, container);
      final path = p.join(tempDir.path, 'soc_top.netcrux-project');

      final ok = await tester.runAsync(() => controller.saveToPath(path));
      expect(ok, isTrue);
      await tester.pump();
      expect(find.textContaining('Saved to'), findsOneWidget);

      // What the file holds is portable: relative where the root is shared.
      final written = await tester.runAsync(
        () => const NetcruxProjectFileReader().read(path),
      );
      expect(written!.sourceFiles, <String>[
        p.join('rtl', 'gpio.v'),
        p.join('rtl', 'soc_top.sv'),
      ]);
      expect(written.includePaths, <String>['inc']);
      expect(written.defines, const <String, String>{'WIDTH': '32'});
      expect(written.sourceFileLanguages, <String, NetcruxSourceLanguage>{
        p.join('rtl', 'soc_top.sv'): NetcruxSourceLanguage.systemVerilog,
      });
      // Anchored the way Open Project anchors it, it is the same design.
      expect(resolveProjectPaths(written, tempDir.path), design);
    });

    testWidgets('a failed write reports and returns false', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(currentProjectProvider.notifier)
          .setProject(designIn(tempDir.path));
      final controller = await _controller(tester, container);
      // A directory that does not exist: the writer cannot create its
      // temporary file there.
      final path = p.join(tempDir.path, 'missing', 'x.netcrux-project');

      final ok = await tester.runAsync(() => controller.saveToPath(path));
      expect(ok, isFalse);
      await tester.pump();
      expect(find.textContaining('Could not save project'), findsOneWidget);
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('ProjectSaveController names', () {
    test('suggests the top module, else the first source, else design', () {
      expect(
        ProjectSaveController.suggestedFileName(
          NetcruxProject.create(
            sourceFiles: const <String>['/w/rtl/gpio.v'],
            topModule: 'soc_top',
          ),
        ),
        'soc_top.netcrux-project',
      );
      expect(
        ProjectSaveController.suggestedFileName(
          NetcruxProject.create(sourceFiles: const <String>['/w/rtl/gpio.v']),
        ),
        'gpio.netcrux-project',
      );
      expect(
        ProjectSaveController.suggestedFileName(
          NetcruxProject.create(sourceFiles: const <String>[]),
        ),
        'design.netcrux-project',
      );
    });

    test('appends the project extension when a chosen name lacks it', () {
      expect(
        ProjectSaveController.withProjectExtension('/w/soc'),
        '/w/soc.netcrux-project',
      );
      expect(
        ProjectSaveController.withProjectExtension('/w/soc.json'),
        '/w/soc.json.netcrux-project',
      );
      expect(
        ProjectSaveController.withProjectExtension('/w/soc.netcrux-project'),
        '/w/soc.netcrux-project',
      );
      expect(
        ProjectSaveController.withProjectExtension('/w/SOC.NetCrux-Project'),
        '/w/SOC.NetCrux-Project',
      );
    });
  });
}
