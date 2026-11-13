// Ports the JS SDK connection unit tests the web transport did not cover yet:
// test/unit/remote/rest_connection.test.ts, fetch_connection.test.ts and
// web_channel_connection.browser.test.ts. Test names are the JS ones.
//
// JS tests a `RestConnection` whose `performRPCRequest()` is replaced; here the
// real transports run against [FakeHttpClient], which records the request the
// browser would send. Header names are compared in lower case: HTTP header
// names are case-insensitive, and gRPC needs them in lower case.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/platform_info.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

import 'fake_http_client.dart';

/// Hands out a fixed OAuth token, the JS `OAuthToken('owner', ...)`.
class _OwnerCredentialsProvider extends EmptyCredentialsProvider {
  @override
  Future<String?> get token => Future<String?>.value('owner');
}

/// Hands out a fixed App Check token, the JS `AppCheckToken(...)`.
class _FixedAppCheckTokenProvider extends AppCheckTokenProvider {
  _FixedAppCheckTokenProvider(this._token) : super(null);

  final String _token;

  @override
  Future<String> get token => Future<String>.value(_token);
}

void main() {
  final DatabaseId databaseId = DatabaseId.forProject('testproject');
  const String database = 'projects/testproject/databases/(default)';

  DatabaseInfo testDatabaseInfo({
    String host = 'example.com',
    int port = 80,
    bool sslEnabled = false,
    String? apiKey = 'rest-connection-test-api-key',
  }) {
    return DatabaseInfo(
      databaseId,
      'persistenceKey',
      host,
      port: port,
      sslEnabled: sslEnabled,
      apiKey: apiKey,
      appId: 'test-app-id',
    );
  }

  ChannelOptionsProvider options({
    EmptyCredentialsProvider? credentials,
    AppCheckTokenProvider? appCheck,
    String? apiKey = 'rest-connection-test-api-key',
  }) {
    return ChannelOptionsProvider(
      databaseId: databaseId,
      credentialsProvider: credentials ?? EmptyCredentialsProvider(),
      appCheckProvider: appCheck,
      apiKey: apiKey,
      appId: 'test-app-id',
    );
  }

  /// Starts [rpc] with [request] on [transport] and returns the HTTP request
  /// it sends. The call itself is left to the test.
  Future<FakeRequest>
  send<Req extends GeneratedMessage, Res extends GeneratedMessage>(
    FakeHttpClient http,
    FirestoreTransport transport,
    FirestoreRpc<Req, Res> rpc,
    Req request,
  ) {
    unawaited(
      transport
          .startCall(rpc, Stream<Req>.value(request))
          .toList()
          .then((_) {}, onError: (Object _) {}),
    );
    return http.next();
  }

  Map<String, String> lowerCase(Map<String, String> headers) => headers.map(
    (String key, String value) =>
        MapEntry<String, String>(key.toLowerCase(), value),
  );

  proto.RunQueryRequest runQuery(String collection) =>
      proto.RunQueryRequest()..parent = '$database/documents/$collection';

  group('RestConnection', () {
    test('url uses from path', () async {
      final FakeHttpClient http = FakeHttpClient();
      final RestTransport connection = RestTransport(
        http,
        testDatabaseInfo(),
        options(),
      );

      final FakeRequest sent = await send(
        http,
        connection,
        FirestoreRpc.commit,
        proto.CommitRequest()..database = database,
      );
      expect(
        sent.url.toString(),
        'http://example.com/v1/projects/testproject/databases/(default)'
        '/documents:commit?key=rest-connection-test-api-key',
      );
      sent.respond(200, body: '{}');
    });

    test('merges headers', () async {
      final FakeHttpClient http = FakeHttpClient();
      final RestTransport connection = RestTransport(
        http,
        testDatabaseInfo(),
        options(
          credentials: _OwnerCredentialsProvider(),
          appCheck: _FixedAppCheckTokenProvider('some-app-check-token'),
        ),
      );

      final FakeRequest sent = await send(
        http,
        connection,
        FirestoreRpc.runQuery,
        runQuery('foo'),
      );
      final Map<String, String> headers = lowerCase(sent.headers);
      // PORTING NOTE: JS sends `gl-js/ fire/<version>`; this SDK names itself
      // (and its gRPC version) in the same header.
      expect(
        headers.remove('x-goog-api-client'),
        'gl-dart/$dartRuntimeVersion fire/${Version.sdkVersion} '
        'grpc/${Version.grpcVersion}',
      );
      expect(headers, <String, String>{
        'authorization': 'Bearer owner',
        'content-type': 'text/plain',
        'x-firebase-gmpid': 'test-app-id',
        'x-firebase-appcheck': 'some-app-check-token',
        'x-goog-request-params': 'project_id=testproject',
        'google-cloud-resource-prefix': database,
      });
      sent.respond(200, body: '[]');
    });

    test('empty app check token is not added to headers', () async {
      final FakeHttpClient http = FakeHttpClient();
      final RestTransport connection = RestTransport(
        http,
        testDatabaseInfo(),
        options(appCheck: _FixedAppCheckTokenProvider('')),
      );

      final FakeRequest sent = await send(
        http,
        connection,
        FirestoreRpc.runQuery,
        runQuery('foo'),
      );
      final Map<String, String> headers = lowerCase(sent.headers)
        ..remove('x-goog-api-client');
      expect(headers, <String, String>{
        'content-type': 'text/plain',
        'x-firebase-gmpid': 'test-app-id',
        'x-goog-request-params': 'project_id=testproject',
        'google-cloud-resource-prefix': database,
        // Note: AppCheck token should not exist here.
      });
      sent.respond(200, body: '[]');
    });

    test(
      'adds custom headers when _customHeaders is set',
      () {},
      skip:
          'DatabaseInfo._customHeaders is an internal JS hook (for the '
          'Firebase console); this SDK has no custom headers to send.',
    );

    test('returns success', () async {
      final FakeHttpClient http = FakeHttpClient();
      final RestClient connection = RestClient(http, 'http://example.com');
      final Future<List<Object?>> response = connection.invoke(
        'RunQuery',
        <String, Object?>{'parent': '$database/documents/coll'},
        const <String, String>{},
      );
      (await http.next()).respond(200, body: '{"response":true}');
      expect(await response, <Object?>[
        <String, Object?>{'response': true},
      ]);
    });

    test('returns error', () async {
      // JS rejects performRPCRequest() with a FirestoreError; the REST
      // answer that becomes that error is an error body.
      final FakeHttpClient http = FakeHttpClient();
      final RestClient connection = RestClient(http, 'http://example.com');
      final Future<List<Object?>> response = connection.invoke(
        'RunQuery',
        <String, Object?>{'parent': '$database/documents/coll'},
        const <String, String>{},
      );
      (await http.next()).respond(
        500,
        body:
            '{"error":{"code":2,"message":"Test exception",'
            '"status":"UNKNOWN"}}',
      );
      await expectLater(
        response,
        throwsA(
          isA<GrpcError>()
              .having((GrpcError e) => e.code, 'code', StatusCode.unknown)
              .having((GrpcError e) => e.message, 'message', 'Test exception'),
        ),
      );
    });

    test('a named database adds its id to the request params', () async {
      expect(
        RestClient.requestParams('projects/test project/databases/other db'),
        'project_id=test%20project&database_id=other%20db',
      );
      expect(RestClient.requestParams(database), 'project_id=testproject');
    });
  });

  group('Fetch Connection', () {
    test(
      'should pass in credentials if using emulator and cloud workstation',
      () async {
        final FakeHttpClient http = FakeHttpClient();
        final RestTransport fetchConnection = RestTransport(
          http,
          testDatabaseInfo(
            host: 'abc.cloudworkstations.dev',
            port: 443,
            sslEnabled: true,
            apiKey: null,
          ),
          options(apiKey: null),
        );

        final FakeRequest sent = await send(
          http,
          fetchConnection,
          FirestoreRpc.commit,
          proto.CommitRequest()..database = database,
        );
        expect(
          sent.url.toString(),
          'https://abc.cloudworkstations.dev/v1/$database/documents:commit',
        );
        expect(sent.includeCredentials, isTrue);
        sent.respond(200, body: '{}');
      },
    );

    test('sends no credentials to other hosts', () async {
      final FakeHttpClient http = FakeHttpClient();
      final RestTransport fetchConnection = RestTransport(
        http,
        testDatabaseInfo(),
        options(),
      );

      final FakeRequest sent = await send(
        http,
        fetchConnection,
        FirestoreRpc.commit,
        proto.CommitRequest()..database = database,
      );
      expect(sent.includeCredentials, isFalse);
      sent.respond(200, body: '{}');
    });

    test(
      'the full SDK sends no credentials, as its WebChannelConnection',
      () async {
        final FakeHttpClient http = FakeHttpClient();
        final WebChannelTransport transport = WebChannelTransport(
          http,
          testDatabaseInfo(
            host: 'abc.cloudworkstations.dev',
            port: 443,
            sslEnabled: true,
          ),
          options(),
        );

        final FakeRequest sent = await send(
          http,
          transport,
          FirestoreRpc.commit,
          proto.CommitRequest()..database = database,
        );
        expect(sent.includeCredentials, isFalse);
        sent.respond(200, body: '{}');
        await transport.shutdown();
      },
    );
  });

  group('WebChannelConnection', () {
    test(
      'Passes the API Key from DatabaseInfo to makeHeaders for openStream',
      () async {
        final FakeHttpClient http = FakeHttpClient();
        final WebChannelTransport connection = WebChannelTransport(
          http,
          testDatabaseInfo(apiKey: 'wc-connection-test-api-key'),
          options(apiKey: 'wc-connection-test-api-key'),
        );
        final StreamController<proto.WriteRequest> requests =
            StreamController<proto.WriteRequest>();
        connection
            .startCall(FirestoreRpc.write, requests.stream)
            .listen((_) {}, onError: (Object _) {});
        requests.add(proto.WriteRequest()..database = database);

        final FakeRequest handshake = await http.next();
        final String headers = handshake.form['headers']!;
        expect(headers, contains('x-goog-api-key:wc-connection-test-api-key'));
        expect(headers, contains('x-firebase-gmpid:test-app-id'));
        await requests.close();
        await connection.shutdown();
      },
    );
  });
}
