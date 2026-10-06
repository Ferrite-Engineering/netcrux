// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/activity_color_scheme.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';

import '../../../support/color_metrics.dart';

/// SC 1.4.11 (graphical objects): a colored wire against the canvas.
const double _minContrastOnCanvas = 3;

/// The coldest color against an uncolored wire: lighter or darker by at
/// least this ratio, on top of a hue step of [_minDeltaE].
const double _minContrastOnDefaultWire = 2;

/// Any ramp color against a faded uncolored wire.
const double _minContrastOnFadedWire = 1.5;

/// Two colors a viewer must tell apart on a busy canvas (CIE76). About 2.3
/// is the smallest difference noticed side by side.
const double _minDeltaE = 20;

/// The clock color against anything a ramp paints.
const double _minClockDeltaE = 30;

/// Scores sampled along each ramp.
final List<double> _samples = <double>[for (var i = 0; i <= 20; i++) i / 20];

void main() {
  group('ActivityColorScheme', () {
    test('JSON round-trip preserves each variant', () {
      for (final s in ActivityColorScheme.values) {
        expect(ActivityColorScheme.fromJsonString(s.toJsonString()), s);
      }
      expect(
        ActivityColorScheme.fromJsonString('nonexistent'),
        ActivityColorScheme.heatmapRedBlue,
      );
    });

    test('every score lands on the ramp: ends are the first and last stop, '
        'stops sit evenly between', () {
      for (final scheme in ActivityColorScheme.values) {
        for (final b in Brightness.values) {
          final stops = scheme.stops(b);
          expect(stops.length, greaterThanOrEqualTo(2));
          for (var i = 0; i < stops.length; i++) {
            expect(
              scheme.colorForScore(i / (stops.length - 1), b),
              stops[i],
              reason: '${scheme.name} ${b.name} stop $i',
            );
          }
        }
      }
    });

    test('a dark and a light canvas get different ramps', () {
      for (final scheme in ActivityColorScheme.values) {
        expect(
          scheme.stops(Brightness.dark),
          isNot(scheme.stops(Brightness.light)),
        );
      }
    });

    test('out-of-range scores clamp to [0, 1]', () {
      const s = ActivityColorScheme.heatmapRedBlue;
      for (final b in Brightness.values) {
        expect(s.colorForScore(-0.5, b), s.colorForScore(0, b));
        expect(s.colorForScore(1.5, b), s.colorForScore(1, b));
      }
    });

    test('interpolation is deterministic (same input, same output)', () {
      const s = ActivityColorScheme.heatmapViridis;
      expect(
        s.colorForScore(0.37, Brightness.dark),
        s.colorForScore(0.37, Brightness.dark),
      );
    });

    test('colorForNet paints a clock the clock color, a data net its '
        'score', () {
      const data = NetActivity(
        netPath: 'tb.dut.state',
        transitionCount: 3,
        dutyCyclePercent: 40,
        activityScore: 0.5,
      );
      final clock = data.copyWith(netPath: 'tb.dut.clk', isClock: true);
      for (final scheme in ActivityColorScheme.values) {
        for (final b in Brightness.values) {
          expect(scheme.colorForNet(clock, b), ActivityColorScheme.clockColor);
          expect(scheme.colorForNet(data, b), scheme.colorForScore(0.5, b));
        }
      }
    });
  });

  group('legibility on every built-in theme', () {
    final canvases = canvasColorsOfEveryPreset();

    test('covers the six built-in presets', () {
      expect(canvases.map((c) => c.presetId).toSet(), <String>{
        'crux-dark',
        'crux-light',
        'solarized-dark',
        'high-contrast-dark',
        'oscilloscope',
        'oled-xr',
      });
    });

    for (final canvas in canvases) {
      group(canvas.presetId, () {
        for (final scheme in ActivityColorScheme.values) {
          test('${scheme.name}: every color reads on the canvas', () {
            for (final t in _samples) {
              final c = scheme.colorForScore(t, canvas.brightness);
              expect(
                contrastRatio(c, canvas.background),
                greaterThanOrEqualTo(_minContrastOnCanvas),
                reason: 'score $t is ${_hex(c)} on ${_hex(canvas.background)}',
              );
            }
          });

          test('${scheme.name}: the coldest color is not an uncolored '
              'wire', () {
            final cold = scheme.colorForScore(0, canvas.brightness);
            expect(
              contrastRatio(cold, canvas.defaultWire),
              greaterThanOrEqualTo(_minContrastOnDefaultWire),
              reason: '${_hex(cold)} beside ${_hex(canvas.defaultWire)}',
            );
            expect(
              deltaE(cold, canvas.defaultWire),
              greaterThanOrEqualTo(_minDeltaE),
              reason: '${_hex(cold)} beside ${_hex(canvas.defaultWire)}',
            );
          });

          test('${scheme.name}: no color reads as a wire the coloring '
              'faded', () {
            // While the coloring is shown, a wire it has no color for
            // paints faded; that is the wire a colored one sits beside.
            final faded = Color.alphaBlend(
              ActivityColorScheme.uncoloredWire(canvas.defaultWire),
              canvas.background,
            );
            for (final t in _samples) {
              final c = scheme.colorForScore(t, canvas.brightness);
              expect(
                contrastRatio(c, faded),
                greaterThanOrEqualTo(_minContrastOnFadedWire),
                reason: 'score $t is ${_hex(c)} beside ${_hex(faded)}',
              );
              expect(
                deltaE(c, faded),
                greaterThanOrEqualTo(_minDeltaE),
                reason: 'score $t is ${_hex(c)} beside ${_hex(faded)}',
              );
            }
          });

          test('${scheme.name}: three activity levels read apart', () {
            // The fewest distinct levels a rank-normalized design has
            // beyond two: cold, middle and hot.
            final levels = <Color>[
              for (final t in const <double>[0, 0.5, 1])
                scheme.colorForScore(t, canvas.brightness),
            ];
            for (var i = 0; i < levels.length; i++) {
              for (var j = i + 1; j < levels.length; j++) {
                expect(
                  deltaE(levels[i], levels[j]),
                  greaterThanOrEqualTo(_minDeltaE),
                  reason: '${_hex(levels[i])} vs ${_hex(levels[j])}',
                );
              }
            }
          });
        }

        test('a faded uncolored wire is still drawn', () {
          final faded = Color.alphaBlend(
            ActivityColorScheme.uncoloredWire(canvas.defaultWire),
            canvas.background,
          );
          expect(contrastRatio(faded, canvas.background), greaterThan(1.3));
        });

        test('the clock color reads on the canvas and apart from an '
            'uncolored wire', () {
          const clock = ActivityColorScheme.clockColor;
          expect(
            contrastRatio(clock, canvas.background),
            greaterThanOrEqualTo(_minContrastOnCanvas),
          );
          expect(
            deltaE(clock, canvas.defaultWire),
            greaterThanOrEqualTo(_minClockDeltaE),
          );
        });
      });
    }

    test('the clock color is apart from every color any ramp paints', () {
      for (final scheme in ActivityColorScheme.values) {
        for (final b in Brightness.values) {
          for (final t in _samples) {
            final c = scheme.colorForScore(t, b);
            expect(
              deltaE(ActivityColorScheme.clockColor, c),
              greaterThanOrEqualTo(_minClockDeltaE),
              reason: '${scheme.name} ${b.name} score $t is ${_hex(c)}',
            );
          }
        }
      }
    });
  });
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
