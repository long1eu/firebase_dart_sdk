// Pins the as-built rows A1, A7, A34 of remote_config.v4-asbuilt.md that no other test pins.
//
// A31 is not pinned: `_Restart` is thrown only by `_afterConflict` and caught by `_ensureRegistered`
// (the one caller that awaits the registration; `getId` swallows it), and `_Superseded` is caught where
// it is thrown (`_sendCreate`, `_sendGenerate`). The `unavailable` mapping in `_public` has no path
// from the public API with fakes.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_installations_dart/src/bounded.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/r3_fis_rig.dart';

typedef _IdToken = ({String id, String token});

const int _mib16 = 16 * 1024 * 1024;
const int _maxSafe = 9007199254740991;

/// The file name of [key] in a `FileKeyValueStore`: lowercase hex SHA-256 of the key plus `.json`.
String _fileName(String key) => '${sha256.convert(utf8.encode(key))}.json';

/// Text that is not 1 to 4096 printable ASCII characters, by reason.
final Map<String, String> _badTokens = <String, String>{
  'empty': '',
  'with a space': 'a b',
  'with a tab': 'a\tb',
  'with DEL': 'a\x7fb',
  'non-ASCII': 'tokén',
  'over 4096 characters': 'a' * 4097,
};

Map<String, Object?> _registered([Map<String, Object?> changes = const {}]) =>
    <String, Object?>{
      'v': 1,
      'fid': r3Fid,
      'status': 'registered',
      'refreshToken': 'refresh-a',
      'token': 'auth-a',
      'tokenCreatedAt': 1000,
      'tokenExpiresIn': 3600000,
      ...changes,
    };

Map<String, Object?> _registering([Map<String, Object?> changes = const {}]) =>
    <String, Object?>{
      'v': 1,
      'fid': r3Fid,
      'status': 'registering',
      'registrationStartedAt': 1000,
      'registrationOwner': 'owner.1',
      ...changes,
    };

InstallationRecord? _parse(Map<String, Object?> json) =>
    InstallationRecord.tryParse(jsonEncode(json));

void main() {
  group('A1 two stores on one directory', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fis_gap_');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
    });

    test('A1 a second store whose first use races the first one is refused '
        'with a StateError; the first one works', () async {
      final FileKeyValueStore first = FileKeyValueStore(dir.path);
      final FileKeyValueStore second = FileKeyValueStore(dir.path);
      addTearDown(first.close);
      addTearDown(second.close);

      final Future<String?> readFirst = first.read('k');
      final Future<String?> readSecond = second.read('k');

      await expectLater(readSecond, throwsStateError);
      expect(await readFirst, isNull);
      await first.write('k', 'v');
      expect(await first.read('k'), 'v');
    });

    test('A1 the refused store can start once the first one has closed, and '
        'the directory is held again by it', () async {
      final FileKeyValueStore first = FileKeyValueStore(dir.path);
      final FileKeyValueStore second = FileKeyValueStore(dir.path);
      final FileKeyValueStore third = FileKeyValueStore(dir.path);
      addTearDown(first.close);
      addTearDown(second.close);
      addTearDown(third.close);
      final Future<String?> readFirst = first.read('k');
      await expectLater(second.read('k'), throwsStateError);
      await readFirst;

      await first.close();
      await second.write('k', 'v');

      await expectLater(third.read('k'), throwsStateError);
      expect(await second.read('k'), 'v');
    });

    test(
      'A1 a path that reaches the directory through a symbolic link counts as '
      'the same directory',
      () async {
        final Directory links = Directory.systemTemp.createTempSync(
          'fis_gap_link_',
        );
        addTearDown(() => links.deleteSync(recursive: true));
        final String alias = '${links.path}${Platform.pathSeparator}alias';
        Link(alias).createSync(dir.path);
        final FileKeyValueStore first = FileKeyValueStore(dir.path);
        final FileKeyValueStore second = FileKeyValueStore(alias);
        addTearDown(first.close);
        addTearDown(second.close);

        final Future<String?> readFirst = first.read('k');
        final Future<String?> readSecond = second.read('k');

        await expectLater(readSecond, throwsStateError);
        expect(await readFirst, isNull);
      },
      skip: Platform.isWindows ? 'symbolic links need privileges' : false,
    );
  });

  group('A7 digit strings', () {
    test('A7 a 16-digit string within 2^53 - 1 parses', () {
      expect(
        parseBoundedInt('9007199254740991', min: 0, max: _maxSafe),
        _maxSafe,
      );
      expect(parseBoundedInt('0000000000000001', min: 0, max: _maxSafe), 1);
      expect(
        parseBoundedInt('1000000000000000', min: 0, max: _maxSafe),
        1000000000000000,
      );
    });

    test('A7 a 16-digit string above 2^53 - 1 is absent', () {
      expect(
        parseBoundedInt('9007199254740992', min: 0, max: _maxSafe),
        isNull,
      );
      expect(
        parseBoundedInt('9999999999999999', min: 0, max: _maxSafe),
        isNull,
      );
    });

    test('A7 a string of 17 digits is absent even when its value is small', () {
      expect(
        parseBoundedInt('00000000000000001', min: 0, max: _maxSafe),
        isNull,
      );
      expect(
        parseBoundedInt('10000000000000000', min: 0, max: _maxSafe),
        isNull,
      );
    });

    test('A7 a stored time written as a 16-digit string parses; as 17 digits '
        'the record is absent', () {
      final InstallationRecord? sixteen = _parse(
        _registered(<String, Object?>{'tokenCreatedAt': '0000001700000000'}),
      );
      expect(sixteen, isNotNull);
      expect(sixteen!.tokenCreatedAt!.millisecondsSinceEpoch, 1700000000);

      expect(
        _parse(
          _registered(<String, Object?>{'tokenCreatedAt': '00000001700000000'}),
        ),
        isNull,
      );
    });
  });

  group('A34 stored records', () {
    for (final MapEntry<String, String> bad in _badTokens.entries) {
      test('A34 a stored refreshToken ${bad.key} makes the record absent', () {
        expect(
          _parse(_registered(<String, Object?>{'refreshToken': bad.value})),
          isNull,
        );
      });

      test('A34 a stored token ${bad.key} makes the record absent', () {
        expect(
          _parse(_registered(<String, Object?>{'token': bad.value})),
          isNull,
        );
      });
    }

    test('A34 tokens of 1 and 4096 printable ASCII characters are kept', () {
      final InstallationRecord? record = _parse(
        _registered(<String, Object?>{
          'refreshToken': '!' * 4096,
          'token': '~',
        }),
      );
      expect(record, isNotNull);
      expect(record!.refreshToken, '!' * 4096);
      expect(record.token, '~');
    });

    test('A34 tokenExpiresIn under 1000 ms makes the record absent; 1000 ms '
        'is kept', () {
      expect(
        _parse(_registered(<String, Object?>{'tokenExpiresIn': 999})),
        isNull,
      );
      expect(
        _parse(_registered(<String, Object?>{'tokenExpiresIn': 0})),
        isNull,
      );
      final InstallationRecord? kept = _parse(
        _registered(<String, Object?>{'tokenExpiresIn': 1000}),
      );
      expect(kept!.tokenExpiresIn, const Duration(seconds: 1));
    });

    test('A34 times are within 0 and the end of year 9999', () {
      expect(
        _parse(_registered(<String, Object?>{'tokenCreatedAt': -1})),
        isNull,
      );
      expect(
        _parse(
          _registered(<String, Object?>{'tokenCreatedAt': 253402300800000}),
        ),
        isNull,
      );
      final InstallationRecord? last = _parse(
        _registered(<String, Object?>{'tokenCreatedAt': 253402300799999}),
      );
      expect(last!.tokenCreatedAt!.millisecondsSinceEpoch, 253402300799999);
      final InstallationRecord? first = _parse(
        _registered(<String, Object?>{'tokenCreatedAt': 0}),
      );
      expect(first!.tokenCreatedAt!.millisecondsSinceEpoch, 0);
    });

    // The spec row says the owner field "voids the marker"; the code (and known limit L1, N6) voids the
    // whole record, so the installation gets a new one. SPEC: A34; code returns null for the record.
    for (final String owner in <String>['', 'a b', 'a/b', 'café', 'x' * 65]) {
      test('A34 a registrationOwner not matching the pattern ("$owner") voids '
          'the record', () {
        expect(
          _parse(_registering(<String, Object?>{'registrationOwner': owner})),
          isNull,
        );
      });

      test('A34 a tokenRequestOwner not matching the pattern ("$owner") voids '
          'the record', () {
        expect(
          _parse(
            _registered(<String, Object?>{
              'tokenRequestStartedAt': 2000,
              'tokenRequestOwner': owner,
            }),
          ),
          isNull,
        );
      });
    }

    test('A34 owners of 1 to 64 letters, digits, dot, underscore and hyphen '
        'are kept', () {
      for (final String owner in <String>['a', 'Az09._-', 'x' * 64]) {
        final InstallationRecord? registering = _parse(
          _registering(<String, Object?>{'registrationOwner': owner}),
        );
        expect(registering!.registrationOwner, owner);
        final InstallationRecord? registered = _parse(
          _registered(<String, Object?>{
            'tokenRequestStartedAt': 2000,
            'tokenRequestOwner': owner,
          }),
        );
        expect(registered!.tokenRequestOwner, owner);
      }
    });
  });

  group('A34 server answers', () {
    for (final MapEntry<String, String> bad in _badTokens.entries) {
      test('A34 a create answer with a refresh token ${bad.key} is '
          'invalid-response and registers nothing', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final FirebaseInstallations installations = rig.instance(fis);
          fis.answer(
            FisRoute.create,
            FisAnswer.create(refreshToken: bad.value),
          );

          final Outcome<_IdToken> outcome = Outcome<_IdToken>(
            installations.getIdAndToken(),
          );
          async.flushMicrotasks();

          expect(outcome.error, isFisException('invalid-response'));
          expect(fis.count(FisRoute.create), 1, reason: 'not retried');
          expect(rig.stored()?['refreshToken'], isNull);
          rig.dispose();
        });
      });

      test('A34 a create answer with an auth token ${bad.key} is '
          'invalid-response and registers nothing', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final FirebaseInstallations installations = rig.instance(fis);
          fis.answer(FisRoute.create, FisAnswer.create(token: bad.value));

          final Outcome<_IdToken> outcome = Outcome<_IdToken>(
            installations.getIdAndToken(),
          );
          async.flushMicrotasks();

          expect(outcome.error, isFisException('invalid-response'));
          expect(rig.stored()?['refreshToken'], isNull);
          rig.dispose();
        });
      });

      test('A34 a generate answer with a token ${bad.key} is '
          'invalid-response and the stored token stays', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final FirebaseInstallations installations = rig.instance(fis);
          final Outcome<_IdToken> registered = Outcome<_IdToken>(
            installations.getIdAndToken(),
          );
          async.flushMicrotasks();
          final String stored = registered.value.token;
          fis.answer(FisRoute.generate, FisAnswer.token(token: bad.value));

          final Outcome<String> refreshed = Outcome<String>(
            installations.getToken(forceRefresh: true),
          );
          async.flushMicrotasks();

          expect(refreshed.error, isFisException('invalid-response'));
          expect(rig.stored()!['token'], stored);
          rig.dispose();
        });
      });
    }

    test('A34 tokens of 4096 printable ASCII characters are accepted', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations installations = rig.instance(fis);
        fis.answer(
          FisRoute.create,
          FisAnswer.create(refreshToken: '!' * 4096, token: '~' * 4096),
        );

        final Outcome<_IdToken> outcome = Outcome<_IdToken>(
          installations.getIdAndToken(),
        );
        async.flushMicrotasks();

        expect(outcome.value.token, '~' * 4096);
        rig.dispose();
      });
    });

    test('A34 a token lifetime under one second is invalid-response', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations installations = rig.instance(fis);
        fis.answer(FisRoute.create, FisAnswer.create(expiresIn: '0s'));

        final Outcome<_IdToken> outcome = Outcome<_IdToken>(
          installations.getIdAndToken(),
        );
        async.flushMicrotasks();

        expect(outcome.error, isFisException('invalid-response'));
        rig.dispose();
      });
    });

    test('A34 DELETE carries no Content-Type; POST does', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations installations = rig.instance(fis);
        final Outcome<_IdToken> registered = Outcome<_IdToken>(
          installations.getIdAndToken(),
        );
        async.flushMicrotasks();
        expect(registered.isDone, isTrue);

        final Outcome<void> deleted = Outcome<void>(installations.delete());
        async.flushMicrotasks();

        expect(deleted.isDone, isTrue);
        expect(deleted.error, isNull);
        final FisRequest delete = fis.requestsTo(FisRoute.delete).single;
        expect(delete.method, 'DELETE');
        expect(delete.headers, isNot(contains('content-type')));
        expect(delete.authorization, startsWith('FIS_v2 '));
        expect(
          fis.requestsTo(FisRoute.create).single.headers['content-type'],
          'application/json',
        );
        rig.dispose();
      });
    });

    for (final String origin in <String>[
      'https://fis.example.test/',
      'https://fis.example.test',
    ]) {
      test('A34 an origin "$origin" is accepted and the requests go to it', () {
        fakeAsync((FakeAsync async) {
          final FakeFis fis = FakeFis();
          final FirebaseApp app = newFisApp();
          final FirebaseInstallations installations = FirebaseInstallations(
            app,
            store: MemoryKeyValueStore(),
            httpClient: fis.client,
            serverOrigin: Uri.parse(origin),
            clock: FisClock(async).call,
            random: () => 0.5,
          );

          final Outcome<_IdToken> outcome = Outcome<_IdToken>(
            installations.getIdAndToken(),
          );
          async.flushMicrotasks();

          expect(outcome.isDone, isTrue);
          expect(outcome.error, isNull);
          final Uri url = fis.requestsTo(FisRoute.create).single.url;
          expect(url.host, 'fis.example.test');
          expect(url.path, '/v1/projects/$fisProjectId/installations');
          unawaited(installations.close());
          unawaited(app.delete());
          async.flushMicrotasks();
        });
      });
    }

    test('A34 an origin with a path other than / is refused', () {
      final FakeFis fis = FakeFis();
      final FirebaseApp app = newFisApp();
      addTearDown(app.delete);

      expect(
        () => FirebaseInstallations(
          app,
          store: MemoryKeyValueStore(),
          httpClient: fis.client,
          serverOrigin: Uri.parse('https://fis.example.test/proxy'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('A34 file store', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fis_gap_store_');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
    });

    FileKeyValueStore open() {
      final FileKeyValueStore store = FileKeyValueStore(dir.path);
      addTearDown(store.close);
      return store;
    }

    test('A34 a value of 16 MiB + 1 byte is refused with storage-error and '
        'the old value stays', () async {
      final FileKeyValueStore store = open();
      await store.write('k', 'old');

      await expectLater(
        store.write('k', 'a' * (_mib16 + 1)),
        throwsA(
          isA<FirebaseInstallationsException>()
              .having(
                (FirebaseInstallationsException e) => e.code,
                'code',
                'storage-error',
              )
              .having(
                (FirebaseInstallationsException e) => e.message,
                'message',
                contains('16 MiB'),
              ),
        ),
      );

      expect(await store.read('k'), 'old');
      final List<String> names = <String>[
        for (final FileSystemEntity entity in dir.listSync())
          entity.uri.pathSegments.where((String s) => s.isNotEmpty).last,
      ];
      expect(names.where((String n) => n.endsWith('.tmp')), isEmpty);
    });

    test('A34 an update that returns 16 MiB + 1 byte is refused too', () async {
      final FileKeyValueStore store = open();

      await expectLater(
        store.update('k', (String? _) => 'a' * (_mib16 + 1)),
        throwsA(isA<FirebaseInstallationsException>()),
      );

      expect(await store.read('k'), isNull);
    });

    test('A34 a value of exactly 16 MiB is written and read back', () async {
      final FileKeyValueStore store = open();
      final String value = 'a' * _mib16;

      await store.write('k', value);

      expect((await store.read('k'))!.length, _mib16);
    });

    test(
      'A34 a directory with content at a key\'s path counts as absent',
      () async {
        final FileKeyValueStore store = open();
        await store.read('start');
        final Directory squatter = Directory(
          '${dir.path}${Platform.pathSeparator}${_fileName('k')}',
        )..createSync();
        File(
          '${squatter.path}${Platform.pathSeparator}inner',
        ).writeAsStringSync('x');

        expect(await store.read('k'), isNull);
      },
    );

    test('A34 an empty directory at a key\'s path counts as absent and is '
        'removed by the next write', () async {
      final FileKeyValueStore store = open();
      await store.read('start');
      final String path =
          '${dir.path}${Platform.pathSeparator}${_fileName('k')}';
      Directory(path).createSync();

      expect(await store.read('k'), isNull);
      await store.write('k', 'v');

      expect(FileSystemEntity.isFileSync(path), isTrue);
      expect(await store.read('k'), 'v');
    });

    test('A34 every call after close throws a StateError', () async {
      final FileKeyValueStore store = FileKeyValueStore(dir.path);
      await store.write('k', 'v');
      await store.close();

      await expectLater(store.read('k'), throwsStateError);
      await expectLater(store.write('k', 'w'), throwsStateError);
      await expectLater(
        store.update('k', (String? current) => current),
        throwsStateError,
      );
    });

    test('A34 calls after close throw a StateError also when the store never '
        'started', () async {
      final FileKeyValueStore store = FileKeyValueStore(dir.path);
      await store.close();

      await expectLater(store.read('k'), throwsStateError);
      expect(
        Directory(dir.path).listSync().where(
          (FileSystemEntity e) => e.path.endsWith('.owner.lock'),
        ),
        isEmpty,
        reason: 'a closed store that never started opens nothing',
      );
    });
  });
}
