// The page of the main library: a real-time list of notes, a form that adds
// one, an online/offline indicator, and a choice of cache.
//
// The web support of cloud_firestore_dart is supported in Chrome. See
// README.md for how to build and serve this page.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/indexeddb_cache.dart';
// Internal: only for the primary/secondary indicator of the multi-tab mode.
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;
import 'package:web_app/app_config.dart';

Future<void> main() async {
  final AppConfig config = AppConfig.fromUri(Uri.base);
  _text('#backend', config.backendLabel);
  _setUpCacheChoice(config.cache);

  final FirebaseApp app = FirebaseApp.withOptions(firebaseOptions);
  Settings settings = Settings();
  if (config.emulatorHost != null) {
    settings = settings.withEmulator(
      config.emulatorHost!,
      config.emulatorPort!,
    );
  }

  final FirebaseFirestore firestore;
  try {
    firestore = config.multiTab
        ? await _openMultiTab(app, settings)
        : await _open(app, settings, config.cache);
  } catch (e) {
    _text('#cache-status', 'The cache could not be opened: $e');
    return;
  }

  final CollectionReference<Map<String, Object?>> notes = firestore.collection(
    notesCollection,
  );
  _listen(notes);
  _setUpForm(notes);
  _setUpNetworkToggle(firestore);
  _watchBrowserConnectivity();
}

/// `?multiTab=1`: the IndexedDB cache shared by the tabs. One tab (the
/// primary) uses the network for all of them; open the page in two tabs and
/// close the primary one to see the other take over.
Future<FirebaseFirestore> _openMultiTab(
  FirebaseApp app,
  Settings settings,
) async {
  _text('#cache-status', 'IndexedDB, shared by the tabs of this page.');
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: settings.copyWith(
      cacheSettings: indexedDbCacheSettings(multiTab: true),
    ),
  );
  await firestore.initialized;
  void showRole() => _text(
    '#tab-role',
    firestore.client.syncEngine.isPrimaryClient
        ? 'Primary: this tab uses the network for all tabs'
        : 'Secondary: the primary tab listens and writes for this one',
  );
  showRole();
  Timer.periodic(const Duration(milliseconds: 500), (_) => showRole());
  return firestore;
}

/// Creates the instance with the cache the page was asked for.
Future<FirebaseFirestore> _open(
  FirebaseApp app,
  Settings settings,
  CacheChoice cache,
) async {
  switch (cache) {
    case CacheChoice.memory:
      _text(
        '#cache-status',
        'Memory: the cache is gone when you close the page.',
      );
      return FirebaseFirestore.instanceFor(
        app: app,
        settings: settings.copyWith(cacheSettings: const MemoryCacheSettings()),
      );
    case CacheChoice.indexeddb:
    case CacheChoice.opfs:
      _text('#cache-status', 'Opening the persistent cache...');
      // A second tab cannot open the same persistent cache (a Web Lock guards
      // it): openWithMemoryFallback then returns an instance with a memory
      // cache.
      final FirebaseFirestore firestore = await openWithMemoryFallback(
        app: app,
        openDatabase: sqliteOpener(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          opfsWorker: cache == CacheChoice.opfs
              ? Uri.parse('sqlite_opfs_worker.js')
              : null,
        ),
        settings: settings.copyWith(cacheSettings: PersistentCacheSettings()),
      );
      // The index manager exists only with a persistent cache.
      if (firestore.persistentCacheIndexManager == null) {
        _text(
          '#cache-status',
          'Memory: another tab has the persistent cache open. Close it and '
              'reload this page to use the persistent cache here.',
        );
      } else {
        _text(
          '#cache-status',
          cache == CacheChoice.opfs
              ? 'Persistent: SQLite in a worker, stored in OPFS (or in '
                    'IndexedDB where the browser has no synchronous OPFS '
                    'access). Reload the page: the notes are there before '
                    'the backend answers.'
              : 'Persistent: SQLite in the page, stored in IndexedDB. Reload '
                    'the page: the notes are there before the backend '
                    'answers.',
        );
      }
      return firestore;
  }
}

/// Shows the 50 newest notes, and whether they come from the backend.
void _listen(CollectionReference<Map<String, Object?>> notes) {
  final web.Element list = web.document.querySelector('#notes')!;
  notes
      .orderBy('createdAt', descending: true)
      .limit(50)
      // includeMetadataChanges: also a snapshot when only isFromCache or
      // hasPendingWrites changed, so that the indicator follows them.
      .snapshots(includeMetadataChanges: true)
      .listen(
        (QuerySnapshot<Map<String, Object?>> snapshot) {
          list.textContent = '';
          for (final QueryDocumentSnapshot<Map<String, Object?>> doc
              in snapshot.docs) {
            // A server timestamp the backend has not set yet reads as null;
            // `estimate` gives the local time instead.
            final Map<String, Object?> data = doc.data(
              serverTimestamps: ServerTimestampBehavior.estimate,
            );
            final web.Element item = web.document.createElement('li');
            final Object? createdAt = data['createdAt'];
            item.textContent =
                '${data['text']}'
                '${createdAt is Timestamp ? '  (${_time(createdAt.toDate())})' : ''}'
                '${doc.metadata.hasPendingWrites ? '  [not sent yet]' : ''}';
            list.append(item);
          }
          if (snapshot.docs.isEmpty) {
            list.textContent = 'No notes yet.';
          }
          final bool fromCache = snapshot.metadata.isFromCache;
          final web.Element status = web.document.querySelector('#sync')!;
          status.className = fromCache ? 'offline' : 'online';
          status.textContent = fromCache
              ? 'Offline: showing the cache'
              : snapshot.metadata.hasPendingWrites
              ? 'Online: sending writes'
              : 'Online: in sync with the backend';
        },
        onError: (Object error) {
          _text('#sync', 'The listener failed: $error');
        },
      );
}

/// Adds a note. The write is in the cache, and in the list, at once; the
/// future completes when the backend has it, which never happens offline, so
/// the form does not wait for it.
void _setUpForm(CollectionReference<Map<String, Object?>> notes) {
  final web.HTMLFormElement form =
      web.document.querySelector('#add') as web.HTMLFormElement;
  final web.HTMLInputElement input =
      web.document.querySelector('#text') as web.HTMLInputElement;
  form.onSubmit.listen((web.Event event) {
    event.preventDefault();
    final String text = input.value.trim();
    if (text.isEmpty) {
      return;
    }
    input.value = '';
    unawaited(
      notes
          .add(<String, Object?>{
            'text': text,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .then<void>(
            (_) {},
            onError: (Object error) => _text('#error', 'Write failed: $error'),
          ),
    );
  });
}

/// Takes the client offline and back, to try offline writes without
/// unplugging anything.
void _setUpNetworkToggle(FirebaseFirestore firestore) {
  final web.HTMLButtonElement button =
      web.document.querySelector('#network') as web.HTMLButtonElement;
  bool enabled = true;
  button.onClick.listen((web.Event _) async {
    button.disabled = true;
    try {
      if (enabled) {
        await firestore.disableNetwork();
      } else {
        await firestore.enableNetwork();
      }
      enabled = !enabled;
      button.textContent = enabled ? 'Disable network' : 'Enable network';
    } finally {
      button.disabled = false;
    }
  });
}

/// What the browser itself says. The client listens to the same `online` and
/// `offline` events and reconnects at once when the network comes back.
void _watchBrowserConnectivity() {
  void show() => _text(
    '#browser',
    web.window.navigator.onLine ? 'Browser: online' : 'Browser: offline',
  );
  show();
  web.EventStreamProviders.onlineEvent
      .forTarget(web.window)
      .listen((web.Event _) => show());
  web.EventStreamProviders.offlineEvent
      .forTarget(web.window)
      .listen((web.Event _) => show());
}

void _setUpCacheChoice(CacheChoice current) {
  final web.HTMLSelectElement select =
      web.document.querySelector('#cache') as web.HTMLSelectElement;
  select.value = current.name;
  // The settings of an instance cannot change: load the page again with the
  // other cache.
  select.onChange.listen((web.Event _) {
    web.window.location.href = withQueryParameter(
      Uri.base,
      'cache',
      select.value,
    ).toString();
  });
}

void _text(String selector, String text) {
  web.document.querySelector(selector)?.textContent = text;
}

String _time(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
