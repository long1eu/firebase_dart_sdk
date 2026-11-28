// Spec v4 5.11 rule 7 for Installations: success bodies stop at 64 KiB, error bodies at 16 KiB, counted
// on the bytes package:http delivers (after dart:io removed gzip); server text kept at most 1 KiB.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:test/test.dart';

import '../support/fis_sec_io.dart';
import '../support/fis_sec_support.dart';

const int _successCap = 64 * 1024;
const int _errorCap = 16 * 1024;

void main() {
  /// The chunks a capped reader may take from an endless body: the cap, plus the chunk that crosses it,
  /// plus one in flight.
  int maxChunks(int cap, FisSecEndless body) => cap ~/ body.chunkSize + 3;

  group('5.11 rule 7 success bodies (64 KiB)', () {
    test(
      '5.11 rule 7: an endless 2xx create body stops at the cap, aborts and is invalid-response',
      () async {
        final FisSecEndless body = FisSecEndless();
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => body.response(200),
        );
        final MemoryKeyValueStore store = MemoryKeyValueStore();
        final FirebaseApp app = fisSecApp();
        final FirebaseInstallations installations = fisSecInstallations(
          app,
          store: store,
          client: client,
        );

        await expectLater(
          installations.getToken(),
          throwsFisCode('invalid-response'),
        );
        expect(body.pulled, lessThanOrEqualTo(maxChunks(_successCap, body)));
        expect(body.bytes, greaterThan(_successCap));
        expect(client.requests.single.aborted, isTrue);
        expect(
          client.requests,
          hasLength(1),
          reason: 'a body over the cap is not retried',
        );
        final InstallationRecord? record = InstallationRecord.tryParse(
          await store.read(fisSecRecordKey(app)),
        );
        expect(
          record?.refreshToken,
          isNull,
          reason: 'nothing is stored from a body over the cap',
        );
      },
    );

    test(
      '5.11 rule 7: an endless 2xx generate body stops at the cap and is invalid-response',
      () async {
        final FisSecEndless body = FisSecEndless(chunkSize: 4096);
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => r.route == 'generate'
              ? body.response(200)
              : fisSecHappyHandler()(r),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await installations.getToken();
        await expectLater(
          installations.getToken(forceRefresh: true),
          throwsFisCode('invalid-response'),
        );
        expect(body.pulled, lessThanOrEqualTo(maxChunks(_successCap, body)));
        expect(client.of('generate').single.aborted, isTrue);
      },
    );

    test('5.11 rule 7: a create body of exactly 64 KiB is read', () async {
      final FisSecClient client = FisSecClient(
        (FisSecRequest r) =>
            fisSecText(200, fisSecPaddedJson(fisSecCreateJson(), _successCap)),
      );
      final FirebaseInstallations installations = fisSecInstallations(
        fisSecApp(),
        store: MemoryKeyValueStore(),
        client: client,
      );
      expect(await installations.getToken(), fisSecAuthToken);
    });

    test(
      '5.11 rule 7: a create body of 64 KiB + 1 byte is invalid-response',
      () async {
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => fisSecText(
            200,
            fisSecPaddedJson(fisSecCreateJson(), _successCap + 1),
          ),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await expectLater(
          installations.getToken(),
          throwsFisCode('invalid-response'),
        );
      },
    );

    test(
      '5.11 rule 7: a generate body of exactly 64 KiB is read, 64 KiB + 1 is invalid-response',
      () async {
        int length = _successCap;
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => r.route == 'generate'
              ? fisSecText(
                  200,
                  fisSecPaddedJson(<String, Object?>{
                    'token': '${fisSecAuthToken}2',
                    'expiresIn': '604800s',
                  }, length),
                )
              : fisSecHappyHandler()(r),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await installations.getToken();
        expect(
          await installations.getToken(forceRefresh: true),
          '${fisSecAuthToken}2',
        );
        length = _successCap + 1;
        await expectLater(
          installations.getToken(forceRefresh: true),
          throwsFisCode('invalid-response'),
        );
      },
    );

    test(
      '5.11 rule 7: a 64 KiB + 1 body sent as many small chunks is still refused',
      () async {
        final List<int> bytes = utf8.encode(
          fisSecPaddedJson(fisSecCreateJson(), _successCap + 1),
        );
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => fisSecChunked(200, bytes, chunkSize: 7),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await expectLater(
          installations.getToken(),
          throwsFisCode('invalid-response'),
        );
      },
    );
  });

  group('5.11 rule 7 error bodies (16 KiB)', () {
    const Map<int, String> codes = <int, String>{
      400: 'bad-config',
      403: 'bad-config',
      429: 'too-many-requests',
      500: 'unavailable',
      503: 'unavailable',
    };
    for (final MapEntry<int, String> entry in codes.entries) {
      test(
        '5.11 rule 7: an endless ${entry.key} create body is cut at 16 KiB and keeps its status (${entry.value})',
        () async {
          final List<FisSecEndless> bodies = <FisSecEndless>[];
          final FisSecClient client = FisSecClient((FisSecRequest r) {
            final FisSecEndless body = FisSecEndless();
            bodies.add(body);
            return body.response(entry.key);
          });
          final FirebaseInstallations installations = fisSecInstallations(
            fisSecApp(),
            store: MemoryKeyValueStore(),
            client: client,
          );
          final FirebaseInstallationsException error = await fisSecFailure(
            installations.getToken,
          );
          expect(error, isFisCode(entry.value));
          expect(error.httpStatus, entry.key);
          expect(bodies, hasLength(entry.key >= 500 ? 2 : 1));
          for (final FisSecEndless body in bodies) {
            expect(body.pulled, lessThanOrEqualTo(maxChunks(_errorCap, body)));
          }
          for (final FisSecRequest request in client.requests) {
            expect(request.aborted, isTrue);
          }
        },
      );
    }

    test(
      '5.11 rule 7: an endless 500 delete body is cut at 16 KiB and is unavailable after the retry',
      () async {
        final List<FisSecEndless> bodies = <FisSecEndless>[];
        final FisSecClient client = FisSecClient((FisSecRequest r) {
          if (r.route != 'delete') {
            return fisSecHappyHandler()(r);
          }
          final FisSecEndless body = FisSecEndless();
          bodies.add(body);
          return body.response(500);
        });
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await installations.getToken();
        await expectLater(installations.delete(), throwsFisCode('unavailable'));
        expect(bodies, hasLength(2));
        for (final FisSecEndless body in bodies) {
          expect(body.pulled, lessThanOrEqualTo(maxChunks(_errorCap, body)));
        }
      },
    );

    test(
      '5.11 rule 7: a JSON error body of exactly 16 KiB is parsed',
      () async {
        final Map<String, Object?> json = <String, Object?>{
          'error': <String, Object?>{
            'code': 400,
            'status': 'INVALID_ARGUMENT',
            'message': 'API key not valid.',
          },
        };
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) =>
              fisSecText(400, fisSecPaddedJson(json, _errorCap)),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        final FirebaseInstallationsException error = await fisSecFailure(
          installations.getToken,
        );
        expect(error, isFisCode('bad-config'));
        expect(error.serverStatus, 'INVALID_ARGUMENT');
        expect(error.serverMessage, 'API key not valid.');
      },
    );

    test(
      '5.11 rule 7: a JSON error body over 16 KiB keeps only the status',
      () async {
        final Map<String, Object?> json = <String, Object?>{
          'error': <String, Object?>{
            'code': 400,
            'status': 'INVALID_ARGUMENT',
            'message': 'x' * (_errorCap + 10),
          },
        };
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => fisSecJson(400, json),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        final FirebaseInstallationsException error = await fisSecFailure(
          installations.getToken,
        );
        expect(error, isFisCode('bad-config'));
        expect(error.httpStatus, 400);
        expect(error.serverMessage, isNull);
      },
    );
  });

  group('5.11 rule 6 server text at most 1 KiB, no control characters', () {
    test(
      '5.11 rule 6: a long server message with control characters is sanitized and cut',
      () async {
        final String message =
            'bad\u0000key\r\n\u0007\u001b[31m\u007f\u0085${'é' * 2000}';
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => fisSecError(
            403,
            serverStatus: 'PERMISSION\nDENIED',
            message: message,
          ),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        final FirebaseInstallationsException error = await fisSecFailure(
          installations.getToken,
        );
        expect(error, isFisCode('bad-config'));
        final FirebaseInstallationsException exception = error;
        final String serverMessage = exception.serverMessage!;
        expect(utf8.encode(serverMessage).length, lessThanOrEqualTo(1024));
        expect(serverMessage, startsWith('badkey[31m'));
        expect(
          serverMessage.runes.where(
            (int r) => r < 0x20 || (r >= 0x7f && r <= 0x9f),
          ),
          isEmpty,
        );
        expect(exception.serverStatus, 'PERMISSIONDENIED');
        expect(exception.toString().runes.where((int r) => r < 0x20), isEmpty);
      },
    );

    test(
      '5.11 rule 6: a server message of a non-string type is dropped',
      () async {
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => fisSecJson(400, <String, Object?>{
            'error': <String, Object?>{
              'code': 400,
              'status': <String>['x'],
              'message': <String, Object?>{'a': 1},
            },
          }),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        final FirebaseInstallationsException error = await fisSecFailure(
          installations.getToken,
        );
        expect(error, isFisCode('bad-config'));
        expect(error.serverMessage, isNull);
        expect(error.serverStatus, isNull);
      },
    );

    test(
      '5.3: an error body {"error": "<string>"} becomes serverMessage, sanitized',
      () async {
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => fisSecJson(400, <String, Object?>{
            'error': 'invalid_grant\n${'z' * 3000}',
          }),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        final FirebaseInstallationsException error = await fisSecFailure(
          installations.getToken,
        );
        final String serverMessage = error.serverMessage!;
        expect(serverMessage, startsWith('invalid_grantzzz'));
        expect(serverMessage.length, 1024);
      },
    );
  });

  group('5.11 rule 7 gzip through a loopback HttpServer', () {
    Future<FirebaseInstallations> installationsFor(FisSecServer server) async {
      final FirebaseInstallations installations = FirebaseInstallations(
        fisSecApp(),
        store: MemoryKeyValueStore(),
        serverOrigin: server.origin,
        randomBytes: fisSecZeroBytes,
        delay: (Duration _) async {},
      );
      addTearDown(installations.close);
      return installations;
    }

    Future<void> Function(HttpRequest request) gzipAnswer(
      int status,
      List<int> compressed,
    ) => (HttpRequest request) async {
      request.response
        ..statusCode = status
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/json')
        ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
        ..add(compressed);
      await request.response.close();
    };

    late List<int> bomb;

    setUpAll(() {
      final Uint8List spaces = Uint8List(32 * 1024 * 1024)
        ..fillRange(0, 32 * 1024 * 1024, 0x20);
      bomb = gzip.encode(spaces);
    });

    test(
      '5.11 rule 7: a 2xx gzip bomb (32 MiB inflated) stops at the cap and is invalid-response',
      () async {
        expect(
          bomb.length,
          lessThan(_successCap),
          reason: 'the compressed bomb fits under the cap',
        );
        final FisSecServer server = await FisSecServer.start(
          gzipAnswer(200, bomb),
        );
        final FirebaseInstallations installations = await installationsFor(
          server,
        );
        await expectLater(
          installations.getToken(),
          throwsFisCode('invalid-response'),
        );
        expect(server.paths, hasLength(1));
      },
    );

    test(
      '5.11 rule 7: a 400 gzip bomb is cut at 16 KiB and stays bad-config',
      () async {
        final FisSecServer server = await FisSecServer.start(
          gzipAnswer(400, bomb),
        );
        final FirebaseInstallations installations = await installationsFor(
          server,
        );
        final FirebaseInstallationsException error = await fisSecFailure(
          installations.getToken,
        );
        expect(error, isFisCode('bad-config'));
        expect(error.httpStatus, 400);
      },
    );

    test(
      '5.11 rule 7: the cap counts inflated bytes: 70 KiB of JSON gzipped small is refused',
      () async {
        final List<int> compressed = gzip.encode(
          utf8.encode(fisSecPaddedJson(fisSecCreateJson(), 70 * 1024)),
        );
        expect(compressed.length, lessThan(_successCap));
        final FisSecServer server = await FisSecServer.start(
          gzipAnswer(200, compressed),
        );
        final FirebaseInstallations installations = await installationsFor(
          server,
        );
        await expectLater(
          installations.getToken(),
          throwsFisCode('invalid-response'),
        );
      },
    );

    test('5.11 rule 7: a gzipped create body under the cap is read', () async {
      final List<int> compressed = gzip.encode(
        utf8.encode(jsonEncode(fisSecCreateJson())),
      );
      final FisSecServer server = await FisSecServer.start(
        gzipAnswer(200, compressed),
      );
      final FirebaseInstallations installations = await installationsFor(
        server,
      );
      expect(await installations.getToken(), fisSecAuthToken);
    });
  });
}
