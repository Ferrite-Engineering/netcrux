// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// elk_wasm_worker.js: the web viewer's layout engine, a dedicated module
// Web Worker holding the vendored elkrs port compiled to WebAssembly
// (`native/elk_wasm`, built by `dart run tool/build_web_wasm.dart` into
// `elk_wasm.js` + `elk_wasm_bg.wasm` beside this file).
//
// The wasm solve is synchronous and a large scope takes seconds, so it runs
// here rather than on the page. The page side is
// `lib/services/layout/elk_web_solver_web.dart`; it starts this worker with
// `new Worker(url, {type: 'module'})`, waits for the first message, and posts
// one message per layout.
//
// Messages to the page:
//   {type: 'ready'}                         the module loaded
//   {type: 'load-error', message}           it did not (the page falls back)
//   {type: 'progress', id, phase, fraction} the solve reached a pipeline step:
//                                           `phase` an elkrs phase name such
//                                           as 'node placement', `fraction`
//                                           the share done, NaN when unknown
//   {type: 'result', id, json}              a laid-out ELK JSON document
//   {type: 'error', id, message, fatal}     the input was rejected; `fatal`
//                                           when the module trapped, after
//                                           which the page discards this worker
// Messages from the page:
//   {id, input}                             an ELK JSON document to lay out
//
// Progress messages are posted from inside the synchronous solve; the page
// receives them while the solve continues. Cancel is the page terminating
// this worker; there is nothing to clean up. Single-threaded wasm, so the
// site needs no cross-origin isolation headers.

// Messages are capped so a pathological error cannot flood the page.
const MAX_MESSAGE = 2000;

function describe(err) {
  const text = String(err && err.message ? err.message : err);
  return text.length > MAX_MESSAGE ? text.slice(0, MAX_MESSAGE) + '...' : text;
}

let solveLayout = null;

self.onmessage = (event) => {
  const { id, input } = event.data || {};
  if (solveLayout === null) {
    self.postMessage({ type: 'error', id, message: 'elk_wasm is not loaded', fatal: true });
    return;
  }
  const progress = (phase, fraction) =>
    self.postMessage({ type: 'progress', id, phase, fraction });
  try {
    self.postMessage({ type: 'result', id, json: solveLayout(input, progress) });
  } catch (err) {
    self.postMessage({
      type: 'error',
      id,
      message: describe(err),
      fatal: err instanceof WebAssembly.RuntimeError,
    });
  }
};

// An editor webview serves its files from a different origin than its
// document, and a browser refuses to start a worker from another origin. The
// extension's page shim therefore fetches this script, `elk_wasm.js` and
// `elk_wasm_bg.wasm`, and starts the worker from one blob: the glue's text,
// then a line defining `self.cruxLayoutHosted`, then this script. The glue
// sits in the same module, so there is nothing to import and this script must
// not declare a top-level name the glue does, and the wasm is
// read from a blob URL because a blob worker cannot resolve a relative path.
// A page that serves this directory normally never defines it.
(async () => {
  try {
    const hosted = self.cruxLayoutHosted;
    const glue = hosted ? hosted.glue : await import('./elk_wasm.js');
    await glue.default({
      module_or_path: hosted ? hosted.wasmUrl : new URL('./elk_wasm_bg.wasm', import.meta.url),
    });
    solveLayout = glue.layoutJsonWithProgress;
    self.postMessage({ type: 'ready' });
  } catch (err) {
    self.postMessage({ type: 'load-error', message: describe(err) });
  }
})();
