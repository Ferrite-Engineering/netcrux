// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';

import 'package:meta/meta.dart';
// The netlist shims each re-export the whole model.
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/rohd_netlist_extensions.dart';

/// What [inferBlackBoxPorts] found: the module types that nothing defines,
/// the pins that a cell's definition does not declare, and how many pins it
/// gave a direction to.
@immutable
class BlackBoxReport {
  /// Creates a report.
  const BlackBoxReport({
    required this.types,
    required this.pinCount,
    required this.guessedPinCount,
    this.undeclaredPins = const <String>[],
    this.undeclaredPinCount = 0,
  });

  /// A report of a netlist with no undefined module types.
  static const BlackBoxReport none = BlackBoxReport(
    types: <String>[],
    pinCount: 0,
    guessedPinCount: 0,
  );

  /// The undefined module types drawn as black boxes, sorted.
  final List<String> types;

  /// Black-box pins whose direction was inferred (every pin of every
  /// black-box instance that Yosys gave no direction, and every connection
  /// to a pin its cell's definition does not declare).
  final int pinCount;

  /// Of [pinCount], the pins the wiring did not decide: see
  /// [inferBlackBoxPorts].
  final int guessedPinCount;

  /// The pins an instance connects that the definition of its module does
  /// not declare, as `TYPE.PIN`, sorted and without repeats.
  final List<String> undeclaredPins;

  /// Of [pinCount], the connections to such pins, one for each instance.
  final int undeclaredPinCount;

  /// Whether the netlist had no black boxes and no undeclared pins at all.
  bool get isEmpty => types.isEmpty && undeclaredPins.isEmpty;

  /// The `Warning:` lines for the diagnostics drawer, in the form the
  /// elaboration stderr uses; empty when [isEmpty].
  List<String> get warningLines {
    if (isEmpty) return const <String>[];
    const shown = 20;
    String list(List<String> names) => names.length <= shown
        ? names.join(', ')
        : '${names.take(shown).join(', ')} and ${names.length - shown} more';
    final lines = <String>[];
    if (types.isNotEmpty) {
      final typeNoun = types.length == 1 ? 'type' : 'types';
      lines.add(
        'Warning: No definition found for ${types.length} module $typeNoun, '
        'drawn as black boxes with pin directions inferred from the wiring: '
        '${list(types)}.',
      );
    }
    if (undeclaredPins.isNotEmpty) {
      final pinNoun = undeclaredPins.length == 1 ? 'pin' : 'pins';
      final connectionNoun = undeclaredPinCount == 1
          ? 'connection'
          : 'connections';
      lines.add(
        'Warning: $undeclaredPinCount $connectionNoun to '
        '${undeclaredPins.length} $pinNoun that the module definition does '
        'not declare, with directions inferred from the wiring: '
        '${list(undeclaredPins)}.',
      );
    }
    if (guessedPinCount != 0) {
      final pinNoun = pinCount == 1 ? 'pin' : 'pins';
      final verb = guessedPinCount == 1 ? 'was' : 'were';
      final remedy = types.isEmpty
          ? 'Check the cell library for these pins.'
          : 'Add a cell library (Liberty) for exact pins.';
      lines.add(
        'Warning: $guessedPinCount of $pinCount black-box $pinNoun had no '
        'direction the wiring decided and $verb guessed. $remedy',
      );
    }
    return lines;
  }

  @override
  bool operator ==(Object other) =>
      other is BlackBoxReport &&
      other.pinCount == pinCount &&
      other.guessedPinCount == guessedPinCount &&
      other.undeclaredPinCount == undeclaredPinCount &&
      _listEquals(other.types, types) &&
      _listEquals(other.undeclaredPins, undeclaredPins);

  @override
  int get hashCode => Object.hash(
    pinCount,
    guessedPinCount,
    undeclaredPinCount,
    Object.hashAll(types),
    Object.hashAll(undeclaredPins),
  );

  @override
  String toString() =>
      'BlackBoxReport(types: $types, pins: $pinCount, '
      'guessed: $guessedPinCount, undeclared: $undeclaredPins)';
}

/// Whether a cell of [type] is an instance of a module that [model] does
/// not define: neither one of its modules nor a Yosys internal cell (every
/// internal cell type starts with `$`), nor, in a netlist written by ROHD,
/// one of the procedural block types that format defines
/// ([rohdBlockCellTypes]).
bool isUndefinedModuleType(NetlistModel model, String type) =>
    !type.startsWith(r'$') &&
    !model.modules.containsKey(type) &&
    !(isRohdCreator(model.creator) && rohdBlockCellTypes.contains(type));

/// Gives every pin of every black-box cell in [model] a direction.
///
/// A black box is a cell whose type [isUndefinedModuleType]: what Yosys
/// keeps of an instance of a missing module when `hierarchy` runs without
/// `-check`, with the connections the instance makes and no
/// `port_directions`. A direction Yosys did give a pin is kept and used as
/// evidence; every other pin is inferred, one module at a time, from what
/// else sits on the bits it connects.
///
/// A cell of a module that is defined (a cell library's stub, say) can also
/// connect a pin the definition does not declare, which `hierarchy` without
/// `-check` allows. Yosys gives such a pin the direction `output`, which
/// would read as a second driver on its net, so it is not believed: the pin
/// is inferred like a black-box pin, and the pins the definition does
/// declare keep their declared directions and are evidence like any known
/// cell's. The inference rules are:
///
/// * **Input** when any of its bits is driven by something else: a
///   constant `0`, `1` or `x`, an input or inout port of the module, an
///   output or inout pin of a cell whose ports are known, or a black-box pin
///   already inferred as an output.
/// * **Output** when, for any of its bits, nothing else drives the bit, no
///   other undecided black-box pin is on it (that pin might be the driver),
///   and something reads it: an output port of the module, an input pin of
///   a known cell, or a black-box pin already inferred as an input.
/// * Evidence each way, on different bits, decides nothing.
///
/// Each decision is evidence for the pins it shares bits with, so the rules
/// run to a fixed point. When they stall, one more rule breaks the tie in a
/// chain of black boxes: a cell with no output yet whose one undecided pin
/// shares a bit with another pin and has nothing else driving it gets that
/// pin as its output (every cell drives something), and the rules run
/// again. A pin decided this way, and
/// any pin still undecided at the end, which becomes an input, count in
/// [BlackBoxReport.guessedPinCount]. So a power pin wired to a supply port
/// or a constant reads as an input.
///
/// Positional connections (`$1`, `$2`, ...) are put in numeric order, as
/// the instance wrote them; Yosys sorts them as strings (`$10` before `$2`).
///
/// Returns [model] itself, with [BlackBoxReport.none], when it has no black
/// boxes.
({NetlistModel model, BlackBoxReport report}) inferBlackBoxPorts(
  NetlistModel model,
) {
  final types = SplayTreeSet<String>();
  final undeclared = SplayTreeSet<String>();
  var pinCount = 0;
  var guessed = 0;
  var undeclaredCount = 0;
  Map<String, Module>? patched;
  for (final entry in model.modules.entries) {
    final result = _inferModule(model, entry.value);
    if (result == null) continue;
    types.addAll(result.types);
    undeclared.addAll(result.undeclaredPins);
    pinCount += result.pinCount;
    guessed += result.guessed;
    undeclaredCount += result.undeclaredCount;
    (patched ??= Map<String, Module>.of(model.modules))[entry.key] =
        result.module;
  }
  if (patched == null) return (model: model, report: BlackBoxReport.none);
  return (
    model: model.copyWith(modules: patched),
    report: BlackBoxReport(
      types: List<String>.unmodifiable(types),
      pinCount: pinCount,
      guessedPinCount: guessed,
      undeclaredPins: List<String>.unmodifiable(undeclared),
      undeclaredPinCount: undeclaredCount,
    ),
  );
}

/// One black-box pin being inferred.
class _Pin {
  _Pin(this.cell, this.name, this.bits);

  final int cell;
  final String name;
  final List<BitRef> bits;
  PortDirection? direction;
  bool guessed = false;
}

/// What is known about one net bit of the module.
class _Bit {
  /// Drivers fixed before inference: module input/inout ports, known cells'
  /// output/inout pins, black-box pins Yosys gave a direction.
  int drivers = 0;

  /// Readers fixed before inference: module output ports, known cells'
  /// input pins.
  int readers = 0;

  /// Black-box pins inferred so far as outputs / inputs.
  int inferredOutputs = 0;
  int inferredInputs = 0;

  /// Occurrences of undecided black-box pins on this bit (a pin listing the
  /// bit twice counts twice).
  int undecided = 0;

  /// Every black-box pin to infer that touches this bit, by index.
  final List<int> pins = <int>[];

  bool get driven => drivers + inferredOutputs > 0;
  bool get read => readers + inferredInputs > 0;
}

typedef _ModuleResult = ({
  Module module,
  Set<String> types,
  Set<String> undeclaredPins,
  int pinCount,
  int guessed,
  int undeclaredCount,
});

/// The connections of [cell] to pins that the definition of its module does
/// not declare, or `null` when the cell has none: its type is not defined in
/// [model] (a black box), or is a Yosys internal cell, or every connection
/// is to a declared pin.
Set<String>? _undeclaredPins(NetlistModel model, Cell cell) {
  final definition = model.modules[cell.type];
  if (definition == null) return null;
  Set<String>? extra;
  for (final name in cell.connections.keys) {
    if (!definition.ports.containsKey(name)) (extra ??= <String>{}).add(name);
  }
  return extra;
}

_ModuleResult? _inferModule(NetlistModel model, Module module) {
  // Cells with pins to infer, in the module's order: black boxes (every
  // pin Yosys gave no direction) and cells of a defined module that connect
  // a pin its definition does not declare (just those pins).
  final blackBoxNames = <String>{};
  final undeclared = <String, Set<String>>{};
  final cellNames = <String>[];
  for (final entry in module.cells.entries) {
    final cell = entry.value;
    if (isUndefinedModuleType(model, cell.type)) {
      blackBoxNames.add(entry.key);
      cellNames.add(entry.key);
      continue;
    }
    final extra = _undeclaredPins(model, cell);
    if (extra == null) continue;
    undeclared[entry.key] = extra;
    cellNames.add(entry.key);
  }
  if (cellNames.isEmpty) return null;

  final bits = <int, _Bit>{};
  _Bit bitFor(int id) => bits.putIfAbsent(id, _Bit.new);

  for (final port in module.ports.values) {
    for (final bit in port.bits) {
      if (bit is! NetBit) continue;
      switch (port.direction) {
        case PortDirection.input:
        case PortDirection.inout:
          bitFor(bit.netId).drivers++;
        case PortDirection.output:
          bitFor(bit.netId).readers++;
      }
    }
  }

  final pins = <_Pin>[];
  final cellPins = <List<int>>[];
  for (final entry in module.cells.entries) {
    final cell = entry.value;
    final isBlackBox = blackBoxNames.contains(entry.key);
    final extra = undeclared[entry.key];
    final ownPins = <int>[];
    for (final connection in cell.connections.entries) {
      // Yosys's direction for a pin the definition lacks is its default,
      // not evidence.
      final isExtra = extra?.contains(connection.key) ?? false;
      final known = isExtra ? null : cell.portDirections[connection.key];
      if (known == null && (isBlackBox || isExtra)) {
        ownPins.add(pins.length);
        pins.add(_Pin(cellPins.length, connection.key, connection.value));
        continue;
      }
      // A known cell's pin with no direction (not something Yosys writes)
      // is no evidence either way.
      if (known == null) continue;
      for (final bit in connection.value) {
        if (bit is! NetBit) continue;
        switch (known) {
          case PortDirection.output:
          case PortDirection.inout:
            bitFor(bit.netId).drivers++;
          case PortDirection.input:
            bitFor(bit.netId).readers++;
        }
      }
    }
    if (isBlackBox || extra != null) cellPins.add(ownPins);
  }
  // Cells whose given directions already include an output (not counting
  // an undeclared pin's default).
  final cellHasOutput = List<bool>.filled(cellPins.length, false);
  {
    var index = 0;
    for (final name in cellNames) {
      final cell = module.cells[name]!;
      final extra = undeclared[name];
      cellHasOutput[index++] = cell.portDirections.entries.any(
        (e) =>
            e.value != PortDirection.input &&
            !(extra?.contains(e.key) ?? false),
      );
    }
  }

  for (var i = 0; i < pins.length; i++) {
    for (final bit in pins[i].bits) {
      if (bit is! NetBit) continue;
      final info = bitFor(bit.netId);
      info.undecided++;
      if (info.pins.isEmpty || info.pins.last != i) info.pins.add(i);
    }
  }

  // Pins to (re)evaluate under the wiring rules, and cells to try the
  // one-output rule on once those stall. Each queue holds an index at most
  // once.
  final pinQueue = Queue<int>();
  final inPinQueue = List<bool>.filled(pins.length, false);
  void enqueuePin(int i) {
    if (pins[i].direction != null || inPinQueue[i]) return;
    inPinQueue[i] = true;
    pinQueue.add(i);
  }

  final cellQueue = Queue<int>();
  final inCellQueue = List<bool>.filled(cellPins.length, false);
  void enqueueCell(int c) {
    if (inCellQueue[c]) return;
    inCellQueue[c] = true;
    cellQueue.add(c);
  }

  void decide(int i, PortDirection direction, {required bool guess}) {
    final pin = pins[i]
      ..direction = direction
      ..guessed = guess;
    if (direction == PortDirection.output) cellHasOutput[pin.cell] = true;
    for (final bit in pin.bits) {
      if (bit is! NetBit) continue;
      final info = bits[bit.netId]!;
      // Whether the other pins on this bit could read differently now: an
      // output drives them all; an input only matters on a bit nothing
      // drives, where it is a new reader and one fewer rival driver.
      final affectsOthers = direction == PortDirection.output || !info.driven;
      info.undecided--;
      if (direction == PortDirection.output) {
        info.inferredOutputs++;
      } else {
        info.inferredInputs++;
      }
      if (affectsOthers) info.pins.forEach(enqueuePin);
    }
    enqueueCell(pin.cell);
  }

  /// The wiring rules' verdict on undecided pin [i]: input, output, or
  /// `null` for no evidence or evidence both ways.
  PortDirection? verdict(int i) {
    final pin = pins[i];
    var input = false;
    var output = false;
    for (final bit in pin.bits) {
      switch (bit) {
        case ConstantBit(:final value):
          if (value != ConstantBitValue.z) input = true;
        case NetBit(:final netId):
          final info = bits[netId]!;
          if (info.driven) {
            input = true;
          } else if (info.read &&
              info.undecided == _occurrences(pin.bits, netId)) {
            output = true;
          }
      }
    }
    if (input == output) return null;
    return input ? PortDirection.input : PortDirection.output;
  }

  /// Whether undecided pin [i] can be its cell's output: no bit of it is
  /// driven by anything else (no second driver), and some bit has something
  /// else on it to drive (a pin with no other connection stays undecided).
  bool canDrive(int i) {
    final pin = pins[i];
    var company = false;
    for (final bit in pin.bits) {
      switch (bit) {
        case ConstantBit(:final value):
          if (value != ConstantBitValue.z) return false;
        case NetBit(:final netId):
          final info = bits[netId]!;
          if (info.driven) return false;
          if (info.read || info.undecided > _occurrences(pin.bits, netId)) {
            company = true;
          }
      }
    }
    return company;
  }

  for (var i = 0; i < pins.length; i++) {
    enqueuePin(i);
  }
  for (var c = 0; c < cellPins.length; c++) {
    enqueueCell(c);
  }
  while (true) {
    while (pinQueue.isNotEmpty) {
      final i = pinQueue.removeFirst();
      inPinQueue[i] = false;
      if (pins[i].direction != null) continue;
      final direction = verdict(i);
      if (direction != null) decide(i, direction, guess: false);
    }
    if (cellQueue.isEmpty) break;
    final c = cellQueue.removeFirst();
    inCellQueue[c] = false;
    if (cellHasOutput[c]) continue;
    int? only;
    var undecided = 0;
    for (final i in cellPins[c]) {
      if (pins[i].direction != null) continue;
      undecided++;
      only = i;
    }
    if (undecided == 1 && canDrive(only!)) {
      decide(only, PortDirection.output, guess: true);
    }
  }

  var guessed = 0;
  for (final pin in pins) {
    if (pin.direction == null) {
      pin
        ..direction = PortDirection.input
        ..guessed = true;
    }
    if (pin.guessed) guessed++;
  }

  final cells = Map<String, Cell>.of(module.cells);
  final types = <String>{};
  final undeclaredPins = <String>{};
  var undeclaredCount = 0;
  for (var c = 0; c < cellNames.length; c++) {
    final name = cellNames[c];
    final cell = module.cells[name]!;
    final extra = undeclared[name];
    if (extra == null) {
      types.add(cell.type);
    } else {
      undeclaredCount += extra.length;
      for (final pin in extra) {
        undeclaredPins.add('${cell.type}.$pin');
      }
    }
    final inferred = <String, PortDirection>{
      for (final i in cellPins[c]) pins[i].name: pins[i].direction!,
    };
    final connections = _inInstanceOrder(cell.connections);
    cells[name] = cell.copyWith(
      connections: connections,
      portDirections: <String, PortDirection>{
        for (final port in connections.keys)
          port: ?(inferred[port] ?? cell.portDirections[port]),
      },
    );
  }
  return (
    module: module.copyWith(cells: cells),
    types: types,
    undeclaredPins: undeclaredPins,
    pinCount: pins.length,
    guessed: guessed,
    undeclaredCount: undeclaredCount,
  );
}

int _occurrences(List<BitRef> bits, int netId) {
  var n = 0;
  for (final bit in bits) {
    if (bit is NetBit && bit.netId == netId) n++;
  }
  return n;
}

final RegExp _positional = RegExp(r'^\$(\d+)$');

/// [connections] with positional names (`$1`, `$2`, ...) in numeric order
/// when every name is positional; otherwise as given.
Map<String, List<BitRef>> _inInstanceOrder(
  Map<String, List<BitRef>> connections,
) {
  if (connections.isEmpty || !connections.keys.every(_positional.hasMatch)) {
    return connections;
  }
  int index(String name) => int.parse(_positional.firstMatch(name)!.group(1)!);
  final names = connections.keys.toList()
    ..sort((a, b) => index(a).compareTo(index(b)));
  return <String, List<BitRef>>{
    for (final name in names) name: connections[name]!,
  };
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
