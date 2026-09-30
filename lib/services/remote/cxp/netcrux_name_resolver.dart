// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';

/// Translates NetCrux's Yosys-elaborated names into and out of canonical
/// [ElementId] form for CXP peer cross-probe.
///
/// The resolver is the seam at which NetCrux meets WaveCrux / LintCrux /
/// SimCrux on a common naming convention. WaveCrux signals,
/// NetCrux instances, LintCrux rule sites, and SimCrux breakpoints all
/// flow through `ElementId` so peers can recognise the references they
/// receive even when they do not natively understand the originating
/// product's data model.
///
/// ## Canonical path format
///
/// Every kind shares one base shape: a dot-joined hierarchical scope path
/// (`top.cpu.alu`) plus a kind-specific leaf. NetCrux's
/// [`buildElementPath`](../../domain/models/selection/element_path.dart)
/// emits the same format already for the clipboard "Copy Path" action;
/// this resolver round-trips with that format so the over-the-wire CXP
/// reference matches what an engineer would type or paste.
///
/// | Element kind         | Canonical path form                       |
/// |----------------------|-------------------------------------------|
/// | [ElementKind.instance] | `top.parent.cellName:cell`              |
/// | [ElementKind.port]     | `top.parent.cellName.portName`          |
/// | [ElementKind.net]      | `top.parent:net:<edgeId>`               |
/// | [ElementKind.scope]    | `top.parent.cellName` (module *type* via instance) |
/// | [ElementKind.source]   | `file:///abs/path.v#L<line>[:C<column>]` |
///
/// `ElementKind.scope` collapses onto the same hierarchical path the
/// instance kind uses minus the `:cell` leaf marker. NetCrux uses scope
/// to mean "the module type behind this instance" — a peer that sends
/// `scope` to NetCrux is asking it to open that module's schematic; the
/// instance path is the locator NetCrux uses to navigate there.
///
/// ## Edge cases
///
/// The format above is intentionally permissive about a few corner cases
/// that exist in real Yosys elaborations:
///
///   - **Yosys `$N` synthetic names.** Elaboration can produce internal
///     names like `$abc$123$auto_456` for cells and nets it inserts.
///     We preserve them verbatim — the resolver does not silently rename
///     them. A peer that sees `$abc$123$auto_456` knows it's a synthetic
///     name from the wire format; both ends must agree on the
///     synthetic-name shape. WaveCrux sees those same synthetic names
///     in VCD as identifier-code aliases, so a `request_highlight` on a
///     synthetic NetCrux name is the strongest cross-tool primitive we
///     have for "find this synthesized wire."
///   - **Generate-block instances.** Verilog `genblk1[3]` names appear
///     as-is in Yosys output and we keep the bracketed-index segment
///     unchanged in the path: `top.cpu.genblk1[3].sum`. The path remains
///     a single dot-joined string and consumers parse it by splitting on
///     `.` with the understanding that bracket subscripts attach to the
///     preceding segment.
///   - **Hierarchical separator normalization.** We accept Verilog's
///     `.` and Yosys's `/` (which it sometimes emits when traversing
///     `$paramod` boundaries) on the inbound path; outbound we always
///     emit `.`. The conversion is symmetric: send `.`, accept `.` or
///     `/`.
///   - **Same module name in different libraries.** Yosys disambiguates
///     these by mangling the type with `$paramod$...` suffixes. The
///     resolver does not unmangle them; the canonical path uses the
///     mangled type because that's what the elaboration actually
///     produced. Two libraries with the same module name resolve to two
///     distinct mangled types.
///   - **Bus-bit slicing.** A port like `sum[31:0]` is preserved
///     verbatim — the slice range is part of the leaf and the resolver
///     does not parse it. Consumers that want bit-level cross-probing
///     emit one [ElementId] per bit (`sum[3]`) and let the resolver
///     concatenate the slice onto the leaf.
///
/// ## Statelessness
///
/// The resolver is stateless and thread-safe — the same instance is used
/// concurrently from inbound and outbound message paths. Resolution does
/// not consult the loaded netlist; it operates purely on the string
/// shape. This is intentional: a [NameResolver] is the static seam, and
/// the live "is this signal actually loaded?" check happens at the
/// request-handler layer, where unresolved references reply with
/// `ErrorResponse(elementNotFound)`. Future enhancement: the handler
/// layer may consult a per-tab `NetlistModel` to validate that the
/// resolved local reference actually exists; the resolver itself stays
/// stateless.
@immutable
class NetcruxNameResolver implements NameResolver {
  /// Const constructor — the resolver carries no state.
  const NetcruxNameResolver();

  @override
  ElementId? toCanonical({required ElementKind kind, required String local}) {
    if (local.isEmpty) return null;
    // Source paths must preserve `/` because they are filesystem URLs;
    // every other kind uses `/` only as a stand-in hierarchical
    // separator from peers that didn't canonicalise to `.`.
    final normalized = kind == ElementKind.source
        ? local
        : _normalizeSeparators(local);
    switch (kind.known) {
      case KnownElementKind.instance:
        // Instance paths gain the `:cell` leaf marker so the canonical form
        // round-trips through buildElementPath. If the caller already
        // appended `:cell` we accept it as-is.
        final path = normalized.endsWith(':cell')
            ? normalized
            : '$normalized:cell';
        return ElementId(kind: ElementKind.instance, path: path);
      case KnownElementKind.port:
        // Port leaf is appended with `.`; no special marker. We trust the
        // caller already concatenated the port name onto the scope path.
        return ElementId(kind: ElementKind.port, path: normalized);
      case KnownElementKind.net:
        // Net references use `:net:<edgeId>` so they cannot collide with
        // port references that happen to end in a numeric name.
        if (normalized.contains(':net:')) {
          return ElementId(kind: ElementKind.net, path: normalized);
        }
        // Caller passed a bare net reference like `top.q[3:0]` — wrap.
        return ElementId(
          kind: ElementKind.net,
          path: '$normalized:net:wire',
        );
      case KnownElementKind.scope:
        // Scope = module path without the `:cell` leaf marker. We strip
        // the marker if the caller included it so two equivalent
        // outbound forms canonicalise to the same path.
        final path = normalized.endsWith(':cell')
            ? normalized.substring(0, normalized.length - ':cell'.length)
            : normalized;
        return ElementId(kind: ElementKind.scope, path: path);
      case KnownElementKind.source:
        // Source locations come in as `file:///abs/path.v#L<line>` or as
        // a bare absolute path. Both pass through unchanged: a missing
        // `#L<line>` fragment is meaningful ("this file, no particular
        // line"), so synthesising one would assert a line the sender
        // never claimed. Consumers treat the fragment as optional.
        return ElementId(kind: ElementKind.source, path: normalized);
      // NetCrux does not natively model the remaining modelled kinds
      // (signal, marker, rule, test, breakpoint) — they are someone
      // else's primary surface. `ElementKind` is an open value type, so
      // `null` additionally covers a kind named by a peer speaking a
      // newer protocol revision than this build. Both pass through
      // verbatim with their kind preserved: the server's inbound path
      // forwards them to whichever handler expects them, and if no
      // handler claims the kind the request layer answers
      // `ErrorResponse(elementNotFound)`. An unrecognized kind is
      // therefore ignored gracefully, never an error at this layer.
      case KnownElementKind.signal:
      case KnownElementKind.marker:
      case KnownElementKind.rule:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
      case null:
        return ElementId(kind: kind, path: normalized);
    }
  }

  @override
  String? toLocal(ElementId id) {
    if (id.path.isEmpty) return null;
    final normalized = id.kind == ElementKind.source
        ? id.path
        : _normalizeSeparators(id.path);
    switch (id.kind.known) {
      case KnownElementKind.instance:
        // Strip the canonical `:cell` marker so consumers receive the
        // bare hierarchical path NetCrux uses internally
        // (`top.cpu.alu`).
        if (normalized.endsWith(':cell')) {
          return normalized.substring(0, normalized.length - ':cell'.length);
        }
        return normalized;
      case KnownElementKind.port:
        return normalized;
      case KnownElementKind.net:
        return normalized;
      case KnownElementKind.scope:
        // Scope kind already has no `:cell` marker — return verbatim.
        return normalized;
      case KnownElementKind.source:
        return normalized;
      // Same forward-compatibility rationale as the outbound switch:
      // unmodelled kinds, and kinds this build does not recognize at
      // all, pass through verbatim rather than failing.
      case KnownElementKind.signal:
      case KnownElementKind.marker:
      case KnownElementKind.rule:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
      case null:
        return normalized;
    }
  }

  /// Accepts both `.` and `/` as hierarchical separators on the inbound
  /// path and normalizes everything to `.` for the canonical form.
  ///
  /// Yosys sometimes emits `/` when traversing `$paramod` boundaries; we
  /// accept it for compatibility. Verilog and the NetCrux clipboard
  /// format both use `.` and we always emit `.`.
  String _normalizeSeparators(String input) {
    return input.replaceAll('/', '.');
  }
}
