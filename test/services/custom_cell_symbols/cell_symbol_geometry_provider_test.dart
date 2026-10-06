// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';
import 'package:netcrux/services/custom_cell_symbols/cell_symbol_geometry_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_registry_provider.dart';

const _symbol = CustomCellSymbol(
  id: 's',
  moduleType: 'uart_tx',
  kind: CustomCellSymbolKind.svg,
  content: '<svg viewBox="0 0 160 120"/>',
  width: 120,
  height: 80,
  portAnchors: <String, PortAnchor>{
    'tx': PortAnchor(x: 1, y: 0.5, side: PortAnchorSide.right),
  },
  createdAt: '',
  updatedAt: '',
);

void main() {
  test('open core has no symbol geometry', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(customCellSymbolSnapshotProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(customCellSymbolSnapshotProvider.future);
    expect(
      container.read(cellSymbolGeometriesProvider),
      same(
        CellSymbolGeometries.none,
      ),
    );
  });

  test('derives each symbol geometry from the snapshot', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        customCellSymbolSnapshotProvider.overrideWith(
          (ref) => Stream<Map<String, CustomCellSymbol>>.value(
            const <String, CustomCellSymbol>{'uart_tx': _symbol},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(customCellSymbolSnapshotProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(customCellSymbolSnapshotProvider.future);
    final geometry = container.read(cellSymbolGeometriesProvider)['uart_tx']!;
    expect(geometry.aspect, closeTo(4 / 3, 1e-9));
    expect(geometry.anchors.keys, <String>['tx']);
  });
}
