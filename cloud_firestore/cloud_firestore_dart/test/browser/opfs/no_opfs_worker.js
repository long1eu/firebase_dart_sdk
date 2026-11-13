// Stands in for sqlite_opfs_worker.js in a browser without synchronous OPFS
// access in workers: answers `load` the way the real worker does there, so
// that web_persistence_opfs_test.dart can check the fallback to IndexedDB in
// any browser.
self.onmessage = (event) => {
  const request = event.data;
  if (request.op === 'load') {
    self.postMessage({id: request.id, result: {supported: false}});
  } else {
    self.postMessage({id: request.id, error: 'unexpected ' + request.op});
  }
};
