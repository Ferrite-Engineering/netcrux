// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Sizing shared with the warning strip, so the two beta-expiry surfaces cannot
/// drift apart.
///
/// The defaults are the suite desktop values (20 dp icon, 44 dp minimum hit
/// area). They live in `crux_license` alongside `CruxBetaExpiryBanner`, which
/// owns the warning strip for all four products. This modal is NetCrux's own
/// (its copy and its quit action are), so it reads the shared defaults rather
/// than re-declaring the two numbers under a fifth name.
const _sizing = CruxBetaExpirySizing();

/// Blocking, non-dismissable modal rendered over the routed app content once
/// the public-beta build has reached or passed its hard expiry date
/// (`BetaExpiryStatus.expired`).
///
/// Stacks a non-dismissable [ModalBarrier] over [child] and centers a card
/// carrying the expiry message, a "Download latest build" action, and a
/// "Quit NetCrux" action. A [PopScope] with `canPop: false` blocks the system
/// back gesture so the modal cannot be escaped. A dumb leaf widget: the
/// hosting `BetaExpiryGate` owns the status provider, the URL launch, and the
/// app exit.
///
/// The quit action is load-bearing on Windows and Linux: those platforms draw
/// custom window chrome, so the in-app close caption button sits *behind* the
/// [ModalBarrier] and the modal would otherwise leave no visible way out of
/// the app (macOS's native traffic lights are unaffected).
class BetaExpiryBlockingOverlay extends StatelessWidget {
  /// Creates the blocking beta-expiry modal wrapping [child].
  const BetaExpiryBlockingOverlay({
    required this.child,
    required this.onDownload,
    required this.onQuit,
    super.key,
  });

  /// Widget key of the primary download action.
  static const Key downloadButtonKey = Key('betaExpiryExpiredDownload');

  /// Widget key of the quit action.
  static const Key quitButtonKey = Key('betaExpiryExpiredQuit');

  /// The routed app content rendered (dimmed and input-blocked) behind the
  /// modal.
  final Widget child;

  /// Invoked when the user activates "Download latest build".
  final VoidCallback onDownload;

  /// Invoked when the user activates "Quit NetCrux".
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          child,
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: SafeArea(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_disabled_outlined,
                          size: _sizing.iconSize * 2,
                          color: scheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.betaExpiryExpiredTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.betaExpiryExpiredBody,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: _sizing.touchTarget,
                          child: FilledButton.icon(
                            key: downloadButtonKey,
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_outlined),
                            label: Text(l10n.betaExpiryExpiredAction),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: _sizing.touchTarget,
                          child: TextButton(
                            key: quitButtonKey,
                            onPressed: onQuit,
                            child: Text(l10n.betaExpiryExpiredQuit),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
