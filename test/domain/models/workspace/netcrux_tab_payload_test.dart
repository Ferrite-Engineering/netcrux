// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';

void main() {
  group('NetcruxTabPayload', () {
    test('default empty payload has no sources and unit transform', () {
      const p = NetcruxTabPayload.empty;
      expect(p.sourceFiles, isEmpty);
      expect(p.topModule, isEmpty);
      expect(p.projectFilePath, isNull);
      expect(p.zoom, 1.0);
      expect(p.panX, 0.0);
      expect(p.panY, 0.0);
      expect(p.selectionJson, isNull);
      expect(p.overlayMode, isNull);
      expect(p.sessionExportPath, isNull);
    });

    test('equality is value-based on every persisted field', () {
      const a = NetcruxTabPayload(
        sourceFiles: ['/d/foo.v'],
        topModule: 'top',
        scopePath: ['u_cpu'],
        zoom: 2,
      );
      const b = NetcruxTabPayload(
        sourceFiles: ['/d/foo.v'],
        topModule: 'top',
        scopePath: ['u_cpu'],
        zoom: 2,
      );
      const c = NetcruxTabPayload(
        sourceFiles: ['/d/foo.v'],
        topModule: 'top',
        scopePath: ['u_cpu'],
        zoom: 3,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only the named fields', () {
      const p = NetcruxTabPayload(
        sourceFiles: ['/d/a.v'],
        topModule: 'top',
        scopePath: ['x'],
      );
      final updated = p.copyWith(
        topModule: 'newTop',
        scopePath: ['y', 'z'],
      );
      expect(updated.sourceFiles, ['/d/a.v']);
      expect(updated.topModule, 'newTop');
      expect(updated.scopePath, ['y', 'z']);
    });

    test('copyWith clear flags reset optional fields to null', () {
      const p = NetcruxTabPayload(
        sourceFiles: ['/d/a.v'],
        overlayMode: 'fanin',
        selectionJson: {'kind': 'cell', 'id': 'u1'},
        projectFilePath: '/d/proj.netcrux-project',
        sessionExportPath: '/d/last.netcrux',
      );
      final cleared = p.copyWith(
        clearOverlayMode: true,
        clearSelection: true,
        clearProjectFilePath: true,
        clearSessionExportPath: true,
      );
      expect(cleared.overlayMode, isNull);
      expect(cleared.selectionJson, isNull);
      expect(cleared.projectFilePath, isNull);
      expect(cleared.sessionExportPath, isNull);
      // Untouched fields survive the clear.
      expect(cleared.sourceFiles, p.sourceFiles);
    });

    test('derivedDisplayName prefers project filename, then source filename, '
        'else "Untitled"', () {
      expect(
        const NetcruxTabPayload(
          sourceFiles: ['/d/foo.v'],
          projectFilePath: '/d/myproj.netcrux-project',
        ).derivedDisplayName,
        'myproj',
      );
      expect(
        const NetcruxTabPayload(sourceFiles: ['/d/bar.v']).derivedDisplayName,
        'bar.v',
      );
      expect(NetcruxTabPayload.empty.derivedDisplayName, 'Untitled');
    });
  });
}
