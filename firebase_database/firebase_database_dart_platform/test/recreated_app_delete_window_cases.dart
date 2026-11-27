// Sequences around the delete itself, from the review of the other-options
// change (S1, S2, S3, S10 there): a use while FirebaseApp.delete() runs, the
// firebase_app_dart app deleted directly, an app created again with the
// earlier options after other ones. A client is written as in [hosts].

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_other_options_cases.dart';
import 'recreated_app_pinned_cases.dart';
import 'recreated_app_pinned_support.dart';

void _setUp(FirebaseDatabase database, BeforeDelete setting) =>
    setting == BeforeDelete.emulator
    ? emulator9000(database)
    : persistenceOff(database);

Future<String> _withSetting(
  BeforeDelete setting,
  Future<String> Function() body,
) => setting == BeforeDelete.persistenceOff
    ? withPersistenceFactory(body)
    : body();

/// S1 ([then] = [options]) and S2 ([then] = [otherKey]): the cached object,
/// set up with [setting], used; the delete started; the object used again
/// before the delete finished (the service dispose has dropped its client,
/// the core still has the app); the app created again with [then]; then
/// `clientFor(again)`, `instanceFor(app: again, databaseURL: url)` and with
/// `url/`, and the cached object.
Future<String> useDuringDelete(
  String name,
  FirebaseOptions then,
  BeforeDelete setting,
) => _withSetting(setting, () async {
  final FirebaseApp app = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app);
  _setUp(db, setting);
  await db.goOnline();
  final Future<void> deleting = app.delete();
  final String window = await outcome(db.goOnline);
  await deleting;
  final FirebaseApp again = await Firebase.initializeApp(
    name: name,
    options: then,
  );
  final String viaClientFor = await outcome(
    () => FirebaseDatabaseDart.clientFor(again),
  );
  final String viaUrl = await outcome(
    () => FirebaseDatabase.instanceFor(
      app: again,
      databaseURL: databaseUrl,
    ).ref('a').set(1),
  );
  final String viaSlash = await outcome(
    () => FirebaseDatabase.instanceFor(
      app: again,
      databaseURL: '$databaseUrl/',
    ).ref('a').set(1),
  );
  final String cached = await outcome(db.goOnline);
  return 'during delete $window; clientFor(again) $viaClientFor; '
      'instanceFor(url) set $viaUrl; instanceFor(url/) set $viaSlash; '
      'cached goOnline $cached; ${hosts()}';
});

/// S10: the cached object set up with [setting] and used; the
/// firebase_app_dart app of the name deleted directly (the FlutterFire app
/// is kept); then `clientFor(app)`, `instanceFor(app:, databaseURL: url/)`
/// and the cached object.
Future<String> dartAppDeletedDirectly(String name, BeforeDelete setting) =>
    _withSetting(setting, () async {
      final FirebaseApp app = await Firebase.initializeApp(
        name: name,
        options: options,
      );
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app);
      _setUp(db, setting);
      await db.goOnline();
      for (final dart_app.FirebaseApp a in dart_app.Firebase.apps.toList()) {
        if (a.name == name) {
          await a.delete();
        }
      }
      final String viaClientFor = await outcome(
        () => FirebaseDatabaseDart.clientFor(app),
      );
      final String viaSlash = await outcome(
        () => FirebaseDatabase.instanceFor(
          app: app,
          databaseURL: '$databaseUrl/',
        ).ref('a').set(1),
      );
      final String cached = await outcome(db.goOnline);
      return 'clientFor(app) $viaClientFor; instanceFor(url/) set $viaSlash; '
          'cached goOnline $cached; ${hosts()}';
    });

/// S3: created with [options] (emulator on the cached object), again with
/// [otherKey], again with [options]: the uses on each.
Future<String> earlierOptionsAgain(String name) async {
  final Recreated r = await recreate(name, otherKey, beforeUse: emulator9000);
  final String onB = await outcome(r.database.goOnline);
  await r.again.delete();
  final FirebaseApp a3 = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final String onA = await outcome(r.database.goOnline);
  final String viaClientFor = await outcome(
    () => FirebaseDatabaseDart.clientFor(a3),
  );
  final String viaOld = await outcome(
    () => FirebaseDatabaseDart.clientFor(r.old),
  );
  return 'with other options ${onB == otherOptionsErrorOf(name) ? 'E' : onB}; '
      'with the earlier options again: cached $onA, clientFor(new) '
      '$viaClientFor, clientFor(old) $viaOld; ${hosts()}';
}

/// The tests of this file. [dartCore]: the core deletes the
/// firebase_app_dart app with the FlutterFire app (the Dart core); the
/// native-like and web-like cores do not, so a client made during the
/// delete stays open there.
void defineDeleteWindowTests({required bool dartCore}) {
  const String emu = 'null|localhost:9000|memory';
  const String mem = 'null|null|memory';
  String clients(BeforeDelete s, int n) =>
      '[${List<String>.filled(n, s == BeforeDelete.emulator ? emu : mem).join(', ')}]';

  group('a use during the delete', () {
    for (final BeforeDelete s in BeforeDelete.values) {
      test('S1 same options, ${s.name}: every path works, every client keeps '
          'the setting', () async {
        expect(
          await useDuringDelete('s1-${s.name}', options, s),
          'during delete ok; clientFor(again) ok; instanceFor(url) set '
          'pending; instanceFor(url/) set pending; cached goOnline ok; '
          '${clients(s, dartCore ? 3 : 2)}',
        );
      });

      test(
        'S2 other options, ${s.name}: the new paths throw; '
        '${dartCore ? 'the cached object throws' : 'the cached object reuses the client made during the delete'}',
        () async {
          final String name = 's2-${s.name}';
          final String got = await useDuringDelete(name, otherKey, s);
          expect(
            got.replaceAll(
              RegExp(
                'StateError: The Firebase app "$name" was deleted and created[^;]*',
              ),
              'E',
            ),
            'during delete ok; clientFor(again) E; instanceFor(url) set E; '
            'instanceFor(url/) set E; cached goOnline ${dartCore ? 'E' : 'ok'}; '
            '${clients(s, 2)}',
          );
        },
      );
    }
  });

  group('the firebase_app_dart app deleted directly', () {
    for (final BeforeDelete s in BeforeDelete.values) {
      test('S10 ${s.name}: one new client, with the setting', () async {
        expect(
          await dartAppDeletedDirectly('s10-${s.name}', s),
          'clientFor(app) ok; instanceFor(url/) set pending; cached goOnline '
          'ok; ${clients(s, 2)}',
        );
      });
    }
  });

  test('S3 created again with the earlier options after other ones: the name '
      'works again', () async {
    expect(
      await earlierOptionsAgain('s3'),
      'with other options E; with the earlier options again: cached ok, '
      'clientFor(new) ok, clientFor(old) ok; [$emu, $emu]',
    );
  });

  group('one app name in two tests of one process', () {
    test(
      'the first test uses a database of the name and deletes the app',
      () async {
        final FirebaseApp app = await Firebase.initializeApp(
          name: 'suite',
          options: options,
        );
        await FirebaseDatabase.instanceFor(app: app).goOnline();
        await app.delete();
      },
    );

    test('a later test creates the name with other options: clientFor throws, '
        'no client', () async {
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'suite',
        options: otherKey,
      );
      expect(() => FirebaseDatabaseDart.clientFor(app), throwsStateError);
      expect(hosts(), isEmpty);
    });
  });
}
