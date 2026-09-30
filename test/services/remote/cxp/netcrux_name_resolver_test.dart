// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';

void main() {
  const resolver = NetcruxNameResolver();

  group('NetcruxNameResolver.toCanonical', () {
    test('instance kind appends :cell marker', () {
      final id = resolver.toCanonical(
        kind: ElementKind.instance,
        local: 'top.cpu.alu',
      );
      expect(id, isNotNull);
      expect(id!.kind, ElementKind.instance);
      expect(id.path, 'top.cpu.alu:cell');
    });

    test('instance kind preserves existing :cell marker', () {
      final id = resolver.toCanonical(
        kind: ElementKind.instance,
        local: 'top.cpu.alu:cell',
      );
      expect(id!.path, 'top.cpu.alu:cell');
    });

    test('port kind passes through unchanged', () {
      final id = resolver.toCanonical(
        kind: ElementKind.port,
        local: 'top.cpu.alu.sum',
      );
      expect(id!.kind, ElementKind.port);
      expect(id.path, 'top.cpu.alu.sum');
    });

    test('net kind preserves :net: tag when already present', () {
      final id = resolver.toCanonical(
        kind: ElementKind.net,
        local: 'top:net:e_4',
      );
      expect(id!.kind, ElementKind.net);
      expect(id.path, 'top:net:e_4');
    });

    test('net kind wraps bare path with :net:wire', () {
      final id = resolver.toCanonical(
        kind: ElementKind.net,
        local: 'top.q',
      );
      expect(id!.path, 'top.q:net:wire');
    });

    test('scope kind strips trailing :cell marker', () {
      final id = resolver.toCanonical(
        kind: ElementKind.scope,
        local: 'top.cpu.alu:cell',
      );
      expect(id!.kind, ElementKind.scope);
      expect(id.path, 'top.cpu.alu');
    });

    test('source kind passes file URL through verbatim', () {
      final id = resolver.toCanonical(
        kind: ElementKind.source,
        local: 'file:///abs/path.v#L42',
      );
      expect(id!.kind, ElementKind.source);
      expect(id.path, 'file:///abs/path.v#L42');
    });

    test('empty local returns null', () {
      final id = resolver.toCanonical(
        kind: ElementKind.instance,
        local: '',
      );
      expect(id, isNull);
    });

    test('hierarchical separator normalization: / accepted, . emitted', () {
      final id = resolver.toCanonical(
        kind: ElementKind.instance,
        local: 'top/cpu/alu',
      );
      expect(id!.path, 'top.cpu.alu:cell');
    });

    test(r'preserves Yosys $N synthetic names verbatim', () {
      final id = resolver.toCanonical(
        kind: ElementKind.instance,
        local: r'top.$abc$123$auto_456',
      );
      expect(id!.path, r'top.$abc$123$auto_456:cell');
    });

    test('preserves generate-block bracket subscripts', () {
      final id = resolver.toCanonical(
        kind: ElementKind.instance,
        local: 'top.cpu.genblk1[3]',
      );
      expect(id!.path, 'top.cpu.genblk1[3]:cell');
    });

    test('preserves bus-bit slice on port', () {
      final id = resolver.toCanonical(
        kind: ElementKind.port,
        local: 'top.cpu.alu.sum[31:0]',
      );
      expect(id!.path, 'top.cpu.alu.sum[31:0]');
    });

    test('unknown kinds pass through verbatim (forward compatibility)', () {
      // Signal is not a NetCrux primary kind but the resolver still
      // accepts it so a peer that emits one doesn't get null.
      final id = resolver.toCanonical(
        kind: ElementKind.signal,
        local: 'top.q',
      );
      expect(id!.kind, ElementKind.signal);
      expect(id.path, 'top.q');
    });
  });

  group('NetcruxNameResolver.toLocal', () {
    test('instance kind strips :cell marker', () {
      final local = resolver.toLocal(
        const ElementId(kind: ElementKind.instance, path: 'top.cpu.alu:cell'),
      );
      expect(local, 'top.cpu.alu');
    });

    test('instance kind handles missing :cell marker', () {
      // A peer that does not bother to append :cell still resolves
      // correctly — we accept both forms on the inbound side.
      final local = resolver.toLocal(
        const ElementId(kind: ElementKind.instance, path: 'top.cpu.alu'),
      );
      expect(local, 'top.cpu.alu');
    });

    test('port kind passes through', () {
      final local = resolver.toLocal(
        const ElementId(
          kind: ElementKind.port,
          path: 'top.cpu.alu.sum',
        ),
      );
      expect(local, 'top.cpu.alu.sum');
    });

    test('net kind passes through', () {
      final local = resolver.toLocal(
        const ElementId(
          kind: ElementKind.net,
          path: 'top:net:e_4',
        ),
      );
      expect(local, 'top:net:e_4');
    });

    test('scope kind passes through', () {
      final local = resolver.toLocal(
        const ElementId(
          kind: ElementKind.scope,
          path: 'top.cpu.alu',
        ),
      );
      expect(local, 'top.cpu.alu');
    });

    test('source kind passes through', () {
      final local = resolver.toLocal(
        const ElementId(
          kind: ElementKind.source,
          path: 'file:///src/cpu.v#L17',
        ),
      );
      expect(local, 'file:///src/cpu.v#L17');
    });

    test('normalizes / separator on inbound', () {
      final local = resolver.toLocal(
        const ElementId(
          kind: ElementKind.instance,
          path: 'top/cpu/alu:cell',
        ),
      );
      expect(local, 'top.cpu.alu');
    });

    test('empty path returns null', () {
      final local = resolver.toLocal(
        const ElementId(kind: ElementKind.instance, path: ''),
      );
      expect(local, isNull);
    });
  });

  group('Round-trip', () {
    test(
      'every ElementKind round-trips through canonical → local → canonical',
      () {
        final samples = <ElementKind, String>{
          ElementKind.instance: 'top.cpu.alu',
          ElementKind.port: 'top.cpu.alu.sum',
          ElementKind.net: 'top:net:e_4',
          ElementKind.scope: 'top.cpu.alu',
          ElementKind.source: 'file:///abs/path.v#L42',
        };
        for (final entry in samples.entries) {
          final canonical = resolver.toCanonical(
            kind: entry.key,
            local: entry.value,
          );
          expect(canonical, isNotNull, reason: 'kind ${entry.key.name}');
          final local = resolver.toLocal(canonical!);
          expect(
            local,
            entry.value,
            reason: 'kind ${entry.key.name} should round-trip',
          );
          // And one more canonicalisation should be idempotent.
          final canonicalAgain = resolver.toCanonical(
            kind: entry.key,
            local: local!,
          );
          expect(
            canonicalAgain,
            canonical,
            reason:
                'kind ${entry.key.name} canonicalisation must be idempotent',
          );
        }
      },
    );
  });

  group('unrecognized element kinds', () {
    // `ElementKind` is an open value type precisely so a peer speaking a
    // newer protocol revision can name a kind this build does not model.
    // The resolver must ignore that gracefully — pass it through with the
    // kind preserved — rather than throwing or dropping it, so the kind
    // stays meaningful to the peer that sent it.
    const resolver = NetcruxNameResolver();
    final unknown = ElementKind('quantum_flux_capacitor');

    test('the kind is genuinely unmodelled by this build', () {
      expect(unknown.known, isNull);
      expect(unknown.isKnown, isFalse);
    });

    test('toCanonical passes an unknown kind through with its kind kept', () {
      final canonical = resolver.toCanonical(kind: unknown, local: 'top/cpu');
      expect(canonical, isNotNull);
      expect(canonical!.kind, unknown);
      expect(canonical.path, 'top.cpu');
    });

    test('toLocal passes an unknown kind through', () {
      final local = resolver.toLocal(
        ElementId(kind: unknown, path: 'top/cpu'),
      );
      expect(local, 'top.cpu');
    });

    test('an unknown kind round-trips', () {
      final canonical = resolver.toCanonical(kind: unknown, local: 'top.cpu')!;
      expect(resolver.toLocal(canonical), 'top.cpu');
    });

    test('an empty local is still rejected for an unknown kind', () {
      expect(resolver.toCanonical(kind: unknown, local: ''), isNull);
      expect(resolver.toLocal(ElementId(kind: unknown, path: '')), isNull);
    });
  });
}
