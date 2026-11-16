// Starts the Dart program named by the data-app attribute of this script tag:
// <app>.dart.js (dart compile js) by default, or <app>.mjs and <app>.wasm
// (dart compile wasm) when the address of the page has ?compiler=wasm.
// Every URL is relative, so the page also works under a sub-path
// (https://<user>.github.io/<repo>/).
(function () {
  const app = document.currentScript.dataset.app;
  const wasm = new URLSearchParams(location.search).get('compiler') === 'wasm';
  document.getElementById('compiler').textContent = wasm ? 'dart2wasm' : 'dart2js';
  const other = document.getElementById('other-compiler');
  other.textContent = wasm ? 'dart2js' : 'dart2wasm';
  other.href = wasm ? './' : './?compiler=wasm';
  const fail = (error) => {
    document.getElementById('error').textContent = 'Could not start the page: ' + error;
  };
  if (!wasm) {
    const script = document.createElement('script');
    script.src = app + '.dart.js';
    script.onerror = () => fail(app + '.dart.js did not load');
    document.body.append(script);
    return;
  }
  (async () => {
    const { compileStreaming } = await import('./' + app + '.mjs');
    const compiled = await compileStreaming(fetch(app + '.wasm'));
    const instance = await compiled.instantiate({});
    instance.invokeMain();
  })().catch(fail);
})();
