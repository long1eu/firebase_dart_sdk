@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_analytics_dart/io.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('analytics_store_');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('reads back what it wrote, and null removes the key', () async {
    final FileAnalyticsStore store = FileAnalyticsStore(
      Directory('${root.path}/nested/dir'),
    );
    expect(await store.read('a/b:c'), isNull);
    await store.write('a/b:c', '{"x":1}');
    expect(await store.read('a/b:c'), '{"x":1}');
    await store.write('a/b:c', '{"x":2}');
    expect(await store.read('a/b:c'), '{"x":2}');
    await store.write('a/b:c', null);
    expect(await store.read('a/b:c'), isNull);
    await store.write('a/b:c', null);
  });

  test(
    'keys that differ only in characters a file name cannot hold get different files',
    () async {
      final FileAnalyticsStore store = FileAnalyticsStore(root);
      await store.write('app/G-1/state', 'one');
      await store.write('app:G-1:state', 'two');
      expect(await store.read('app/G-1/state'), 'one');
      expect(await store.read('app:G-1:state'), 'two');
      final List<String> names = root
          .listSync()
          .map((FileSystemEntity e) => e.uri.pathSegments.last)
          .toList();
      expect(names, hasLength(2));
      expect(names.every((String n) => !n.endsWith('.tmp')), isTrue);
    },
  );

  test('a client on the file store keeps its client id across runs', () async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        appId: '1:123:web:abc',
        projectId: 'demo-test',
      ),
      name: 'analytics-io-test',
    );
    FirebaseAnalytics open() => FirebaseAnalytics(
      app,
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 'secret'),
      store: FileAnalyticsStore(root),
      onWarning: (_) {},
      httpClient: MockClient(
        (http.Request request) async => http.Response('', 204),
      ),
    );
    final FirebaseAnalytics first = open();
    final String? id = await first.appInstanceId;
    await first.close();
    final FirebaseAnalytics second = open();
    expect(await second.appInstanceId, id);
    await second.close();
  });
}
