// Threat model: storage_threat_model.md, "Paths and percent-encoding" (T1, T2).
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:test/test.dart';

import 'security_support.dart';

void main() {
  late RecordingClient client;
  late FirebaseStorage storage;

  setUp(() {
    client = RecordingClient(
      (SentRequest request) => respondJson(objectResource('x')),
    );
    storage = securityStorage(securityApp(), client);
  });

  tearDown(() => storage.close());

  group('object names reach the server as exactly one path segment', () {
    const List<String> names = <String>[
      'a/b',
      'a/../b',
      'a/./b',
      'a%2Fb',
      '%2e%2e',
      'a?b#c',
      'a b+c',
      'x&name=y',
      'ünï/çødé/😀',
      r'a\b',
      'a;b=c',
    ];
    for (final String name in names) {
      test('metadata() of "$name"', () async {
        final Reference ref = storage.ref(name);
        await ref.metadata();
        final Uri url = client.sent.single.url;
        expect(url.scheme, 'https');
        expect(url.host, 'firebasestorage.googleapis.com');
        expect(url.pathSegments, <String>['v0', 'b', 'b', 'o', ref.fullPath]);
      });
    }
  });

  group(
    'dot names cannot step out of /o/ (Uri.parse removes dot segments)',
    () {
      for (final String name in <String>['.', '..']) {
        for (final MapEntry<String, Future<Object?> Function(Reference)> op
            in <String, Future<Object?> Function(Reference)>{
              'metadata': (Reference r) => r.metadata(),
              'delete': (Reference r) => r.delete(),
              'getBytes': (Reference r) => r.getBytes(),
            }.entries) {
          test('${op.key}() of "$name" fails before any request', () async {
            await expectLater(
              op.value(storage.ref(name)),
              throwsA(isA<FirebaseStorageException>()),
            );
            expect(client.sent, isEmpty);
          });
        }
      }

      test('child("..") of a folder is not its parent', () async {
        final Reference ref = storage.ref('users/u1').child('..');
        expect(ref.fullPath, isNot('users'));
        try {
          await ref.metadata();
        } on FirebaseStorageException {
          // Rejecting the name is fine.
        }
        for (final SentRequest sent in client.sent) {
          expect(sent.url.pathSegments.take(4), <String>['v0', 'b', 'b', 'o']);
          expect(sent.url.pathSegments, hasLength(5));
        }
      });
    },
  );

  group('bucket names cannot step out of /b/', () {
    for (final String bucket in <String>['.', '..']) {
      test(
        'refFromUrl("gs://$bucket/x") is rejected or stays in its bucket',
        () async {
          Reference? ref;
          try {
            ref = storage.refFromUrl('gs://$bucket/x');
          } on FirebaseStorageException {
            return;
          } on ArgumentError {
            return;
          }
          try {
            await ref.metadata();
          } on FirebaseStorageException {
            // Rejecting at the operation is fine as long as nothing was sent.
          }
          expect(
            client.sent,
            isEmpty,
            reason: 'sent ${client.sent.map((SentRequest s) => s.url)}',
          );
        },
      );
    }

    test('a "../x" bucket in the constructor is rejected', () {
      expect(
        () => FirebaseStorage(securityApp(), bucket: '..', httpClient: client),
        throwsA(anyOf(isA<ArgumentError>(), isA<FirebaseStorageException>())),
      );
    });
  });

  group('query parameters cannot be smuggled through names or tokens', () {
    test('the upload name is one query value', () async {
      final Reference ref = storage.ref('a&name=evil&uploadType=resumable');
      await ref.putString('x');
      final Uri url = client.sent.single.url;
      expect(url.queryParametersAll['name'], <String>[ref.fullPath]);
      expect(url.queryParametersAll.keys, <String>['name']);
    });

    test('list prefix and page token are single query values', () async {
      await storage
          .ref('a&delimiter=x')
          .list(pageToken: 'p&maxResults=1000000&delimiter=evil');
      final Map<String, List<String>> query =
          client.sent.single.url.queryParametersAll;
      expect(query['delimiter'], <String>['/']);
      expect(query['prefix'], <String>['a&delimiter=x/']);
      expect(query['pageToken'], <String>[
        'p&maxResults=1000000&delimiter=evil',
      ]);
      expect(query.containsKey('maxResults'), isFalse);
    });
  });
}
