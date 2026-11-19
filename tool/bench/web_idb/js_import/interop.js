// The JS SDK side of the interop check (interop_check.sh): one step per page load, chosen by the JSON in the URL
// hash ({step, project, user, port}). The page reports in window.interopResult, as JSON: {state, checks: [{name, pass,
// detail}]}, the state "holding" for a step that keeps its client alive until the tab is closed.
// The other side is interop_engine.dart (the IndexedDB engine of this repository), on the same origin and profile.
//
// Every step uses the official JS SDK (`firebase` 12 from node_modules) with persistentLocalCache and
// persistentSingleTabManager, against the Firestore emulator on 127.0.0.1:<port>, as the user <user> (the emulator's
// mockUserToken).
import { initializeApp } from 'firebase/app';
import {
  initializeFirestore, persistentLocalCache, persistentSingleTabManager, connectFirestoreEmulator,
  enableIndexedDbPersistence, disableNetwork, enableNetwork, doc, collection, query, where, orderBy, getDocFromCache,
  getDocsFromCache, getDocsFromServer, getDocFromServer, setDoc, updateDoc, onSnapshot, terminate, loadBundle,
  namedQuery, setIndexConfiguration, setLogLevel, waitForPendingWrites, Timestamp, GeoPoint, Bytes, vector,
} from 'firebase/firestore';

const params = JSON.parse(decodeURIComponent(location.hash.slice(1)));
const checks = [];
const logs = [];

for (const method of ['log', 'debug', 'info', 'warn', 'error']) {
  const original = console[method].bind(console);
  console[method] = (...args) => {
    logs.push(args.map(String).join(' '));
    original(...args);
  };
}

/** Shows where a step is, in the title: the driver prints it when the step times out. */
function progress(message) {
  document.title = `${params.step}: ${message}`;
}

function check(name, pass, detail = '') {
  checks.push({ name, pass: !!pass, detail: typeof detail === 'string' ? detail : JSON.stringify(detail) });
}

let hold = false;

function report() {
  window.interopResult = JSON.stringify({ state: hold ? 'holding' : 'result', checks });
  document.title = hold ? 'holding' : 'result';
}

const dbName = () => `firestore/[DEFAULT]/${params.project}/main`;

/** A client with a persistent single-tab cache, or, with [plain], without cache settings (for
 * enableIndexedDbPersistence). */
function open({ cacheSizeBytes, plain = false } = {}) {
  const app = initializeApp({ apiKey: 'fake', appId: 'fake', projectId: params.project });
  const db = plain ? initializeFirestore(app, {}) : initializeFirestore(app, { localCache: persistentLocalCache({
    tabManager: persistentSingleTabManager({}), ...(cacheSizeBytes ? { cacheSizeBytes } : {}) }) });
  connectFirestoreEmulator(db, '127.0.0.1', params.port, { mockUserToken: { sub: params.user } });
  return { app, db };
}

/** The number of rows of [store] in the database of this project, read with raw IndexedDB. */
function countRows(store) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName());
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const idb = request.result;
      const count = idb.transaction(store).objectStore(store).count();
      count.onsuccess = () => { idb.close(); resolve(count.result); };
      count.onerror = () => { idb.close(); reject(count.error); };
    };
  });
}

function getRow(store, key, index) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName());
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const idb = request.result;
      const objects = idb.transaction(store).objectStore(store);
      const get = (index ? objects.index(index) : objects).get(key);
      get.onsuccess = () => { idb.close(); resolve(get.result); };
      get.onerror = () => { idb.close(); reject(get.error); };
    };
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(what, condition, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await condition()) return true;
    await sleep(500);
  }
  return false;
}

function element(obj) {
  const s = JSON.stringify(obj);
  return `${new TextEncoder().encode(s).length}${s}`;
}

/** A bundle with two documents of `bund` and the named query `nq` (`bund` ordered by `n` descending, limit 1). */
function buildBundle(project) {
  const parent = `projects/${project}/databases/(default)/documents`;
  const t = { seconds: '1700000000', nanos: 123456000 };
  const body = [
    element({ namedQuery: { name: 'nq', readTime: t, bundledQuery: { parent, structuredQuery: {
      from: [{ collectionId: 'bund' }], orderBy: [{ field: { fieldPath: 'n' }, direction: 'DESCENDING' }],
      limit: { value: 1 } }, limitType: 'FIRST' } } }),
  ];
  for (const [id, n] of [['x', 1], ['y', 2]]) {
    const name = `${parent}/bund/${id}`;
    body.push(element({ documentMetadata: { name, readTime: t, exists: true, queries: ['nq'] } }));
    body.push(element({ document: { name, createTime: t, updateTime: t, fields: { n: { integerValue: `${n}` } } } }));
  }
  const total = body.reduce((n, e) => n + new TextEncoder().encode(e).length, 0);
  return element({ metadata: { id: 'bundle', createTime: t, version: 1, totalDocuments: 2, totalBytes: total } }) + body.join('');
}

const cityIndex = { indexes: [{ collectionGroup: 'cities', queryScope: 'COLLECTION', fields: [
  { fieldPath: 'country', order: 'ASCENDING' }, { fieldPath: 'pop', order: 'ASCENDING' }] }] };
const kindIndex = { indexes: [{ collectionGroup: 'kinds', queryScope: 'COLLECTION', fields: [
  { fieldPath: 'v', order: 'ASCENDING' }] }] };

/** The values of step D, by kind: each is the field `v` of the document kinds/<kind>. */
function kindValues(db) {
  return {
    map: { b: 1, a: 2, 10: 'ten', 2: 'two', z: { y: 1, x: 2 } },
    timestamp: Timestamp.fromMillis(1700000000123),
    timestamp0: new Timestamp(0, 5),
    reference: doc(db, 'kinds/target'),
    bytes: Bytes.fromUint8Array(new Uint8Array([0, 1, 255, 0])),
    array: [1, 'two', { k: true }, null],
    integer: 42,
    double: 2.5,
    negzero: -0,
    nan: NaN,
    vector: vector([1, 2.5, -3]),
    string: 'héllo \u{1F600}',
    bool: true,
    geopoint: new GeoPoint(-0, 12.5),
    null: null,
  };
}

const ids = (snapshot) => snapshot.docs.map((d) => d.id);
const usedIndex = (from) => logs.slice(from).some((l) => l.includes('Using index'));

const steps = {
  /** A: the JS SDK writes, as alice: documents of a listen, an index with entries, a bundle, two pending writes. */
  async 'a-write'() {
    const { db } = open();
    progress('index configuration');
    await setIndexConfiguration(db, JSON.stringify(cityIndex));
    progress('writes');
    for (let i = 0; i < 20; i++) {
      await setDoc(doc(db, `cities/c${i}`), { country: i < 4 ? 'RO' : 'other', pop: 1000 * i });
    }
    for (const id of ['d1', 'd2', 'd3']) await setDoc(doc(db, `docs/${id}`), { title: `doc ${id}` });
    // A listen: the documents of the backend, in a target.
    progress('listen');
    await new Promise((resolve, reject) => {
      const unsubscribe = onSnapshot(collection(db, 'docs'), { includeMetadataChanges: true }, (s) => {
        if (!s.metadata.fromCache && s.size === 3) { unsubscribe(); resolve(); }
      }, reject);
    });
    progress('get cities');
    await getDocsFromServer(collection(db, 'cities'));
    progress('bundle');
    await loadBundle(db, buildBundle(params.project));
    progress('backfill');
    check('A1 listen, writes and bundle', true);
    // The backfill runs 15 s after the start, 50 documents a run.
    const filled = await waitFor('entries', async () => (await countRows('indexEntries')) >= 20, 45000);
    check('A1 the JS SDK backfilled its index', filled, `indexEntries=${await countRows('indexEntries')}`);
    await disableNetwork(db);
    setDoc(doc(db, 'pend/a1'), { by: 'alice' }).catch(() => {});
    updateDoc(doc(db, 'docs/d1'), { title: 'changed by alice' }).catch(() => {});
    await getDocFromCache(doc(db, 'pend/a1'));
    await terminate(db);
    check('A1 two pending writes of alice', true);
  },

  async 'a-write-bob'() {
    const { db } = open();
    await disableNetwork(db);
    setDoc(doc(db, 'pend/b1'), { by: 'bob' }).catch(() => {});
    await getDocFromCache(doc(db, 'pend/b1'));
    await terminate(db);
    check('A2 a pending write of bob', true);
  },

  /** B: the JS SDK reads what the engine wrote, collects garbage, then sends alice's writes. */
  async 'b-read'() {
    setLogLevel('debug');
    const { db } = open({ cacheSizeBytes: 1048576 });
    await disableNetwork(db);
    const docs = await getDocsFromCache(collection(db, 'docs'));
    check('B3 the documents of the listen', JSON.stringify(ids(docs)) === '["d1","d2","d3"]'
      && docs.docs[0].get('title') === 'changed by alice' && docs.docs[0].metadata.hasPendingWrites, ids(docs));
    const from = logs.length;
    const ro = await getDocsFromCache(query(collection(db, 'cities'), where('country', '==', 'RO'), orderBy('pop')));
    check('B3 the index of the engine serves a query', JSON.stringify(ids(ro)) === '["c0","c1","c2","c3"]' && usedIndex(from),
      { ids: ids(ro), usedIndex: usedIndex(from) });
    const nq = await namedQuery(db, 'nq');
    const nqDocs = nq ? ids(await getDocsFromCache(nq)) : null;
    check('B3 the named query of the engine', JSON.stringify(nqDocs) === '["y"]', nqDocs);

    // The garbage collector of the JS SDK runs 1 min after the start; the cache is over 1 MB (bulk/*).
    const before = await countRows('remoteDocumentsV14');
    const collected = await waitFor('gc', async () => (await countRows('remoteDocumentsV14')) < before, 100000);
    const gcErrors = logs.filter((l) => /LruGarbageCollector|garbage/i.test(l) && /error|fail/i.test(l));
    check('B3 the JS SDK collected garbage on the engine database', collected && gcErrors.length === 0,
      { before, after: await countRows('remoteDocumentsV14'), errors: gcErrors.slice(0, 3) });
    const kept = [];
    for (const path of ['bulk/0', 'bulk/1']) {
      try { kept.push(`${path}:${(await getDocFromCache(doc(db, path))).get('mark')}`); } catch (e) { kept.push(`${path}:gone`); }
    }
    check('B3 documents with pending writes (of alice and of bob) were kept', JSON.stringify(kept) === '["bulk/0:alice","bulk/1:null"]'
      && !!(await getRow('remoteDocumentsV14', [[], 'bulk', '1'], 'documentKeyIndex')), kept);

    await enableNetwork(db);
    await waitForPendingWrites(db);
    const sent = (await getDocFromServer(doc(db, 'pend/a1'))).data();
    check('B3 the JS SDK sent the pending writes of the engine (alice)', sent?.by === 'alice', sent);
    await terminate(db);
  },

  async 'b-read-bob'() {
    const { db } = open();
    await waitForPendingWrites(db);
    const sent = (await getDocFromServer(doc(db, 'pend/b1'))).data();
    const bulk1 = (await getDocFromServer(doc(db, 'bulk/1'))).data();
    check('B4 the JS SDK sent the pending writes of the engine (bob)', sent?.by === 'bob' && bulk1?.mark === 'bob', { sent, bulk1: bulk1?.mark });
    await terminate(db);
  },

  /** C: a JS client that stays alive until the tab is closed. */
  async 'c-hold'() {
    const { db } = open();
    await disableNetwork(db);
    setDoc(doc(db, 'lease/js'), { by: 'js' }).catch(() => {});
    await getDocFromCache(doc(db, 'lease/js'));
    check('C a JS client holds the database', true);
    hold = true;
  },

  /** C: enabling persistence fails while the engine holds the database. */
  async 'c-refused'() {
    const owner = await getRow('owner', 'owner');
    const zombie = owner ? localStorage.getItem(`firestore_zombie_firestore/[DEFAULT]/${params.project}/_${owner.ownerId}`) : null;
    check('C the engine holds a live lease', owner && Date.now() - owner.leaseTimestampMs < 5000 && zombie === null,
      { owner, ageMs: owner && Date.now() - owner.leaseTimestampMs, zombie });
    // The JS SDK 12 does not fail enableIndexedDbPersistence: the client falls back to a memory cache at its start,
    // with a warning that names the error.
    const { db } = open({ plain: true });
    await enableIndexedDbPersistence(db);
    await getDocFromCache(doc(db, 'lease/engine')).catch(() => {});
    const fallback = logs.find((l) => l.includes('Falling back to memory cache'));
    check('C the JS SDK is refused while the engine holds the lease (falls back to memory)',
      !!fallback && fallback.includes('failed-precondition'), fallback ?? 'no fallback: it used the database');
    await terminate(db);
  },

  async 'c-open'() {
    const { db } = open({ plain: true });
    await enableIndexedDbPersistence(db);
    await disableNetwork(db);
    const engine = await getDocFromCache(doc(db, 'lease/engine'));
    const fallback = logs.find((l) => l.includes('Falling back to memory cache'));
    check('C the JS SDK opens after the engine tab closed, and reads its write', engine.get('by') === 'engine' && !fallback,
      { data: engine.data(), fallback });
    await terminate(db);
  },

  /** D: one document per value kind, an index on `v`, filled by the JS SDK. */
  async 'd-write'() {
    const { db } = open();
    await setIndexConfiguration(db, JSON.stringify(kindIndex));
    const values = kindValues(db);
    for (const [kind, v] of Object.entries(values)) await setDoc(doc(db, `kinds/${kind}`), { v });
    // The documents as the backend sends them, as a listen would.
    await getDocsFromServer(collection(db, 'kinds'));
    const row = await getRow('remoteDocumentsV14', [[], 'kinds', 'map'], 'documentKeyIndex');
    const keys = Object.keys(row?.document?.fields?.v?.mapValue?.fields ?? {});
    check('D1 key order of a map in the JS cache (written b, a, 10, 2, z)', true, keys);
    const filled = await waitFor('entries', async () => (await countRows('indexEntries')) >= Object.keys(values).length, 45000);
    check('D1 the JS SDK backfilled its index', filled, `indexEntries=${await countRows('indexEntries')}`);
    await terminate(db);
  },

  /** D: equality queries on the engine's index, one per kind. */
  async 'd-read'() {
    setLogLevel('debug');
    const { db } = open();
    await disableNetwork(db);
    const values = kindValues(db);
    for (const [kind, v] of Object.entries(values)) {
      const from = logs.length;
      let result;
      try {
        result = ids(await getDocsFromCache(query(collection(db, 'kinds'), where('v', '==', v))));
      } catch (e) {
        result = `error ${e}`;
      }
      const expected = kind === 'null' ? '["null"]' : `["${kind}"]`;
      check(`D4 ${kind}: the JS SDK finds the engine's entry`, JSON.stringify(result) === expected && usedIndex(from),
        { result, usedIndex: usedIndex(from) });
    }
    await terminate(db);
  },
};

(async () => {
  try {
    await steps[params.step]();
  } catch (e) {
    check(`${params.step} ran without error`, false, `${e}\n${e.stack}`);
  }
  report();
})();
