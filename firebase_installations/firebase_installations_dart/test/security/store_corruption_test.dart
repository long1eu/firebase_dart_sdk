// Spec v4 5.10 / 5.3 for Installations: a stored record that is corrupt in any way counts as absent, no
// call throws because of it, and the next write replaces it with a valid record.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:test/test.dart';

import '../support/fis_sec_io.dart';
import '../support/fis_sec_support.dart';

/// A valid registered record of fisSecServerFid; a corrupt variant must not give this FID back.
Map<String, Object?> _base() =>
    fisSecRegisteredJson()..['fid'] = fisSecServerFid;

String _baseText() => jsonEncode(_base());

Map<String, Object?> _without(String key) => _base()..remove(key);

Map<String, Object?> _with(String key, Object? value) => _base()..[key] = value;

void main() {
  final String base = _baseText();
  final Map<String, String> corrupt = <String, String>{
    'empty': '',
    'an open brace': '{',
    'null': 'null',
    'an empty list': '[]',
    'a string': '"text"',
    'a number': '42',
    'true': 'true',
    'an empty object': '{}',
    'no v': jsonEncode(_without('v')),
    'v 2 (unknown version)': jsonEncode(_with('v', 2)),
    'v 0': jsonEncode(_with('v', 0)),
    'v as a string': jsonEncode(_with('v', '1')),
    'v 1.5': jsonEncode(_with('v', 1.5)),
    'v null': jsonEncode(_with('v', null)),
    'fid a number': jsonEncode(_with('fid', 7)),
    'fid null': jsonEncode(_with('fid', null)),
    'fid missing': jsonEncode(_without('fid')),
    'fid not matching the pattern': jsonEncode(_with('fid', 'not-a-fid')),
    'fid a list': jsonEncode(_with('fid', <String>[fisSecServerFid])),
    'status unknown': jsonEncode(_with('status', 'done')),
    'status upper-case': jsonEncode(_with('status', 'REGISTERED')),
    'status a number': jsonEncode(_with('status', 2)),
    'status missing': jsonEncode(_without('status')),
    'registered without refreshToken': jsonEncode(_without('refreshToken')),
    'refreshToken empty': jsonEncode(_with('refreshToken', '')),
    'refreshToken a number': jsonEncode(_with('refreshToken', 12345)),
    'refreshToken an object': jsonEncode(
      _with('refreshToken', <String, Object?>{'t': 'x'}),
    ),
    'token without tokenCreatedAt': jsonEncode(_without('tokenCreatedAt')),
    'token without tokenExpiresIn': jsonEncode(_without('tokenExpiresIn')),
    'tokenCreatedAt without token': jsonEncode(_without('token')),
    'token a number': jsonEncode(_with('token', 1)),
    'token empty': jsonEncode(_with('token', '')),
    'tokenCreatedAt a word': jsonEncode(_with('tokenCreatedAt', 'abc')),
    'tokenExpiresIn a list': jsonEncode(_with('tokenExpiresIn', <int>[1])),
    'registering without registrationStartedAt': jsonEncode(<String, Object?>{
      'v': 1,
      'fid': fisSecServerFid,
      'status': 'registering',
    }),
    'truncated in the middle': base.substring(0, base.length ~/ 2),
    'truncated by one character': base.substring(0, base.length - 1),
    'trailing garbage': '${base}x',
    'two records': '$base$base',
    'oversized (64 KiB + 1)': fisSecPaddedJson(
      _base(),
      installationRecordCap + 1,
    ),
    'NUL characters': '\u0000\u0000\u0000',
    'deeply nested lists': '${'[' * 30000}${']' * 30000}',
    'deeply nested objects, unterminated': '{"a":' * 10000,
  };

  group('5.10 corrupt records in a MemoryKeyValueStore', () {
    for (final MapEntry<String, String> entry in corrupt.entries) {
      test(
        '5.10: a record that is ${entry.key} is absent, nothing throws, the next write repairs it',
        () async {
          final FirebaseApp app = fisSecApp();
          final MemoryKeyValueStore store = MemoryKeyValueStore();
          await store.write(fisSecRecordKey(app), entry.value);
          final FisSecClient client = FisSecClient(fisSecHappyHandler());
          final FisSecLog log = FisSecLog();
          final FirebaseInstallations installations = fisSecInstallations(
            app,
            store: store,
            client: client,
            logger: log.call,
          );

          expect(await installations.getId(), fisSecFid);
          expect(await installations.getToken(), fisSecAuthToken);
          final InstallationRecord? repaired = InstallationRecord.tryParse(
            await store.read(fisSecRecordKey(app)),
          );
          expect(repaired, isNotNull);
          expect(repaired!.fid, fisSecFid);
          expect(repaired.status, InstallationStatus.registered);
          for (final FisSecRequest request in client.requests) {
            expect(request.url.pathSegments, isNot(contains(fisSecServerFid)));
          }
          expect(
            log.lines.where(
              (String line) =>
                  line.startsWith('warning:') &&
                  line.contains('could not be read'),
            ),
            hasLength(1),
          );
        },
      );
    }

    test(
      '5.10: InstallationRecord.tryParse never throws on any corrupt text',
      () {
        for (final MapEntry<String, String> entry in corrupt.entries) {
          expect(
            () => InstallationRecord.tryParse(entry.value),
            returnsNormally,
            reason: entry.key,
          );
          expect(
            InstallationRecord.tryParse(entry.value),
            isNull,
            reason: entry.key,
          );
        }
        expect(
          InstallationRecord.tryParse(base)?.fid,
          fisSecServerFid,
          reason: 'the base record itself is valid',
        );
      },
    );

    test(
      '5.10: delete with a corrupt record sends nothing and does not throw',
      () async {
        final FirebaseApp app = fisSecApp();
        final MemoryKeyValueStore store = MemoryKeyValueStore();
        await store.write(fisSecRecordKey(app), '{');
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          app,
          store: store,
          client: client,
        );
        await installations.delete();
        expect(client.requests, isEmpty);
      },
    );

    test(
      '5.10: getToken(forceRefresh) and getIdAndToken with a corrupt record register a new FID',
      () async {
        final FirebaseApp app = fisSecApp();
        final MemoryKeyValueStore store = MemoryKeyValueStore();
        await store.write(fisSecRecordKey(app), '[]');
        final FirebaseInstallations installations = fisSecInstallations(
          app,
          store: store,
          client: FisSecClient(fisSecHappyHandler()),
        );
        expect(
          await installations.getToken(forceRefresh: true),
          fisSecAuthToken,
        );
        expect(await installations.getIdAndToken(), (
          id: fisSecFid,
          token: fisSecAuthToken,
        ));
      },
    );

    test(
      '5.10: a record corrupted after registration gives a new FID at the next call',
      () async {
        final FirebaseApp app = fisSecApp();
        final MemoryKeyValueStore store = MemoryKeyValueStore();
        int creates = 0;
        final FisSecClient client = FisSecClient((FisSecRequest r) {
          if (r.route == 'create') {
            creates++;
            return fisSecCreateOk(fid: creates == 1 ? fisSecServerFid : null);
          }
          return fisSecHappyHandler()(r);
        });
        final FirebaseInstallations installations = fisSecInstallations(
          app,
          store: store,
          client: client,
        );
        final List<String> ids = <String>[];
        final StreamSubscription<String> subscription = installations.onIdChange
            .listen(ids.add);
        addTearDown(subscription.cancel);

        await installations.getToken();
        expect(await installations.getId(), fisSecServerFid);
        await store.write(fisSecRecordKey(app), '{"v":1,"fid":');
        expect(await installations.getId(), fisSecFid);
        expect(await installations.getToken(), fisSecAuthToken);
        expect(creates, 2);
        await pumpEventQueue();
        expect(ids, <String>[fisSecFid, fisSecServerFid, fisSecFid]);
      },
    );
  });

  group('5.10 corrupt files in a FileKeyValueStore', () {
    final Map<String, List<int>> files = <String, List<int>>{
      'bytes 0xFF': <int>[0xFF, 0xFE, 0xFF, 0xFF],
      'a record with an invalid UTF-8 byte': <int>[
        ...utf8.encode(base.substring(0, 20)),
        0xC3,
        0x28,
        ...utf8.encode(base.substring(20)),
      ],
      'a zero-length file': <int>[],
      'NUL bytes': List<int>.filled(64, 0),
      'a truncated record': utf8.encode(base.substring(0, base.length - 3)),
      'a record over 64 KiB': utf8.encode(
        fisSecPaddedJson(_base(), installationRecordCap + 100),
      ),
      'an unknown version': utf8.encode(jsonEncode(_with('v', 99))),
    };
    for (final MapEntry<String, List<int>> entry in files.entries) {
      test(
        '5.10: a record file holding ${entry.key} is absent and the next write repairs it',
        () async {
          final Directory dir = fisSecTempDir();
          final FirebaseApp app = fisSecApp();
          final File file = fisSecStoreFile(dir, fisSecRecordKey(app));
          file.writeAsBytesSync(entry.value);
          final FileKeyValueStore store = FileKeyValueStore(dir.path);
          addTearDown(store.close);
          final FirebaseInstallations installations = fisSecInstallations(
            app,
            store: store,
            client: FisSecClient(fisSecHappyHandler()),
          );

          expect(await installations.getId(), fisSecFid);
          expect(await installations.getToken(), fisSecAuthToken);
          final InstallationRecord? repaired = InstallationRecord.tryParse(
            utf8.decode(file.readAsBytesSync()),
          );
          expect(repaired?.fid, fisSecFid);
          expect(repaired?.status, InstallationStatus.registered);
        },
      );
    }
  });
}
