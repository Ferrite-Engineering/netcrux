// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/file_open/gtk_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('netcrux/file_dialog');
  late List<MethodCall> calls;
  late List<String> answer;
  late Directory dir;

  setUp(() {
    calls = <MethodCall>[];
    answer = const <String>[];
    dir = Directory.systemTemp.createTempSync('gtk_file_picker_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  test('pickFiles sends the filter and returns the chosen files', () async {
    final top = File('${dir.path}/top.v')..writeAsStringSync('module top;');
    answer = <String>[top.path];

    final result = await GtkFilePicker().pickFiles(
      dialogTitle: 'Open Source Files',
      initialDirectory: dir.path,
      type: FileType.custom,
      allowedExtensions: const <String>['v', 'sv'],
      allowMultiple: true,
    );

    expect(calls.single.method, 'open');
    expect(calls.single.arguments, <String, Object?>{
      'title': 'Open Source Files',
      'folder': dir.path,
      'multiple': true,
      'extensions': <String>['v', 'sv'],
    });
    final file = result!.files.single;
    expect(file.path, top.path);
    expect(file.name, 'top.v');
    expect(file.size, 'module top;'.length);
  });

  test('pickFiles returns null when the user cancels', () async {
    expect(await GtkFilePicker().pickFiles(), isNull);
    expect(
      (calls.single.arguments as Map<Object?, Object?>)['extensions'],
      isNull,
    );
  });

  test(
    'saveFile returns the path and writes only bytes it was given',
    () async {
      final target = '${dir.path}/session.netcrux';
      answer = <String>[target];

      final path = await GtkFilePicker().saveFile(
        fileName: 'session.netcrux',
        bytes: Uint8List(0),
      );

      expect(path, target);
      expect(calls.single.method, 'save');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['name'],
        'session.netcrux',
      );
      expect(File(target).existsSync(), isFalse);

      await GtkFilePicker().saveFile(
        fileName: 'theme.json',
        bytes: Uint8List.fromList('{}'.codeUnits),
      );
      expect(File(target).readAsStringSync(), '{}');
    },
  );

  test('getDirectoryPath returns the chosen folder or null', () async {
    answer = <String>[dir.path];
    expect(await GtkFilePicker().getDirectoryPath(), dir.path);
    expect(calls.single.method, 'directory');

    answer = const <String>[];
    expect(await GtkFilePicker().getDirectoryPath(), isNull);
  });

  test('useGtkFileDialogsOnLinux installs it on Linux only', () {
    final original = FilePickerPlatform.instance;
    addTearDown(() {
      FilePickerPlatform.instance = original;
      debugDefaultTargetPlatformOverride = null;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    useGtkFileDialogsOnLinux();
    expect(FilePickerPlatform.instance, same(original));

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    useGtkFileDialogsOnLinux();
    expect(FilePickerPlatform.instance, isA<GtkFilePicker>());
  });
}
