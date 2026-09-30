// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The NetCrux app-icon bitmap, resolved resiliently across both packaging
/// contexts so it never throws an unguarded `Unable to load asset` error —
/// and never *attempts* a load that is known to fail.
///
///  * When `netcrux` is consumed as a path/pub dependency (the Pro
///    overlay, or any downstream app), the open-core image assets are bundled
///    under `packages/netcrux/assets/images/...`.
///  * When `netcrux` is the *root* application (open-core standalone, and
///    every `flutter test` / `integration_test` run launched from the
///    open-core repo), the root package's own assets are bundled at the bare
///    `assets/...` path and are NOT mirrored under `packages/netcrux/`.
///
/// The packaging context is decided by looking the key up in the
/// [AssetManifest] — a cached in-memory lookup — rather than by attempting
/// the load and catching the failure, so a miss never surfaces as a logged
/// HTTP 404 on web. If neither key is bundled we degrade to a neutral glyph
/// rather than throwing (an unguarded `Image.asset` failure trips
/// `tester.takeException()` and reddens otherwise-passing tests). Mirrors
/// WaveCrux's `WaveCruxIconImage`.
class NetcruxIconImage extends StatelessWidget {
  /// Creates the resilient NetCrux icon image at [size] logical pixels square.
  const NetcruxIconImage({required this.size, super.key});

  /// Width and height of the rendered icon, in logical pixels.
  final double size;

  /// Path to the icon as declared in the open-core `netcrux` pubspec.
  static const String assetPath = 'assets/images/netcrux_icon_1024.png';

  /// Open-core package name used to namespace the asset when `netcrux` is a
  /// dependency rather than the root app.
  static const String assetPackage = 'netcrux';

  /// Fully-qualified manifest key for the dependency-packaging context.
  static const String packagedAssetKey = 'packages/$assetPackage/$assetPath';

  static final Expando<String> _resolvedKeyCache = Expando<String>();

  static Future<String> _resolveKey(AssetBundle bundle) async {
    final cached = _resolvedKeyCache[bundle];
    if (cached != null) return cached;
    String resolved;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle);
      final assets = manifest.listAssets();
      resolved = assets.contains(packagedAssetKey)
          ? packagedAssetKey
          : assets.contains(assetPath)
          ? assetPath
          : '';
    } on Object {
      resolved = '';
    }
    return _resolvedKeyCache[bundle] = resolved;
  }

  @override
  Widget build(BuildContext context) {
    final bundle = DefaultAssetBundle.of(context);
    final cached = _resolvedKeyCache[bundle];
    if (cached != null) return _buildForKey(context, bundle, cached);
    return FutureBuilder<String>(
      future: _resolveKey(bundle),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(width: size, height: size);
        }
        return _buildForKey(context, bundle, snapshot.data!);
      },
    );
  }

  Widget _buildForKey(BuildContext context, AssetBundle bundle, String key) {
    if (key.isEmpty) return _glyph(context);
    return Image.asset(
      key,
      bundle: bundle,
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) => _glyph(context),
    );
  }

  /// Neutral fallback glyph for consumers that bundled no icon asset.
  Widget _glyph(BuildContext context) => Icon(
    Icons.account_tree_outlined,
    size: size,
    color: Theme.of(context).colorScheme.onSurface,
  );
}
