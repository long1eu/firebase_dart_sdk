// Starts the Dart program named by the data-app attribute of this script tag:
// <app>.dart.js (dart compile js) by default, or <app>.mjs and <app>.wasm
// (dart compile wasm) when the address of the page has ?compiler=wasm.
(function () {
  const app = document.currentScript.dataset.app;
  const wasm = new URLSearchParams(location.search).get('compiler') === 'wasm';
  document.getElementById('compiler').textContent = wasm ? 'dart2wasm' : 'dart2js';
  // Keep the query string (emulator, compiler) when switching pages.
  for (const link of document.querySelectorAll('nav a')) {
    link.href = link.getAttribute('href') + location.search;
  }
  if (!wasm) {
    const script = document.createElement('script');
    script.src = app + '.dart.js';
    document.body.append(script);
    return;
  }
  (async () => {
    const { compileStreaming } = await import('./' + app + '.mjs');
    const compiled = await compileStreaming(fetch(app + '.wasm'));
    const instance = await compiled.instantiate({});
    instance.invokeMain();
  })().catch((error) => {
    document.getElementById('error').textContent = 'Could not start ' + app + '.wasm: ' + error;
  });
})();
