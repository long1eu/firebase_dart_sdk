// Writes a few documents with the official JS SDK (IndexedDB persistence, network disabled) so that the database
// holds pending mutations and a cached remote document. Network never starts: the project is a fake demo- one and
// disableNetwork() runs before any write. Result is reported in document.title and on the page.
import { initializeApp } from 'firebase/app';
import {
  initializeFirestore, persistentLocalCache, persistentSingleTabManager, disableNetwork, doc, setDoc, updateDoc,
  getDocFromCache, loadBundle, Timestamp, GeoPoint, Bytes, serverTimestamp, increment, arrayUnion, deleteDoc,
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
  ];
  const total = body.reduce((n, e) => n + new TextEncoder().encode(e).length, 0);
  const meta = element({ metadata: { id: 'b1', createTime: t, version: 1, totalDocuments: 1, totalBytes: total } });
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
  // Reading from the cache runs after the writes on the same queue, so they are persisted when this returns.
  const snap = await getDocFromCache(doc(db, 'items/w1'));
  log('local doc w1 exists=' + snap.exists() + ' ' + JSON.stringify(snap.data()?.title));
  const c = await getDocFromCache(doc(db, 'items/cached1'));
  log('cached1 exists=' + c.exists());
  document.title = 'done: ' + out.join(' | ').replace(/\n/g,' ');
}
main().catch((e) => { log('ERROR ' + e); document.title = 'error: ' + e + ' after ' + out.join(' | '); });
