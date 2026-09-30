// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens / focuses the Switching Activity Heatmap pane.
///
/// Open-core default is a no-op so [NetcruxAction.showActivityHeatmap]
/// remains discoverable in the command palette / menu bar on
/// open-core builds. The Pro overlay overrides this with a
/// callback that mounts the panel through the workspace's docking
/// infrastructure.
typedef ShowActivityHeatmapOpener = void Function(BuildContext context);

/// Prompts the user for a VCD/FST/GHW path (via the platform file
/// picker) and loads it into the active
/// [WaveformSourceService]. The Pro overlay's opener also surfaces a
/// progress indicator while the load runs; open-core's no-op is a
/// safe entry point because [NoopWaveformSourceService] would
/// throw [UnimplementedWaveformLoad] anyway.
typedef OpenWaveformFileOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Unloads the currently-loaded waveform source. Open-core's no-op
/// is safe to invoke when nothing is loaded.
typedef CloseWaveformFileOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Runs full-design activity analysis via
/// [ActivityAnalysisService.analyze] using the current per-tab
/// [activityHeatmapStateProvider]'s time range + color scheme,
/// routes the result into the per-tab state notifier, and opens the
/// panel.
typedef RunActivityAnalysisOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Clears the per-edge activity color override map so the schematic
/// painter falls back to its default wire color. Does not clear the
/// underlying analysis result.
typedef ClearActivityColoringOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Opens the color-scheme picker dialog. The Pro overlay's opener
/// mounts a dropdown of the three built-in schemes.
typedef ConfigureActivitySchemeOpener =
    void Function(
      BuildContext context,
    );

/// Open-core extension point for showing the Activity Heatmap pane.
final showActivityHeatmapOpenerProvider = Provider<ShowActivityHeatmapOpener>(
  (_) => (_) {
    // Open-core no-op. Pro overlay overrides this with a callback
    // that mounts the Switching Activity Heatmap panel.
  },
  name: 'showActivityHeatmapOpenerProvider',
);

/// Open-core extension point for loading a waveform file.
final openWaveformFileOpenerProvider = Provider<OpenWaveformFileOpener>(
  (_) => (_, _) {
    // Open-core no-op. Pro overlay overrides with the file picker.
  },
  name: 'openWaveformFileOpenerProvider',
);

/// Open-core extension point for closing the loaded waveform.
final closeWaveformFileOpenerProvider = Provider<CloseWaveformFileOpener>(
  (_) => (_, _) {
    // Open-core no-op. Pro overlay calls
    // WaveformSourceService.unloadWaveform().
  },
  name: 'closeWaveformFileOpenerProvider',
);

/// Open-core extension point for running full-design activity
/// analysis.
final runActivityAnalysisOpenerProvider = Provider<RunActivityAnalysisOpener>(
  (_) => (_, _) {
    // Open-core no-op. Pro overlay overrides this.
  },
  name: 'runActivityAnalysisOpenerProvider',
);

/// Open-core extension point for clearing the activity color
/// override.
final clearActivityColoringOpenerProvider =
    Provider<ClearActivityColoringOpener>(
      (_) => (_, _) {
        // Open-core no-op — there is nothing to clear when no Pro
        // controller has published an override. Pro overlay calls into
        // its `ProActivityColorOverrideController.clear()`.
      },
      name: 'clearActivityColoringOpenerProvider',
    );

/// Open-core extension point for opening the color-scheme picker.
final configureActivitySchemeOpenerProvider =
    Provider<ConfigureActivitySchemeOpener>(
      (_) => (_) {
        // Open-core no-op.
      },
      name: 'configureActivitySchemeOpenerProvider',
    );
