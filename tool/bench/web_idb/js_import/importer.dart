// Runs importJsSdkCache against the database that writer.js left (same origin), with a memory cache (hence
// allowMemoryCache: the page only reads the writes back), and reports the result and the local view of the documents
// in document.title. The network never starts: the client points at a closed local port and its network is disabled
// before the import.
//
//   cd .. && dart compile js js_import/importer.dart -o js_import/static/importer.js
//   js_import/run_page.sh importer.html
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

final StringBuffer out = StringBuffer();
void log(String m) {
  out.writeln(m);
  web.document.body!.textContent = out.toString();
}

Future<void> main() async {
  try {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'fake',
        appId: 'fake',
        projectId: 'demo-idb',
      ),
    );
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app)
      ..useFirestoreEmulator('127.0.0.1', 1);
    await firestore.disableNetwork();

    final JsSdkCacheImportResult result = await importJsSdkCache(
      firestore,
      allowMemoryCache: true,
    );
    log('$result');
    for (final String path in <String>[
      'items/cached1',
      'items/gone',
      'items/w1',
      'items/w2',
      'items/w3',
      'items/b1',
      'items/b2',
    ]) {
      try {
        final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
            .doc(path)
            .get(const GetOptions(source: Source.cache));
        log(
          '$path exists=${snapshot.exists} pending=${snapshot.metadata.hasPendingWrites} '
          'data=${snapshot.data()}',
        );
      } on FirestoreException catch (e) {
        log('$path not in cache (${e.errorCode.name})');
      }
    }
    log(
      'pending writes of the signed-out user: ${await firestore.getPendingWriteCount()}',
    );
    final JsSdkCacheImportResult again = await importJsSdkCache(
      firestore,
      allowMemoryCache: true,
    );
    log('again: $again');
    web.document.title = 'ok: ${out.toString().replaceAll('\n', ' | ')}';
  } catch (e, st) {
    log('ERROR $e\n$st');
    web.document.title = 'error: ${out.toString().replaceAll('\n', ' | ')}';
  }
}
