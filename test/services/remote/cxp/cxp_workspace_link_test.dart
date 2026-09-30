// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';

void main() {
  late Directory workspaceDir;
  late Directory designDir;
  late File sourceFile;

  setUp(() {
    workspaceDir = Directory.systemTemp.createTempSync('cxp_ws_');
    designDir = Directory.systemTemp.createTempSync('cxp_design_');
    // resolveArtifact prunes entries whose path no longer exists, so the
    // artifact must be a real file on disk.
    sourceFile = File('${designDir.path}/cdc_capture.v')
      ..writeAsStringSync('module top; endmodule');
  });

  tearDown(() {
    workspaceDir.deleteSync(recursive: true);
    designDir.deleteSync(recursive: true);
  });

  ProviderContainer boot() => ProviderContainer(
    overrides: [
      cxpWorkspaceStoreProvider.overrideWithValue(
        CxpWorkspaceStore(workspaceDirectory: workspaceDir.path),
      ),
    ],
  );

  test('cxpDesignIdForProject keys on the source-file directory', () {
    final project = NetcruxProject.create(
      sourceFiles: <String>[sourceFile.path],
    );
    expect(cxpDesignIdForProject(project), cxpDesignIdForPath(sourceFile.path));
    expect(cxpDesignIdForProject(NetcruxProject.empty), isNull);
  });

  test(
    'publishes source under the source-dir design id (shared-workspace producer)',
    () async {
      final container = boot();
      addTearDown(container.dispose);

      final designId = cxpDesignIdForPath(sourceFile.path);
      await publishDesignSourceArtifact(
        container,
        serverRunning: true,
        designId: designId,
        sourcePath: sourceFile.path,
        topModule: 'top',
      );

      final store = container.read(cxpWorkspaceStoreProvider);
      final resolved = store.resolveArtifact(designId, 'source');
      expect(resolved, isNotNull);
      expect(resolved!.path, sourceFile.path);
      expect(resolved.kind, 'source');
      expect(resolved.producer, 'netcrux');
      expect(resolved.topModule, 'top');
      expect(resolved.basename, 'cdc_capture.v');

      // The shared-workspace consumer resolver finds the same file.
      expect(
        resolveDesignSourceArtifactPath(container, designId),
        sourceFile.path,
      );
    },
  );

  test('is a no-op when the CXP server is not running', () async {
    final container = boot();
    addTearDown(container.dispose);

    final designId = cxpDesignIdForPath(sourceFile.path);
    await publishDesignSourceArtifact(
      container,
      serverRunning: false,
      designId: designId,
      sourcePath: sourceFile.path,
      topModule: 'top',
    );

    expect(
      container.read(cxpWorkspaceStoreProvider).readArtifacts(designId),
      isEmpty,
    );
  });
}
