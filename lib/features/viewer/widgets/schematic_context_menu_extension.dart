// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

/// A single extra entry contributed by the Pro overlay (or by future
/// extension points) to the schematic right-click / long-press context
/// menu.
///
/// Each entry carries a localized [label] and an async [onTap]
/// callback. The `SchematicContextMenuController` appends these
/// entries below the open-core built-in items and dispatches via
/// [onTap] when the user selects one.
///
/// The [enabled] flag lets the contributor disable an entry while
/// keeping it discoverable (the menu still renders it greyed). Use
/// for cases like "Cross-probe to peer" entries that should render
/// even when no peers are connected, paired with a tooltip
/// explaining the disabled state.
///
/// [requiredTier] is the licence tier the entry's action needs. The menu
/// draws the same tier chip beside the label that the menu bar and the
/// command palette draw for that tier, at every licence tier, so a Pro
/// entry is marked as Pro before it is clicked. Contributors take it from
/// the gate the entry's [onTap] checks, so the chip and the gate agree.
/// `null` or [LicenseTier.openCore] draws no chip.
@immutable
class SchematicContextMenuExtensionEntry {
  /// Creates a context-menu extension entry.
  const SchematicContextMenuExtensionEntry({
    required this.id,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.tooltip,
    this.requiredTier,
  });

  /// Stable id (within a single build) — exposed so widget tests can
  /// find the [PopupMenuItem] by value.
  final String id;

  /// Localized label shown in the menu.
  final String label;

  /// Optional tooltip shown when the entry is disabled.
  final String? tooltip;

  /// The licence tier the entry's action needs, drawn as a tier chip
  /// beside the label; `null` for an entry every tier can use.
  final LicenseTier? requiredTier;

  /// True when the entry is selectable; false renders the entry
  /// greyed but still visible.
  final bool enabled;

  /// Invoked when the user selects the entry. Receives the build
  /// context (mounted at dispatch time) and a Riverpod [WidgetRef]
  /// so the contributor can dispatch into providers without
  /// reaching out to a global container.
  final Future<void> Function(BuildContext context, WidgetRef ref) onTap;
}

/// Signature for an extension-entry builder. Builders receive the
/// element the user right-clicked / long-pressed on and the active
/// Riverpod [WidgetRef]; they return zero or more entries for that
/// (target, ref) pair. Returning an empty list is fine — the menu
/// simply does not show any entries from this contributor.
typedef SchematicContextMenuExtensionBuilder =
    List<SchematicContextMenuExtensionEntry> Function(
      WidgetRef ref,
      SelectedElement target,
    );

/// Open-core extension-point provider — list of builders the Pro
/// overlay registers to inject extra entries into the schematic
/// right-click / long-press context menu.
///
/// Open-core resolves this to an empty list so the dispatch path
/// (controller → builder → entries → showMenu) is exercised in tests
/// without the Pro overlay present. The Pro overlay's `proOverrides`
/// registers a builder that emits one entry per (connected peer,
/// supported element kind) for cross-probe origination.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override with `.overrideWith` without taking the
/// build_runner generator dep. Matches the
/// [coneOfInfluenceServiceProvider] / [xTraceServiceProvider] /
/// [bookmarkAnnotationStoreProvider] pattern.
final schematicContextMenuExtensionsProvider =
    Provider<List<SchematicContextMenuExtensionBuilder>>(
      (ref) => const <SchematicContextMenuExtensionBuilder>[],
      name: 'schematicContextMenuExtensionsProvider',
    );
