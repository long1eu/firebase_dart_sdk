import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../fakes.dart';

// Against the Cloud Storage emulator of tool/start_storage_emulator.sh (buckets demo-test.appspot.com with open
// rules and demo-test-auth.appspot.com with rules that need a user). Run with
// FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:<port>.
void main() {
  final String? host = FirebaseStorage.emulatorHostFromEnvironment;
  final String? skip = host == null
      ? 'Set FIREBASE_STORAGE_EMULATOR_HOST to the Storage emulator (tool/start_storage_emulator.sh).'
      : null;

  late FirebaseApp app;
  late FirebaseStorage storage;
  late Reference dir;

  setUp(() {
    app = newApp(storageBucket: 'demo-test.appspot.com');
    storage = FirebaseStorage(app, emulatorHost: host);
    dir = storage.ref('it-${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  test('putString, metadata, getBytes and delete', () async {
    final Reference ref = dir.child('a b/hello.txt');
    final FullMetadata uploaded = await ref.putString(
      'Hello, wörld',
      metadata: const SettableMetadata(
        contentType: 'text/plain',
        customMetadata: <String, String>{'k': 'v'},
      ),
    );
    expect(uploaded.fullPath, ref.fullPath);
    expect(uploaded.name, 'hello.txt');
    expect(uploaded.bucket, 'demo-test.appspot.com');
    expect(uploaded.size, utf8.encode('Hello, wörld').length);
    expect(uploaded.contentType, 'text/plain');
    expect(uploaded.customMetadata, <String, String>{'k': 'v'});
    expect(uploaded.timeCreated, isNotNull);

    expect(await ref.metadata(), uploaded);
    expect(utf8.decode(await ref.getBytes()), 'Hello, wörld');

    await ref.delete();
    await expectLater(
      ref.metadata(),
      throwsA(
        isA<FirebaseStorageException>()
            .having(
              (FirebaseStorageException e) => e.code,
              'code',
              'object-not-found',
            )
            .having(
              (FirebaseStorageException e) => e.httpStatus,
              'httpStatus',
              404,
            ),
      ),
    );
    await expectLater(ref.delete(), throwsStorageCode('object-not-found'));
  }, skip: skip);

  test('putBytes of binary data and of a data URL', () async {
    final Uint8List bytes = Uint8List.fromList(
      List<int>.generate(1000, (int i) => i % 256),
    );
    final Reference bin = dir.child('bin');
    final FullMetadata metadata = await bin.putBytes(bytes);
    expect(metadata.contentType, 'application/octet-stream');
    expect(await bin.getBytes(), bytes);

    final Reference png = dir.child('pixel');
    final FullMetadata pngMetadata = await png.putString(
      'data:image/png;base64,iVBORw0KGgo=',
      format: StringFormat.dataUrl,
    );
    expect(pngMetadata.contentType, 'image/png');
    expect(await png.getBytes(), base64.decode('iVBORw0KGgo='));
  }, skip: skip);

  test('getBytes with maxSize', () async {
    final Reference ref = dir.child('ten');
    await ref.putString('0123456789');
    expect(utf8.decode(await ref.getBytes(maxSize: 10)), '0123456789');
    expect(utf8.decode(await ref.getBytes(maxSize: 100)), '0123456789');
    await expectLater(
      ref.getBytes(maxSize: 4),
      throwsStorageCode('download-size-exceeded'),
    );
  }, skip: skip);

  test('downloadUrl downloads without credentials and parses back', () async {
    final Reference ref = dir.child('dl/file.txt');
    await ref.putString('content');
    final String url = await ref.downloadUrl();
    expect(url, startsWith('http://$host/v0/b/demo-test.appspot.com/o/'));
    final http.Response response = await http.get(Uri.parse(url));
    expect(response.statusCode, 200);
    expect(response.body, 'content');
    expect(storage.refFromUrl(url), ref);
  }, skip: skip);

  test('updateMetadata sets and deletes fields', () async {
    final Reference ref = dir.child('meta');
    await ref.putString(
      'x',
      metadata: const SettableMetadata(contentLanguage: 'en'),
    );
    final FullMetadata updated = await ref.updateMetadata(
      const SettableMetadata(
        cacheControl: 'max-age=5',
        contentType: 'text/x-new',
        customMetadata: <String, String>{'a': '1'},
      ),
    );
    expect(updated.cacheControl, 'max-age=5');
    expect(updated.contentType, 'text/x-new');
    expect(updated.contentLanguage, 'en');
    expect(updated.customMetadata, <String, String>{'a': '1'});

    final FullMetadata cleared = await ref.updateMetadata(
      const SettableMetadata(
        delete: <MetadataField>{MetadataField.cacheControl},
      ),
    );
    expect(cleared.cacheControl, isNull);
    expect(cleared.contentType, 'text/x-new');
  }, skip: skip);

  test('list, listAll and listPages', () async {
    for (final String name in <String>[
      'a.txt',
      'b.txt',
      'c.txt',
      'sub/d.txt',
    ]) {
      await dir.child(name).putString(name);
    }
    final ListResult all = await dir.listAll();
    expect(
      all.items.map((Reference r) => r.name),
      unorderedEquals(<String>['a.txt', 'b.txt', 'c.txt']),
    );
    expect(all.prefixes, <Reference>[dir.child('sub')]);

    final ListResult first = await dir.list(maxResults: 2);
    expect(first.items, hasLength(2));
    expect(first.nextPageToken, isNotNull);

    final List<ListResult> pages = await dir.listPages(pageSize: 2).toList();
    expect(
      pages.expand((ListResult p) => p.items).map((Reference r) => r.name),
      unorderedEquals(<String>['a.txt', 'b.txt', 'c.txt']),
    );
    expect(pages.last.nextPageToken, isNull);
  }, skip: skip);

  group('rules', () {
    late FirebaseApp authApp;

    setUp(() => authApp = newApp(storageBucket: 'demo-test-auth.appspot.com'));
    tearDown(() => authApp.delete());

    String unsignedJwt(String uid) {
      String part(Map<String, Object?> json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      return '${part(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.${part(<String, Object?>{'user_id': uid, 'sub': uid})}.';
    }

    test('signed out is unauthorized with the status and the body', () async {
      final FirebaseStorage s = FirebaseStorage(authApp, emulatorHost: host);
      addTearDown(s.close);
      await expectLater(
        s.ref('users/u1/x').putString('x'),
        throwsA(
          isA<FirebaseStorageException>()
              .having(
                (FirebaseStorageException e) => e.code,
                'code',
                'unauthorized',
              )
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'httpStatus',
                403,
              )
              .having(
                (FirebaseStorageException e) => e.serverResponse,
                'serverResponse',
                contains('Permission denied'),
              ),
        ),
      );
    }, skip: skip);

    test('the user of the auth provider passes the rules', () async {
      authApp.authProvider = FakeAuth(<String>[unsignedJwt('u1')]);
      final FirebaseStorage s = FirebaseStorage(authApp, emulatorHost: host);
      addTearDown(s.close);
      final Reference own = s.ref(
        'users/u1/it-${DateTime.now().microsecondsSinceEpoch}',
      );
      await own.putString('mine');
      expect(utf8.decode(await own.getBytes()), 'mine');
      await expectLater(
        s.ref('users/u2/x').putString('x'),
        throwsStorageCode('unauthorized'),
      );
      await own.delete();
    }, skip: skip);

    test('mockUserToken owner is an admin', () async {
      final FirebaseStorage s = FirebaseStorage(
        authApp,
        emulatorHost: host,
        mockUserToken: 'owner',
      );
      addTearDown(s.close);
      final Reference ref = s.ref(
        'anywhere/it-${DateTime.now().microsecondsSinceEpoch}',
      );
      await ref.putString('admin');
      expect((await s.ref('anywhere').listAll()).items, contains(ref));
      await ref.delete();
    }, skip: skip);
  });
}
