// Ports the JS SDK test/unit/remote/datastore.test.ts.
//
// JS injects a `Connection` whose invokeRPC() / invokeStreamingRPC() each test
// replaces; here a [FirestoreTransport] plays that part. As in JS, the unary
// path is reached through a commit and the server-streaming path through a
// document lookup (BatchGetDocuments).

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

class _FakeResponse implements Response {
  @override
  Future<Map<String, String>> get headers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<Map<String, String>> get trailers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<void> cancel() async {}
}

/// The JS `MockConnection`: every call fails with [error] unless it is null,
/// in which case reaching the wire fails the test.
class _MockTransport implements FirestoreTransport {
  _MockTransport([this.error]);

  final Object? error;
  bool terminateInvoked = false;

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    final Object? error = this.error;
    if (error == null) {
      throw StateError(
        '_MockTransport.startCall(${rpc.name}) must be replaced',
      );
    }
    return ResponseStream<Res>(_FakeResponse(), Stream<Res>.error(error));
  }

  @override
  Future<void> shutdown() async {
    terminateInvoked = true;
  }
}

class _MockAuthCredentialsProvider extends EmptyCredentialsProvider {
  bool invalidateTokenInvoked = false;

  @override
  void invalidateToken() {
    invalidateTokenInvoked = true;
  }
}

class _MockAppCheckTokenProvider extends AppCheckTokenProvider {
  _MockAppCheckTokenProvider() : super(null);

  bool invalidateTokenInvoked = false;

  @override
  void invalidateToken() {
    invalidateTokenInvoked = true;
  }
}

void main() {
  final DatabaseInfo databaseInfo = DatabaseInfo(
    DatabaseId.forProject('test-project'),
    'persistenceKey',
    'host',
    sslEnabled: false,
  );

  Datastore newDatastore(
    _MockTransport transport, {
    _MockAuthCredentialsProvider? authCredentials,
    _MockAppCheckTokenProvider? appCheckCredentials,
  }) {
    return Datastore(
      TaskScheduler('datastore_test'),
      databaseInfo,
      authCredentials ?? _MockAuthCredentialsProvider(),
      appCheckProvider: appCheckCredentials ?? _MockAppCheckTokenProvider(),
      transportFactory: (ChannelOptionsProvider _) => transport,
    );
  }

  Future<void> invokeDatastoreImplInvokeRpc(Datastore datastore) {
    return datastore.transactionClient.commit(<Mutation>[]);
  }

  Future<void> invokeDatastoreImplInvokeStreamingRpc(Datastore datastore) {
    return datastore.transactionClient.lookup(const <DocumentKey>[]);
  }

  Matcher firestoreError(FirestoreErrorCode code, Matcher message) {
    return isA<FirestoreError>()
        .having((FirestoreError e) => e.code, 'code', code)
        .having((FirestoreError e) => e.message, 'message', message);
  }

  test('newDatastore() returns an an instance of Datastore', () {
    final Datastore datastore = newDatastore(_MockTransport());
    expect(datastore, isA<Datastore>());
  });

  test('DatastoreImpl.invokeRPC() fails if terminated', () async {
    final Datastore datastore = newDatastore(_MockTransport());
    await datastore.shutdown();
    await expectLater(
      invokeDatastoreImplInvokeRpc(datastore),
      throwsA(
        firestoreError(
          FirestoreErrorCode.failedPrecondition,
          matches(RegExp('terminated')),
        ),
      ),
    );
  });

  test('Connection.terminate() invoked if Datastore terminated', () async {
    final _MockTransport connection = _MockTransport();
    final Datastore datastore = newDatastore(connection);
    await datastore.shutdown();
    expect(connection.terminateInvoked, isTrue);
  });

  test('DatastoreImpl.invokeRPC() rethrows a FirestoreError', () async {
    final _MockTransport connection = _MockTransport(
      const GrpcError.aborted('zzyzx'),
    );
    final _MockAuthCredentialsProvider authCredentials =
        _MockAuthCredentialsProvider();
    final _MockAppCheckTokenProvider appCheckCredentials =
        _MockAppCheckTokenProvider();
    final Datastore datastore = newDatastore(
      connection,
      authCredentials: authCredentials,
      appCheckCredentials: appCheckCredentials,
    );
    await expectLater(
      invokeDatastoreImplInvokeRpc(datastore),
      throwsA(firestoreError(FirestoreErrorCode.aborted, contains('zzyzx'))),
    );
    expect(authCredentials.invalidateTokenInvoked, isFalse);
    expect(appCheckCredentials.invalidateTokenInvoked, isFalse);
  });

  test(
    'DatastoreImpl.invokeRPC() wraps unknown exceptions in a FirestoreError',
    () async {
      final _MockTransport connection = _MockTransport('zzyzx');
      final _MockAuthCredentialsProvider authCredentials =
          _MockAuthCredentialsProvider();
      final _MockAppCheckTokenProvider appCheckCredentials =
          _MockAppCheckTokenProvider();
      final Datastore datastore = newDatastore(
        connection,
        authCredentials: authCredentials,
        appCheckCredentials: appCheckCredentials,
      );
      await expectLater(
        invokeDatastoreImplInvokeRpc(datastore),
        throwsA(firestoreError(FirestoreErrorCode.unknown, contains('zzyzx'))),
      );
      expect(authCredentials.invalidateTokenInvoked, isFalse);
      expect(appCheckCredentials.invalidateTokenInvoked, isFalse);
    },
  );

  test(
    'DatastoreImpl.invokeRPC() invalidates the token if unauthenticated',
    () async {
      final _MockTransport connection = _MockTransport(
        const GrpcError.unauthenticated('zzyzx'),
      );
      final _MockAuthCredentialsProvider authCredentials =
          _MockAuthCredentialsProvider();
      final _MockAppCheckTokenProvider appCheckCredentials =
          _MockAppCheckTokenProvider();
      final Datastore datastore = newDatastore(
        connection,
        authCredentials: authCredentials,
        appCheckCredentials: appCheckCredentials,
      );
      await expectLater(
        invokeDatastoreImplInvokeRpc(datastore),
        throwsA(
          firestoreError(FirestoreErrorCode.unauthenticated, contains('zzyzx')),
        ),
      );
      expect(authCredentials.invalidateTokenInvoked, isTrue);
      expect(appCheckCredentials.invalidateTokenInvoked, isTrue);
    },
  );

  test('DatastoreImpl.invokeStreamingRPC() fails if terminated', () async {
    final Datastore datastore = newDatastore(_MockTransport());
    await datastore.shutdown();
    await expectLater(
      invokeDatastoreImplInvokeStreamingRpc(datastore),
      throwsA(
        firestoreError(
          FirestoreErrorCode.failedPrecondition,
          matches(RegExp('terminated')),
        ),
      ),
    );
  });

  test(
    'DatastoreImpl.invokeStreamingRPC() rethrows a FirestoreError',
    () async {
      final _MockTransport connection = _MockTransport(
        const GrpcError.aborted('zzyzx'),
      );
      final _MockAuthCredentialsProvider authCredentials =
          _MockAuthCredentialsProvider();
      final _MockAppCheckTokenProvider appCheckCredentials =
          _MockAppCheckTokenProvider();
      final Datastore datastore = newDatastore(
        connection,
        authCredentials: authCredentials,
        appCheckCredentials: appCheckCredentials,
      );
      await expectLater(
        invokeDatastoreImplInvokeStreamingRpc(datastore),
        throwsA(firestoreError(FirestoreErrorCode.aborted, contains('zzyzx'))),
      );
      expect(authCredentials.invalidateTokenInvoked, isFalse);
      expect(appCheckCredentials.invalidateTokenInvoked, isFalse);
    },
  );

  test(
    'DatastoreImpl.invokeStreamingRPC() wraps unknown exceptions in a FirestoreError',
    () async {
      final _MockTransport connection = _MockTransport('zzyzx');
      final _MockAuthCredentialsProvider authCredentials =
          _MockAuthCredentialsProvider();
      final _MockAppCheckTokenProvider appCheckCredentials =
          _MockAppCheckTokenProvider();
      final Datastore datastore = newDatastore(
        connection,
        authCredentials: authCredentials,
        appCheckCredentials: appCheckCredentials,
      );
      await expectLater(
        invokeDatastoreImplInvokeStreamingRpc(datastore),
        throwsA(firestoreError(FirestoreErrorCode.unknown, contains('zzyzx'))),
      );
      expect(authCredentials.invalidateTokenInvoked, isFalse);
      expect(appCheckCredentials.invalidateTokenInvoked, isFalse);
    },
  );

  test(
    'DatastoreImpl.invokeStreamingRPC() invalidates the token if unauthenticated',
    () async {
      final _MockTransport connection = _MockTransport(
        const GrpcError.unauthenticated('zzyzx'),
      );
      final _MockAuthCredentialsProvider authCredentials =
          _MockAuthCredentialsProvider();
      final _MockAppCheckTokenProvider appCheckCredentials =
          _MockAppCheckTokenProvider();
      final Datastore datastore = newDatastore(
        connection,
        authCredentials: authCredentials,
        appCheckCredentials: appCheckCredentials,
      );
      await expectLater(
        invokeDatastoreImplInvokeStreamingRpc(datastore),
        throwsA(
          firestoreError(FirestoreErrorCode.unauthenticated, contains('zzyzx')),
        ),
      );
      expect(authCredentials.invalidateTokenInvoked, isTrue);
      expect(appCheckCredentials.invalidateTokenInvoked, isTrue);
    },
  );
}
