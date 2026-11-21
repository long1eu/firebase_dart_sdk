// Threat model: storage_threat_model.md, "Hosts, schemes and redirects" (T3, T4, T5, T6, T7).
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
// ignore: implementation_imports, the token-scope tests drive the internal request layer.
import 'package:firebase_storage_dart/src/request/requester.dart';
import 'package:test/test.dart';

import 'security_support.dart';

void main() {
  late RecordingClient client;

  setUp(() {
    client = RecordingClient(
      (SentRequest request) => respondJson(objectResource('x')),
    );
  });

  group('refFromUrl never lets a URL choose the host', () {
    const List<String> foreign = <String>[
      'https://evil.example/v0/b/b/o/x',
      'https://firebasestorage.googleapis.com.evil.example/v0/b/b/o/x',
      'https://firebasestorage.googleapis.com@evil.example/v0/b/b/o/x',
      'https://evil.example/firebasestorage.googleapis.com/v0/b/b/o/x',
      'https://evil.example/https://firebasestorage.googleapis.com/v0/b/b/o/x',
      'https://storage.googleapis.com.evil.example/b/x',
      'ftp://firebasestorage.googleapis.com/v0/b/b/o/x',
      'gs:/b/x',
      ' gs://b/x',
    ];
    for (final String url in foreign) {
      test('"$url" is invalid-url', () {
        final FirebaseStorage storage = securityStorage(securityApp(), client);
        addTearDown(storage.close);
        expect(() => storage.refFromUrl(url), throwsStorageCode('invalid-url'));
      });
    }

    test(
      'an http:// download URL is still fetched over https from the API host',
      () async {
        final FirebaseStorage storage = securityStorage(securityApp(), client);
        addTearDown(storage.close);
        await storage
            .refFromUrl(
              'http://firebasestorage.googleapis.com/v0/b/other/o/x?alt=media&token=t',
            )
            .metadata();
        final Uri url = client.sent.single.url;
        expect(url.scheme, 'https');
        expect(url.host, 'firebasestorage.googleapis.com');
        expect(url.pathSegments, <String>['v0', 'b', 'other', 'o', 'x']);
        expect(
          url.query,
          isEmpty,
          reason: 'the download token of the URL is not reused',
        );
      },
    );

    test(
      'with an emulator, a production URL does not move requests to production',
      () {
        final FirebaseStorage storage = securityStorage(
          securityApp(),
          client,
          emulatorHost: '127.0.0.1:9199',
        );
        addTearDown(storage.close);
        expect(
          () => storage.refFromUrl(
            'https://firebasestorage.googleapis.com/v0/b/b/o/x',
          ),
          throwsStorageCode('invalid-url'),
        );
      },
    );
  });

  group('production requests', () {
    test(
      'go over https to firebasestorage.googleapis.com with the tokens',
      () async {
        final FirebaseStorage storage = securityStorage(securityApp(), client);
        addTearDown(storage.close);
        await storage.ref('x').metadata();
        final SentRequest sent = client.sent.single;
        expect(sent.url.origin, 'https://firebasestorage.googleapis.com');
        expect(sent.headers['Authorization'], 'Firebase $secretIdToken');
        expect(sent.headers['X-Firebase-AppCheck'], secretAppCheckToken);
      },
    );

    test(
      'do not follow redirects (custom token headers survive a cross-origin redirect)',
      () async {
        final FirebaseStorage storage = securityStorage(securityApp(), client);
        addTearDown(storage.close);
        await storage.ref('x').metadata();
        expect(client.sent.single.request.followRedirects, isFalse);
      },
    );

    test('a 3xx answer is an error, not something to follow', () async {
      client = RecordingClient(
        (SentRequest request) => respond(
          302,
          headers: const <String, String>{
            'location': 'https://evil.example/steal',
          },
        ),
      );
      final FirebaseStorage storage = securityStorage(securityApp(), client);
      addTearDown(storage.close);
      await expectLater(
        storage.ref('x').metadata(),
        throwsA(isA<FirebaseStorageException>()),
      );
      expect(
        client.sent.map((SentRequest s) => s.url.host),
        everyElement('firebasestorage.googleapis.com'),
      );
    });
  });

  group('emulator', () {
    test('emulatorHost must be a bare host:port', () {
      for (final String host in <String>[
        'evil.example:80/path',
        'user:pw@127.0.0.1:9199',
        '127.0.0.1',
        'https://127.0.0.1:9199',
        '127.0.0.1:9199?x=1',
        '127.0.0.1:9199#f',
        '127.0.0.1:9199\r\nX-Evil: 1',
      ]) {
        expect(
          () => FirebaseStorage(
            securityApp(),
            emulatorHost: host,
            httpClient: client,
          ),
          throwsArgumentError,
          reason: host,
        );
      }
    });

    test('mockUserToken is refused without an emulator', () {
      expect(
        () => FirebaseStorage(
          securityApp(),
          mockUserToken: 'owner',
          httpClient: client,
        ),
        throwsArgumentError,
      );
    });

    test('the mock token replaces the real ID token', () async {
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        client,
        emulatorHost: '127.0.0.1:9199',
        mockUserToken: 'mock',
      );
      addTearDown(storage.close);
      await storage.ref('x').metadata();
      final String printed = client.sent.single.headers.values.join('\n');
      expect(printed, isNot(contains(secretIdToken)));
    });

    test(
      'the configured emulator gets both tokens over plain http (lead decision, JS behaviour)',
      () async {
        // Not a loopback address: the tokens go there only because it is the configured emulatorHost.
        final FirebaseStorage storage = securityStorage(
          securityApp(),
          client,
          emulatorHost: '10.0.0.5:9199',
        );
        addTearDown(storage.close);
        await storage.ref('x').metadata();
        final SentRequest sent = client.sent.single;
        expect(sent.url.origin, 'http://10.0.0.5:9199');
        expect(sent.headers['Authorization'], 'Firebase $secretIdToken');
        expect(sent.headers['X-Firebase-AppCheck'], secretAppCheckToken);
      },
    );
  });

  group('token scope of the request layer', () {
    // The public API cannot aim a request at another host (refFromUrl keeps the origin, the upload session
    // URL is checked), so this drives the internal request layer directly to pin the rule underneath.
    Future<SentRequest> sendTo(String url, {String? emulatorHost}) async {
      final RecordingClient recording = RecordingClient(
        (SentRequest r) => respond(200),
      );
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        recording,
        emulatorHost: emulatorHost,
      );
      addTearDown(storage.close);
      // ignore: invalid_use_of_internal_member, the rule lives in the internal Requester.
      await storage.requester.send(
        // ignore: invalid_use_of_internal_member, same.
        StorageRequest(
          method: 'GET',
          url: Uri.parse(url),
          timeout: Duration.zero,
          errorMapper: (int status, String body) => FirebaseStorageException(
            code: 'unknown',
            message: 'HTTP $status',
          ),
        ),
      );
      return recording.sent.single;
    }

    bool carriesAnyToken(SentRequest sent) {
      final String headers = sent.headers.entries
          .map((MapEntry<String, String> e) => '${e.key}: ${e.value}')
          .join('\n');
      return sent.headers.keys.any(
            (String k) =>
                k.toLowerCase() == 'authorization' ||
                k.toLowerCase() == 'x-firebase-appcheck',
          ) ||
          headers.contains(secretIdToken) ||
          headers.contains(secretAppCheckToken);
    }

    for (final String url in <String>[
      'http://evil.example/v0/b/b/o/x',
      'http://firebasestorage.googleapis.com/v0/b/b/o/x',
      'http://10.0.0.6:9199/v0/b/b/o/x',
      'http://10.0.0.5:9200/v0/b/b/o/x',
      'http://127.0.0.1.evil.example/v0/b/b/o/x',
      'http://localhost.evil.example/v0/b/b/o/x',
    ]) {
      test('no token of any kind goes to $url', () async {
        expect(
          carriesAnyToken(await sendTo(url, emulatorHost: '10.0.0.5:9199')),
          isFalse,
        );
      });
    }

    for (final String url in <String>[
      'https://firebasestorage.googleapis.com/v0/b/b/o/x',
      'http://10.0.0.5:9199/v0/b/b/o/x',
      'http://127.0.0.1:9199/v0/b/b/o/x',
      'http://localhost:9199/v0/b/b/o/x',
      'http://[::1]:9199/v0/b/b/o/x',
    ]) {
      test(
        'tokens go to $url (https, the configured emulator, loopback)',
        () async {
          expect(
            carriesAnyToken(await sendTo(url, emulatorHost: '10.0.0.5:9199')),
            isTrue,
          );
        },
      );
    }
  });
}
