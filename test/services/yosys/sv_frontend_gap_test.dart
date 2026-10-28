// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Recognising the SystemVerilog Yosys's built-in reader refuses, from the
// stderr of a failed run. The messages are Yosys 0.69's, captured on the
// eduBOS5 RV32I core (openPCIE) and on minimal reductions of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/sv_frontend_gap.dart';

void main() {
  String? noSource(String path, int line) => null;

  test('a return in a function is recognised from the source line', () {
    const stderr =
        '/work/edubos5_pkg.sv:182: ERROR: syntax error, unexpected TOK_ID\n';
    expect(
      svFrontendGapIn(
        stderr,
        readLine: (path, line) {
          expect(path, '/work/edubos5_pkg.sv');
          expect(line, 182);
          return '    return y;';
        },
      ),
      SvFrontendGap.returnStatement,
    );
  });

  test('the same syntax error on any other line is not a gap', () {
    const stderr = '/work/top.sv:7: ERROR: syntax error, unexpected TOK_ID\n';
    expect(
      svFrontendGapIn(stderr, readLine: (_, _) => '  wire foo bar;'),
      isNull,
    );
    expect(svFrontendGapIn(stderr, readLine: noSource), isNull);
  });

  test('a package import in a module header or body', () {
    expect(
      svFrontendGapIn(
        '/work/edubos5_rf.sv:10: ERROR: syntax error, unexpected TOK_IMPORT, '
        "expecting '#' or '(' or ';'\n",
        readLine: noSource,
      ),
      SvFrontendGap.packageImport,
    );
    expect(
      svFrontendGapIn(
        '/work/cast.sv:5: ERROR: syntax error, unexpected TOK_IMPORT\n',
        readLine: noSource,
      ),
      SvFrontendGap.packageImport,
    );
  });

  test('a cast of a non-constant expression to a type', () {
    expect(
      svFrontendGapIn(
        '/work/edubos5.sv:258: ERROR: Static cast with non constant '
        'expression!\n',
        readLine: noSource,
      ),
      SvFrontendGap.nonConstantCast,
    );
  });

  test('only the first error counts, and other failures are not gaps', () {
    expect(
      svFrontendGapIn(
        'Warning: something\n'
        "/work/a.v:3: ERROR: Identifier `\\x' is implicitly declared.\n"
        '/work/b.sv:9: ERROR: syntax error, unexpected TOK_IMPORT\n',
        readLine: noSource,
      ),
      isNull,
    );
    expect(
      svFrontendGapIn(
        r"ERROR: Module `\sub' referenced in module `\top' is not part of "
        'the design.\n',
        readLine: noSource,
      ),
      isNull,
    );
    expect(svFrontendGapIn('', readLine: noSource), isNull);
  });
}
