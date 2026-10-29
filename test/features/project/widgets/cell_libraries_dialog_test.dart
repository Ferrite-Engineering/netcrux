// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/project/widgets/cell_libraries_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';

class _FakePicker extends FileOpenService {
  _FakePicker(this.paths);

  final List<String> paths;
  int calls = 0;

  @override
  Future<FileOpenResult> pickLibertyFiles({required String dialogTitle}) async {
    calls++;
    return FileOpenResult(paths);
  }
}

/// Pumps a button that opens the dialog over [initial]; the dialog's
/// result goes to [onClosed] when it closes.
Future<void> _open(
  WidgetTester tester, {
  required List<String> initial,
  required FileOpenService picker,
  required void Function(List<String>? result) onClosed,
  Locale? locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => onClosed(
            await showCellLibrariesDialog(
              context: context,
              initial: initial,
              picker: picker,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists, removes, adds and applies', (tester) async {
    final picker = _FakePicker(<String>['/pdk/b.lib', '/pdk/a.lib']);
    List<String>? result;
    await _open(
      tester,
      initial: const <String>['/pdk/a.lib', '/pdk/old.lib'],
      picker: picker,
      onClosed: (r) => result = r,
    );

    expect(find.text('Cell Libraries (Liberty)'), findsOneWidget);
    expect(find.text('a.lib'), findsOneWidget);
    expect(find.text('old.lib'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove old.lib'));
    await tester.pump();
    expect(find.text('old.lib'), findsNothing);

    // a.lib is already listed, so only b.lib is added.
    await tester.tap(find.byKey(const ValueKey<String>('cellLibrariesAdd')));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);

    await tester.tap(find.byKey(const ValueKey<String>('cellLibrariesApply')));
    await tester.pumpAndSettle();
    expect(result, <String>['/pdk/a.lib', '/pdk/b.lib']);
  });

  testWidgets('Cancel returns null; an empty list says so', (tester) async {
    var closed = false;
    List<String>? result = const <String>['sentinel'];
    await _open(
      tester,
      initial: const <String>[],
      picker: _FakePicker(const <String>[]),
      onClosed: (r) {
        closed = true;
        result = r;
      },
    );
    expect(find.text('No cell libraries.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  // ── locale sweep ──
  for (final locale in L10N.supportedLocales) {
    testWidgets('renders in $locale without exceptions', (tester) async {
      await _open(
        tester,
        locale: locale,
        initial: const <String>['/pdk/a.lib', '/pdk/b.lib'],
        picker: _FakePicker(const <String>[]),
        onClosed: (_) {},
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CruxDialog), findsOneWidget);
    });
  }
}
