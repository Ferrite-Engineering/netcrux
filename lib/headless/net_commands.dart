// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The headless `netcrux` subcommands, `info`, `search` and `connections`:
/// each writes one document (`crux_mcp`'s envelope) and each is the `netcrux
/// mcp` tool of the same name.
library;

import 'package:args/args.dart';
import 'package:crux_mcp/crux_mcp.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/headless/cli_version.dart';
import 'package:netcrux/headless/net_design.dart';
import 'package:netcrux/services/hierarchy/hierarchy_walk.dart';
import 'package:netcrux/services/host_bridge/element_source_location.dart';
import 'package:netcrux/services/links/netcrux_link.dart';
import 'package:netcrux/services/links/netcrux_link_placement.dart';
import 'package:netcrux/services/remote/cxp/cxp_design_names.dart';
import 'package:netcrux/services/search/design_search_service.dart';
import 'package:path/path.dart' as p;

/// The program every document names, and the MCP server's `serverInfo`.
const McpProgram kNetCruxProgram = McpProgram(
  name: 'netcrux',
  version: kNetCruxCliVersion,
);

/// The description of every tool's `design` property.
const String kNetDesignDescription =
    'Source files, one Yosys JSON netlist, or one .crux-project.';

/// `search --limit`: the default.
const int kSearchLimitDefault = 50;

/// `search --limit`: the most.
const int kSearchLimitMax = 500;

/// The most cells and nets one `search` counts; past it, `total` is a floor
/// and a warning says so.
const int kSearchCountCap = 100000;

/// The most instances `info` lists.
const int kInfoHierarchyLimit = 200;

/// The most pins `connections` lists.
const int kConnectionsPinLimit = 500;

/// The `search --kind` values.
const List<String> kSearchKinds = <String>['cell', 'net', 'port', 'module'];

/// A refused argument: the command writes a `usage_error` and runs nothing
/// more.
class NetUsageException implements Exception {
  /// A refusal saying [message].
  const NetUsageException(this.message);

  /// One sentence naming the argument and what is wrong.
  final String message;

  @override
  String toString() => message;
}

/// What every command shares: where designs are read, and how a design that
/// could not be produced ends a command.
class NetCommandContext {
  /// A context reading designs through [reader].
  NetCommandContext({
    required this.reader,
    this.program = kNetCruxProgram,
    this.mapProblem = classifyNetDesignProblem,
  });

  /// Reads and holds designs.
  final NetDesignReader reader;

  /// The program the documents name.
  final McpProgram program;

  /// How a design problem ends a command.
  final NetDesignProblemMap mapProblem;

  /// The `--license-file` the `mcp` server was started with, for a command
  /// that reads a licence; null on the command line, where each command
  /// takes its own flag. The three commands of this library read none.
  String? licenseFile;
}

/// One subcommand: its MCP tool, its flags, and the document it writes.
abstract class NetCommand {
  /// The subcommand's name, which is its tool's.
  String get name;

  /// One line for `--help`.
  String get summary;

  /// How it is called, for `--help`.
  String get invocation;

  /// Its tool: the definition `tools/list` sends, and how a call's fields
  /// become this command's arguments.
  McpTool get tool;

  /// Adds the command's own flags (not `--json` or `--help`) to [parser].
  void addFlags(ArgParser parser);

  /// Runs the command and returns its document. Throws a
  /// [NetUsageException] for a refused argument.
  Future<McpDocument> run(NetCommandContext context, ArgResults args);

  /// The document's answer as lines for a person, without `--json`.
  List<String> describe(Map<String, Object?> body);
}

/// The three open-core commands, in listing order.
List<NetCommand> openCoreNetCommands() => <NetCommand>[
  InfoCommand(),
  SearchCommand(),
  ConnectionsCommand(),
];

// ── shared helpers ──────────────────────────────────────────────────────────

/// The `design` field every tool has.
const McpField kNetDesignField = McpField(
  'design',
  kind: McpFieldKind.path,
  many: true,
  description: kNetDesignDescription,
);

/// The `top` field every tool has.
const McpField kNetTopField = McpField(
  'top',
  kind: McpFieldKind.text,
  flag: '--top',
);

/// The check every tool runs before its command: the files a manifest or a
/// filelist names are inside the root, each filelist confined before it is
/// read.
Future<RefusedPath?> checkNetDesignFiles(
  McpArguments arguments,
  Confinement confinement,
) async {
  final design = (arguments.values['design'] as List<Object?>?) ?? const [];
  final refusal = await checkNetDesignNamedFiles(
    <String>[for (final d in design) d! as String],
    (path) => switch (confinement.confine(path)) {
      ConfinedPath() => null,
      RefusedPath(:final message) => message,
    },
  );
  return refusal == null ? null : RefusedPath('design', refusal);
}

/// Adds `--top`.
void addNetTopFlag(ArgParser parser) => parser.addOption(
  'top',
  help: 'The top module. By default, the one Yosys or the netlist marks.',
  valueHelp: 'module',
);

/// The design files of [args]: every positional argument but the last
/// [trailing], made absolute.
List<String> netDesignArguments(ArgResults args, {int trailing = 0}) {
  final rest = args.rest;
  if (rest.length <= trailing) {
    throw const NetUsageException('give at least one design file');
  }
  return <String>[
    for (final f in rest.take(rest.length - trailing)) p.absolute(f),
  ];
}

String? _top(ArgResults args) {
  final top = args.option('top');
  if (top == null) return null;
  if (top.isEmpty || top.startsWith('-')) {
    throw NetUsageException('`--top $top` is not a module name');
  }
  return top;
}

/// The design [args] name, read, or the document that says why it is not.
///
/// Public so that a command defined outside this library reads, refuses and
/// maps a failure exactly as these three do.
Future<(NetDesign?, McpDocument?)> openNetDesignForCommand(
  NetCommandContext context,
  String command,
  ArgResults args, {
  int trailing = 0,
}) async {
  McpDocument fail(
    McpOutcome outcome,
    McpDiagnostic diagnostic, {
    List<McpEngine> engines = const <McpEngine>[],
  }) => McpDocument(
    tool: context.program,
    command: command,
    outcome: outcome,
    engines: engines,
    diagnostics: <McpDiagnostic>[diagnostic],
  );

  final files = netDesignArguments(args, trailing: trailing);
  final top = _top(args);
  try {
    final input = await resolveNetDesign(files, top: top);
    final (design, problem, engines) = await context.reader.read(input);
    if (design != null) return (design, null);
    final failure = context.mapProblem(problem!);
    return (null, fail(failure.outcome, failure.diagnostic, engines: engines));
  } on NetDesignException catch (e) {
    return (null, fail(e.outcome, e.diagnostic, engines: e.engines));
  }
}

/// A document that answers about [design].
McpDocument netAnswer(
  NetCommandContext context,
  String command,
  NetDesign design,
  Map<String, Object?> body, {
  List<McpDiagnostic> diagnostics = const <McpDiagnostic>[],
}) => McpDocument(
  tool: context.program,
  command: command,
  outcome: McpOutcome.completed,
  engines: design.engines,
  design: design.fingerprint,
  body: body,
  diagnostics: <McpDiagnostic>[...design.warnings, ...diagnostics],
);

/// The first place [src] (a Yosys `src` attribute) names, as a source
/// location; null when it names none.
McpSourceLocation? netSourceLocation(String? src) {
  final first = parseYosysSrc(src).firstOrNull;
  if (first == null) return null;
  return McpSourceLocation(
    file: first.filePath,
    line: first.line,
    column: first.column,
  );
}

/// Builds the locations of one document, and the warnings for names no link
/// can carry.
class NetLocations {
  /// Locations in [design].
  NetLocations(this.design);

  /// The design.
  final NetDesign design;

  final List<McpDiagnostic> _warnings = <McpDiagnostic>[];
  final Set<String> _warned = <String>{};

  /// One `link.unavailable` warning per name a link cannot carry.
  List<McpDiagnostic> get warnings => List.unmodifiable(_warnings);

  /// The location of the [kind] at the hierarchical [path] of [module],
  /// declared at [src]. It carries a link when the design's file can be
  /// opened by one and the app finds the element under that name
  /// ([findNetCruxLinkElement]), so no location carries a link that does
  /// not open.
  McpElementLocation element(
    McpElementKind kind,
    String path,
    String module, {
    String? src,
  }) {
    final source = netSourceLocation(src);
    final placeable =
        design.linked &&
        findNetCruxLinkElement(
              design.model,
              kind == McpElementKind.cell
                  ? NetCruxLinkElementKind.cell
                  : NetCruxLinkElementKind.net,
              path,
            ) !=
            null;
    if (placeable) {
      try {
        return McpElementLocation(
          file: design.file,
          kind: kind,
          name: path,
          module: module,
          src: source,
          linked: true,
        );
      } on McpLocationException catch (e) {
        if (_warned.add(path)) {
          _warnings.add(
            McpDiagnostic.warning(
              'link.unavailable',
              'no link can name `$path`: ${e.message}; its location gives '
                  'the file and the name only',
            ),
          );
        }
      }
    }
    return McpElementLocation(
      file: design.file,
      kind: kind,
      name: path,
      module: module,
      src: source,
    );
  }
}

/// The hierarchical name of [leaf] in [scope].
String netPath(NetlistModel model, HierarchyNode scope, String leaf) =>
    '${scope.canonicalPath(model)}.$leaf';

/// The scopes of [model] in pre-order, the top first, as the app's search
/// and hierarchy walk them: a recursive instantiation is not entered, and
/// the walk is bounded in count and depth.
Iterable<HierarchyNode> netScopes(NetlistModel model) sync* {
  final root = HierarchyNode.rootOf(model);
  if (root == null) return;
  final path = HierarchyWalkPath();
  final stack = <HierarchyWalkFrame>[HierarchyWalkFrame.root(root)];
  var visited = 0;
  while (stack.isNotEmpty && visited < maxHierarchyWalkScopes) {
    final frame = stack.removeLast();
    path.enter(frame);
    visited++;
    yield frame.node;
    if (!frame.canDescend) continue;
    final children = frame.node.childInstanceNames(model);
    for (var i = children.length - 1; i >= 0; i--) {
      final child = frame.node.child(model, children[i]);
      if (child == null) continue;
      final childFrame = path.childFrame(child);
      if (childFrame.isRecursive) continue;
      stack.add(childFrame);
    }
  }
}

int _limit(ArgResults args, {required int fallback, required int max}) {
  final raw = args.option('limit');
  if (raw == null) return fallback;
  final value = int.tryParse(raw);
  if (value == null || value < 1 || value > max) {
    throw NetUsageException('`--limit $raw` is a whole number from 1 to $max');
  }
  return value;
}

// ── info ────────────────────────────────────────────────────────────────────

/// `netcrux info <design>...`: the top module, hierarchy and cell and net
/// counts of a design.
class InfoCommand extends NetCommand {
  @override
  String get name => 'info';

  @override
  String get summary =>
      'Elaborate a design: its top module, hierarchy and cell and net counts.';

  @override
  String get invocation => 'netcrux info <design>... [--top <module>] [--json]';

  @override
  late final McpTool tool = McpTool(
    name: 'info',
    description:
        'Elaborate a design and return its top module, hierarchy and cell '
        'and net counts.',
    fields: const <McpField>[kNetDesignField, kNetTopField],
    required: const <String>['design'],
    checkNamedFiles: checkNetDesignFiles,
  );

  @override
  void addFlags(ArgParser parser) => addNetTopFlag(parser);

  @override
  Future<McpDocument> run(NetCommandContext context, ArgResults args) async {
    final (design, failed) = await openNetDesignForCommand(context, name, args);
    if (failed != null) return failed;
    final model = design!.model;
    final top = model.topModule!;
    var cells = 0;
    var nets = 0;
    for (final module in model.modules.values) {
      cells += module.cells.length;
      nets += module.nets.length;
    }
    final hierarchy = <Object?>[];
    var truncated = false;
    for (final scope in netScopes(model)) {
      if (hierarchy.length == kInfoHierarchyLimit) {
        truncated = true;
        break;
      }
      hierarchy.add(<String, Object?>{
        'path': scope.canonicalPath(model),
        'module': scope.moduleName,
        'cells': scope.resolve(model)?.cells.length ?? 0,
      });
    }
    return netAnswer(context, name, design, <String, Object?>{
      'top': top.name,
      'modules': model.modules.length,
      'cells': cells,
      'nets': nets,
      'hierarchy': hierarchy,
      'truncated': truncated,
    });
  }

  @override
  List<String> describe(Map<String, Object?> body) => <String>[
    _counts(body),
    for (final h
        in (body['hierarchy']! as List<Object?>).cast<Map<String, Object?>>())
      '  ${h['path']} (${h['module']}, ${h['cells']} cells)',
    if (body['truncated'] == true) '  ... more instances not listed',
  ];

  static String _counts(Map<String, Object?> body) =>
      'top ${body['top']}: ${body['modules']} modules, '
      '${body['cells']} cells, ${body['nets']} nets';
}

// ── search ──────────────────────────────────────────────────────────────────

/// `netcrux search <design>... <query>`: cells, nets, ports and modules by
/// name.
class SearchCommand extends NetCommand {
  @override
  String get name => 'search';

  @override
  String get summary =>
      'Find cells, nets, ports or modules by name; each hit with its source '
      'line.';

  @override
  String get invocation =>
      'netcrux search <design>... <query> [--top <module>] '
      '[--kind cell|net|port|module] [--glob] [--limit <n>] [--json]';

  @override
  late final McpTool tool = McpTool(
    name: 'search',
    description:
        'Find cells, nets, ports or modules by name in an elaborated design. '
        'Each hit carries its source line.',
    fields: const <McpField>[
      kNetDesignField,
      kNetTopField,
      McpField('query', kind: McpFieldKind.text),
      McpField(
        'kind',
        kind: McpFieldKind.text,
        flag: '--kind',
        description: 'cell, net, port or module.',
      ),
      McpField('glob', kind: McpFieldKind.boolean, flag: '--glob'),
      McpField(
        'limit',
        kind: McpFieldKind.integer,
        flag: '--limit',
        description: 'Default 50, at most 500.',
        minimum: 1,
      ),
    ],
    required: const <String>['design', 'query'],
    checkNamedFiles: checkNetDesignFiles,
  );

  @override
  void addFlags(ArgParser parser) {
    addNetTopFlag(parser);
    parser
      ..addOption(
        'kind',
        help: 'Only this kind of element: ${kSearchKinds.join(', ')}.',
        valueHelp: 'kind',
      )
      ..addFlag(
        'glob',
        negatable: false,
        help:
            'Match the whole name with * and ?. By default the query is a '
            'case-insensitive substring.',
      )
      ..addOption(
        'limit',
        help:
            'Hits to return, from 1 to $kSearchLimitMax '
            '(default $kSearchLimitDefault).',
        valueHelp: 'n',
      );
  }

  @override
  Future<McpDocument> run(NetCommandContext context, ArgResults args) async {
    final rest = args.rest;
    if (rest.length < 2) {
      throw const NetUsageException('give a design and a query');
    }
    final query = rest.last;
    if (query.trim().isEmpty) throw const NetUsageException('give a query');
    final kind = args.option('kind');
    if (kind != null && !kSearchKinds.contains(kind)) {
      throw NetUsageException(
        '`--kind $kind` is not cell, net, port or module',
      );
    }
    final limit = _limit(
      args,
      fallback: kSearchLimitDefault,
      max: kSearchLimitMax,
    );
    final mode = args.flag('glob') ? SearchMode.glob : SearchMode.substring;
    final (design, failed) = await openNetDesignForCommand(
      context,
      name,
      args,
      trailing: 1,
    );
    if (failed != null) return failed;
    final model = design!.model;
    final matches = DesignSearchService.matcherFor(query.trim(), mode)!;
    final locations = NetLocations(design);
    final hits = <Map<String, Object?>>[];
    var total = 0;
    var capped = false;
    void hit(Map<String, Object?> Function() make) {
      total++;
      if (hits.length < limit) hits.add(make());
    }

    if (kind == null || kind == 'cell' || kind == 'net') {
      final found = const DesignSearchService().search(
        model: model,
        query: query,
        mode: mode,
        maxResults: kSearchCountCap,
      );
      capped = found.length >= kSearchCountCap;
      for (final r in found) {
        final isNet = r.kind == SearchResultKind.net;
        if (kind == 'cell' && isNet) continue;
        if (kind == 'net' && !isNet) continue;
        final module = r.scopeNode.resolve(model)!;
        final path = netPath(model, r.scopeNode, r.name);
        hit(() {
          if (isNet) {
            final net = module.nets[r.name]!;
            return _hit(
              'net',
              path,
              module.name,
              type: null,
              width: net.width,
              location: locations.element(
                McpElementKind.net,
                path,
                module.name,
                src: net.attributes['src'],
              ),
            );
          }
          final cell = module.cells[r.name]!;
          return _hit(
            'cell',
            path,
            module.name,
            type: cell.type,
            width: null,
            location: locations.element(
              McpElementKind.cell,
              path,
              module.name,
              src: cell.attributes['src'],
            ),
          );
        });
      }
    }
    if (kind == null || kind == 'port') {
      for (final scope in netScopes(model)) {
        final module = scope.resolve(model);
        if (module == null) continue;
        for (final port in module.ports.values) {
          if (!matches(port.name)) continue;
          final path = netPath(model, scope, port.name);
          hit(
            () => _hit(
              'port',
              path,
              module.name,
              type: port.direction.toJsonString(),
              width: port.width,
              location: locations.element(
                McpElementKind.net,
                path,
                module.name,
                src: module.nets[port.name]?.attributes['src'],
              ),
            ),
          );
        }
      }
    }
    if (kind == null || kind == 'module') {
      for (final module in model.modules.values) {
        if (!matches(module.name)) continue;
        hit(
          () => _hit(
            'module',
            module.name,
            module.name,
            type: null,
            width: null,
            location: _moduleLocation(model, module, locations),
          ),
        );
      }
    }
    return netAnswer(
      context,
      name,
      design,
      <String, Object?>{
        'query': query,
        'total': total,
        'returned': hits.length,
        'truncated': total > hits.length,
        'hits': hits,
      },
      diagnostics: <McpDiagnostic>[
        ...locations.warnings,
        if (capped)
          const McpDiagnostic.warning(
            'search.count_capped',
            'more than $kSearchCountCap cells and nets match; `total` counts '
                'the first $kSearchCountCap of them',
            fix: 'narrow the query',
          ),
      ],
    );
  }

  static Map<String, Object?> _hit(
    String kind,
    String path,
    String module, {
    required String? type,
    required int? width,
    required McpLocation? location,
  }) => <String, Object?>{
    'kind': kind,
    'path': path,
    'module': module,
    'type': type,
    'width': width,
    'location': location?.toJson(),
  };

  /// Where a module is declared: its `src` line; else, for a module with no
  /// source line, its first instance in the hierarchy; null for a top
  /// module with neither.
  static McpLocation? _moduleLocation(
    NetlistModel model,
    Module module,
    NetLocations locations,
  ) {
    final src = netSourceLocation(module.attributes['src']);
    if (src != null) return src;
    for (final scope in netScopes(model)) {
      final parent = scope.resolve(model);
      if (parent == null) continue;
      for (final cell in parent.cells.values) {
        if (cell.type != module.name) continue;
        return locations.element(
          McpElementKind.cell,
          netPath(model, scope, cell.name),
          parent.name,
          src: cell.attributes['src'],
        );
      }
    }
    return null;
  }

  @override
  List<String> describe(Map<String, Object?> body) => <String>[
    for (final h
        in (body['hits']! as List<Object?>).cast<Map<String, Object?>>())
      _describeHit(h),
    '${body['returned']} of ${body['total']} hits',
  ];

  static String _describeHit(Map<String, Object?> h) {
    final type = h['type'] == null ? '' : '  ${h['type']}';
    final width = h['width'] == null ? '' : '  [${h['width']}]';
    return '${h['kind']}  ${h['path']}$type$width';
  }
}

// ── connections ─────────────────────────────────────────────────────────────

/// `netcrux connections <design>... <name>`: one step of connectivity of a
/// cell or a net, within its module.
class ConnectionsCommand extends NetCommand {
  @override
  String get name => 'connections';

  @override
  String get summary =>
      "A cell's pins and their nets, or a net's driving and driven pins.";

  @override
  String get invocation =>
      'netcrux connections <design>... <name> [--top <module>] [--json]';

  @override
  late final McpTool tool = McpTool(
    name: 'connections',
    description:
        'One step of connectivity within a module: for a cell, its pins and '
        'the net on each; for a net, the pins that drive it and the pins it '
        'drives.',
    fields: const <McpField>[
      kNetDesignField,
      kNetTopField,
      McpField(
        'name',
        kind: McpFieldKind.text,
        description: 'Hierarchical cell or net name.',
      ),
    ],
    required: const <String>['design', 'name'],
    checkNamedFiles: checkNetDesignFiles,
  );

  @override
  void addFlags(ArgParser parser) => addNetTopFlag(parser);

  @override
  Future<McpDocument> run(NetCommandContext context, ArgResults args) async {
    final rest = args.rest;
    if (rest.length < 2) {
      throw const NetUsageException('give a design and a cell or net name');
    }
    final name = rest.last;
    final (design, failed) = await openNetDesignForCommand(
      context,
      this.name,
      args,
      trailing: 1,
    );
    if (failed != null) return failed;
    final model = design!.model;
    final found = _find(model, name);
    if (found == null) {
      return McpDocument(
        tool: context.program,
        command: this.name,
        outcome: McpOutcome.inputError,
        engines: design.engines,
        design: design.fingerprint,
        diagnostics: <McpDiagnostic>[
          ...design.warnings,
          McpDiagnostic.error(
            'name.not_found',
            'the design has no cell or net `$name`',
            fix: 'find its full name with `netcrux search`',
          ),
        ],
      );
    }
    final (scope, leaf, isCell, ambiguous) = found;
    final module = scope.resolve(model)!;
    final scopePath = scope.canonicalPath(model);
    final locations = NetLocations(design);
    final bits = _BitNames(module, scopePath);
    final diagnostics = <McpDiagnostic>[
      if (ambiguous)
        McpDiagnostic.warning(
          'name.ambiguous',
          '`$leaf` names both a cell and a net in `$scopePath`; this is the '
              'cell',
        ),
    ];
    final Map<String, Object?> body;
    if (isCell) {
      final cell = module.cells[leaf]!;
      final path = '$scopePath.$leaf';
      final pins = <Object?>[];
      var truncated = false;
      for (final entry in cell.connections.entries) {
        if (pins.length == kConnectionsPinLimit) {
          truncated = true;
          break;
        }
        pins.add(<String, Object?>{
          'pin': entry.key,
          'direction': _direction(
            model,
            cell.type,
            cell.portDirections,
            entry.key,
          ),
          'net': bits.text(entry.value),
        });
      }
      body = <String, Object?>{
        'kind': 'cell',
        'path': path,
        'module': module.name,
        'location': locations
            .element(
              McpElementKind.cell,
              path,
              module.name,
              src: cell.attributes['src'],
            )
            .toJson(),
        'pins': pins,
        'drivers': null,
        'loads': null,
        'truncated': truncated,
      };
    } else {
      final net = findNetNamed(module, leaf)!;
      final path = '$scopePath.${net.name}';
      final ids = <int>{
        for (final b in net.bits)
          if (b is NetBit) b.netId,
      };
      bool touches(List<BitRef> pinBits) =>
          pinBits.any((b) => b is NetBit && ids.contains(b.netId));
      final drivers = <Map<String, Object?>>[];
      final loads = <Map<String, Object?>>[];
      for (final cell in module.cells.values) {
        for (final entry in cell.connections.entries) {
          if (!touches(entry.value)) continue;
          final direction = _direction(
            model,
            cell.type,
            cell.portDirections,
            entry.key,
          );
          final cellPath = '$scopePath.${cell.name}';
          Map<String, Object?> pin() => <String, Object?>{
            'cell': cellPath,
            'pin': entry.key,
            'location': locations
                .element(
                  McpElementKind.cell,
                  cellPath,
                  module.name,
                  src: cell.attributes['src'],
                )
                .toJson(),
          };
          if (direction != 'input') drivers.add(pin());
          if (direction != 'output') loads.add(pin());
        }
      }
      // A module port is a pin of the scope itself: an input drives the net
      // from outside, an output carries it out.
      for (final port in module.ports.values) {
        if (!touches(port.bits)) continue;
        final portPath = '$scopePath.${port.name}';
        Map<String, Object?> pin() => <String, Object?>{
          'cell': scopePath,
          'pin': port.name,
          'location': locations
              .element(
                McpElementKind.net,
                portPath,
                module.name,
                src: module.nets[port.name]?.attributes['src'],
              )
              .toJson(),
        };
        if (port.direction != PortDirection.output) drivers.add(pin());
        if (port.direction != PortDirection.input) loads.add(pin());
      }
      final keptDrivers = drivers.take(kConnectionsPinLimit).toList();
      final keptLoads = loads
          .take(kConnectionsPinLimit - keptDrivers.length)
          .toList();
      body = <String, Object?>{
        'kind': 'net',
        'path': path,
        'module': module.name,
        'location': locations
            .element(
              McpElementKind.net,
              path,
              module.name,
              src: net.attributes['src'],
            )
            .toJson(),
        'pins': null,
        'drivers': keptDrivers,
        'loads': keptLoads,
        'truncated':
            keptDrivers.length + keptLoads.length <
            drivers.length + loads.length,
      };
    }
    return netAnswer(
      context,
      this.name,
      design,
      body,
      diagnostics: <McpDiagnostic>[...diagnostics, ...locations.warnings],
    );
  }

  /// The scope and leaf [name] names, whether it is a cell, and whether a
  /// net has the same name; null when the design has neither. The reading
  /// rule is the link's ([findNetCruxLinkElement]): rooted at the top
  /// first, then from just below it; never the last segment alone.
  static (HierarchyNode, String, bool, bool)? _find(
    NetlistModel model,
    String name,
  ) {
    final top = model.topModule?.name;
    final candidates = <String>[
      name,
      if (top != null && !name.startsWith('$top.')) '$top.$name',
    ];
    for (final candidate in candidates) {
      final scoped = scopeOfHierarchicalName(model, candidate);
      final module = scoped?.scope.resolve(model);
      if (scoped == null || module == null) continue;
      final isCell = module.cells.containsKey(scoped.leaf);
      final net = findNetNamed(module, scoped.leaf);
      if (isCell) return (scoped.scope, scoped.leaf, true, net != null);
      if (net != null) return (scoped.scope, scoped.leaf, false, false);
    }
    return null;
  }

  /// The direction of [pin] on a cell of [type]: the netlist's own, else
  /// the port of the module [type] names; null when neither says.
  static String? _direction(
    NetlistModel model,
    String type,
    Map<String, PortDirection> directions,
    String pin,
  ) => (directions[pin] ?? model.modules[type]?.ports[pin]?.direction)
      ?.toJsonString();

  @override
  List<String> describe(Map<String, Object?> body) {
    List<Map<String, Object?>> list(String key) =>
        ((body[key] as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>();
    if (body['kind'] == 'cell') {
      return <String>[
        'cell ${body['path']} in ${body['module']}',
        for (final pin in list('pins'))
          '  ${pin['pin']} (${pin['direction'] ?? 'unknown'}) ${pin['net']}',
      ];
    }
    return <String>[
      'net ${body['path']} in ${body['module']}',
      for (final d in list('drivers')) '  driven by ${d['cell']}.${d['pin']}',
      for (final l in list('loads')) '  drives ${l['cell']}.${l['pin']}',
    ];
  }
}

/// The text of a pin's bits: the hierarchical name of the net they make up
/// (`top.u.data`), a slice of one (`top.u.data[7:4]`, `top.u.data[3]`,
/// positions counted from 0 at the net's least significant bit), a constant
/// (`1'b0`), or a concatenation of single bits, most significant first
/// (`{top.u.a[1], 1'b0}`). A named net is preferred to one Yosys named.
class _BitNames {
  _BitNames(this.module, this.scope) {
    for (final internal in <bool>[false, true]) {
      for (final net in module.nets.values) {
        if ((net.hideName || net.name.startsWith(r'$')) != internal) continue;
        for (var i = 0; i < net.bits.length; i++) {
          final bit = net.bits[i];
          if (bit is NetBit) _of.putIfAbsent(bit.netId, () => (net.name, i));
        }
      }
    }
  }

  final Module module;
  final String scope;
  final Map<int, (String, int)> _of = <int, (String, int)>{};

  String text(List<BitRef> bits) {
    if (bits.isEmpty) return '';
    final named = <(String, int)?>[
      for (final b in bits) _named(b),
    ];
    if (named.every((n) => n != null)) {
      final net = named.first!.$1;
      final start = named.first!.$2;
      var contiguous = true;
      for (var i = 0; i < named.length; i++) {
        if (named[i]!.$1 != net || named[i]!.$2 != start + i) {
          contiguous = false;
          break;
        }
      }
      if (contiguous) {
        final width = module.nets[net]!.width;
        if (start == 0 && named.length == width) return '$scope.$net';
        if (named.length == 1) return '$scope.$net[$start]';
        return '$scope.$net[${start + named.length - 1}:$start]';
      }
    }
    final parts = <String>[
      for (var i = bits.length - 1; i >= 0; i--) _bit(bits[i], named[i]),
    ];
    return parts.length == 1 ? parts.single : '{${parts.join(', ')}}';
  }

  (String, int)? _named(BitRef bit) => switch (bit) {
    NetBit(:final netId) => _of[netId],
    ConstantBit() => null,
  };

  String _bit(BitRef bit, (String, int)? named) {
    switch (bit) {
      case ConstantBit():
        return "1'b${bit.toJson()}";
      case NetBit(:final netId):
        if (named == null) return '\$$netId';
        final width = module.nets[named.$1]!.width;
        return width == 1
            ? '$scope.${named.$1}'
            : '$scope.${named.$1}[${named.$2}]';
    }
  }
}
