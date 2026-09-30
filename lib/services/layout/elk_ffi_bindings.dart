// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Hand-written `dart:ffi` binding for the four-function C ABI of
// `native/elk_ffi` (see its `src/lib.rs`). Small enough that a generator
// would be more to maintain than the binding.

import 'dart:convert';
import 'dart:ffi' as ffi;

typedef _AllocDart = ffi.Pointer<ffi.Uint8> Function(int len);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8> ptr, int len);
typedef _LayoutDart =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8> ptr,
      int len,
      ffi.Pointer<ffi.Size> outLen,
      ffi.Pointer<ffi.Int32> status,
    );
typedef _VersionDart = ffi.Pointer<ffi.Uint8> Function();

/// The outcome of one native solve: either the laid-out ELK JSON document or
/// the engine's error message.
class ElkFfiResult {
  const ElkFfiResult._(this.json, this.error);

  /// The laid-out document, or `null` when the solve failed.
  final String? json;

  /// The engine's message when the solve failed, else `null`.
  final String? error;
}

/// Bound entry points of one opened `elk_ffi` library.
class ElkFfiBindings {
  /// Looks up every symbol at once, so a library that is the wrong build
  /// fails here, with the symbol's name, rather than on the first solve.
  ElkFfiBindings(ffi.DynamicLibrary library)
    : _alloc = library
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(ffi.Size),
            _AllocDart
          >(
            'elk_alloc',
          ),
      _free = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
            _FreeDart
          >('elk_free'),
      _layout = library
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Size,
              ffi.Pointer<ffi.Size>,
              ffi.Pointer<ffi.Int32>,
            ),
            _LayoutDart
          >('elk_layout_json'),
      _version = library
          .lookupFunction<ffi.Pointer<ffi.Uint8> Function(), _VersionDart>(
            'elk_engine_version',
          );

  final _AllocDart _alloc;
  final _FreeDart _free;
  final _LayoutDart _layout;
  final _VersionDart _version;

  /// The engine's self-description, e.g. `elkrs 0.1.1`.
  String engineVersion() {
    final ptr = _version();
    var len = 0;
    while (ptr[len] != 0) {
      len++;
    }
    return utf8.decode(ptr.asTypedList(len));
  }

  /// Lays out [inputJson] on the engine's own thread and returns the result
  /// once it is done. Blocks the calling isolate for the whole solve, which
  /// is why the layout service calls it from its worker isolate.
  ElkFfiResult layoutJson(String inputJson) {
    final inputBytes = utf8.encode(inputJson);
    final input = _alloc(inputBytes.length);
    final outLen = _alloc(ffi.sizeOf<ffi.Size>()).cast<ffi.Size>();
    final status = _alloc(ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();
    ffi.Pointer<ffi.Uint8> output = ffi.nullptr;
    var outputLength = 0;
    try {
      input.asTypedList(inputBytes.length).setAll(0, inputBytes);
      output = _layout(input, inputBytes.length, outLen, status);
      outputLength = outLen.value;
      final text = utf8.decode(output.asTypedList(outputLength));
      return status.value == 0
          ? ElkFfiResult._(text, null)
          : ElkFfiResult._(null, text);
    } finally {
      if (output != ffi.nullptr) _free(output, outputLength);
      _free(status.cast<ffi.Uint8>(), ffi.sizeOf<ffi.Int32>());
      _free(outLen.cast<ffi.Uint8>(), ffi.sizeOf<ffi.Size>());
      _free(input, inputBytes.length);
    }
  }
}
