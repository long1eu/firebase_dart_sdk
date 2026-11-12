// Node harness for the Dart <-> JS SDK interop tests.
//
//   node harness.mjs <command> <input.json> <output.json>
//
// Talks to the Firestore emulator only (no credentials). The input is a JSON object with at least `projectId`,
// `host` and `port`; the output is a JSON object. See test/integration/firebase/firestore/js_interop_test.dart in
// cloud_firestore_dart for the caller.

import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { deleteApp, initializeApp } from 'firebase/app';
import {
  Bytes,
  DocumentReference,
  GeoPoint,
  Timestamp,
  VectorValue,
  collection,
  collectionGroup,
  connectFirestoreEmulator,
  doc,
  documentSnapshotFromJSON,
  getDoc,
  getDocs,
  getFirestore,
  limit,
  limitToLast,
  onSnapshotResume,
  or,
  orderBy,
  query,
  querySnapshotFromJSON,
  setDoc,
  terminate,
  vector,
  where
} from 'firebase/firestore';

const [command, inputFile, outputFile] = process.argv.slice(2);
const input = JSON.parse(readFileSync(inputFile, 'utf8'));

const app = initializeApp({ projectId: input.projectId, apiKey: 'none' }, 'interop');
const db = getFirestore(app);
connectFirestoreEmulator(db, input.host, input.port);

// ---- Values: a tagged description shared with the Dart tests ----

/** Describes a value read from Firestore. Numbers are one type in JS: integers and doubles are both 'number'. */
function describe(value) {
  if (value === null) {
    return { t: 'null' };
  } else if (typeof value === 'boolean') {
    return { t: 'bool', v: value };
  } else if (typeof value === 'number') {
    return { t: 'number', v: Object.is(value, -0) ? '-0' : String(value) };
  } else if (typeof value === 'string') {
    return { t: 'string', v: value };
  } else if (value instanceof Timestamp) {
    return { t: 'timestamp', s: String(value.seconds), n: value.nanoseconds };
  } else if (value instanceof GeoPoint) {
    return { t: 'geo', lat: String(value.latitude), lng: String(value.longitude) };
  } else if (value instanceof Bytes) {
    return { t: 'bytes', v: value.toBase64() };
  } else if (value instanceof DocumentReference) {
    return { t: 'ref', v: value.path };
  } else if (value instanceof VectorValue) {
    return { t: 'vector', v: value.toArray().map(String) };
  } else if (Array.isArray(value)) {
    return { t: 'array', v: value.map(describe) };
  } else if (typeof value === 'object') {
    const result = {};
    for (const key of Object.keys(value)) {
      result[key] = describe(value[key]);
    }
    return { t: 'map', v: result };
  }
  throw new Error(`Cannot describe ${value}`);
}

/** Builds the value to write for a description ('int' and 'double' are both written as a JS number). */
function build(spec) {
  switch (spec.t) {
    case 'null':
      return null;
    case 'bool':
    case 'string':
      return spec.v;
    case 'int':
    case 'double':
      return Number(spec.v);
    case 'timestamp':
      return new Timestamp(Number(spec.s), spec.n);
    case 'geo':
      return new GeoPoint(Number(spec.lat), Number(spec.lng));
    case 'bytes':
      return Bytes.fromBase64String(spec.v);
    case 'ref':
      return doc(db, spec.v);
    case 'vector':
      return vector(spec.v.map(Number));
    case 'array':
      return spec.v.map(build);
    case 'map': {
      const result = {};
      for (const key of Object.keys(spec.v)) {
        result[key] = build(spec.v[key]);
      }
      return result;
    }
    default:
      throw new Error(`Unknown spec ${JSON.stringify(spec)}`);
  }
}

function describeDocs(snapshot) {
  return snapshot.docs.map(d => ({ id: d.id, path: d.ref.path, data: describe(d.data()) }));
}

async function attempt(fn) {
  try {
    return await fn();
  } catch (e) {
    return { error: `${e && e.code ? e.code + ': ' : ''}${e && e.message ? e.message : e}` };
  }
}

function withTimeout(promise, what, ms = 10000) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error(`Timed out: ${what}`)), ms))
  ]);
}

// ---- Snapshot JSON ----

/** The queries of the snapshot cases, by name, over the collection [name]. */
function snapshotQueries(name) {
  const coll = collection(db, name);
  return {
    query: query(coll, orderBy('n')),
    limit: query(coll, orderBy('n'), limit(2)),
    limitToLast: query(coll, orderBy('n'), limitToLast(2)),
    filter: query(coll, where('n', '>=', 2), orderBy('n', 'desc')),
    or: query(coll, or(where('n', '==', 1), where('n', '==', 3))),
    subcollection: query(collection(db, `${name}/a/sub-${name}`), orderBy('n')),
    collectionGroup: query(collectionGroup(db, `sub-${name}`), orderBy('n')),
    empty: query(coll, where('n', '>', 100))
  };
}

/** Writes the documents of the snapshot cases and returns the toJSON() of each case. */
async function writeSnapshots() {
  const name = input.collection;
  const coll = collection(db, name);
  await setDoc(doc(coll, 'a'), { n: 1, s: 'one' });
  await setDoc(doc(coll, 'b'), { n: 2, s: 'two' });
  await setDoc(doc(coll, 'c'), { n: 3, s: 'three \u{1F60A} é' });
  await setDoc(doc(db, `${name}/a/sub-${name}/x`), { n: 10 });
  await setDoc(doc(db, `${name}/a/sub-${name}/y`), { n: 20 });

  const result = {
    document: (await getDoc(doc(coll, 'a'))).toJSON(),
    missingDocument: (await getDoc(doc(coll, 'missing'))).toJSON()
  };
  const queries = snapshotQueries(name);
  for (const key of Object.keys(queries)) {
    result[key] = (await getDocs(queries[key])).toJSON();
  }
  return result;
}

/**
 * Reads the snapshot JSON objects in `input.snapshots` (written by the Dart SDK): fromJSON, then onSnapshotResume
 * until the listener is in sync with the backend.
 */
async function readSnapshots() {
  const result = {};
  for (const key of Object.keys(input.snapshots)) {
    const json = input.snapshots[key];
    const isDocument = json.bundleSource === 'DocumentSnapshot';
    const entry = {};
    entry.fromJson = await attempt(() => {
      if (isDocument) {
        const snapshot = documentSnapshotFromJSON(db, json);
        return {
          exists: snapshot.exists(),
          path: snapshot.ref.path,
          data: snapshot.exists() ? describe(snapshot.data()) : null
        };
      }
      return { docs: describeDocs(querySnapshotFromJSON(db, json)) };
    });
    entry.resume = await attempt(async () => {
      const events = [];
      let unsubscribe = () => {};
      const synced = new Promise((resolve, reject) => {
        unsubscribe = onSnapshotResume(
          db,
          json,
          { includeMetadataChanges: true },
          snapshot => {
            const event = isDocument
              ? {
                  fromCache: snapshot.metadata.fromCache,
                  exists: snapshot.exists(),
                  data: snapshot.exists() ? describe(snapshot.data()) : null
                }
              : { fromCache: snapshot.metadata.fromCache, docs: describeDocs(snapshot) };
            events.push(event);
            if (!snapshot.metadata.fromCache) {
              resolve();
            }
          },
          reject
        );
      });
      try {
        await withTimeout(synced, `resume of ${key}`);
      } finally {
        unsubscribe();
      }
      return { events };
    });
    result[key] = entry;
  }
  return result;
}

// ---- Value JSON helpers ----

function valuesToJson() {
  return {
    timestamp: new Timestamp(1234567890, 123456789).toJSON(),
    negativeTimestamp: new Timestamp(-62135596800, 0).toJSON(),
    geoPoint: new GeoPoint(12.5, -77.25).toJSON(),
    bytes: Bytes.fromUint8Array(new Uint8Array([0, 1, 2, 254, 255])).toJSON(),
    emptyBytes: Bytes.fromUint8Array(new Uint8Array([])).toJSON(),
    documentReference: doc(db, 'rooms/eros/messages/1').toJSON(),
    vector: vector([1, 2.5, -3]).toJSON(),
    emptyVector: vector([]).toJSON()
  };
}

async function valuesFromJson() {
  const values = input.values;
  const readers = {
    timestamp: json => Timestamp.fromJSON(json),
    negativeTimestamp: json => Timestamp.fromJSON(json),
    geoPoint: json => GeoPoint.fromJSON(json),
    bytes: json => Bytes.fromJSON(json),
    emptyBytes: json => Bytes.fromJSON(json),
    documentReference: json => DocumentReference.fromJSON(db, json),
    vector: json => VectorValue.fromJSON(json),
    emptyVector: json => VectorValue.fromJSON(json)
  };
  const result = {};
  for (const key of Object.keys(values)) {
    result[key] = await attempt(() => describe(readers[key](values[key])));
  }
  return result;
}

// ---- Data round trip ----

/** Writes `input.documents` ({id: spec}) to `input.collection` and returns the toJSON() of their snapshots. */
async function writeData() {
  const snapshots = {};
  for (const id of Object.keys(input.documents)) {
    const reference = doc(db, input.collection, id);
    await setDoc(reference, build(input.documents[id]));
    snapshots[id] = (await getDoc(reference)).toJSON();
  }
  return { snapshots };
}

/** Reads `input.collection` ordered by `input.orderBy` (document id when missing) from the backend. */
async function readData() {
  const coll = collection(db, input.collection);
  const snapshot = await getDocs(input.orderBy ? query(coll, orderBy(input.orderBy)) : coll);
  return { docs: describeDocs(snapshot) };
}

// ---- Bundles (firebase-admin, emulator only) ----

async function buildBundle() {
  process.env.FIRESTORE_EMULATOR_HOST = `${input.host}:${input.port}`;
  const adminAppModule = await import('firebase-admin/app');
  const adminFirestore = await import('firebase-admin/firestore');
  const adminApp = adminAppModule.initializeApp({ projectId: input.projectId }, 'interop-admin');
  const adminDb = adminFirestore.getFirestore(adminApp);
  const coll = adminDb.collection(input.collection);
  await coll.doc('a').set({ n: 1, s: 'one', when: new adminFirestore.Timestamp(100, 5000) });
  await coll.doc('b').set({ n: 2, s: 'two \u{1F60A}', where: new adminFirestore.GeoPoint(1, 2) });
  await coll.doc('c').set({ n: 3, ref: coll.doc('a'), bytes: Buffer.from([1, 2, 3]), list: [1, 'x', null] });

  const bundle = adminDb.bundle(input.bundleId);
  bundle.add(await coll.doc('a').get());
  bundle.add('all', await coll.orderBy('n').get());
  bundle.add('last-two', await coll.orderBy('n').limitToLast(2).get());
  bundle.add('first-one', await coll.orderBy('n', 'desc').limit(1).get());
  bundle.add(await coll.doc('missing').get());
  const bytes = bundle.build();
  writeFileSync(join(input.tempDirectory, input.bundleFile), bytes);
  await adminAppModule.deleteApp(adminApp);
  return { bytes: bytes.length };
}

const commands = {
  'write-snapshots': writeSnapshots,
  'read-snapshots': readSnapshots,
  'values-to-json': valuesToJson,
  'values-from-json': valuesFromJson,
  'write-data': writeData,
  'read-data': readData,
  'build-bundle': buildBundle
};

let exitCode = 0;
try {
  if (!commands[command]) {
    throw new Error(`Unknown command ${command}`);
  }
  writeFileSync(outputFile, JSON.stringify(await commands[command](), null, 1));
} catch (e) {
  console.error(e);
  exitCode = 1;
} finally {
  await terminate(db).catch(() => {});
  await deleteApp(app).catch(() => {});
}
process.exit(exitCode);
