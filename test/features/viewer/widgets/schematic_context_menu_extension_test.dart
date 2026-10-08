// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/widgets/bookmark_annotation_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extensions_provider.dart';

void main() {
  group('schematicContextMenuExtensionsProvider', () {
    test('open-core default is the bookmark / annotation builder alone', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(schematicContextMenuExtensionsProvider),
        <SchematicContextMenuExtensionBuilder>[
          buildBookmarkAnnotationMenuEntries,
        ],
      );
    });

    testWidgets(
      'override registers a builder that emits entries per target',
      (tester) async {
        late List<SchematicContextMenuExtensionEntry> emitted;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              schematicContextMenuExtensionsProvider.overrideWith(
                (_) => <SchematicContextMenuExtensionBuilder>[
                  (ref, target) => [
                    if (target is SelectedElementCell)
                      SchematicContextMenuExtensionEntry(
                        id: 'fake-${target.cellId}',
                        label: 'Fake for ${target.cellId}',
                        onTap: (ctx, _) async {},
                      ),
                  ],
                ],
              ),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                final builders = ref.read(
                  schematicContextMenuExtensionsProvider,
                );
                emitted = builders.single(
                  ref,
                  const SelectedElement.cell(cellId: 'u_alu'),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(emitted, hasLength(1));
        expect(emitted.single.id, 'fake-u_alu');
        expect(emitted.single.label, 'Fake for u_alu');
        expect(emitted.single.enabled, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    test('an entry carries no tier unless one is given', () {
      final free = SchematicContextMenuExtensionEntry(
        id: 'a',
        label: 'A',
        onTap: (_, _) async {},
      );
      final pro = SchematicContextMenuExtensionEntry(
        id: 'b',
        label: 'B',
        requiredTier: LicenseTier.pro,
        onTap: (_, _) async {},
      );
      expect(free.requiredTier, isNull);
      expect(pro.requiredTier, LicenseTier.pro);
    });

    test('entries support an enabled=false greyed state with tooltip', () {
      const entry = SchematicContextMenuExtensionEntry(
        id: 'no-peer',
        label: 'Cross-probe to peer →',
        tooltip: 'No CXP peers connected',
        enabled: false,
        onTap: _noopTap,
      );
      expect(entry.enabled, isFalse);
      expect(entry.tooltip, 'No CXP peers connected');
    });
  });
}

Future<void> _noopTap(BuildContext context, WidgetRef ref) async {}
