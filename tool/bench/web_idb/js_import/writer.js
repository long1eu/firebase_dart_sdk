// Writes a few documents with the official JS SDK (IndexedDB persistence, network disabled) so that the database
// holds pending mutations and cached remote documents. Network never starts: the project is a fake demo- one and
// disableNetwork() runs before any write. Result is reported in document.title and on the page.
//
// For the importer (importer.dart): the bundle also has a deleted document (a noDocument row), one batch has three
// writes (a WriteBatch), the client terminates at the end (it releases its lease and removes its clientMetadata row,
// as a tab that closes normally does), and a copy of the first batch is then added for a second user, user2, with
// raw IndexedDB (signing in needs a backend): its rows have the shape the JS SDK writes.
import { initializeApp } from 'firebase/app';
import {
  initializeFirestore, persistentLocalCache, persistentSingleTabManager, disableNetwork, doc, setDoc, updateDoc,
  getDocFromCache, loadBundle, Timestamp, GeoPoint, Bytes, serverTimestamp, increment, arrayUnion, deleteDoc,
  writeBatch, terminate,
} from 'firebase/firestore';

const out = [];
const log = (m) => { out.push(m); document.body.textContent = out.join('\n'); };

function element(obj) {
  const s = JSON.stringify(obj);
  return `${new TextEncoder().encode(s).length}${s}`;
}

function buildBundle(project) {
  const parent = `projects/${project}/databases/(default)/documents`;
  const t = { seconds: '1700000000', nanos: 123456000 };
  const name = `${parent}/items/cached1`;
  const body = [
    element({ namedQuery: { name: 'q1', readTime: t, bundledQuery: { parent, structuredQuery: { from: [{ collectionId: 'items' }] } } } }),
    element({ documentMetadata: { name, readTime: t, exists: true, queries: ['q1'] } }),
    element({ document: { name, createTime: t, updateTime: t, fields: {
      title: { stringValue: 'from bundle' }, n: { integerValue: '42' }, d: { doubleValue: 1.5 },
      ts: { timestampValue: '2023-11-14T22:13:20.123456Z' }, b: { bytesValue: 'AAEC' },
      g: { geoPointValue: { latitude: 1.5, longitude: -2.5 } }, r: { referenceValue: `${parent}/items/other` },
      m: { mapValue: { fields: { x: { booleanValue: true }, y: { nullValue: 'NULL_VALUE' } } } },
      a: { arrayValue: { values: [{ stringValue: 'p' }, { integerValue: '7' }] } },
    } } }),
    element({ documentMetadata: { name: `${parent}/items/gone`, readTime: t, exists: false } }),
  ];
  const total = body.reduce((n, e) => n + new TextEncoder().encode(e).length, 0);
  const meta = element({ metadata: { id: 'b1', createTime: t, version: 1, totalDocuments: 2, totalBytes: total } });
  return meta + body.join('');
}

async function main() {
  const project = 'demo-idb';
  const app = initializeApp({ apiKey: 'fake', appId: 'fake', projectId: project });
  const db = initializeFirestore(app, { localCache: persistentLocalCache({ tabManager: persistentSingleTabManager({}) }) });
  await disableNetwork(db);
  log('network disabled');

  const task = loadBundle(db, buildBundle(project));
  await task;
  log('bundle loaded');

  // Do not await the writes: they only resolve when the backend acknowledges them.
  const step = (label, f) => { try { f().catch(() => {}); log('queued ' + label); } catch (e) { log('FAILED ' + label + ': ' + e); } };
  step('w1', () => setDoc(doc(db, 'items/w1'), {
    title: 'written offline', n: 1, d: 2.5, ts: Timestamp.fromMillis(1700000000123), b: Bytes.fromUint8Array(new Uint8Array([1, 2, 3])),
    g: new GeoPoint(10, 20), r: doc(db, 'items/other'), m: { x: true, y: null }, a: [1, 'two'], st: serverTimestamp(),
  }));
  step('w2', () => setDoc(doc(db, 'items/w2'), { count: 1 }));
  step('w2u', () => updateDoc(doc(db, 'items/w2'), { count: increment(5), tags: arrayUnion('a', 'b'), 'nested.field': 'v' }));
  step('w3', () => deleteDoc(doc(db, 'items/w3')));
  step('batch', () => writeBatch(db)
    .set(doc(db, 'items/b1'), { inBatch: true })
    .update(doc(db, 'items/cached1'), { title: 'updated offline' })
    .delete(doc(db, 'items/b2'))
    .commit());
  // Reading from the cache runs after the writes on the same queue, so they are persisted when this returns.
  const snap = await getDocFromCache(doc(db, 'items/w1'));
  log('local doc w1 exists=' + snap.exists() + ' ' + JSON.stringify(snap.data()?.title));
  const c = await getDocFromCache(doc(db, 'items/cached1'));
  log('cached1 exists=' + c.exists());
  await terminate(db);
  log('terminated');
  await addSecondUser(`firestore/[DEFAULT]/${project}/main`);
  log('copied the first batch for user2');
  document.title = 'done: ' + out.join(' | ').replace(/\n/g,' ');
}

const req = (r) => new Promise((resolve, reject) => { r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error); });

// The rows the JS SDK writes for a batch (indexeddb_mutation_queue.ts addMutationBatch): the batch with an
// auto-incremented batchId, the user's mutationQueues row, and one documentMutations key per document
// ([userId, encodeResourcePath(path), batchId]; each segment followed by \u0001\u0001).
async function addSecondUser(name) {
  const idb = await req(indexedDB.open(name));
  const tx = idb.transaction(['mutations', 'mutationQueues', 'documentMutations'], 'readwrite');
  const done = new Promise((resolve, reject) => { tx.oncomplete = resolve; tx.onabort = () => reject(tx.error); });
  const first = (await req(tx.objectStore('mutations').getAll()))[0];
  const copy = { ...first, userId: 'user2', localWriteTimeMs: first.localWriteTimeMs + 1 };
  delete copy.batchId;
  const batchId = await req(tx.objectStore('mutations').add(copy));
  await req(tx.objectStore('mutationQueues').put({ userId: 'user2', lastAcknowledgedBatchId: -1, lastStreamToken: '' }));
  for (const write of copy.mutations) {
    const docName = write.update ? write.update.name : write.delete;
    const path = docName.split('/documents/')[1].split('/').map((s) => s + '\u0001\u0001').join('');
    await req(tx.objectStore('documentMutations').put({}, ['user2', path, batchId]));
  }
  await done;
  idb.close();
}
main().catch((e) => { log('ERROR ' + e); document.title = 'error: ' + e + ' after ' + out.join(' | '); });
