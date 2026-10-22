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

let layoutJsonWithProgress = null;

self.onmessage = (event) => {
  const { id, input } = event.data || {};
  if (layoutJsonWithProgress === null) {
    self.postMessage({ type: 'error', id, message: 'elk_wasm is not loaded', fatal: true });
    return;
  }
  const progress = (phase, fraction) =>
    self.postMessage({ type: 'progress', id, phase, fraction });
  try {
    self.postMessage({ type: 'result', id, json: layoutJsonWithProgress(input, progress) });
  } catch (err) {
    self.postMessage({
      type: 'error',
      id,
      message: describe(err),
      fatal: err instanceof WebAssembly.RuntimeError,
    });
  }
};

(async () => {
  try {
    const glue = await import('./elk_wasm.js');
    await glue.default({ module_or_path: new URL('./elk_wasm_bg.wasm', import.meta.url) });
    layoutJsonWithProgress = glue.layoutJsonWithProgress;
    self.postMessage({ type: 'ready' });
  } catch (err) {
    self.postMessage({ type: 'load-error', message: describe(err) });
  }
})();
