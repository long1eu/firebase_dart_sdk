// The API key of the app goes with every request, as in the JS SDK: the
// x-goog-api-key header over gRPC and WebChannel, and the `key` query
// parameter of a REST call (Firestore Lite sends no header, a WebChannel
// unary call sends both). The Android SDK sends no API key.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Firestore, FirestoreSettings, MemoryCacheSettings;
import 'package:cloud_firestore_dart/lite.dart' as lite;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart'
    show liteTransportOverride;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart'
    show FirestoreInternal;
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:grpc/service_api.dart' show MetadataProvider;
import 'package:test/test.dart';

import 'unused_transport.dart';
import 'web/fake_http_client.dart';

const String database = 'projects/p/databases/(default)';

void main() {
  final DatabaseId databaseId = DatabaseId.forProject('p');

  ChannelOptionsProvider options(String? apiKey) => ChannelOptionsProvider(
    databaseId: databaseId,
    credentialsProvider: EmptyCredentialsProvider(),
    apiKey: apiKey,
  );

  DatabaseInfo info(String? apiKey) => DatabaseInfo(
    databaseId,
    'key',
    'example.test',
    port: 8443,
    sslEnabled: true,
    apiKey: apiKey,
  );

  Future<Map<String, String>> metadataOf(
    ChannelOptionsProvider provider,
  ) async {
    final Map<String, String> metadata = <String, String>{};
    for (final MetadataProvider metadataProvider
        in provider.callOptions.metadataProviders) {
      await metadataProvider(metadata, 'uri');
    }
    return metadata;
  }

  Stream<proto.CommitRequest> commit() => Stream<proto.CommitRequest>.value(
    proto.CommitRequest()..database = database,
  );

  group('gRPC metadata', () {
    test('carries x-goog-api-key when the app has an API key', () async {
      final Map<String, String> metadata = await metadataOf(options('my key'));
      expect(metadata['x-goog-api-key'], 'my key');
    });

    test('has no x-goog-api-key without an API key', () async {
      expect(
        await metadataOf(options(null)),
        isNot(contains('x-goog-api-key')),
      );
      expect(await metadataOf(options('')), isNot(contains('x-goog-api-key')));
    });
  });

  group('REST', () {
    test('the key is a query parameter, not a header', () async {
      final FakeHttpClient http = FakeHttpClient();
      final RestTransport transport = RestTransport(
        http,
        info('a+b&c'),
        options('a+b&c'),
      );
      unawaited(
        transport
            .startCall(FirestoreRpc.commit, commit())
            .toList()
            .then((_) {}, onError: (Object _) {}),
      );

      final FakeRequest sent = await http.next();
      expect(
        sent.url.toString(),
        'https://example.test:8443/v1/projects/p/databases/(default)'
        '/documents:commit?key=a%2Bb%26c',
      );
      expect(sent.url.queryParameters['key'], 'a+b&c');
      expect(sent.headers, isNot(contains('x-goog-api-key')));
      sent.respond(200, body: '{"commitTime":"2026-11-12T21:14:41Z"}');
    });

    test('no key, no query parameter', () {
      final RestClient client = RestClient(
        FakeHttpClient(),
        'https://example.test:8443',
      );
      expect(
        client.urlFor('Commit', <String, Object?>{
          'database': database,
        }).hasQuery,
        isFalse,
      );
    });
  });

  group('WebChannel', () {
    late FakeHttpClient http;
    late WebChannelTransport transport;

    setUp(() {
      http = FakeHttpClient();
      transport = WebChannelTransport(http, info('k1'), options('k1'));
    });

    test('a unary call has the key as header and query parameter', () async {
      unawaited(
        transport
            .startCall(FirestoreRpc.commit, commit())
            .toList()
            .then((_) {}, onError: (Object _) {}),
      );

      final FakeRequest sent = await http.next();
      expect(sent.url.queryParameters['key'], 'k1');
      expect(sent.headers['x-goog-api-key'], 'k1');
      sent.respond(200, body: '{"commitTime":"2026-11-12T21:14:41Z"}');
    });

    test('a stream sends the key with its headers', () async {
      final StreamController<proto.WriteRequest> requests =
          StreamController<proto.WriteRequest>();
      final ResponseStream<proto.WriteResponse> call = transport.startCall(
        FirestoreRpc.write,
        requests.stream,
      );
      call.listen((_) {}, onError: (Object _) {});
      requests.add(proto.WriteRequest()..database = database);

      final FakeRequest handshake = await http.next();
      expect(handshake.form['headers'], contains('x-goog-api-key:k1'));
      await requests.close();
      await transport.shutdown();
    });
  });

  group('the API key of the app', () {
    FirebaseApp newApp(String name) {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'fake-api-key-x',
          applicationId: 'appId',
          projectId: 'test-project',
        ),
        name: name,
      );
      addTearDown(app.delete);
      return app;
    }

    test('reaches the database info of an instance', () async {
      final Firestore firestore = Firestore.instanceFor(
        app: newApp('api-key-full'),
        settings: FirestoreSettings(
          cacheSettings: const MemoryCacheSettings(),
        ).withEmulator('127.0.0.1', 1),
      );
      addTearDown(firestore.terminate);
      expect(firestore.client.databaseInfo.apiKey, 'fake-api-key-x');
    });

    test('reaches the transport of Firestore Lite', () async {
      DatabaseInfo? seenInfo;
      ChannelOptionsProvider? seenOptions;
      liteTransportOverride =
          (DatabaseInfo databaseInfo, ChannelOptionsProvider options) {
            seenInfo = databaseInfo;
            seenOptions = options;
            return UnusedTransport();
          };
      addTearDown(() => liteTransportOverride = null);

      final lite.Firestore firestore = lite.Firestore.instanceFor(
        app: newApp('api-key-lite'),
        settings: lite.FirestoreSettings().withEmulator('127.0.0.1', 1),
      );
      addTearDown(firestore.terminate);
      await firestore
          .doc('a/b')
          .get()
          .then<void>((_) {}, onError: (Object _) {});

      expect(seenInfo?.apiKey, 'fake-api-key-x');
      expect(seenOptions?.apiKey, 'fake-api-key-x');
    });
  });
}
