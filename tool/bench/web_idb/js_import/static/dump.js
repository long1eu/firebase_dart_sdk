// Dumps the JS SDK's database that writer.js left (same origin) as JSON and POSTs it to /dump (see dump.sh): the
// version, and for every object store its key path, autoIncrement, indexes and records (key and value). Binary values
// (Uint8Array, ArrayBuffer) are written as {"__u8": base64}; the loader of the browser tests turns them back.
// Plain JS, no bundle.
const NAME = 'firestore/[DEFAULT]/demo-idb/main';
const req = (r) => new Promise((resolve, reject) => { r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error); });

function encode(v) {
  if (v instanceof ArrayBuffer) v = new Uint8Array(v);
  if (ArrayBuffer.isView(v)) {
    let s = '';
    for (const b of new Uint8Array(v.buffer, v.byteOffset, v.byteLength)) s += String.fromCharCode(b);
    return { __u8: btoa(s) };
  }
  if (v instanceof Date) throw new Error('Date values are not supported');
  if (Array.isArray(v)) return v.map(encode);
  if (v !== null && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) if (v[k] !== undefined) o[k] = encode(v[k]);
    return o;
  }
  return v;
}

async function main() {
  const db = await req(indexedDB.open(NAME));
  const stores = [];
  for (const name of Array.from(db.objectStoreNames)) {
    const tx = db.transaction(name, 'readonly');
    const store = tx.objectStore(name);
    const indexes = Array.from(store.indexNames).map((i) => {
      const index = store.index(i);
      return { name: i, keyPath: index.keyPath, unique: index.unique, multiEntry: index.multiEntry };
    });
    const records = [];
    await new Promise((resolve, reject) => {
      const c = store.openCursor();
      c.onerror = () => reject(c.error);
      c.onsuccess = () => {
        const cursor = c.result;
        if (!cursor) { resolve(); return; }
        records.push({ key: encode(cursor.key), value: encode(cursor.value) });
        cursor.continue();
      };
    });
    stores.push({ name, keyPath: store.keyPath, autoIncrement: store.autoIncrement, indexes, records });
  }
  db.close();
  const dump = { name: NAME, version: db.version, stores };
  const res = await fetch('/dump', { method: 'POST', body: JSON.stringify(dump, null, 1) });
  document.title = 'dumped: ' + res.status + ' ' + stores.map((s) => s.name + '=' + s.records.length).join(' ');
}
main().catch((e) => { document.title = 'error: ' + e; });
