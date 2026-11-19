// Starts the Dart program named by the data-app attribute of this script tag.
//
// By default it runs the dart2wasm build (<app>.mjs and <app>.wasm) when the
// browser can, and the dart2js build (<app>.dart.js) otherwise: when the
// browser has no WebAssembly garbage collection, or when the module does not
// compile (a missing WebAssembly feature, or a Content-Security-Policy
// without 'wasm-unsafe-eval'). The client's own work (serialization, queries
// on the cache, snapshots) runs two to five times faster as WebAssembly in
// Chrome; see "dart2js or dart2wasm in the browser" in
// docs/guides/performance.md.
//
// The address can pick one: ?compiler=js runs dart2js, ?compiler=wasm runs
// dart2wasm and shows the error instead of falling back.
//
// Every URL is relative, so the page also works under a sub-path
// (https://<user>.github.io/<repo>/).
(function () {
  const app = document.currentScript.dataset.app;
  const asked = new URLSearchParams(location.search).get('compiler');

  // Keep the query string (emulator, cache, compiler) when switching pages.
  for (const link of document.querySelectorAll('nav a')) {
    link.href = link.getAttribute('href') + location.search;
  }

  // The check that dart2wasm writes next to the module (<app>.support.js):
  // a module that declares a struct type validates only with WebAssembly
  // garbage collection.
  const supportsWasm = (() => {
    try {
      return typeof WebAssembly === 'object' && WebAssembly.validate(
        new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 95, 1, 120, 0]));
    } catch (_) {
      return false;
    }
  })();

  const fail = (error) => {
    document.getElementById('error').textContent = 'Could not start the page: ' + error;
  };

  // What runs, and a link to the other build.
  const show = (wasm, note) => {
    document.getElementById('compiler').textContent =
        (wasm ? 'dart2wasm' : 'dart2js') + (note ? ' (' + note + ')' : '');
    const other = document.getElementById('other-compiler');
    if (other) {
      const query = new URLSearchParams(location.search);
      query.set('compiler', wasm ? 'js' : 'wasm');
      other.textContent = wasm ? 'dart2js' : 'dart2wasm';
      other.href = '?' + query;
    }
  };

  const startJs = (note) => {
    show(false, note);
    const script = document.createElement('script');
    script.src = app + '.dart.js';
    script.onerror = () => fail(app + '.dart.js did not load');
    document.body.append(script);
  };

  if (asked === 'js' || (asked !== 'wasm' && !supportsWasm)) {
    startJs(asked === 'js' ? '' : 'this browser cannot run the WebAssembly build');
    return;
  }

  (async () => {
    let instance;
    try {
      const { compileStreaming } = await import('./' + app + '.mjs');
      const compiled = await compileStreaming(fetch(app + '.wasm'));
      instance = await compiled.instantiate({});
    } catch (error) {
      if (asked === 'wasm') {
        show(true, 'did not start');
        throw error;
      }
      // Nothing of the program ran yet: start the other build instead.
      console.warn('The WebAssembly build did not start, using dart2js:', error);
      startJs('the WebAssembly build did not start here');
      return;
    }
    show(true, '');
    instance.invokeMain();
  })().catch(fail);
})();
