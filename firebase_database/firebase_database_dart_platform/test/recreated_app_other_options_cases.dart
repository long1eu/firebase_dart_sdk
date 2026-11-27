// The sequences of the recreated_app_other_options_*_test.dart files: an app
// deleted and created again under the same name with other options (one row
// per field that FirebaseOptions == compares), with the same options, and an
// app never deleted. Each returns what happened as a string, and each test
// file (one per core) pins those strings. A client is written as in [hosts].

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_pinned_cases.dart';
import 'recreated_app_pinned_support.dart';

/// The StateError of an app named [name] created again with other options,
/// as [describe] writes it (cut at 60 characters).
String otherOptionsErrorOf(String name) {
  final String text =
      'The Firebase app "$name" was deleted and created again with other '
      'options.';
  return 'StateError: ${text.length > 60 ? text.substring(0, 60) : text}';
}

/// [options] with one field changed, for each field that `FirebaseOptions
/// ==` compares (its `asMap`, firebase_core_platform_interface 8.2.0).
final Map<String, FirebaseOptions> otherOptionsByField =
    <String, FirebaseOptions>{
      'apiKey': options.copyWith(apiKey: 'other-api-key'),
      'appId': options.copyWith(appId: '1:2:web:2'),
      'messagingSenderId': options.copyWith(messagingSenderId: '2'),
      'projectId': options.copyWith(projectId: 'demo-other'),
      'authDomain': options.copyWith(authDomain: 'other.example.com'),
      'databaseURL': otherDatabase,
      'storageBucket': options.copyWith(storageBucket: 'other-bucket'),
      'measurementId': options.copyWith(measurementId: 'G-OTHER'),
      'trackingId': options.copyWith(trackingId: 'UA-OTHER'),
      'deepLinkURLScheme': options.copyWith(deepLinkURLScheme: 'other'),
      'androidClientId': options.copyWith(androidClientId: 'other-android'),
      'iosClientId': options.copyWith(iosClientId: 'other-ios'),
      'iosBundleId': options.copyWith(iosBundleId: 'com.example.other'),
      'appGroupId': options.copyWith(appGroupId: 'group.other'),
    };

/// [options] with only `recaptchaSiteKey` set, which `FirebaseOptions ==`
/// does not compare.
const FirebaseOptions otherRecaptchaOnly = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
  databaseURL: databaseUrl,
  recaptchaSiteKey: 'other-site-key',
);

/// The setting made on the cached object before its first use: the emulator
/// `localhost:9000`, or persistence off under a configuration with a
/// persistence factory (so that a client without the setting would be on
/// disk).
enum BeforeDelete {
  /// `useDatabaseEmulator('localhost', 9000)`.
  emulator,

  /// `setPersistenceEnabled(false)`, with a persistence factory configured.
  persistenceOff,
}

/// K0 to K3 after [recreate] of app [name] with [then], the cached object
/// set up with [setting]. Every path names the database of the cached
/// object ([databaseUrl]). Gives `K1 ...; K2 ...; K2 default ...; K3 ...;
/// K0 ...; clients`, where `K2 default` is `clientFor(again)` without a URL
/// (another database when [then] has another databaseURL).
Future<String> kRow(String name, FirebaseOptions then, BeforeDelete setting) {
  Future<String> body() async {
    final Recreated r = await recreate(
      name,
      then,
      beforeUse: setting == BeforeDelete.emulator
          ? emulator9000
          : persistenceOff,
    );
    final String k1 = await outcome(
      () => FirebaseDatabase.instanceFor(
        app: r.again,
        databaseURL: databaseUrl,
      ).ref('a').set(1),
    );
    final String k2 = await outcome(
      () => FirebaseDatabaseDart.clientFor(r.again, databaseURL: databaseUrl),
    );
    final String k2Default = await outcome(
      () => FirebaseDatabaseDart.clientFor(r.again),
    );
    final String k3 = await outcome(
      () => FirebaseDatabaseDart.clientFor(r.old),
    );
    final String k0 = await outcome(r.database.goOnline);
    return 'K1 $k1; K2 $k2; K2 default $k2Default; K3 $k3; K0 $k0; ${hosts()}';
  }

  return setting == BeforeDelete.persistenceOff
      ? withPersistenceFactory(body)
      : body();
}

/// K1 and K2 naming a database the earlier app did not use ([otherUrl]),
/// after [recreate] of app [name] with [then], the cached object set up
/// with [setting], and `clientFor(old app object, databaseURL: [otherUrl])`.
/// Gives `K1 new ...; K2 new ...; K3 new ...; clients`.
Future<String> newDatabaseRow(
  String name,
  FirebaseOptions then,
  BeforeDelete setting,
) {
  Future<String> body() async {
    final Recreated r = await recreate(
      name,
      then,
      beforeUse: setting == BeforeDelete.emulator
          ? emulator9000
          : persistenceOff,
    );
    final String k1 = await outcome(
      () => FirebaseDatabase.instanceFor(
        app: r.again,
        databaseURL: otherUrl,
      ).ref('a').set(1),
    );
    final String k2 = await outcome(
      () => FirebaseDatabaseDart.clientFor(r.again, databaseURL: otherUrl),
    );
    final String k3 = await outcome(
      () => FirebaseDatabaseDart.clientFor(r.old, databaseURL: otherUrl),
    );
    return 'K1 new $k1; K2 new $k2; K3 new $k3; ${hosts()}';
  }

  return setting == BeforeDelete.persistenceOff
      ? withPersistenceFactory(body)
      : body();
}

/// An app that never had a FirebaseDatabase instance, deleted and created
/// again with [otherKey]: its use, `clientFor`, and the clients.
Future<String> neverUsedThenOtherOptions(String name) async {
  final FirebaseApp first = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  await first.delete();
  final FirebaseApp again = await Firebase.initializeApp(
    name: name,
    options: otherKey,
  );
  final String set = await outcome(
    () => FirebaseDatabase.instanceFor(app: again).ref('a').set(1),
  );
  final String client = await outcome(
    () => FirebaseDatabaseDart.clientFor(again),
  );
  return 'set $set; clientFor $client; ${hosts()}';
}

/// An instance kept for [databaseUrl] only (emulator set), the app created
/// again with the same options, then a second database ([otherUrl]) used.
Future<String> sameOptionsThenSecondDatabase(String name) async {
  final Recreated r = await recreate(name, options, beforeUse: emulator9000);
  final String set = await outcome(
    () => FirebaseDatabase.instanceFor(
      app: r.again,
      databaseURL: otherUrl,
    ).ref('a').set(1),
  );
  final String client = await outcome(
    () => FirebaseDatabaseDart.clientFor(r.again, databaseURL: otherUrl),
  );
  final String first = await outcome(r.database.goOnline);
  return 'second database set $set; clientFor $client; cached object '
      'goOnline $first; ${hosts()}';
}

/// An app never deleted, used [uses] times, each time through
/// `instanceFor`, the cached object and `clientFor` with an app object read
/// again by `Firebase.app(name)`. Gives whether two reads are identical,
/// whether every use gave the same object and client, the outcome of the
/// last use, and the clients.
Future<String> neverDeletedManyReads(String name, {int uses = 100}) async {
  final FirebaseApp app = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final bool readsIdentical = identical(Firebase.app(name), Firebase.app(name));
  final FirebaseDatabase cached = FirebaseDatabase.instanceFor(app: app);
  final fs.FirebaseDatabase client = FirebaseDatabaseDart.clientFor(app);
  bool same = true;
  String last = '';
  for (int i = 0; i < uses; i++) {
    final FirebaseApp read = Firebase.app(name);
    same &= identical(FirebaseDatabase.instanceFor(app: read), cached);
    same &= identical(FirebaseDatabaseDart.clientFor(read), client);
    same &= identical(
      FirebaseDatabaseDart.clientFor(
        Firebase.app(name),
        databaseURL: databaseUrl,
      ),
      client,
    );
    final String viaInstanceFor = await outcome(
      () => FirebaseDatabase.instanceFor(app: Firebase.app(name)).goOnline(),
    );
    last = '$viaInstanceFor/${await outcome(cached.goOnline)}';
  }
  return 'two reads identical $readsIdentical; every use same object and '
      'client $same; use $uses: $last; ${hosts()}';
}

/// The app [name] recreated with another databaseURL ([otherDatabase]), the
/// cached object with the emulator: what the objects of the new database
/// (`instanceFor(app: again)` and `clientFor(again)` without a URL, which
/// name [otherUrl]) give.
Future<String> otherDatabaseDefault(String name) async {
  final Recreated r = await recreate(
    name,
    otherDatabase,
    beforeUse: emulator9000,
  );
  final String cached =
      '${identical(FirebaseDatabase.instanceFor(app: r.again), r.database)}';
  final String viaUrl = await outcome(
    () => FirebaseDatabase.instanceFor(
      app: r.again,
      databaseURL: otherUrl,
    ).ref('a').set(1),
  );
  final String viaClientFor = await outcome(
    () => FirebaseDatabaseDart.clientFor(r.again),
  );
  return 'instanceFor(app: again) is the cached object $cached; '
      'instanceFor(app: again, databaseURL: new URL) set $viaUrl; '
      'clientFor(again) $viaClientFor; ${hosts()}';
}

/// An app never deleted: `instanceFor` and `clientFor` called again with the
/// same app object and with the object `Firebase.app(name)` reads now.
Future<String> neverDeletedRepeated(String name) async {
  final FirebaseApp app = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final FirebaseDatabase x = FirebaseDatabase.instanceFor(app: app)
    ..useDatabaseEmulator('localhost', 9000);
  final String use = await outcome(x.goOnline);
  final FirebaseApp reread = Firebase.app(name);
  final fs.FirebaseDatabase client = FirebaseDatabaseDart.clientFor(app);
  final List<bool> same = <bool>[
    identical(FirebaseDatabase.instanceFor(app: app), x),
    identical(FirebaseDatabase.instanceFor(app: reread), x),
    identical(FirebaseDatabaseDart.clientFor(app), client),
    identical(FirebaseDatabaseDart.clientFor(reread), client),
    identical(
      FirebaseDatabaseDart.clientFor(reread, databaseURL: databaseUrl),
      client,
    ),
  ];
  final String viaUrl = await outcome(
    () => FirebaseDatabase.instanceFor(
      app: reread,
      databaseURL: databaseUrl,
    ).goOnline(),
  );
  return 'use $use; re-read object is the app object ${identical(reread, app)}; '
      'same object and client $same; instanceFor(re-read, databaseURL) use '
      '$viaUrl; ${hosts()}';
}

/// The calls of the cached object after the app was created again with
/// [then]: [oldObjectTable] with the emulator set before the delete, each
/// row on its own app named `$prefix-<n>`.
Future<Map<String, String>> oldObjectCallsAfter(
  String prefix,
  FirebaseOptions then,
) => oldObjectTable(prefix, then, beforeUse: emulator9000);

const String _emulatorClient = 'null|localhost:9000|memory';

/// What [kRow] gives when every path throws [otherOptionsErrorOf] and no
/// client is created after the delete.
String _allThrow(String name, FirebaseOptions then, BeforeDelete setting) {
  final String e = otherOptionsErrorOf(name);
  final String client = setting == BeforeDelete.emulator
      ? _emulatorClient
      : 'null|null|memory';
  return 'K1 $e; K2 $e; K2 default $e; K3 $e; K0 $e; [$client]';
}

/// The tests of the recreated_app_other_options_*_test.dart files; each
/// gives the same result on every core.
void defineRecreatedAppTests() {
  group('other options: every path that needs a client throws', () {
    int n = 0;
    for (final MapEntry<String, FirebaseOptions> row
        in otherOptionsByField.entries) {
      for (final BeforeDelete setting in BeforeDelete.values) {
        final String name = 'oo${n++}';
        test('${row.key} changed, ${setting.name} before the delete: K0 to K3 '
            'throw, no client after the delete', () async {
          expect(
            await kRow(name, row.value, setting),
            _allThrow(name, row.value, setting),
          );
          expect(productionClients(), hasLength(setting.index));
        });
      }
    }

    for (final String field in <String>['apiKey', 'databaseURL']) {
      for (final BeforeDelete setting in BeforeDelete.values) {
        final String name = 'nd-$field-${setting.name}';
        test('$field changed, ${setting.name} before the delete: K1 and K2 '
            'naming a new database throw, no client after the delete', () async {
          final String e = otherOptionsErrorOf(name);
          expect(
            await newDatabaseRow(name, otherOptionsByField[field]!, setting),
            'K1 new $e; K2 new $e; K3 new $e; '
            '[${setting == BeforeDelete.emulator ? _emulatorClient : 'null|null|memory'}]',
          );
        });
      }
    }

    test(
      'databaseURL changed: the objects of the new database throw',
      () async {
        final String e = otherOptionsErrorOf('odb');
        expect(
          await otherDatabaseDefault('odb'),
          'instanceFor(app: again) is the cached object true; '
          'instanceFor(app: again, databaseURL: new URL) set $e; '
          'clientFor(again) $e; [$_emulatorClient]',
        );
      },
    );

    test('an app that never had an instance, created again with other '
        'options, works as a new app', () async {
      expect(
        await neverUsedThenOtherOptions('never-used'),
        'set pending; clientFor ok; [null|null|memory]',
      );
    });

    test('the calls of the cached object (emulator set before the delete), '
        'apiKey changed', () async {
      final Map<String, String> table = await oldObjectCallsAfter(
        'old',
        otherKey,
      );
      String e(int n) => otherOptionsErrorOf('old-$n');
      expect(table, <String, String>{
        'ref': 'ok; then goOnline: ${e(0)}; [$_emulatorClient]',
        'set': '${e(1)}; then goOnline: ${e(1)}; [$_emulatorClient]',
        'get': '${e(2)}; then goOnline: ${e(2)}; [$_emulatorClient]',
        'useDatabaseEmulator same':
            'ok; then goOnline: ${e(3)}; [$_emulatorClient]',
        'useDatabaseEmulator other':
            'ok; then goOnline: ${e(4)}; [$_emulatorClient]',
        'setPersistenceEnabled(true)':
            'ok; then goOnline: ${e(5)}; [$_emulatorClient]',
        'setPersistenceEnabled(false)':
            'ok; then goOnline: ${e(6)}; [$_emulatorClient]',
        'goOnline': '${e(7)}; then goOnline: ${e(7)}; [$_emulatorClient]',
        'goOffline': '${e(8)}; then goOnline: ${e(8)}; [$_emulatorClient]',
        'purgeOutstandingWrites':
            '${e(9)}; then goOnline: ${e(9)}; [$_emulatorClient]',
        'onValue':
            'error ${e(10)}; then goOnline: ${e(10)}; [$_emulatorClient]',
      });
    });
  });

  group('same options', () {
    const String two = '[$_emulatorClient, $_emulatorClient]';

    test('once, emulator: K0 to K3 work and share one new client with the '
        'emulator', () async {
      expect(
        await kRow('same-k', options, BeforeDelete.emulator),
        'K1 pending; K2 ok; K2 default ok; K3 ok; K0 ok; $two',
      );
    });

    test(
      'once, persistence off: K0 to K3 share one new client in memory',
      () async {
        expect(
          await kRow('same-kp', options, BeforeDelete.persistenceOff),
          'K1 pending; K2 ok; K2 default ok; K3 ok; K0 ok; '
          '[null|null|memory, null|null|memory]',
        );
      },
    );

    test(
      'once: instanceFor(app: again) is the cached object, clientFor(again) '
      'and clientFor(old) return the one client of the cached object',
      () async {
        expect(
          await newObjects('same-n', options, beforeUse: emulator9000),
          <String, String>{
            'instanceFor(app: again) is the old object': 'true',
            'instanceFor(app: again, databaseURL) is the old object': 'false',
            'old client closed': 'true',
            'new object set': 'pending',
            'old object goOnline': 'ok',
            'clientFor(again) is clientFor(old)': 'true',
            'clientFor(again)': 'client',
            'clients': two,
          },
        );
      },
    );

    test('twice: the cached object keeps the emulator and persistence off set '
        'between the recreates, one client per app', () async {
      expect(
        await twice('same-r1', second: emulator9000),
        'gen2 use: ok; gen3 use: ok; '
        '[null|null|memory, $_emulatorClient, $_emulatorClient]',
      );
      createdClients.clear();
      expect(
        await withPersistenceFactory(
          () => twice('same-r2', second: persistenceOff),
        ),
        'gen2 use: ok; gen3 use: ok; '
        '[null|null|disk, null|null|memory, null|null|memory]',
      );
    });

    test('the calls of the cached object: each works; a setter called after '
        'the delete and before the next use takes effect', () async {
      final Map<String, String> table = await oldObjectCallsAfter(
        'same-old',
        options,
      );
      expect(table, <String, String>{
        'ref': 'ok; then goOnline: ok; $two',
        'set': 'pending; then goOnline: ok; $two',
        'get': 'pending; then goOnline: ok; $two',
        'useDatabaseEmulator same': 'ok; then goOnline: ok; $two',
        'useDatabaseEmulator other':
            'ok; then goOnline: ok; [$_emulatorClient, '
            'null|localhost:9001|memory]',
        'setPersistenceEnabled(true)': 'ok; then goOnline: ok; $two',
        'setPersistenceEnabled(false)': 'ok; then goOnline: ok; $two',
        'goOnline': 'ok; then goOnline: ok; $two',
        'goOffline': 'ok; then goOnline: ok; $two',
        'purgeOutstandingWrites': 'ok; then goOnline: ok; $two',
        'onValue': 'nothing; then goOnline: ok; $two',
      });
    });

    test('an instance kept for one database, then a second database: a new '
        'client without the settings of the first', () async {
      expect(
        await sameOptionsThenSecondDatabase('same-db2'),
        'second database set pending; clientFor ok; cached object goOnline '
        'ok; [$_emulatorClient, https://other-ns.firebaseio.com|null|memory, '
        '$_emulatorClient]',
      );
    });

    test('only recaptchaSiteKey changed counts as the same options', () async {
      expect(
        await kRow('same-rc', otherRecaptchaOnly, BeforeDelete.emulator),
        'K1 pending; K2 ok; K2 default ok; K3 ok; K0 ok; $two',
      );
    });
  });

  group('an app never deleted', () {
    test('100 uses with a freshly read app object each: one object, one '
        'client', () async {
      expect(
        await neverDeletedManyReads('never-100'),
        'two reads identical false; every use same object and client true; '
        'use 100: ok/ok; [null|null|memory]',
      );
    });

    test('instanceFor and clientFor again, with the app object and a re-read '
        'one, give the same object and client', () async {
      expect(
        await neverDeletedRepeated('never'),
        'use ok; re-read object is the app object false; same object and '
        'client [true, true, true, true, true]; instanceFor(re-read, '
        'databaseURL) use ok; [$_emulatorClient]',
      );
    });

    test('W1 and W2: plain use and a write, one client', () async {
      expect(
        await neverDeleted('never-w1', emulator: false),
        'use ok; set ok; use again ok; one client true; '
        '[null|null|memory]',
      );
      createdClients.clear();
      expect(
        await neverDeleted('never-w2', emulator: true),
        'use ok; set ok; use again ok; one client true; [$_emulatorClient]',
      );
    });
  });
}
