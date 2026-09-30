// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
// Conditional import: the desktop worker's solver factory picks the native
// elkrs engine, or elkjs on a JavaScript engine when kept by environment or
// when the native library cannot start. Web never reaches it.
import 'package:netcrux/services/layout/elk_solver_stub.dart'
    if (dart.library.io) 'package:netcrux/services/layout/elk_solver_io.dart';
// Conditional import: on web the elkjs solve runs natively in the
// browser (the browser is a JS engine — no flutter_js, no isolate). Off
// web `kElkWebSolverAvailable` is false and the isolate path is used.
import 'package:netcrux/services/layout/elk_web_solver_stub.dart'
    if (dart.library.html) 'package:netcrux/services/layout/elk_web_solver_web.dart';

/// Narrow seam over [JavascriptRuntime] — exposing only what
/// [ElkLayoutService] actually needs. Implementing a full
/// [JavascriptRuntime] surface in tests is brittle; this interface keeps
/// the test fake to four members.
abstract class ElkJsHost {
  /// Synchronously evaluates [code] and returns the stringified result.
  String evaluate(String code);

  /// Advances one pending Promise / microtask job. Returns the number of
  /// jobs the engine had after this call (0 = idle).
  int executePendingJob();

  /// Releases the underlying engine. Subsequent calls are no-ops.
  void dispose();
}

/// One layout engine behind the worker: ELK JSON in, laid-out ELK JSON out.
///
/// Two implementations share the contract. `NativeElkSolver` calls the
/// vendored elkrs port through `native/elk_ffi` and is the desktop default;
/// [JsElkSolver] drives the vendored elkjs bundle on a JavaScript engine and
/// stays as the escape hatch and the parity reference. The service, the
/// caches and the renderer never learn which one answered.
abstract class ElkSolver {
  /// Lays out [inputJson] and returns the result document. Throws
  /// [LayoutException] when the engine rejects the input.
  String solve(String inputJson);

  /// A short name for the stderr announcement and diagnostics, such as
  /// `native (elkrs 0.1.1)`.
  String get engineDescription;

  /// Releases the engine. Subsequent calls are no-ops.
  void dispose();
}

/// [ElkSolver] over an initialised [ElkJsHost]: the elkjs path.
class JsElkSolver implements ElkSolver {
  /// Wraps [host], which must already have run [initElkRuntime].
  JsElkSolver(this._host);

  final ElkJsHost _host;

  @override
  String get engineDescription => 'elkjs';

  @override
  String solve(String inputJson) => runElkLayoutOnHost(_host, inputJson);

  @override
  void dispose() => _host.dispose();
}

/// Thrown by [ElkLayoutService] when the layout pipeline fails — either
/// the elkjs bundle cannot be loaded, the JS runtime is unavailable on
/// the host, or elk itself rejected the input. Carries a short message
/// suitable for snackbar display and retains the underlying cause for
/// the diagnostics panel.
class LayoutException implements Exception {
  /// Creates a layout exception.
  const LayoutException(this.message, {this.cause});

  /// One-line user-facing message.
  final String message;

  /// Underlying error (if any) — JS evaluation error, asset load error,
  /// parse error.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'LayoutException: $message'
      : 'LayoutException: $message (cause: $cause)';
}

/// Pluggable persistent store for solved layouts, keyed by a stable content
/// hash of the ELK input, so a re-opened design skips the multi-second elkjs
/// solve. Implemented per-platform — `dart:io` files on desktop, a no-op on
/// web (which renders pre-laid-out netlists and never solves). The value is
/// the raw elkjs result JSON string. All methods are best-effort: `read`
/// returns null on miss/error, `write` silently drops on error.
abstract interface class LayoutDiskCache {
  /// Returns the cached layout-result JSON for [key], or null on miss.
  Future<String?> read(String key);

  /// Stores [value] (the layout-result JSON) under [key].
  Future<void> write(String key, String value);
}

/// Builds the ELK-compatible input JSON for a single module out of a
/// [NetlistModel]. Pure function — exposed at the top level so it can be
/// unit-tested without spinning up a JS runtime.
///
/// Each Yosys [Cell] becomes one ELK node; each module [Port] also
/// becomes a node sitting on the boundary. Each Yosys [Net] (or each
/// connection between a cell port and another cell port / module port)
/// becomes one ELK edge. Bit-level granularity is collapsed to net-level
/// — no bit-fanout / bit-merge cells are drawn.
Map<String, Object?> buildElkInput(Module module) {
  final children = <Map<String, Object?>>[];
  final edges = <Map<String, Object?>>[];

  // Module ports become nodes on the boundary so ELK can route edges to
  // them as endpoints.
  for (final entry in module.ports.entries) {
    final port = entry.value;
    children.add(<String, Object?>{
      'id': 'port:${port.name}',
      'width': 16,
      'height': 16,
      'labels': <Map<String, Object?>>[
        <String, Object?>{'text': port.name},
      ],
      'properties': <String, Object?>{
        'kind': 'port',
        'direction': port.direction.toJsonString(),
      },
    });
  }

  // Cells become inner nodes. Each cell's connections list expands into
  // ELK ports beneath the node.
  for (final entry in module.cells.entries) {
    final cell = entry.value;
    final ports = <Map<String, Object?>>[
      for (final portName in cell.connections.keys)
        <String, Object?>{
          'id': '${cell.name}:$portName',
          'width': 4,
          'height': 4,
          'properties': <String, Object?>{
            'side': _portSideForDirection(cell.portDirections[portName]),
          },
        },
    ];
    children.add(<String, Object?>{
      'id': cell.name,
      'width': 80,
      'height': 32 + (ports.length * 10),
      'labels': <Map<String, Object?>>[
        <String, Object?>{'text': '${cell.name}\\n(${cell.type})'},
      ],
      'ports': ports,
      'properties': <String, Object?>{
        'kind': 'cell',
        'cellType': cell.type,
      },
    });
  }

  // Build edges by finding which cell ports drive which other cell ports
  // for each net id. The result is a list of "for each net id, all the
  // (node, port) attachments" — every output→input pair becomes an edge.
  final attachmentsByNetId = <int, List<_Attachment>>{};
  for (final entry in module.cells.entries) {
    final cell = entry.value;
    for (final connEntry in cell.connections.entries) {
      final direction = cell.portDirections[connEntry.key];
      for (final bit in connEntry.value) {
        // bit is a BitRef; we care about NetBit only (constants don't
        // route).
        final id = bit.toJson();
        if (id is! int) continue;
        attachmentsByNetId
            .putIfAbsent(id, () => <_Attachment>[])
            .add(
              _Attachment(
                nodeId: cell.name,
                portId: '${cell.name}:${connEntry.key}',
                isDriver: direction?.toJsonString() == 'output',
              ),
            );
      }
    }
  }
  for (final portEntry in module.ports.entries) {
    final port = portEntry.value;
    for (final bit in port.bits) {
      final id = bit.toJson();
      if (id is! int) continue;
      attachmentsByNetId
          .putIfAbsent(id, () => <_Attachment>[])
          .add(
            _Attachment(
              nodeId: 'port:${port.name}',
              portId: 'port:${port.name}',
              isDriver: port.direction.toJsonString() == 'input',
            ),
          );
    }
  }

  // Route only "datapath" nets as point-to-point edges, skipping
  // high-fanout global nets (clock, reset, enable — which drive every
  // flop). A net whose driver×sink product exceeds [highFanoutEdgeCap]
  // is treated as global and left un-routed in the layout.
  //
  // Why: a single high-fanout net (clk → ~1 600 flops) expands to ~1 600
  // point-to-point edges, and ELK's layered algorithm inserts a dummy
  // routing node for every layer each edge crosses — which ballooned
  // picorv32 to ~21 000 edges, a 13 000 × 63 000 px layout, and a ~7 s
  // solve. Schematic tools don't route clock/reset anyway (they're shown
  // as implied global nets), so skipping them keeps the datapath
  // connectivity that actually drives a readable, compact layout. Edges
  // stay 'simple' (1 source → 1 target) as ELK's layered algorithm
  // requires — it rejects multi-endpoint hyperedges.
  const highFanoutEdgeCap = 32;
  var edgeCounter = 0;
  for (final entry in attachmentsByNetId.entries) {
    final attachments = entry.value;
    final drivers = attachments.where((a) => a.isDriver).toList();
    final sinks = attachments.where((a) => !a.isDriver).toList();
    if (drivers.isEmpty || sinks.isEmpty) continue;
    if (drivers.length * sinks.length > highFanoutEdgeCap) continue;
    for (final driver in drivers) {
      for (final sink in sinks) {
        edges.add(<String, Object?>{
          'id': 'e_${entry.key}_${edgeCounter++}',
          'sources': <String>[driver.portId],
          'targets': <String>[sink.portId],
        });
      }
    }
  }

  // For a large dense scope the layered solve dominates wall-time —
  // picorv32's 1 599-cell core is ~4.5 s in QuickJS-interpreted elkjs. Two
  // knobs roughly halve it with comparable layout quality:
  //  * `thoroughness: 1` — a single crossing-minimization pass instead of
  //    the default multi-pass search.
  //  * `cycleBreaking: DEPTH_FIRST` — cheaper than the default greedy
  //    minimal-reversal search, which is costly on the many feedback loops a
  //    register-heavy netlist has (every flop's Q→D is a cycle).
  // Measured on picorv32: 4.5 s → ~2 s, bounds comparable. Gated to large
  // scopes only — small modules are already instant and keep the
  // higher-quality defaults (DEPTH_FIRST can reverse a few more edges, very
  // slightly hurting the left-to-right signal-flow reading you'd want when
  // studying a small datapath up close).
  const largeScopeCellThreshold = 500;
  final layoutOptions = <String, Object?>{
    'elk.algorithm': 'layered',
    'elk.direction': 'RIGHT',
    'elk.spacing.nodeNode': '20',
    'elk.layered.spacing.nodeNodeBetweenLayers': '30',
    if (module.cells.length > largeScopeCellThreshold) ...<String, Object?>{
      'elk.layered.thoroughness': '1',
      'elk.layered.cycleBreaking.strategy': 'DEPTH_FIRST',
    },
  };
  return <String, Object?>{
    'id': 'root',
    'layoutOptions': layoutOptions,
    'children': children,
    'edges': edges,
  };
}

/// The number of things ELK has to place and route for [input], the output
/// of [buildElkInput]: nodes plus edges. The size proxy behind
/// [layoutTimeoutFor].
int elkElementCount(Map<String, Object?> input) {
  final children = input['children'];
  final edges = input['edges'];
  return (children is List ? children.length : 0) +
      (edges is List ? edges.length : 0);
}

/// How long a solve of [elementCount] elements may run before the worker is
/// killed and the scope reports "timed out".
///
/// Two minutes covers every scope a JIT engine lays out comfortably, then a
/// minute per thousand elements up to twenty minutes: on the interpreter
/// Linux falls back to and Windows always runs, a two-thousand-cell scope
/// needs several minutes that a flat cap used to cut off. The wait is
/// bounded rather than open-ended because the engine cannot be interrupted
/// mid-solve, and it is not the user's only way out: leaving the scope
/// abandons the solve through [ElkLayoutService.cancelInFlightLayout].
Duration layoutTimeoutFor({required int elementCount}) {
  const base = Duration(minutes: 2);
  const perThousand = Duration(minutes: 1);
  const cap = Duration(minutes: 20);
  final total = base + perThousand * (elementCount ~/ 1000);
  return total > cap ? cap : total;
}

String _portSideForDirection(PortDirection? direction) {
  switch (direction) {
    case PortDirection.input:
      return 'WEST';
    case PortDirection.output:
    case PortDirection.inout:
    case null:
      return 'EAST';
  }
}

class _Attachment {
  const _Attachment({
    required this.nodeId,
    required this.portId,
    required this.isDriver,
  });
  final String nodeId;
  final String portId;
  final bool isDriver;
}

/// Async layout pipeline over the Eclipse Layout Kernel.
///
/// Lifecycle:
///   * Lazily start a worker isolate on the first [layout] call. The worker
///     picks its engine ([ElkSolver]): the vendored elkrs port through
///     `native/elk_ffi` on desktop, or the vendored `assets/elk/elk.bundled.js`
///     on a JavaScript engine when kept by `NETCRUX_LAYOUT_ENGINE` or when
///     the native library cannot start. The browser runs elkjs natively.
///   * On each [layout] call, convert the [Module] to ELK input JSON
///     (see [buildElkInput]), solve, and parse the result via
///     [NetlistLayout.fromJson].
///
/// All failures (asset missing, JS engine boot failure, elk error,
/// JSON parse error) surface as [LayoutException]. The service is safe
/// to share across multiple layout requests — initialization is guarded
/// by a `Future` so concurrent first-callers see the same initialization
/// promise.
class ElkLayoutService {
  /// Creates a service. Optional [hostFactory], [solverFactory] and
  /// [assetLoader] are the test seams: an in-process elkjs host, an
  /// in-process [ElkSolver] of any kind, and the asset loader, which default
  /// to the worker isolate's own engine choice and the Flutter `rootBundle`.
  ElkLayoutService({
    ElkJsHost Function()? hostFactory,
    ElkSolver Function()? solverFactory,
    Future<String> Function(String assetKey)? assetLoader,
    LayoutDiskCache? diskCache,
    this.maxMemCacheEntries = 16,
    this.maxMemCacheBytes = 64 * 1024 * 1024,
  }) : // The public params are `hostFactory` / `diskCache`; an initializing
       // formal can't map them to the private fields without leaking the
       // underscore into the API.
       // ignore: prefer_initializing_formals
       _hostFactory = hostFactory,
       // Same public-param/private-field mapping as `_hostFactory` above.
       // ignore: prefer_initializing_formals
       _solverFactory = solverFactory,
       _assetLoader = assetLoader ?? rootBundle.loadString,
       // Same public-param/private-field mapping as `_hostFactory` above.
       // ignore: prefer_initializing_formals
       _diskCache = diskCache;

  /// Asset keys checked, in order, when loading the bundled elkjs UMD.
  /// The first key is the in-package path that works under
  /// `flutter test` against the netcrux package itself. The second key
  /// is the path Flutter rewrites the asset to when netcrux is consumed
  /// as a path dependency from the Pro overlay (or any other downstream
  /// app): the bundler prepends `packages/<package>/` to every
  /// package-declared asset. Without the second fallback the production
  /// app loads with elkjs missing — every elaboration succeeded but
  /// the schematic painted blank.
  static const List<String> _elkAssetKeys = <String>[
    'assets/elk/elk.bundled.js',
    'packages/netcrux/assets/elk/elk.bundled.js',
  ];

  /// In-process host factory. When non-null (the test seam), [layout] runs
  /// the elkjs solve synchronously on the calling isolate against this host.
  /// When null (the production default), [layout] offloads the solve to a
  /// dedicated background isolate so a large scope's multi-second layout
  /// never blocks the UI isolate.
  final ElkJsHost Function()? _hostFactory;

  /// In-process solver factory (the other test seam): when non-null,
  /// [layout] solves synchronously on the calling isolate with the solver it
  /// makes, whatever engine that is. Lets a test drive the native engine
  /// without a worker isolate.
  final ElkSolver Function()? _solverFactory;
  ElkSolver? _solver;
  final Future<String> Function(String assetKey) _assetLoader;

  /// Persistent (cross-session) layout cache, or null when disabled (tests /
  /// web). Keyed by [_cacheKey].
  final LayoutDiskCache? _diskCache;

  /// Maximum number of layouts retained in [_memCache].
  final int maxMemCacheEntries;

  /// Maximum summed [_MemCacheEntry.approxBytes] retained in [_memCache].
  final int maxMemCacheBytes;

  /// In-session LRU memory cache so re-navigating to a scope (A → B → A)
  /// returns instantly without re-solving. Keyed by [_cacheKey].
  ///
  /// Bounded two ways — [maxMemCacheEntries] (count) and [maxMemCacheBytes]
  /// (summed result-JSON length, the size proxy for a parsed
  /// [NetlistLayout]) — because a session that walks a deep hierarchy visits
  /// one scope per node and each retained layout is megabytes for a large
  /// scope. Eviction is least-recently-used and never touches the entry
  /// being stored, so the scope the user is currently viewing always stays
  /// cached even when it alone exceeds the byte budget. Mirrors
  /// [ElaborationCacheService]'s policy.
  ///
  /// `Map` preserves insertion order; the LRU ordering is maintained by
  /// removing and re-inserting an entry on read.
  final Map<String, _MemCacheEntry> _memCache = <String, _MemCacheEntry>{};

  int _memCacheBytes = 0;

  /// Number of layouts currently held in the in-session memory cache.
  @visibleForTesting
  int get memCacheLength => _memCache.length;

  /// Summed size proxy of the layouts currently held in the memory cache.
  @visibleForTesting
  int get memCacheBytes => _memCacheBytes;

  /// Bumped when the layout result format or the elkjs engine changes, to
  /// invalidate persisted layouts (the input-derived part of the key already
  /// covers changes to `buildElkInput`).
  static const String _cacheVersion = 'elk1';

  ElkJsHost? _host;
  Future<void>? _initialization;
  _ElkLayoutIsolate? _isolate;

  /// Lays out [module] using elkjs. Throws [LayoutException] on any
  /// failure in the pipeline.
  ///
  /// The ELK input is built and the result parsed on the calling isolate
  /// (both pure, fast Dart). The elkjs solve itself — the multi-second cost
  /// for a large scope — runs in-process against the injected [_hostFactory]
  /// host (tests), or on a dedicated background isolate (production), so it
  /// never blocks the UI isolate. The provider stays in its loading state
  /// while the isolate works, so the canvas can paint a live progress
  /// indicator.
  Future<NetlistLayout> layout(Module module) async {
    final input = buildElkInput(module);
    final inputJson = jsonEncode(input);
    final key = _cacheKey(inputJson);

    final cached = _lookupMemCache(key);
    if (cached != null) return cached;

    final diskJson = await _diskCache?.read(key);
    if (diskJson != null) {
      try {
        final fromDisk = _parseLayout(diskJson);
        _storeMemCache(key, fromDisk, diskJson.length);
        return fromDisk;
      } on Object {
        // Corrupt / stale cache entry — fall through and re-solve.
      }
    }

    final resultJson = await _solve(
      inputJson,
      timeout: layoutTimeoutFor(elementCount: elkElementCount(input)),
    );
    final layout = _parseLayout(resultJson);
    _storeMemCache(key, layout, resultJson.length);
    // Fire-and-forget: persisting must not delay the first paint.
    unawaited(_diskCache?.write(key, resultJson) ?? Future<void>.value());
    return layout;
  }

  /// Whether a solve is running on the worker right now.
  bool get hasLayoutInFlight => _isolate?.hasInFlight ?? false;

  /// Abandons the solve in flight, if any, so a scope nobody is looking at
  /// any more stops burning a core. The abandoned [layout] call completes
  /// with a [LayoutException]; the next call starts a fresh worker. A no-op
  /// when nothing is in flight, so the warm worker survives ordinary
  /// navigation.
  void cancelInFlightLayout() => _isolate?.cancelInFlight();

  /// Runs the elkjs solve for [inputJson] and returns the result JSON string,
  /// in-process against the injected host (tests) or on the worker isolate
  /// (production). [timeout] bounds the worker path only: the in-process host
  /// is a test seam and the browser awaits elkjs's own Promise.
  Future<String> _solve(String inputJson, {required Duration timeout}) async {
    if (_solverFactory != null) {
      return (_solver ??= _solverFactory()).solve(inputJson);
    }
    if (_hostFactory != null) {
      await _ensureInitialized();
      return runElkLayoutOnHost(_host!, inputJson);
    }
    // On web the browser runs the vendored elkjs natively and awaits its
    // real layout Promise — there is no flutter_js (needs `dart:ffi`) and
    // no `Isolate.spawn` (unsupported on web). Off web this is compiled
    // out (`kElkWebSolverAvailable` is a const `false`) and the solve runs
    // on the background isolate.
    if (kElkWebSolverAvailable) {
      return solveElkOnWeb(inputJson, _loadElkSource);
    }
    return (_isolate ??= _ElkLayoutIsolate(_loadElkSource)).layout(
      inputJson,
      timeout: timeout,
    );
  }

  /// Returns the cached layout for [key], promoting it to the LRU tail,
  /// or `null` when there is no entry.
  NetlistLayout? _lookupMemCache(String key) {
    final entry = _memCache.remove(key);
    if (entry == null) return null;
    _memCache[key] = entry;
    return entry.layout;
  }

  /// Stores [layout] under [key] with [approxBytes] as its size proxy,
  /// then evicts least-recently-used entries while either bound is
  /// exceeded. The just-stored entry is never evicted.
  void _storeMemCache(String key, NetlistLayout layout, int approxBytes) {
    final previous = _memCache.remove(key);
    if (previous != null) _memCacheBytes -= previous.approxBytes;
    _memCache[key] = _MemCacheEntry(layout: layout, approxBytes: approxBytes);
    _memCacheBytes += approxBytes;
    while (_memCache.length > 1 &&
        (_memCache.length > maxMemCacheEntries ||
            _memCacheBytes > maxMemCacheBytes)) {
      final oldest = _memCache.keys.first;
      final evicted = _memCache.remove(oldest);
      _memCacheBytes -= evicted!.approxBytes;
    }
  }

  NetlistLayout _parseLayout(String resultJson) {
    final decoded = jsonDecode(resultJson);
    if (decoded is! Map<String, Object?>) {
      throw const LayoutException('elkjs returned a non-object layout result');
    }
    return NetlistLayout.fromJson(decoded);
  }

  /// Stable, cross-session cache key for a layout. The input JSON fully
  /// determines the layout (it folds in the module structure AND the
  /// `buildElkInput` options), so a content hash of it — plus its length to
  /// make a hash collision astronomically unlikely, plus the engine version —
  /// is a safe key. Uses FNV-1a so it is deterministic across runs (unlike
  /// `String.hashCode`).
  static String _cacheKey(String inputJson) =>
      '${_cacheVersion}_${inputJson.length}_'
      '${_fnv1a32(inputJson).toRadixString(16)}';

  static int _fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final code in input.codeUnits) {
      hash ^= code & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      hash ^= (code >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// Convenience: lays out the top module of [model], or `null` when
  /// no module is marked top.
  Future<NetlistLayout?> layoutTop(NetlistModel model) async {
    final top = model.topModule;
    if (top == null) return null;
    return layout(top);
  }

  /// Disposes the in-process host or solver (tests) and tears down the
  /// layout isolate (production). Call when shutting down the app or to free
  /// the engine's memory.
  void dispose() {
    _host?.dispose();
    _host = null;
    _solver?.dispose();
    _solver = null;
    _initialization = null;
    _isolate?.dispose();
    _isolate = null;
    _memCache.clear();
    _memCacheBytes = 0;
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  /// Loads the elkjs UMD bundle, falling back across the keys declared
  /// in [_elkAssetKeys]. The first key that resolves to a non-empty
  /// string wins; if every key fails the last error is rethrown so the
  /// outer try/catch can wrap it in a [LayoutException].
  Future<String> _loadElkSource() async {
    Object? lastError;
    for (final key in _elkAssetKeys) {
      try {
        final source = await _assetLoader(key);
        if (source.isNotEmpty) return source;
      } on Object catch (e) {
        lastError = e;
      }
    }
    if (lastError is Exception) throw lastError;
    if (lastError is Error) throw lastError;
    throw const LayoutException('elkjs asset not found in any known key');
  }

  Future<void> _initialize() async {
    try {
      final host = _hostFactory!();
      final source = await _loadElkSource();
      initElkRuntime(host, source);
      _host = host;
    } on Object catch (e) {
      _initialization = null;
      if (e is LayoutException) rethrow;
      throw LayoutException(
        'Failed to initialize the elkjs runtime',
        cause: e,
      );
    }
  }
}

/// Boots the elkjs runtime on [host]: installs the GWT/browser shims, loads
/// the [elkSource] UMD bundle, and constructs the singleton `ELK` instance.
/// Throws [LayoutException] if the constructor fails. Top-level so it runs
/// both in-process and inside the layout worker isolate.
void initElkRuntime(ElkJsHost host, String elkSource) {
  host
    // Shim browser/GWT globals that ELK's bundled JS expects.
    //
    // ELK is GWT-compiled — its runtime references `$wnd` (GWT's pointer to
    // the browser window) at constructor time
    // (`$wnd.Error.stackTraceLimit = Error.stackTraceLimit = 64`). QuickJS
    // via flutter_js has no `$wnd`, no `window`, and no
    // `Error.stackTraceLimit`, so `new ELK()` threw synchronously — the
    // exception was swallowed by an outer try/catch in the UMD wrapper,
    // leaving `globalThis.__elkInstance` undefined. Every subsequent
    // `layout()` call then resolved to an empty result and the schematic
    // canvas painted nothing. Map `$wnd` / `window` onto `globalThis` so the
    // GWT runtime sees a host object to drive.
    //
    // ELK's PromisedWorker dispatch also wraps every worker message in
    // `setTimeout(fn, 0)`. QuickJS via flutter_js has no timer driver, so the
    // default flutter_js runtime lacks `setTimeout`. We polyfill it as a FIFO
    // queue that the layout loop drains by calling
    // `globalThis.__drainSetTimeout()` between `executePendingJob` ticks. The
    // polyfill is good enough for ELK's in-band dispatch — it doesn't honor
    // the `ms` argument because ELK only ever passes 0.
    ..evaluate(r'''
      (function(){
        var __setTimeoutQueue = [];
        var __setTimeoutId = 0;
        globalThis.setTimeout = function(fn, ms){
          var id = ++__setTimeoutId;
          __setTimeoutQueue.push({id: id, fn: fn});
          return id;
        };
        globalThis.clearTimeout = function(id){
          for (var i = 0; i < __setTimeoutQueue.length; i++) {
            if (__setTimeoutQueue[i].id === id) {
              __setTimeoutQueue.splice(i, 1);
              return;
            }
          }
        };
        globalThis.__drainSetTimeout = function(){
          while (__setTimeoutQueue.length > 0) {
            var entry = __setTimeoutQueue.shift();
            try { entry.fn(); } catch (e) { /* swallow */ }
          }
        };
        // GWT compatibility shims — see comment above.
        globalThis.$wnd = globalThis;
        if (typeof globalThis.window === "undefined") {
          globalThis.window = globalThis;
        }
        if (typeof globalThis.Error.stackTraceLimit === "undefined") {
          globalThis.Error.stackTraceLimit = 64;
        }
      })();
    ''')
    ..evaluate(elkSource)
    // The UMD bundle attaches `ELK` to globalThis via `g.ELK = f()`. Wrap in
    // a try/catch that surfaces the constructor failure through
    // __elkInitError so callers see a real error instead of a silently-unset
    // __elkInstance.
    ..evaluate('''
      (function(){
        globalThis.__elkInitError = null;
        try {
          globalThis.__elkInstance = new ELK();
        } catch (e) {
          globalThis.__elkInitError = String(e && e.message ? e.message : e);
        }
      })();
    ''');
  final initError = host.evaluate('globalThis.__elkInitError || ""');
  if (initError.isNotEmpty) {
    throw LayoutException('elkjs constructor threw: $initError');
  }
}

/// Runs one elkjs solve on an already-[initElkRuntime]-booted [host] and
/// returns the layout result as a JSON string. Throws [LayoutException] on
/// an elk error or empty result. Top-level so it runs both in-process and
/// inside the layout worker isolate.
String runElkLayoutOnHost(ElkJsHost host, String inputJson) {
  // Stash the input on globalThis and call elk.layout(...), which returns a
  // Promise resolved via a then handler that stores the JSON result back on
  // globalThis under __elk_result. Errors become __elk_error.
  host
    ..evaluate('globalThis.__elk_input = $inputJson;')
    ..evaluate('globalThis.__elk_result = null;')
    ..evaluate('globalThis.__elk_error = null;')
    ..evaluate('''
      globalThis.__elkInstance
        .layout(globalThis.__elk_input)
        .then(function(r){ globalThis.__elk_result = JSON.stringify(r); })
        .catch(function(e){ globalThis.__elk_error = String(e && e.message ? e.message : e); });
    ''');
  // Advance the JS event loop until the Promise resolves. ELK schedules its
  // in-band worker dispatch with `setTimeout(fn, 0)`, which
  // QuickJS-via-flutter_js doesn't drain through `executePendingJob`
  // (microtasks only). The setTimeout polyfill (see initElkRuntime) queues
  // callbacks into a global array; we drain it on every probe tick alongside
  // the microtask queue. Without this, ELK's PromisedWorker.onmessage
  // callback never fires and the promise hangs "pending" forever.
  for (var i = 0; i < 5000; i++) {
    host
      ..executePendingJob()
      ..evaluate(
        'globalThis.__drainSetTimeout && globalThis.__drainSetTimeout();',
      )
      ..executePendingJob();
    final probe = host.evaluate(
      'globalThis.__elk_result === null && globalThis.__elk_error === null ? "pending" : "done"',
    );
    if (probe != 'pending') break;
  }
  final error = host.evaluate('globalThis.__elk_error || ""');
  if (error.isNotEmpty) {
    throw LayoutException('elkjs rejected the layout input: $error');
  }
  final resultStr = host.evaluate('globalThis.__elk_result || ""');
  if (resultStr.isEmpty) {
    throw const LayoutException('elkjs returned an empty layout');
  }
  return resultStr;
}

/// A dedicated long-lived background isolate that owns a flutter_js elkjs
/// runtime and services layout requests, so a large scope's multi-second
/// solve never blocks the UI isolate. The elk UMD source is loaded on the
/// main isolate (via `rootBundle`) and handed to the worker once at init —
/// the worker never touches `rootBundle` (which needs a root-isolate token).
class _ElkLayoutIsolate {
  _ElkLayoutIsolate(this._loadSource);

  /// Loads the elk UMD bundle on the main isolate.
  final Future<String> Function() _loadSource;

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _errors;
  Future<void>? _ready;

  Future<void> _ensureReady() => _ready ??= _start();

  Future<void> _start() async {
    final handshake = ReceivePort();
    // The worker has no `WidgetsBinding`, so anything in flutter_js that
    // reaches for one (its fetch polyfill did, before the host stopped
    // enabling it) surfaces as an asynchronous error that does not affect
    // the layout result. Spawn with `errorsAreFatal: false` and drain the
    // error port — otherwise the default fatal handling tears the worker
    // down mid-flight and every pending `layout()` hangs forever.
    _errors = ReceivePort()..listen((_) {});
    try {
      _isolate = await Isolate.spawn(
        _elkIsolateEntry,
        handshake.sendPort,
        debugName: 'elk-layout',
        errorsAreFatal: false,
        onError: _errors!.sendPort,
      );
      _commands = await handshake.first as SendPort;
    } finally {
      handshake.close();
    }
    final source = await _loadSource();
    final reply = ReceivePort();
    _commands!.send(<String, Object?>{
      'type': 'init',
      'source': source,
      'reply': reply.sendPort,
    });
    final result = await reply.first as Map<Object?, Object?>;
    reply.close();
    if (result['ok'] != true) {
      _ready = null;
      throw LayoutException('elkjs isolate init failed: ${result['error']}');
    }
  }

  /// What [Future.any] yields when the solve was abandoned first.
  static const Object _cancelled = Object();

  /// Completer for the solve in flight; completed by [dispose].
  Completer<void>? _cancelInFlight;

  /// Whether a solve is running on the worker right now.
  bool get hasInFlight => _cancelInFlight != null;

  /// Runs one solve on the worker and returns its result JSON.
  ///
  /// Three ways out besides a result: the worker reports an elkjs error,
  /// [timeout] elapses (the worker is killed, since a solve that long has
  /// hung or is hopeless on this engine), or [cancelInFlight] abandons it.
  Future<String> layout(String inputJson, {required Duration timeout}) async {
    await _ensureReady();
    final reply = ReceivePort();
    final cancel = _cancelInFlight = Completer<void>();
    _commands!.send(<String, Object?>{
      'type': 'layout',
      'input': inputJson,
      'reply': reply.sendPort,
    });
    try {
      final first = await Future.any<Object?>(<Future<Object?>>[
        reply.first,
        cancel.future.then((_) => _cancelled),
      ]).timeout(timeout);
      if (identical(first, _cancelled)) {
        throw const LayoutException('elkjs layout cancelled');
      }
      final result = first! as Map<Object?, Object?>;
      if (result['ok'] != true) {
        throw LayoutException('elkjs layout failed: ${result['error']}');
      }
      return result['result']! as String;
    } on TimeoutException {
      dispose();
      throw const LayoutException('elkjs layout timed out');
    } finally {
      reply.close();
      if (identical(_cancelInFlight, cancel)) _cancelInFlight = null;
    }
  }

  /// Abandons the solve in flight, if any: the pending [layout] call
  /// completes with a [LayoutException] and the worker is killed, because
  /// the engine cannot be interrupted mid-solve. A no-op when idle, so the
  /// warm worker is kept.
  void cancelInFlight() {
    if (_cancelInFlight == null) return;
    dispose();
  }

  void dispose() {
    final cancel = _cancelInFlight;
    _cancelInFlight = null;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _errors?.close();
    _errors = null;
    _ready = null;
  }
}

/// Entry point for the elk layout worker isolate. Owns one [ElkSolver],
/// chosen by [createDefaultElkSolver] at `init`; services `init` and
/// `layout` commands, replying on each message's port. The `init` reply
/// carries the engine's description.
Future<void> _elkIsolateEntry(SendPort handshake) async {
  final commands = ReceivePort();
  handshake.send(commands.sendPort);
  ElkSolver? solver;
  await for (final message in commands) {
    final command = message as Map<Object?, Object?>;
    final reply = command['reply']! as SendPort;
    try {
      switch (command['type']) {
        case 'init':
          solver = createDefaultElkSolver(command['source']! as String);
          reply.send(<String, Object?>{
            'ok': true,
            'engine': solver.engineDescription,
          });
        case 'layout':
          final result = solver!.solve(command['input']! as String);
          reply.send(<String, Object?>{'ok': true, 'result': result});
        case 'dispose':
          solver?.dispose();
          reply.send(<String, Object?>{'ok': true});
          commands.close();
      }
    } on Object catch (e) {
      reply.send(<String, Object?>{'ok': false, 'error': '$e'});
    }
  }
}

/// One entry in [ElkLayoutService]'s in-session LRU memory cache: the
/// parsed [layout] plus [approxBytes], the size proxy driving the byte
/// bound (the length of the result JSON the layout was parsed from).
class _MemCacheEntry {
  const _MemCacheEntry({required this.layout, required this.approxBytes});

  final NetlistLayout layout;
  final int approxBytes;
}
