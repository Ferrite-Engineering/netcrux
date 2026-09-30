// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';

void main() {
  group('currentProjectProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('defaults to empty', () {
      expect(container.read(currentProjectProvider), NetcruxProject.empty);
    });

    test('setProject installs the value', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['a.v'],
        topModule: 'top',
      );
      container.read(currentProjectProvider.notifier).setProject(project);
      expect(container.read(currentProjectProvider), project);
    });

    test('setProject is idempotent (no rebuild on equal state)', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['a.v'],
      );
      container.read(currentProjectProvider.notifier)
        ..setProject(project)
        ..setProject(project);
      // Re-issuing the same project leaves the held instance untouched
      // — the notifier's equality guard returns early.
      expect(container.read(currentProjectProvider), project);
    });

    test('setSourceFiles materialises a fresh project with defaults', () {
      container.read(currentProjectProvider.notifier).setSourceFiles(
        const <String>['cpu.v', 'alu.v'],
      );
      final stored = container.read(currentProjectProvider);
      expect(stored.sourceFiles, <String>['cpu.v', 'alu.v']);
      expect(stored.topModule, '');
      expect(stored.defines, isEmpty);
    });

    test('clear resets to empty', () {
      container.read(currentProjectProvider.notifier)
        ..setSourceFiles(const <String>['cpu.v'])
        ..clear();
      expect(container.read(currentProjectProvider), NetcruxProject.empty);
    });
  });
}
