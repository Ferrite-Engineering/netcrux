// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Renders one scope of a design to an SVG or PNG file without opening the
// app: for CI, documentation, and sharing a picture of a design.
//
//   dart run tool/render_schematic.dart [options] --out FILE.svg|FILE.png \
//       <source files... | netlist.json>
//
// Options:
//   --top NAME          top module (otherwise Yosys picks the uninstantiated one)
//   --scope PATH        instance path below the top, e.g. u_core.u_rf
//   -D NAME[=VALUE]     preprocessor define, repeatable (also --define)
//   -I DIR              include directory, repeatable (also --include)
//   --zoom Z            PNG pixels per layout unit (default 1.0)
//   --region X,Y,W,H    the part of the layout to show, in layout units
//   --theme dark|light  PNG colours (default dark)
//   --font FILE.ttf     label font for a PNG (default: Arial where present)
//
// Sources are elaborated with Yosys as NetCrux elaborates them; a single
// `.json` argument is read as an already elaborated Yosys netlist. The layout
// is the app's own (the native engine: build it first with
// `cargo build --release --manifest-path native/elk_ffi/Cargo.toml`). The
// drawing is done by `test/tools/render_schematic_test.dart` under
// `flutter test`, which provides the Flutter engine the painter needs.
//
// Run from the open-core checkout root. Exit status: 0 written, 64 bad
// arguments, 65 elaboration failed, 70 the render failed.

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:path/path.dart' as p;

const _usage =
    'usage: dart run tool/render_schematic.dart [--top NAME] [--scope PATH] '
    '[-D NAME[=VALUE]]... [-I DIR]... [--zoom Z] [--region X,Y,W,H] '
    '[--theme dark|light] [--font FILE.ttf] --out FILE.svg|FILE.png '
    '<sources... | netlist.json>';

const _defaultFonts = <String>[
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  '/Library/Fonts/Arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  r'C:\Windows\Fonts\arial.ttf',
];

Never _fail(String message, int code) {
  stderr.writeln('render_schematic: $message');
  exit(code);
}

Future<void> main(List<String> argv) async {
  String? top;
  var scope = '';
  String? out;
  var zoom = 1.0;
  String? region;
  var theme = 'dark';
  String? font;
  final defines = <String>[];
  final includes = <String>[];
  final inputs = <String>[];

  String value(int i, String flag) {
    if (i >= argv.length) _fail('$flag needs a value\n$_usage', 64);
    return argv[i];
  }

  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    switch (arg) {
      case '--top':
        top = value(++i, arg);
      case '--scope':
        scope = value(++i, arg);
      case '--out':
      case '-o':
        out = value(++i, arg);
      case '--zoom':
        final z = double.tryParse(value(++i, arg));
        if (z == null || z <= 0) _fail('--zoom must be a positive number', 64);
        zoom = z;
      case '--region':
        region = value(++i, arg);
      case '--theme':
        theme = value(++i, arg);
        if (theme != 'dark' && theme != 'light') {
          _fail('--theme is dark or light', 64);
        }
      case '--font':
        font = value(++i, arg);
      case '-D':
      case '--define':
        defines.add(value(++i, arg));
      case '-I':
      case '--include':
        includes.add(value(++i, arg));
      case '-h':
      case '--help':
        stdout.writeln(_usage);
        return;
      default:
        if (arg.startsWith('-D') && arg.length > 2) {
          defines.add(arg.substring(2));
        } else if (arg.startsWith('-I') && arg.length > 2) {
          includes.add(arg.substring(2));
        } else if (arg.startsWith('-')) {
          _fail('unknown option $arg\n$_usage', 64);
        } else {
          inputs.add(arg);
        }
    }
  }
  if (out == null) _fail('--out is required\n$_usage', 64);
  final extension = p.extension(out).toLowerCase();
  if (extension != '.svg' && extension != '.png') {
    _fail('--out must end in .svg or .png', 64);
  }
  if (inputs.isEmpty) _fail('no sources given\n$_usage', 64);
  for (final input in inputs) {
    if (!File(input).existsSync()) _fail('no such file: $input', 64);
  }

  final work = await Directory.systemTemp.createTemp('netcrux_render_');
  try {
    final String netlist;
    if (inputs.length == 1 && p.extension(inputs.single) == '.json') {
      netlist = p.absolute(inputs.single);
    } else {
      netlist = await _elaborate(work, inputs, top, defines, includes);
    }
    font ??= _defaultFonts.firstWhere(
      (f) => File(f).existsSync(),
      orElse: () => '',
    );
    final request = <String, Object?>{
      'netlist': netlist,
      'scope': scope,
      'out': p.absolute(out),
      'zoom': zoom,
      'region': region,
      'theme': theme,
      if (font.isNotEmpty) 'font': p.absolute(font),
    };
    final encoded = base64Url.encode(utf8.encode(jsonEncode(request)));
    final harness = Process.runSync(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      <String>[
        'test',
        'test/tools/render_schematic_test.dart',
        '--dart-define=NETCRUX_RENDER=$encoded',
        '--reporter=expanded',
      ],
    );
    if (harness.exitCode != 0) {
      stderr
        ..write(harness.stdout)
        ..write(harness.stderr);
      _fail('the render failed (flutter test exit ${harness.exitCode})', 70);
    }
    if (!File(out).existsSync()) _fail('the render wrote no file', 70);
    stdout.writeln('wrote $out');
  } finally {
    await work.delete(recursive: true);
  }
}

/// Elaborates [sources] with Yosys and returns the path of the netlist JSON,
/// moved into [work] so the caller's removal of [work] deletes it.
Future<String> _elaborate(
  Directory work,
  List<String> sources,
  String? top,
  List<String> defines,
  List<String> includes,
) async {
  YosysSourceFile source(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.sv' || '.svh' => YosysSourceFile.systemVerilog(path),
        '.vhd' || '.vhdl' => YosysSourceFile.vhdl(path),
        _ => YosysSourceFile(path),
      };
  final result = await YosysRunner().runKeepingJson(
    YosysRunRequest(
      sources: <YosysSourceFile>[for (final s in sources) source(s)],
      topModule: top,
      vhdlTopUnit: top,
      defines: defines,
      includePaths: includes,
    ),
  );
  switch (result) {
    case YosysRunSuccess(:final jsonPath?):
      final kept = File(jsonPath);
      final target = p.join(work.path, 'netlist.json');
      try {
        kept.renameSync(target);
      } on FileSystemException {
        kept
          ..copySync(target)
          ..deleteSync();
      }
      return target;
    case YosysRunSuccess():
      _fail('Yosys wrote no netlist', 65);
    case YosysRunFailure(:final stderr):
      _fail('Yosys could not elaborate the sources:\n$stderr', 65);
    case YosysRunTimeout() || YosysRunCancelled():
      _fail('Yosys did not finish', 65);
  }
}
