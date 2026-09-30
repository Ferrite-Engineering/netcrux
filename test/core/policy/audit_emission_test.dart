// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';

class _CapturingSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);

  @override
  Future<void> close() async {}

  @override
  AuditSinkHealth get health => AuditSinkHealth.healthy;
}

(ProviderContainer, _CapturingSink) _container() {
  final sink = _CapturingSink();
  final container = ProviderContainer(
    overrides: [
      cruxAuditSinkProvider.overrideWithValue(sink),
      cruxAuditProductIdProvider.overrideWithValue(NetCruxPolicyKeys.productId),
    ],
  );
  addTearDown(container.dispose);
  return (container, sink);
}

void main() {
  group('schematic opens', () {
    test('records the design source and how many files it carries', () async {
      final (container, sink) = _container();

      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['/rtl/top.sv', '/rtl/alu.sv'],
              topModule: 'top',
            ),
          );
      await pumpEventQueue();

      final event = sink.events.single;
      expect(event.product, 'netcrux');
      expect(event.kind, NetCruxAuditKinds.schematicOpened);
      expect(event.payload['fileCount'], 2);
      expect(event.payload['topModule'], 'top');
      expect(event.payload['source'], 'rtl');
    });

    test('no source PATH reaches the payload', () async {
      final (container, sink) = _container();

      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['/Users/dana/secret_ip/top.sv'],
            ),
          );
      await pumpEventQueue();

      // A source path carries the user's home directory, and this file is read
      // by whoever runs the organization's log shipper.
      final line = sink.events.single.toJsonLine();
      expect(line, isNot(contains('martin')));
      expect(line, isNot(contains('secret_ip')));
    });

    test('re-opening the same project still records an open', () async {
      final (container, sink) = _container();
      final project = NetcruxProject.create(
        sourceFiles: const <String>['/rtl/top.sv'],
      );
      final notifier = container.read(currentProjectProvider.notifier)
        ..setProject(project)
        ..setProject(project);
      await pumpEventQueue();

      // `setProject` early-returns on an equal project to avoid re-running
      // elaboration, but re-opening the same design IS a project open, and an
      // audit trail that skipped it would under-report exactly the repeat
      // access an investigation looks for. Same reason `activeSource` is
      // updated past that early return.
      expect(sink.events, hasLength(2));
      expect(notifier.activeSource.name, 'rtl');
    });
  });

  group('the registered vocabulary', () {
    test('every emitted kind is one this product registered', () async {
      final (container, sink) = _container();
      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(sourceFiles: const <String>['/rtl/top.sv']),
          );
      await pumpEventQueue();

      for (final event in sink.events) {
        expect(
          NetCruxAuditKinds.all,
          contains(event.kind),
          reason: '${event.kind} is not in NetCruxAuditKinds.all',
        );
      }
    });
  });

  group('the default sink', () {
    test('emission is inert until an administrator configures a path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(cruxAuditSinkProvider), isA<NoopAuditSink>());
      expect(
        () => container
            .read(currentProjectProvider.notifier)
            .setProject(
              NetcruxProject.create(sourceFiles: const <String>['/rtl/top.sv']),
            ),
        returnsNormally,
      );
    });
  });

  group('schematic.opened names the design it opened', () {
    // On the netlist-JSON route the payload was
    // `{"source":"rtl","fileCount":1,"topModule":""}`, which names nothing.
    // An Enterprise audit trail exists to answer *which design did this
    // person open*, and there it answered *a design was opened*.
    test('a netlist open is not recorded as rtl', () async {
      final (container, sink) = _container();

      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['/w/soc/soc_top.json'],
            ),
            source: NetcruxDesignSource.netlistJson,
          );
      await pumpEventQueue();

      // A Yosys netlist is the OUTPUT of elaboration, not source.
      expect(sink.events.single.payload['source'], 'netlistJson');
    });

    test('one source and no top module records the basename', () async {
      final (container, sink) = _container();

      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['/w/soc/soc_top.json'],
            ),
            source: NetcruxDesignSource.netlistJson,
          );
      await pumpEventQueue();

      expect(sink.events.single.payload['design'], 'soc_top.json');
    });

    test('the basename carries no directory', () async {
      final (container, sink) = _container();

      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['/Users/dana/secret_ip/soc.json'],
            ),
            source: NetcruxDesignSource.netlistJson,
          );
      await pumpEventQueue();

      final line = sink.events.single.toJsonLine();
      expect(line, contains('soc.json'));
      expect(line, isNot(contains('dana')));
      expect(line, isNot(contains('secret_ip')));
      expect(line, isNot(contains('/Users')));
    });

    test('a resolved top module is identity enough — no basename', () async {
      final (container, sink) = _container();

      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['/rtl/top.sv'],
              topModule: 'top',
            ),
          );
      await pumpEventQueue();

      // Not redundant noise: the question is already answered.
      expect(sink.events.single.payload.containsKey('design'), isFalse);
      expect(sink.events.single.payload['topModule'], 'top');
    });

    test('several sources name no single design, so none is claimed', () async {
      final (container, sink) = _container();

      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['/rtl/a.sv', '/rtl/b.sv'],
            ),
          );
      await pumpEventQueue();

      // `fileCount` already says how many. Naming the first would record a
      // design nobody opened.
      expect(sink.events.single.payload.containsKey('design'), isFalse);
      expect(sink.events.single.payload['fileCount'], 2);
    });
  });
}
