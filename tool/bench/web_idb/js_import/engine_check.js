// Opens, with the official JS SDK (`firebase` 12, persistentLocalCache with persistentSingleTabManager, network
// disabled), the database that the IndexedDB engine of this SDK wrote (idb_engine/engine_page.dart, project demo-idb),
// reads what the Dart page wrote, adds one write of its own (items/fromjs) and terminates. Then the Dart page reads that
// write back. Result in document.title.
//
//   cd tool/bench/web_idb/js_import && npm install
//   npx esbuild engine_check.js --bundle --platform=browser --main-fields=browser,module,main \
//     --conditions=browser --outfile=static/engine_check.bundle.js
//   rm -rf /tmp/idb_profile
//   ../idb_engine/run_page.sh index.html             # the Dart engine writes (and reloads once)
//   ./run_page.sh engine_check.html                  # the JS SDK reads that and writes items/fromjs
//   ../idb_engine/run_page.sh 'index.html#phase2'    # the Dart engine reads items/fromjs
//
// The other way round (a database the JS SDK wrote, opened by the Dart engine): run writer.html first (writer.js),
// then '../idb_engine/run_page.sh index.html#phase2' (the rows of the JS SDK's bundle and writes are listed).
import { initializeApp } from 'firebase/app';
import {
  initializeFirestore, persistentLocalCache, persistentSingleTabManager, disableNetwork, doc, collection, query, where,
  getDocFromCache, getDocsFromCache, setDoc, terminate,
} from 'firebase/firestore';

const out = [];
const log = (m) => { out.push(m); document.body.textContent = out.join('\n'); };

async function main() {
  const app = initializeApp({ apiKey: 'fake', appId: 'fake', projectId: 'demo-idb' });
  const db = initializeFirestore(app, { localCache: persistentLocalCache({ tabManager: persistentSingleTabManager({}) }) });
  await disableNetwork(db);
  for (const path of ['items/a', 'items/b']) {
    try {
      const snap = await getDocFromCache(doc(db, path));
      log(`${path} exists=${snap.exists()} pending=${snap.metadata.hasPendingWrites} ${JSON.stringify(snap.data())}`);
    } catch (e) {
      log(`${path}: ${e}`);
    }
  }
  const q = await getDocsFromCache(query(collection(db, 'items'), where('n', '>', 0)));
  log('items where n > 0: ' + JSON.stringify(q.docs.map((d) => d.id)));
  setDoc(doc(db, 'items/fromjs'), { n: 3, by: 'js' }).catch(() => {});
  const mine = await getDocFromCache(doc(db, 'items/fromjs'));
  log('items/fromjs written: ' + JSON.stringify(mine.data()));
  await terminate(db);
  document.title = 'ok: ' + out.join(' | ');
}
main().catch((e) => { log('ERROR ' + e); document.title = 'error: ' + e + ' after ' + out.join(' | '); });
