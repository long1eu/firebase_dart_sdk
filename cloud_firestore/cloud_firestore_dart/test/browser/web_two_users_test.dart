// Two signed-in users in one page, each with its own FirebaseApp, its own
// FirebaseUserAuth and its own Firestore client, against the Firebase Auth
// emulator and a Firestore emulator with the rules of
// tool/auth_emulators/firestore.rules (`two_users/`: every signed-in user
// writes, only an `owner-` email may lock a document, and a locked document
// is written by the owner only).
//
// tool/test_browser.sh starts both emulators (tool/start_auth_emulators.sh)
// and writes their addresses to test/browser/auth_emulators.txt:
//
//   auth=127.0.0.1:9297
//   firestore=127.0.0.1:8297
//
// Without that file the tests skip themselves.

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'browser_test_util.dart' show EventLog;

typedef Json = Map<String, Object?>;

String? authHost;
String? rulesHost;

Future<void> loadAuthEmulators() async {
  try {
    final web.Response response = await web.window
        .fetch(Uri.base.resolve('auth_emulators.txt').toString().toJS)
        .toDart;
    if (!response.ok) {
      return;
    }
    for (final String line in (await response.text().toDart).toDart.split(
      '\n',
    )) {
      final int eq = line.indexOf('=');
      if (eq < 0) {
        continue;
      }
      final String value = line.substring(eq + 1).trim();
      switch (line.substring(0, eq).trim()) {
        case 'auth':
          authHost = value;
        case 'firestore':
          rulesHost = value;
      }
    }
  } catch (_) {
    // No file: the tests skip.
  }
}

final Random _random = Random();

/// One client of the page: an app named per client, its user and Firestore.
class Client {
  Client._(this.app, this.auth, this.firestore, this.email, this._clock);

  final FirebaseApp app;
  final FirebaseUserAuth auth;
  final FirebaseFirestore firestore;
  final String email;

  /// The token changes after sign-in.
  int refreshes = 0;

  final _Clock _clock;

  /// Added to the clock of [auth]: an ID token is stale for it when
  /// `clock + 5 min` is past the token's expiry.
  set clockOffset(Duration offset) => _clock.offset = offset;

  static Future<Client> start(String role) async {
    final String id =
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(1 << 30)}';
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:dart:browser',
        projectId: 'demo-test',
      ),
      name: 'client-$role-$id',
    );
    final _Clock clock = _Clock();
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: app.options.apiKey,
      appId: app.options.appId,
      storageKey: 'two-users:${app.name}',
      emulatorHost: authHost,
      clock: clock.now,
    );
    await auth.restore();
    app.authProvider = auth;
    final String email = '$role-$id@example.com';
    await auth.createUserWithEmailAndPassword(
      email: email,
      password: 'demo-password',
    );
    final int colon = rulesHost!.lastIndexOf(':');
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings(cacheSettings: const MemoryCacheSettings())
          .withEmulator(
            rulesHost!.substring(0, colon),
            int.parse(rulesHost!.substring(colon + 1)),
          ),
    );
    final Client client = Client._(app, auth, firestore, email, clock);
    auth.onTokenChanged.listen((_) {
      client.refreshes++;
      // The new token is not stale: back to the real time.
      clock.offset = Duration.zero;
    });
    addTearDown(() async {
      await firestore.terminate();
      try {
        await auth.deleteCurrentUser();
      } catch (_) {
        // Already gone with the emulator.
      }
      await auth.dispose();
      await app.delete();
    });
    return client;
  }

  Future<void> write(DocumentReference<Json> ref, Json data) => firestore
      .doc(ref.path)
      .set(<String, Object?>{...data, 'by': email}, SetOptions(merge: true));
}

class _Clock {
  Duration offset = Duration.zero;

  DateTime now() => DateTime.now().add(offset);
}

Matcher refused = throwsA(
  isA<FirestoreException>().having(
    (FirestoreException e) => e.errorCode,
    'code',
    FirestoreErrorCode.permissionDenied,
  ),
);

void main() {
  setUpAll(() async {
    // The refused writes are on purpose; Firestore logs each as a warning.
    FirebaseFirestore.setLogLevel(LogLevel.error);
    await loadAuthEmulators();
  });

  String? skip() => authHost == null || rulesHost == null
      ? 'test/browser/auth_emulators.txt is missing: tool/test_browser.sh '
            'writes it when it could start tool/start_auth_emulators.sh'
      : null;

  test('two apps, two users, one page: each sees the other\'s writes, and '
      'the rules apply per user', () async {
    if (skip() case final String reason) {
      markTestSkipped(reason);
      return;
    }
    final Client owner = await Client.start('owner');
    final Client guest = await Client.start('guest');
    // Nothing is shared between the two clients.
    expect(identical(owner.app, guest.app), isFalse);
    expect(owner.auth.uid, isNot(guest.auth.uid));

    final String path = 'two_users/${DateTime.now().microsecondsSinceEpoch}';
    final DocumentReference<Json> doc = owner.firestore.doc(path);
    final EventLog<DocumentSnapshot<Json>> ownerSees = EventLog(
      owner.firestore.doc(path).snapshots(),
    );
    final EventLog<DocumentSnapshot<Json>> guestSees = EventLog(
      guest.firestore.doc(path).snapshots(),
    );

    await owner.write(doc, <String, Object?>{'text': 'one', 'locked': false});
    await guestSees.waitFor(
      (DocumentSnapshot<Json> s) =>
          s.data()?['text'] == 'one' && !s.metadata.isFromCache,
    );
    await guest.write(doc, <String, Object?>{'text': 'two', 'locked': false});
    await ownerSees.waitFor(
      (DocumentSnapshot<Json> s) =>
          s.data()?['text'] == 'two' && s.data()?['by'] == guest.email,
    );

    // The guest may not lock it; the owner may.
    await expectLater(
      guest.write(doc, <String, Object?>{'locked': true}),
      refused,
    );
    await owner.write(doc, <String, Object?>{'locked': true});
    await guestSees.waitFor(
      (DocumentSnapshot<Json> s) => s.data()?['locked'] == true,
    );
    // Locked, the guest's write is refused and the owner's is not.
    await expectLater(
      guest.write(doc, <String, Object?>{'text': 'three'}),
      refused,
    );
    await owner.write(doc, <String, Object?>{'text': 'four'});
    final DocumentSnapshot<Json> last = await guestSees.waitFor(
      (DocumentSnapshot<Json> s) => s.data()?['text'] == 'four',
    );
    expect(last.data()?['by'], owner.email);
  });

  test('token refresh per app: a stale token of one user refreshes only that '
      'client', () async {
    if (skip() case final String reason) {
      markTestSkipped(reason);
      return;
    }
    final Client a = await Client.start('owner');
    final Client b = await Client.start('guest');
    final String path = 'two_users/${DateTime.now().microsecondsSinceEpoch}';
    final DocumentReference<Json> doc = a.firestore.doc(path);
    final EventLog<DocumentSnapshot<Json>> bSees = EventLog(
      b.firestore.doc(path).snapshots(),
    );
    await a.write(doc, <String, Object?>{'text': 'before', 'locked': false});
    await bSees.waitFor(
      (DocumentSnapshot<Json> s) => s.data()?['text'] == 'before',
    );
    a.refreshes = 0;
    b.refreshes = 0;

    // A's token expires: for its clock it is two hours later. Its streams
    // reconnect, ask for a token, and get a refreshed one from the Auth
    // emulator; B's client is not involved.
    a.clockOffset = const Duration(hours: 2);
    await a.firestore.disableNetwork();
    await a.firestore.enableNetwork();
    await a.write(doc, <String, Object?>{'text': 'after'});
    await bSees.waitFor(
      (DocumentSnapshot<Json> s) => s.data()?['text'] == 'after',
    );

    expect(a.refreshes, greaterThanOrEqualTo(1));
    expect(b.refreshes, 0);
    // Both still write as themselves, under their own rules.
    await b.write(doc, <String, Object?>{'text': 'from b'});
    await expectLater(b.write(doc, <String, Object?>{'locked': true}), refused);
    expect(b.refreshes, 0);
  });
}
