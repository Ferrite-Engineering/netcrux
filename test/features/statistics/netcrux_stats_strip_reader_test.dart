// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/project/providers/netlist_reader_run_provider.dart';
import 'package:netcrux/features/statistics/widgets/netcrux_stats_strip.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// A pipeline that is idle or, when [loading], never finishes.
class _Netlist extends LoadedNetlist {
  _Netlist({required this.loading});

  final bool loading;

  @override
  Future<NetlistModel?> build() =>
      loading ? Completer<NetlistModel?>().future : Future.value();
}

class _Run extends NetlistReaderRunNotifier {
  _Run(this.run);

  final NetlistReaderRun? run;

  @override
  NetlistReaderRun? build() => run;
}

/// The Elaboration statistic says which reader read the design on screen,
/// and that the native reader is reading while it does.
void main() {
  Future<L10N> pumpStrip(
    WidgetTester tester, {
    required NetlistReaderRun? run,
    bool loading = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loadedNetlistProvider.overrideWith(() => _Netlist(loading: loading)),
          currentLaidOutGraphProvider.overrideWith(
            (ref) => Completer<Never>().future,
          ),
          netlistReaderRunProvider.overrideWith(() => _Run(run)),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(body: NetcruxStatsStrip()),
        ),
      ),
    );
    await tester.pump();
    final l10n = await L10N.delegate.load(const Locale('en'));
    // The strip opens collapsed; its segments show once expanded.
    await tester.tap(find.byTooltip(l10n.statsStripExpandTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return l10n;
  }

  testWidgets('before any read the strip says Idle', (tester) async {
    final l10n = await pumpStrip(tester, run: null);
    expect(find.text(l10n.statsElaborationIdle), findsOneWidget);
  });

  testWidgets('after a native read it says so', (tester) async {
    final l10n = await pumpStrip(
      tester,
      run: const NetlistReaderRun(NetlistReaderKind.native),
    );
    expect(find.text(l10n.statsElaborationIdleNative), findsOneWidget);
    expect(l10n.statsElaborationIdleNative, contains('native'));
  });

  testWidgets('after Yosys read the design, by choice or by fallback', (
    tester,
  ) async {
    final l10n = await pumpStrip(
      tester,
      run: const NetlistReaderRun(NetlistReaderKind.yosys, fellBack: true),
    );
    expect(find.text(l10n.statsElaborationIdleYosys), findsOneWidget);
  });

  testWidgets('while the native reader reads, the strip says Reading', (
    tester,
  ) async {
    final l10n = await pumpStrip(
      tester,
      run: const NetlistReaderRun(NetlistReaderKind.native),
      loading: true,
    );
    expect(find.text(l10n.statsElaborationReadingNative), findsOneWidget);
  });
}
