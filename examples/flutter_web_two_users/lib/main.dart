// Two signed-in users in one Flutter web page. Each column is a whole client:
// its own FirebaseApp (named per client, not per user), its own signed-in
// user (FirebaseUserAuth against the Auth emulator) and its own
// FirebaseFirestore. Both show and write the document boards/shared; the
// security rules (firestore.rules) let only the owner lock it.
//
// ?cache=sqlite gives each client a SQLite cache in IndexedDB (one database
// per app); without it the cache is in memory. run.sh builds and serves the
// page and starts the emulators.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'session_storage.dart';

// The emulators; run.sh passes its ports with --dart-define.
const String firestoreEmulator = String.fromEnvironment(
  'FIRESTORE_EMULATOR',
  defaultValue: '127.0.0.1:8202',
);
const String authEmulator = String.fromEnvironment(
  'AUTH_EMULATOR',
  defaultValue: '127.0.0.1:9201',
);

// A demo- project id: the emulators accept it and nothing reaches Google.
const FirebaseOptions options = FirebaseOptions(
  apiKey: 'demo-key',
  appId: '1:1234567890:web:two-users',
  projectId: 'demo-two-users',
);

/// The two users. Only the owner may lock the board (firestore.rules).
const List<({String client, String email, bool owner})> users =
    <({String client, String email, bool owner})>[
      (client: 'client-left', email: 'alice@example.com', owner: true),
      (client: 'client-right', email: 'bob@example.com', owner: false),
    ];

final Stopwatch sinceStart = Stopwatch();

void main() {
  sinceStart.start();
  final bool sqlite = Uri.base.queryParameters['cache'] == 'sqlite';
  runApp(TwoUsersApp(sqlite: sqlite));
}

class TwoUsersApp extends StatelessWidget {
  const TwoUsersApp({super.key, required this.sqlite});

  final bool sqlite;

  void _open({required bool sqlite}) {
    web.window.location.search = sqlite ? '?cache=sqlite' : '';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Two users, one page',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Two users, one page'),
          actions: <Widget>[
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Memory cache')),
                ButtonSegment<bool>(value: true, label: Text('SQLite cache')),
              ],
              selected: <bool>{sqlite},
              onSelectionChanged: (Set<bool> value) =>
                  _open(sqlite: value.single),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => web.window.location.reload(),
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final user in users)
              Expanded(
                child: ClientColumn(
                  client: user.client,
                  email: user.email,
                  owner: user.owner,
                  sqlite: sqlite,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One client: an app, a signed-in user and a Firestore instance.
class Client {
  Client._(this.app, this.auth, this.firestore);

  final FirebaseApp app;
  final FirebaseUserAuth auth;
  final FirebaseFirestore firestore;

  static Future<Client> start({
    required String name,
    required String email,
    required bool sqlite,
  }) async {
    // Named per client: app names are global in the page, and the same user
    // could be signed in in two columns.
    final FirebaseApp app = FirebaseApp.withOptions(options, name: name);
    // Before the Firestore instance: it becomes the token provider of the app.
    // The session is kept in sessionStorage, so a reload keeps the user.
    final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
      app,
      emulatorHost: authEmulator,
      storage: SessionAuthStorage(),
    );
    if (auth.currentUser == null) {
      const String password = 'demo-password';
      try {
        await auth.signInWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException {
        await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    }
    final int colon = firestoreEmulator.lastIndexOf(':');
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      // One IndexedDB database per app. sqlite3.wasm must be next to the page.
      openDatabase: sqlite ? sqliteOpener() : null,
      settings:
          Settings(
            cacheSettings: sqlite
                ? PersistentCacheSettings()
                : const MemoryCacheSettings(),
          ).withEmulator(
            firestoreEmulator.substring(0, colon),
            int.parse(firestoreEmulator.substring(colon + 1)),
          ),
    );
    return Client._(app, auth, firestore);
  }
}

class ClientColumn extends StatefulWidget {
  const ClientColumn({
    super.key,
    required this.client,
    required this.email,
    required this.owner,
    required this.sqlite,
  });

  final String client;
  final String email;
  final bool owner;
  final bool sqlite;

  @override
  State<ClientColumn> createState() => _ClientColumnState();
}

class _ClientColumnState extends State<ClientColumn> {
  Client? _client;
  StreamSubscription<DocumentSnapshot<Map<String, Object?>>>? _subscription;
  DocumentSnapshot<Map<String, Object?>>? _snapshot;
  String? _firstSnapshot;
  String? _firstFromServer;
  String _result = '';
  String? _error;
  int _writes = 0;

  DocumentReference<Map<String, Object?>> get _board =>
      _client!.firestore.doc('boards/shared');

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final Client client = await Client.start(
        name: widget.client,
        email: widget.email,
        sqlite: widget.sqlite,
      );
      setState(() => _client = client);
      _subscription = _board
          .snapshots(includeMetadataChanges: true)
          .listen(_onSnapshot, onError: _onError);
    } catch (e) {
      _onError(e);
    }
  }

  void _onSnapshot(DocumentSnapshot<Map<String, Object?>> snapshot) {
    final String at = '${sinceStart.elapsedMilliseconds} ms';
    setState(() {
      _snapshot = snapshot;
      _firstSnapshot ??=
          '$at, ${snapshot.metadata.isFromCache ? 'from the cache' : 'from the server'}'
          '${snapshot.exists ? '' : ' (no document yet)'}';
      if (!snapshot.metadata.isFromCache) {
        _firstFromServer ??= at;
      }
    });
    _publish();
  }

  void _onError(Object error) {
    setState(() => _error = '$error');
    _publish();
  }

  Future<void> _write(Map<String, Object?> data, String done) async {
    final Client client = _client!;
    try {
      await _board.set(<String, Object?>{
        ...data,
        'updatedBy': client.auth.uid,
        'by': widget.email,
        'at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _result = done);
    } on FirestoreException catch (e) {
      setState(() => _result = 'Refused: ${e.errorCode.name}');
    }
    _publish();
  }

  bool get _locked => _snapshot?.data()?['locked'] == true;

  /// The state of the column for the driver script (README, "How it was
  /// tried"): `window.twoUsers` in the page.
  void _publish() {
    final Map<String, Object?> data = _snapshot?.data() ?? <String, Object?>{};
    final JSObject all =
        globalContext.getProperty<JSObject?>('twoUsers'.toJS) ?? JSObject();
    all.setProperty(
      widget.client.toJS,
      jsonEncode(<String, Object?>{
        'email': widget.email,
        'text': data['text'],
        'locked': data['locked'],
        'fromCache': _snapshot?.metadata.isFromCache,
        'pending': _snapshot?.metadata.hasPendingWrites,
        'firstSnapshot': _firstSnapshot,
        'firstFromServer': _firstFromServer,
        'result': _result,
        'error': _error,
      }).toJS,
    );
    globalContext.setProperty('twoUsers'.toJS, all);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Client? client = _client;
    final Map<String, Object?>? data = _snapshot?.data();
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.email, style: text.titleLarge),
            Text(
              widget.owner
                  ? 'Owner: may lock the board'
                  : 'Guest: may write while it is unlocked',
            ),
            const Divider(),
            Text('App: ${widget.client}'),
            Text(
              widget.sqlite
                  ? 'Cache: SQLite in IndexedDB '
                        '"cloud_firestore_dart/firestore.${widget.client}.'
                        '${options.projectId}.%28default%29"'
                  : 'Cache: memory',
            ),
            Text('First snapshot: ${_firstSnapshot ?? '...'}'),
            Text('First from the server: ${_firstFromServer ?? '...'}'),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const Divider(),
            Text('boards/shared', style: text.titleMedium),
            Text(
              data == null
                  ? (_snapshot == null ? 'Loading...' : 'No document yet')
                  : '"${data['text'] ?? ''}"',
              style: text.headlineSmall,
            ),
            if (data != null)
              Text('${_locked ? 'Locked' : 'Unlocked'}, last by ${data['by']}'),
            if (_snapshot != null)
              Text(
                '${_snapshot!.metadata.isFromCache ? 'From the cache' : 'From the server'}'
                '${_snapshot!.metadata.hasPendingWrites ? ', a write not sent yet' : ''}',
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: client == null
                      ? null
                      : () => _write(<String, Object?>{
                          'text':
                              'Hello from ${widget.email.split('@').first} '
                              '#${++_writes}',
                          'locked': _locked,
                        }, 'Written'),
                  child: const Text('Write'),
                ),
                OutlinedButton(
                  onPressed: client == null
                      ? null
                      : () => _write(<String, Object?>{
                          'locked': !_locked,
                        }, _locked ? 'Unlocked' : 'Locked'),
                  child: Text(_locked ? 'Unlock' : 'Lock'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_result),
          ],
        ),
      ),
    );
  }
}
