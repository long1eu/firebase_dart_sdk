// Generates the fixtures of the browser tests of importJsSdkCache (test/browser/js_sdk_cache_fixtures/ of
// cloud_firestore_dart) with the real JS SDK of tool/interop/node_modules. Run by fixtures.sh, which serves this page
// and writes what it POSTs to /fixture/<name>.
//
// Every scenario runs its writes twice, in the same order:
//
// - offline, with IndexedDB persistence and the network disabled, then terminates the client (or, for the live
//   scenarios, leaves it running) and dumps the database in the format of dump.js: what the test imports;
// - online, with a memory cache, against the emulator in a reference project, each write awaited: what the backend
//   holds when the JS SDK itself sends them. The documents the writes touch are then read over the emulator's REST
//   API and saved as `expected` (proto3 JSON fields, or null for a missing document).
//
// The seed documents are written in the reference project first and saved as `seed` (proto3 JSON fields): the test
// writes them into its own project before it imports.
//
// Query parameters: open=<port of an emulator with open rules> (required), rules=<port of the emulator of
// tool/start_auth_emulators.sh> (optional: the users scenario is then also sent there).
import { initializeApp, deleteApp, SDK_VERSION } from '@firebase/app';
import {
  initializeFirestore, persistentLocalCache, persistentSingleTabManager, persistentMultipleTabManager,
  memoryLocalCache, connectFirestoreEmulator, disableNetwork, doc, setDoc, updateDoc, deleteDoc, writeBatch,
  getDocFromCache, terminate, Timestamp, GeoPoint, Bytes, FieldPath, serverTimestamp, increment, arrayUnion,
  arrayRemove, deleteField, vector,
} from '@firebase/firestore';

const params = new URLSearchParams(location.search);
const OPEN_PORT = Number(params.get('open'));
const RULES_PORT = params.get('rules') ? Number(params.get('rules')) : null;
const HOST = '127.0.0.1';

const out = [];
const log = (m) => { out.push(m); document.getElementById('o').textContent = out.join('\n'); };
const req = (r) => new Promise((resolve, reject) => { r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error); });

// ---- The writes ----

/** The documents written online before the writes, in the reference project (and by the test in its project). */
const WRITES_SEED = [
  ['docs/upd', { a: 1, nested: { x: 1, y: 2 }, keep: 'k', arr: [1, 2] }],
  ['docs/merge', { a: 1, m: { p: 1, q: 2 } }],
  ['docs/mergeFields', { a: 1, b: 1, m: { p: 1, q: 2 } }],
  ['docs/transforms', { n: 1, d: 0.5, arr: ['a', 'b', 'c', 'b'], big: 9007199254740990, nested: { c: 1 } }],
  ['docs/del', { a: 1 }],
  ['docs/exists', { a: 1 }],
  ['docs/b3', { a: 1 }],
];

/** Every kind of write the JS SDK queues: [label, (db) => the write's promise]. */
const WRITES = [
  ['set every value type', (db) => setDoc(doc(db, 'docs/values'), {
    s: 'text é中😀', empty: '', t: true, f: false, nul: null,
    i: 42, negI: -7, maxSafe: Number.MAX_SAFE_INTEGER, minSafe: Number.MIN_SAFE_INTEGER, zero: 0,
    d: 2.5, negD: -0.125, nan: NaN, inf: Infinity, negInf: -Infinity, negZero: -0, tiny: 5e-324, huge: 1.7976931348623157e308,
    ts: new Timestamp(1700000000, 123456000), tsOld: new Timestamp(-62135596800, 0), tsMax: new Timestamp(253402300799, 999999999),
    b: Bytes.fromUint8Array(new Uint8Array([0, 1, 2, 254, 255])), bEmpty: Bytes.fromUint8Array(new Uint8Array([])),
    g: new GeoPoint(-90, 180), r: doc(db, 'docs/other'), rSub: doc(db, 'docs/exists/sub/s1'),
    v: vector([1.5, -2, 0]),
    m: { a: { b: { c: [1, { d: 'deep', e: [2] }] } }, 'key.with.dots': 1, 'key with spaces': 2, 'üml': 3 },
    emptyMap: {}, emptyArray: [], mixed: [1, 'two', 3.5, null, true, { x: 1 }],
  })],
  ['set with merge, a server timestamp', (db) => setDoc(doc(db, 'docs/merge'),
    { m: { q: 20, r: 3 }, b: 2, st: serverTimestamp() }, { merge: true })],
  ['set with mergeFields', (db) => setDoc(doc(db, 'docs/mergeFields'),
    { a: 9, b: 9, m: { p: 9, q: 9 } }, { mergeFields: ['a', 'm.p'] })],
  ['update nested paths, deleteField, a field path with a dot', (db) => updateDoc(doc(db, 'docs/upd'),
    'nested.x', 10, 'nested.z.deep', true, 'keep', deleteField(), new FieldPath('a.b'), 'literal dot', 'arr', [3])],
  ['update with every transform', (db) => updateDoc(doc(db, 'docs/transforms'), {
    n: increment(2), d: increment(0.25), arr: arrayRemove('b'), added: arrayUnion(1, { x: 1 }, 1),
    at: serverTimestamp(), big: increment(1), 'nested.c': increment(1.5), 'nested.when': serverTimestamp(),
  })],
  ['a second update of the same document', (db) => updateDoc(doc(db, 'docs/transforms'),
    { n: increment(-10), added: arrayUnion(2), arr: arrayUnion('z') })],
  ['set with transforms on a new document', (db) => setDoc(doc(db, 'docs/setTransforms'), {
    count: increment(3), list: arrayUnion('x', 'x'), rm: arrayRemove('y'), at: serverTimestamp(), plain: 1,
    m: { when: serverTimestamp(), n: increment(1) },
  })],
  ['delete', (db) => deleteDoc(doc(db, 'docs/del'))],
  ['delete of a missing document', (db) => deleteDoc(doc(db, 'docs/neverExisted'))],
  ['update of a missing document (precondition fails)', (db) => updateDoc(doc(db, 'docs/missing'), { a: 1 })],
  ['batch: set, update, delete, subcollections', (db) => writeBatch(db)
    .set(doc(db, 'docs/b1'), { inBatch: true })
    .update(doc(db, 'docs/exists'), { a: increment(1), 'm.n': 'x' })
    .delete(doc(db, 'docs/b3'))
    .set(doc(db, 'docs/exists/sub/s1'), { deep: true, ref: doc(db, 'docs/b1') })
    .set(doc(db, 'deep/a/b/c/d/e'), { depth: 3 })
    .commit()],
  ['batch whose update fails: none of it is applied', (db) => writeBatch(db)
    .set(doc(db, 'docs/batchFail'), { x: 1 })
    .update(doc(db, 'docs/missing2'), { a: 1 })
    .commit()],
  ['order 1: set', (db) => setDoc(doc(db, 'docs/order'), { v: 1, log: ['1'] })],
  ['order 2: update', (db) => updateDoc(doc(db, 'docs/order'), { v: 2, log: arrayUnion('2') })],
  ['order 3: update', (db) => updateDoc(doc(db, 'docs/order'), { v: 3, log: arrayUnion('3') })],
  ['order 4: set with merge', (db) => setDoc(doc(db, 'docs/order'), { log: arrayUnion('4'), w: increment(1) }, { merge: true })],
  ['order 5: delete and set again', (db) => writeBatch(db)
    .delete(doc(db, 'docs/order2')).set(doc(db, 'docs/order2'), { again: true }).commit()],
  ['a document id with spaces and unicode', (db) => setDoc(doc(db, 'docs/with space é'), { ok: 1 })],
];

const WRITES_PATHS = [
  'docs/values', 'docs/merge', 'docs/mergeFields', 'docs/upd', 'docs/transforms', 'docs/setTransforms', 'docs/del',
  'docs/neverExisted', 'docs/missing', 'docs/b1', 'docs/exists', 'docs/b3', 'docs/exists/sub/s1', 'deep/a/b/c/d/e',
  'docs/batchFail', 'docs/missing2', 'docs/order', 'docs/order2', 'docs/with space é',
];

// ---- Several users: [user ('' signed out), label, write]. The users write disjoint documents. ----

const USERS = [
  ['alice', 'alice 1: set her note', (db) => setDoc(doc(db, 'users/alice/notes/n1'), { v: 1, log: ['first'] })],
  ['', 'signed out 1: set an open document', (db) => setDoc(doc(db, 'open/anon1'), { by: 'anon' })],
  ['bob', 'bob 1: set his note', (db) => setDoc(doc(db, 'users/bob/notes/n1'), { v: 1 })],
  ['alice', 'alice 2: update her note', (db) => updateDoc(doc(db, 'users/alice/notes/n1'), { v: 2, log: arrayUnion('second') })],
  ['alice', 'alice 3: write to bob (denied by the rules)', (db) => setDoc(doc(db, 'users/bob/notes/fromAlice'), { x: 1 })],
  ['', 'signed out 2: write to alice (denied by the rules)', (db) => setDoc(doc(db, 'users/alice/notes/anon'), { x: 1 })],
  ['bob', 'bob 2: increment his note', (db) => updateDoc(doc(db, 'users/bob/notes/n1'), { v: increment(10) })],
  ['alice', 'alice 4: a signed-in document', (db) => setDoc(doc(db, 'signed_in/alice'), { ok: true, at: serverTimestamp() })],
  ['', 'signed out 3: update the open document', (db) => updateDoc(doc(db, 'open/anon1'), { n: increment(1) })],
  ['bob', 'bob 3: a batch', (db) => writeBatch(db)
    .set(doc(db, 'users/bob/notes/n2'), { b: true }).update(doc(db, 'users/bob/notes/n1'), { v: increment(100) }).commit()],
];

const USERS_PATHS = [
  'users/alice/notes/n1', 'open/anon1', 'users/bob/notes/n1', 'users/bob/notes/fromAlice', 'users/alice/notes/anon',
  'signed_in/alice', 'users/bob/notes/n2',
];

// ---- Helpers ----

function firestoreFor(app, cache, port, uid) {
  const db = initializeFirestore(app, { localCache: cache });
  connectFirestoreEmulator(db, HOST, port, uid ? { mockUserToken: { sub: uid } } : undefined);
  return db;
}

let apps = 0;

/** A client on the database of [appName] with the network disabled, signed in as [uid] ('' signed out). */
async function offlineClient(appName, projectId, uid, multiTab = false) {
  const app = initializeApp({ apiKey: 'fake', appId: 'fake', projectId }, appName);
  const db = firestoreFor(app, persistentLocalCache({
    tabManager: multiTab ? persistentMultipleTabManager() : persistentSingleTabManager({}),
  }), OPEN_PORT, uid);
  await disableNetwork(db);
  return { app, db };
}

/** Queues [write] without waiting for it (it only resolves when the backend acknowledges it). */
async function queue(db, label, write, probePath) {
  write(db).catch(() => {});
  // A read from the cache runs after the write on the same queue: the write is persisted when it returns.
  await getDocFromCache(doc(db, probePath)).catch(() => {});
  log('queued ' + label);
}

async function rest(port, method, path, body) {
  const res = await fetch(`http://${HOST}:${port}${path}`, {
    method,
    headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`${method} ${path}: HTTP ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : {};
}

const docsPath = (projectId) => `/v1/projects/${projectId}/databases/(default)/documents`;
const encodePath = (path) => path.split('/').map(encodeURIComponent).join('/');

async function clearProject(port, projectId) {
  await rest(port, 'DELETE', `/emulator/v1/projects/${projectId}/databases/(default)/documents`);
}

async function readFields(port, projectId, paths) {
  const result = {};
  for (const path of paths) {
    const d = await rest(port, 'GET', `${docsPath(projectId)}/${encodePath(path)}`);
    result[path] = d === null ? null : (d.fields || {});
  }
  return result;
}

/** Runs [ops] ([uid, label, write]) online, one after the other, against the reference project; returns what each did. */
async function runReference(port, projectId, seed, ops) {
  await clearProject(port, projectId);
  const clients = new Map();
  const clientOf = (uid) => {
    if (!clients.has(uid)) {
      const app = initializeApp({ apiKey: 'fake', appId: 'fake', projectId }, `ref-${apps++}`);
      clients.set(uid, { app, db: firestoreFor(app, memoryLocalCache(), port, uid) });
    }
    return clients.get(uid).db;
  };
  for (const [path, data] of seed) {
    await setDoc(doc(clientOf(''), path), data);
  }
  const outcomes = [];
  for (const [uid, label, write] of ops) {
    try {
      await write(clientOf(uid));
      outcomes.push({ user: uid, label, outcome: 'ok' });
    } catch (e) {
      outcomes.push({ user: uid, label, outcome: e.code || String(e) });
    }
  }
  for (const { app } of clients.values()) await deleteApp(app);
  return outcomes;
}

function encode(v) {
  if (v instanceof ArrayBuffer) v = new Uint8Array(v);
  if (ArrayBuffer.isView(v)) {
    let s = '';
    for (const b of new Uint8Array(v.buffer, v.byteOffset, v.byteLength)) s += String.fromCharCode(b);
    return { __u8: btoa(s) };
  }
  if (typeof v === 'number' && !Number.isFinite(v)) throw new Error('a non-finite number in a row: ' + v);
  if (Object.is(v, -0)) throw new Error('-0 in a row');
  if (v instanceof Date) throw new Error('Date values are not supported');
  if (Array.isArray(v)) return v.map(encode);
  if (v !== null && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) if (v[k] !== undefined) o[k] = encode(v[k]);
    return o;
  }
  return v;
}

/** The database [name] in the format of dump.js. */
async function dump(name) {
  const db = await req(indexedDB.open(name));
  const stores = [];
  for (const storeName of Array.from(db.objectStoreNames)) {
    const tx = db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);
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
    stores.push({ name: storeName, keyPath: store.keyPath, autoIncrement: store.autoIncrement, indexes, records });
  }
  db.close();
  return { name, version: db.version, stores };
}

async function save(name, fixture) {
  const res = await fetch('/fixture/' + name, { method: 'POST', body: JSON.stringify(fixture, null, 1) });
  if (!res.ok) throw new Error('saving ' + name + ': HTTP ' + res.status);
  log('saved ' + name);
}

const header = (what) => ({
  generatedBy: 'tool/bench/web_idb/js_import/fixtures.sh (static/fixtures.js)',
  jsSdkVersion: SDK_VERSION,
  what,
});

// ---- Scenarios ----

async function writesScenario() {
  const appName = 'js-writes';
  const projectId = 'demo-jsimport';
  const dbName = `firestore/${appName}/${projectId}/main`;
  await req(indexedDB.deleteDatabase(dbName));
  const { app, db } = await offlineClient(appName, projectId, '');
  for (const [label, write] of WRITES) await queue(db, label, write, 'docs/values');
  await terminate(db);
  await deleteApp(app);

  const ops = WRITES.map(([label, write]) => ['', label, write]);
  const outcomes = await runReference(OPEN_PORT, 'demo-jsref', WRITES_SEED, ops);
  const expected = await readFields(OPEN_PORT, 'demo-jsref', WRITES_PATHS);
  // The seed as the JS SDK writes it, from a project that holds the seed only.
  await runReference(OPEN_PORT, 'demo-jsref-seed', WRITES_SEED, []);
  const seed = await readFields(OPEN_PORT, 'demo-jsref-seed', WRITES_SEED.map(([p]) => p));
  await save('writes', {
    ...header('Every kind of write of the signed-out user, queued offline by the JS SDK and terminated.'),
    projectId, appName, referenceProject: 'demo-jsref', ops: { open: outcomes }, seed, expected: { open: expected },
    ...(await dump(dbName)),
  });
}

async function usersScenario() {
  const appName = 'js-users';
  const projectId = 'demo-jsimport-users';
  const dbName = `firestore/${appName}/${projectId}/main`;
  await req(indexedDB.deleteDatabase(dbName));
  // One client per stretch of writes of the same user, on the same database: switching users the way an app that
  // signs in and out does, without an Auth backend (the emulator's mockUserToken).
  let current = null;
  for (const [uid, label, write] of USERS) {
    if (!current || current.uid !== uid) {
      if (current) { await terminate(current.db); await deleteApp(current.app); }
      current = { uid, ...(await offlineClient(appName, projectId, uid)) };
    }
    await queue(current.db, label, write, 'open/probe');
  }
  await terminate(current.db);
  await deleteApp(current.app);

  const expected = {};
  const ops = {};
  ops.open = await runReference(OPEN_PORT, 'demo-jsref-users', [], USERS);
  expected.open = await readFields(OPEN_PORT, 'demo-jsref-users', USERS_PATHS);
  if (RULES_PORT) {
    ops.rules = await runReference(RULES_PORT, 'demo-jsref-users', [], USERS);
    expected.rules = await readFields(RULES_PORT, 'demo-jsref-users', USERS_PATHS);
  }
  await save('users', {
    ...header('Writes of alice, bob and the signed-out user, interleaved, queued offline by the JS SDK (mockUserToken).'),
    projectId, appName, referenceProject: 'demo-jsref-users', ops, seed: {}, expected,
    ...(await dump(dbName)),
  });
}

/** A JS client that is still running: its owner lease and clientMetadata rows are in the dump. */
async function liveScenario(name, multiTab) {
  const appName = `js-${name}`;
  const projectId = 'demo-jsimport';
  const dbName = `firestore/${appName}/${projectId}/main`;
  await req(indexedDB.deleteDatabase(dbName));
  const { app, db } = await offlineClient(appName, projectId, '', multiTab);
  await queue(db, 'one write', (d) => setDoc(doc(d, 'live/doc'), { live: true }), 'live/doc');
  const fixture = {
    ...header(`A JS client (${multiTab ? 'persistentMultipleTabManager' : 'persistentSingleTabManager'}) still running when the database was dumped.`),
    projectId, appName, dumpedAtMs: Date.now(), ...(await dump(dbName)),
  };
  await terminate(db);
  await deleteApp(app);
  await save(name, fixture);
}

async function main() {
  if (!OPEN_PORT) throw new Error('open=<port> is missing');
  log('JS SDK ' + SDK_VERSION);
  await writesScenario();
  await usersScenario();
  await liveScenario('live_single_tab', false);
  await liveScenario('live_multi_tab', true);
  document.title = 'done: ' + out.join(' | ');
}

main().catch((e) => { log('ERROR ' + (e.stack || e)); document.title = 'error: ' + e + ' after ' + out.join(' | '); });
