// Spec v4 5.11 rules 1-5 for Installations: origins, where the refresh token goes, URL building from
// validated parts, the allowed extra headers, and refused redirects.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/src/http_rules.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:test/test.dart';

import '../support/fis_sec_io.dart';
import '../support/fis_sec_support.dart';

void main() {
  group('5.11 rule 1 origins', () {
    const Map<String, String> accepted = <String, String>{
      'https://example.com': 'https://example.com',
      'https://EXAMPLE.com': 'https://example.com',
      'HTTPS://example.com': 'https://example.com',
      'https://example.com:8443': 'https://example.com:8443',
      'https://example.com/': 'https://example.com',
      'http://localhost': 'http://localhost',
      'http://localhost:9099': 'http://localhost:9099',
      'http://127.0.0.1': 'http://127.0.0.1',
      'http://127.0.0.1:8080': 'http://127.0.0.1:8080',
      'http://127.255.10.3:1': 'http://127.255.10.3:1',
      'http://[::1]:9000': 'http://[::1]:9000',
    };
    for (final MapEntry<String, String> entry in accepted.entries) {
      test('5.11 rule 1: ${entry.key} is accepted as ${entry.value}', () {
        expect(checkOrigin(Uri.parse(entry.key)), Uri.parse(entry.value));
      });
    }

    const List<String> refused = <String>[
      'http://example.com',
      'http://10.0.0.1',
      'http://192.168.1.1:8080',
      'http://128.0.0.1',
      'http://127.0.0.256',
      'http://127.0.0',
      'http://127.0.0.1.evil.example',
      'http://localhost.evil.example',
      'http://[::2]',
      'ws://localhost',
      'ftp://example.com',
      'file:///tmp/x',
      'https://user@example.com',
      'https://user:pass@example.com',
      'https://example.com/v1',
      'https://example.com/path/',
      'https://example.com?key=1',
      'https://example.com#fragment',
      'https://',
      'example.com',
      '//example.com',
    ];
    for (final String origin in refused) {
      test('5.11 rule 1: $origin is refused with ArgumentError', () {
        expect(() => checkOrigin(Uri.parse(origin)), throwsArgumentError);
      });

      test(
        '5.11 rule 1: the constructor refuses $origin and sends nothing',
        () {
          final FisSecClient client = FisSecClient(fisSecHappyHandler());
          expect(
            () => FirebaseInstallations(
              fisSecApp(),
              store: MemoryKeyValueStore(),
              httpClient: client,
              serverOrigin: Uri.parse(origin),
            ),
            throwsArgumentError,
          );
          expect(client.requests, isEmpty);
        },
      );
    }

    test(
      '5.11 rule 1: the default origin is https://firebaseinstallations.googleapis.com',
      () async {
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = FirebaseInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          httpClient: client,
          randomBytes: fisSecZeroBytes,
        );
        addTearDown(installations.close);
        await installations.getToken();
        expect(client.requests, isNotEmpty);
        for (final FisSecRequest request in client.requests) {
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'firebaseinstallations.googleapis.com');
          expect(request.url.hasPort && request.url.port != 443, isFalse);
        }
      },
    );

    test(
      '5.11 rule 1: the client appends /v1/projects/<id>/installations to the origin only',
      () async {
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
          serverOrigin: Uri.parse('https://fis.test.example:8443/'),
        );
        await installations.getToken();
        await installations.getToken(forceRefresh: true);
        await installations.delete();
        expect(client.requests.map((FisSecRequest r) => r.route), <String>[
          'create',
          'generate',
          'delete',
        ]);
        for (final FisSecRequest request in client.requests) {
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'fis.test.example');
          expect(request.url.port, 8443);
          expect(request.url.hasQuery, isFalse);
          expect(request.url.hasFragment, isFalse);
          expect(request.url.userInfo, isEmpty);
          expect(request.url.pathSegments.take(4), <String>[
            'v1',
            'projects',
            fisSecProjectId,
            'installations',
          ]);
          expect(request.url.path, isNot(contains('//')));
        }
        expect(client.of('generate').single.url.pathSegments, <String>[
          'v1',
          'projects',
          fisSecProjectId,
          'installations',
          fisSecFid,
          'authTokens:generate',
        ]);
        expect(client.of('delete').single.url.pathSegments, <String>[
          'v1',
          'projects',
          fisSecProjectId,
          'installations',
          fisSecFid,
        ]);
      },
    );
  });

  group('5.11 rule 2 refresh token', () {
    test(
      '5.11 rule 2: the refresh token goes only to the FIS origin, only as FIS_v2 Authorization of generate and delete',
      () async {
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await installations.getToken();
        await installations.getToken(forceRefresh: true);
        await installations.delete();

        for (final FisSecRequest request in client.requests) {
          expect(
            request.url.origin,
            fisSecOrigin.origin,
            reason: request.route,
          );
          expect(request.url.toString(), isNot(contains(fisSecRefreshToken)));
          expect(
            request.body,
            isNot(contains(fisSecRefreshToken)),
            reason: request.route,
          );
          final List<String> carrying = request.headers.entries
              .where(
                (MapEntry<String, String> e) =>
                    e.value.contains(fisSecRefreshToken),
              )
              .map((MapEntry<String, String> e) => e.key.toLowerCase())
              .toList();
          if (request.route == 'create') {
            expect(carrying, isEmpty);
            expect(
              request.headers.keys.map((String k) => k.toLowerCase()),
              isNot(contains('authorization')),
            );
          } else {
            expect(carrying, <String>['authorization'], reason: request.route);
            expect(
              request.headers.entries
                  .firstWhere(
                    (MapEntry<String, String> e) =>
                        e.key.toLowerCase() == 'authorization',
                  )
                  .value,
              'FIS_v2 $fisSecRefreshToken',
            );
          }
        }
      },
    );

    test(
      '5.11 rule 2: the auth token is never sent back to the server',
      () async {
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await installations.getToken();
        await installations.getToken(forceRefresh: true);
        await installations.delete();
        for (final FisSecRequest request in client.requests) {
          expect(
            request.allText,
            isNot(contains(fisSecAuthToken)),
            reason: request.route,
          );
        }
      },
    );

    test(
      '5.11 rule 2: after a 401 recovery the old and new refresh tokens go only to the FIS origin',
      () async {
        int generates = 0;
        final FisSecClient client = FisSecClient((FisSecRequest r) {
          switch (r.route) {
            case 'generate':
              generates++;
              return generates == 1
                  ? fisSecError(401, serverStatus: 'UNAUTHENTICATED')
                  : fisSecGenerateOk();
            case 'create':
              return fisSecJson(
                200,
                fisSecCreateJson(refreshToken: '${fisSecRefreshToken}2'),
              );
            default:
              return fisSecJson(200, <String, Object?>{});
          }
        });
        final MemoryKeyValueStore store = MemoryKeyValueStore();
        final FirebaseApp app = fisSecApp();
        await store.write(
          fisSecRecordKey(app),
          fisSecRegisteredRecord(
            fid: fisSecServerFid,
            tokenCreatedAt: fisSecNow.subtract(const Duration(days: 30)),
          ),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          app,
          store: store,
          client: client,
        );
        await installations.getToken();
        expect(client.requests.map((FisSecRequest r) => r.route), <String>[
          'generate',
          'create',
          'generate',
        ]);
        for (final FisSecRequest request in client.requests) {
          expect(request.url.origin, fisSecOrigin.origin);
          expect(request.url.toString(), isNot(contains(fisSecRefreshToken)));
          expect(request.body, isNot(contains(fisSecRefreshToken)));
        }
      },
    );
  });

  group('5.11 rule 3 URLs from validated parts', () {
    const Map<String, Object?> badServerFids = <String, Object?>{
      'path traversal': '../../../../../../../x',
      'slash inside': 'cAAAAAAAAAA/AAAAAAAAAA',
      'percent escape': 'cAAAAAAAAAAAAAAAAAA%2F',
      'query mark': 'cAAAAAAAAAAAAAAAAAAAA?',
      '21 characters': 'cAAAAAAAAAAAAAAAAAAAA',
      '23 characters': 'cAAAAAAAAAAAAAAAAAAAAAA',
      'wrong first character': 'gAAAAAAAAAAAAAAAAAAAAA',
      'empty': '',
      'a number': 12345,
      'an object': <String, Object?>{'fid': 'x'},
    };
    for (final MapEntry<String, Object?> entry in badServerFids.entries) {
      test(
        '5.11 rule 3: a server FID that fails the pattern (${entry.key}) is invalid-response and never reaches a URL',
        () async {
          final Map<String, Object?> body = fisSecCreateJson()
            ..['fid'] = entry.value;
          bool bad = true;
          final FisSecClient client = FisSecClient((FisSecRequest r) {
            if (r.route == 'create') {
              return bad ? fisSecJson(200, body) : fisSecCreateOk();
            }
            return fisSecHappyHandler()(r);
          });
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
          final InstallationRecord? record = InstallationRecord.tryParse(
            await store.read(fisSecRecordKey(app)),
          );
          expect(record?.status, isNot(InstallationStatus.registered));
          expect(record?.refreshToken, isNull);

          bad = false;
          await installations.getToken(forceRefresh: true);
          await installations.delete();
          for (final FisSecRequest request in client.requests) {
            expect(request.url.pathSegments, isNot(contains(entry.value)));
            expect(request.url.path, isNot(contains('..')));
          }
          expect(client.of('generate').single.url.pathSegments[4], fisSecFid);
        },
      );
    }

    const String storedRefreshToken = 'refresh-of-the-rejected-record';
    const List<String> badStoredFids = <String>[
      'cAAAAAAAAAAAAAAAAAAA..',
      'cAAAAAAAAA/../AAAAAAAA',
      '../../../../../../../.',
      'cAAAAAAAAAAAAAAAAAAA%2',
      'gAAAAAAAAAAAAAAAAAAAAA',
    ];
    for (final String fid in badStoredFids) {
      test(
        '5.11 rule 3: a stored FID that fails the pattern ($fid) makes the record absent',
        () async {
          final MemoryKeyValueStore store = MemoryKeyValueStore();
          final FirebaseApp app = fisSecApp();
          final Map<String, Object?> json = fisSecRegisteredJson()
            ..['fid'] = fid
            ..['refreshToken'] = storedRefreshToken;
          await store.write(fisSecRecordKey(app), jsonEncode(json));
          final FisSecClient client = FisSecClient(fisSecHappyHandler());
          final FirebaseInstallations installations = fisSecInstallations(
            app,
            store: store,
            client: client,
          );

          expect(await installations.getId(), fisSecFid);
          await installations.getToken(forceRefresh: true);
          await installations.delete();
          expect(client.requests, isNotEmpty);
          for (final FisSecRequest request in client.requests) {
            expect(request.url.pathSegments, isNot(contains(fid)));
            expect(request.url.path, isNot(contains('..')));
            // The refresh token of the rejected record is never sent.
            expect(request.allText, isNot(contains(storedRefreshToken)));
          }
          for (final FisSecRequest request in client.of('generate')) {
            expect(request.url.pathSegments[4], fisSecFid);
          }
        },
      );
    }

    test(
      '5.11 rule 3: a project id with dots and colons stays one path segment',
      () async {
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(projectId: 'demo.fis:sec-1'),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await installations.getToken();
        expect(client.requests.single.url.pathSegments, <String>[
          'v1',
          'projects',
          'demo.fis:sec-1',
          'installations',
        ]);
      },
    );

    const List<String?> badProjectIds = <String?>[
      null,
      '',
      'demo/../other',
      'demo?x=1',
      'demo#x',
      'demo x',
      '.demo',
      '-demo',
      'demo%2Fother',
    ];
    for (final String? projectId in badProjectIds) {
      test(
        '5.3 / 5.11 rule 3: project id ${projectId == null ? 'null' : '"$projectId"'} is invalid-app-config',
        () {
          final FisSecClient client = FisSecClient(fisSecHappyHandler());
          expect(
            () => FirebaseInstallations(
              fisSecApp(projectId: projectId),
              store: MemoryKeyValueStore(),
              httpClient: client,
            ),
            throwsA(isFisCode('invalid-app-config')),
          );
          expect(client.requests, isEmpty);
        },
      );
    }

    test(
      '5.3 / 5.11 rule 3: a project id of 129 characters is invalid-app-config',
      () {
        expect(
          () => FirebaseInstallations(
            fisSecApp(projectId: 'a' * 129),
            store: MemoryKeyValueStore(),
            httpClient: FisSecClient(fisSecHappyHandler()),
          ),
          throwsA(isFisCode('invalid-app-config')),
        );
      },
    );
  });

  group('5.11 rule 4 headers', () {
    const Map<String, String> allowed = <String, String>{
      'X-Android-Package': 'com.example.app',
      'x-android-cert': 'ABCDEF0123456789',
      'X-IOS-BUNDLE-IDENTIFIER': 'com.example.ios',
    };

    test(
      '5.11 rule 4: the three allowed headers (any case) are sent on create, generate and delete',
      () async {
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
          headers: allowed,
        );
        await installations.getToken();
        await installations.getToken(forceRefresh: true);
        await installations.delete();
        expect(client.requests, hasLength(3));
        for (final FisSecRequest request in client.requests) {
          final Map<String, String> lower = <String, String>{
            for (final MapEntry<String, String> e in request.headers.entries)
              e.key.toLowerCase(): e.value,
          };
          for (final MapEntry<String, String> entry in allowed.entries) {
            expect(
              lower[entry.key.toLowerCase()],
              entry.value,
              reason: '${request.route} ${entry.key}',
            );
          }
          expect(lower['x-goog-api-key'], fisSecApiKey);
        }
      },
    );

    const List<String> refusedNames = <String>[
      'Authorization',
      'authorization',
      'x-goog-api-key',
      'X-Goog-Api-Key',
      'Content-Type',
      'Accept',
      'Accept-Encoding',
      'Host',
      'Cookie',
      'X-Firebase-Client',
      'X-Goog-Firebase-Installations-Auth',
      'x-android-package ',
      ' x-android-package',
      'x-android-package\r\nX-Evil',
      '',
    ];
    for (final String name in refusedNames) {
      test(
        '5.11 rule 4: header name "${name.replaceAll('\r', r'\r').replaceAll('\n', r'\n')}" is refused with ArgumentError',
        () {
          final FisSecClient client = FisSecClient(fisSecHappyHandler());
          expect(
            () => FirebaseInstallations(
              fisSecApp(),
              store: MemoryKeyValueStore(),
              httpClient: client,
              headers: <String, String>{name: 'value'},
            ),
            throwsArgumentError,
          );
          expect(client.requests, isEmpty);
        },
      );
    }

    const Map<String, String> refusedValues = <String, String>{
      'CR': 'com.example\rX-Evil: 1',
      'LF': 'com.example\nX-Evil: 1',
      'CRLF': 'com.example\r\nX-Evil: 1',
      'NUL': 'com.example\u0000',
    };
    for (final MapEntry<String, String> entry in refusedValues.entries) {
      test(
        '5.11 rule 4: a header value with ${entry.key} is refused with ArgumentError',
        () {
          expect(
            () => FirebaseInstallations(
              fisSecApp(),
              store: MemoryKeyValueStore(),
              httpClient: FisSecClient(fisSecHappyHandler()),
              headers: <String, String>{'X-Android-Package': entry.value},
            ),
            throwsArgumentError,
          );
        },
      );
    }

    test(
      '5.11 rule 4: headers is unmodifiable and a later change of the caller map is not sent',
      () async {
        final Map<String, String> given = <String, String>{
          'X-Android-Package': 'com.example.app',
        };
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
          headers: given,
        );
        expect(
          () => installations.headers['Authorization'] = 'x',
          throwsUnsupportedError,
        );
        given['Authorization'] = 'Bearer injected';
        await installations.getToken();
        for (final FisSecRequest request in client.requests) {
          expect(request.allText, isNot(contains('injected')));
        }
      },
    );
  });

  group('5.11 rule 5 redirects', () {
    test('5.11 rule 5: every request sets followRedirects to false', () async {
      final FisSecClient client = FisSecClient(fisSecHappyHandler());
      final FirebaseInstallations installations = fisSecInstallations(
        fisSecApp(),
        store: MemoryKeyValueStore(),
        client: client,
      );
      await installations.getToken();
      await installations.getToken(forceRefresh: true);
      await installations.delete();
      expect(client.requests, hasLength(3));
      for (final FisSecRequest request in client.requests) {
        expect(request.followRedirects, isFalse, reason: request.route);
      }
    });

    for (final int status in <int>[300, 301, 302, 303, 307, 308]) {
      test(
        '5.11 rule 5: create answered $status is invalid-response, not followed',
        () async {
          final FisSecClient client = FisSecClient(
            (FisSecRequest r) => fisSecText(
              status,
              '',
              headers: <String, String>{
                'location': 'https://evil.example/v1/projects/x/installations',
              },
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
          expect(error, isFisCode('invalid-response'));
          expect(error.httpStatus, status);
          expect(client.requests, hasLength(1));
          expect(
            client.requests.every(
              (FisSecRequest r) => r.url.host == fisSecOrigin.host,
            ),
            isTrue,
          );
        },
      );
    }

    test(
      '5.11 rule 5: generate answered 302 is invalid-response, not followed',
      () async {
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => r.route == 'generate'
              ? fisSecText(
                  302,
                  '',
                  headers: <String, String>{
                    'location': 'https://evil.example/',
                  },
                )
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
        expect(
          client.requests.every(
            (FisSecRequest r) => r.url.host == fisSecOrigin.host,
          ),
          isTrue,
        );
        expect(client.of('generate'), hasLength(1));
      },
    );

    test(
      '5.11 rule 5: delete answered 307 is invalid-response, not followed',
      () async {
        final FisSecClient client = FisSecClient(
          (FisSecRequest r) => r.route == 'delete'
              ? fisSecText(
                  307,
                  '',
                  headers: <String, String>{
                    'location': 'https://evil.example/',
                  },
                )
              : fisSecHappyHandler()(r),
        );
        final FirebaseInstallations installations = fisSecInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          client: client,
        );
        await installations.getToken();
        await expectLater(
          installations.delete(),
          throwsFisCode('invalid-response'),
        );
        expect(client.of('delete'), hasLength(1));
      },
    );

    test(
      '5.11 rule 5: a real 302 from a loopback server is not followed by the default client',
      () async {
        final FisSecServer server = await FisSecServer.start((
          HttpRequest request,
        ) async {
          if (request.uri.path.startsWith('/elsewhere')) {
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(
                '{"name":"x","refreshToken":"r","authToken":{"token":"t","expiresIn":"604800s"}}',
              );
          } else {
            request.response
              ..statusCode = 302
              ..headers.set(
                'location',
                '/elsewhere/v1/projects/x/installations',
              );
          }
          await request.response.close();
        });
        final FirebaseInstallations installations = FirebaseInstallations(
          fisSecApp(),
          store: MemoryKeyValueStore(),
          serverOrigin: server.origin,
          randomBytes: fisSecZeroBytes,
          delay: (Duration _) async {},
        );
        addTearDown(installations.close);
        await expectLater(
          installations.getToken(),
          throwsFisCode('invalid-response'),
        );
        expect(server.paths, hasLength(1));
        expect(
          server.paths.single,
          startsWith('/v1/projects/$fisSecProjectId/installations'),
        );
      },
    );
  });
}
