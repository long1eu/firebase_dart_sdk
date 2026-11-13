// Fuzz: the response bodies of the web transports, which come from the
// network: WebChannel handshakes and back channel chunks (Listen), and REST
// responses (BatchGetDocuments). Bodies are truncated, oversized, framed
// wrongly, of the wrong JSON types, deeply nested, and arrive in pieces.
//
// A call must deliver responses or end with a GrpcError, in bounded time and
// with a bounded number of requests; no error may escape uncaught. The
// responses it delivers go through the RemoteSerializer, which must decode
// them or reject them cleanly (see isCleanRejection).

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:test/test.dart';

import '../../util/fuzz.dart';
import '../../util/property.dart';
import '../firebase/firestore/remote/web/fake_http_client.dart';

const String database = 'projects/p/databases/(default)';
const String documents = '$database/documents';

final DatabaseId databaseId = DatabaseId.forProject('p');
final RemoteSerializer remote = RemoteSerializer(databaseId);

/// More requests than this in one case is a retry storm.
const int maxRequests = 40;

const Duration caseTimeout = Duration(seconds: 10);

extension on Gen {
  /// Any JSON value, with the names of the Firestore messages as keys.
  Object? json([int depth = 0]) {
    switch (below(depth < 4 ? 12 : 8)) {
      case 0:
        return null;
      case 1:
        return chance(50);
      case 2:
        return integer();
      case 3:
        return pick(const <Object>[1.5, -0.0, 1e300, 0.1, -1]);
      case 4:
        return string();
      case 5:
        return pick(const <String>[
          'ADD', 'REMOVE', 'CURRENT', 'RESET', 'NO_CHANGE', 'NULL_VALUE', //
          '2020-01-01T00:00:00Z', '0000-01-01T00:00:00Z', 'AAAA', '!',
          '$documents/c/d',
          '$documents/c',
          'projects/x/databases/y/documents/c/d',
          '1', '-1', '9223372036854775808', 'NaN', 'Infinity', 'c', 'noop',
          'stop', 'close',
        ]);
      case 6:
        return <Object?>[];
      case 7:
        return <String, Object?>{};
      case 8:
        return <Object?>[for (int i = below(4); i > 0; i--) json(depth + 1)];
      default:
        return <String, Object?>{
          for (int i = below(4); i > 0; i--)
            pick(const <String>[
              'targetChange', 'documentChange', 'documentDelete', //
              'documentRemove', 'filter', 'targetChangeType', 'targetIds',
              'resumeToken', 'readTime', 'cause', 'code', 'message', 'details',
              'document', 'name', 'fields', 'updateTime', 'createTime',
              'removedTargetIds', 'count', 'unchangedNames', 'found',
              'missing', 'transaction', 'error', 'status', '__sm__',
              'integerValue', 'mapValue', 'arrayValue', 'values', 'nullValue',
              'timestampValue', 'referenceValue', 'bytesValue',
            ]): json(
              depth + 1,
            ),
        };
    }
  }

  /// A Listen response that is valid now and then.
  Object? listenMessage() {
    switch (below(5)) {
      case 0:
        return <String, Object?>{
          'targetChange': <String, Object?>{
            'targetChangeType': pick(const <String>[
              'ADD',
              'CURRENT',
              'REMOVE',
            ]),
            'targetIds': <Object?>[2],
            if (chance(50)) 'readTime': json(),
            if (chance(50)) 'resumeToken': json(),
            if (chance(30)) 'cause': json(),
          },
        };
      case 1:
        return <String, Object?>{
          'documentChange': <String, Object?>{
            'document': <String, Object?>{
              'name': chance(60) ? '$documents/c/d' : json(),
              'fields': <String, Object?>{'a': json()},
              'updateTime': chance(60) ? '2020-01-01T00:00:00Z' : json(),
            },
            'targetIds': chance(70) ? <Object?>[2] : json(),
          },
        };
      case 2:
        return <String, Object?>{
          'error': <String, Object?>{
            'code': json(),
            'message': json(),
            'status': json(),
          },
        };
      default:
        return json();
    }
  }

  /// One `[arrayId, payload]` of the server.
  Object? array(int id) {
    final Object? arrayId = chance(80) ? id : json();
    switch (below(6)) {
      case 0:
        return <Object?>[
          arrayId,
          <Object?>[listenMessage()],
        ];
      case 1:
        return <Object?>[
          arrayId,
          <Object?>[
            pick(const <String>['noop', 'stop', 'close', 'c']),
          ],
        ];
      case 2:
        return <Object?>[
          arrayId,
          <String, Object?>{
            '__sm__': <String, Object?>{
              'status': <Object?>[
                <Object?>[
                  <String, Object?>{
                    'error': <String, Object?>{
                      'code': json(),
                      'status': json(),
                      'message': json(),
                    },
                  },
                ],
              ],
            },
          },
        ];
      case 3:
        return <Object?>[arrayId, json()];
      default:
        return chance(50)
            ? json()
            : <Object?>[
                arrayId,
                <Object?>[listenMessage()],
              ];
    }
  }

  /// A WebChannel body: chunks of arrays, framed rightly or not.
  String channelBody(int firstId) {
    final StringBuffer body = StringBuffer();
    int id = firstId;
    for (int i = between(1, 3); i > 0; i--) {
      final String json = jsonEncode(<Object?>[
        for (int j = between(1, 3); j > 0; j--) array(id++),
      ]);
      switch (below(8)) {
        case 0:
          body.write('${json.length + between(-3, 3)}\n$json');
          break;
        case 1:
          body.write(
            '${pick(<String>['-1', 'x', '', '1e3', '99999999999', '${1 << 40}'])}\n$json',
          );
          break;
        case 2:
          body.write(json.substring(0, below(json.length + 1)));
          break;
        case 3:
          final String deep = '${'[' * 5000}${']' * 5000}';
          body.write('${deep.length}\n$deep');
          break;
        default:
          body.write('${json.length}\n$json');
      }
    }
    return body.toString();
  }

  String handshake() {
    final Object? sessionId = chance(70) ? 'session' : json();
    final Object? timeoutHint = chance(50) ? 30000 : json();
    final List<Object?> open = <Object?>[
      'c',
      sessionId,
      '',
      8,
      12,
      timeoutHint,
    ];
    switch (below(6)) {
      case 0:
        return channelBody(0);
      case 1:
        return string();
      default:
        final String json = jsonEncode(<Object?>[
          <Object?>[0, open],
        ]);
        return '${json.length}\n$json';
    }
  }

  /// [text] in a few pieces, as the network delivers it.
  List<String> pieces(String text) {
    final List<String> result = <String>[];
    int i = 0;
    while (i < text.length) {
      final int end = (i + between(1, 64)).clamp(0, text.length);
      result.add(text.substring(i, end));
      i = end;
    }
    return result;
  }
}

/// Runs [body] and fails if an error escapes it uncaught, it takes too long,
/// or more than [maxRequests] requests are sent.
Future<void> guarded(FakeHttpClient http, Future<void> Function() body) async {
  final List<(Object, StackTrace)> uncaught = <(Object, StackTrace)>[];
  final Completer<void> done = Completer<void>();
  // The zone outlives this call: its uncaught errors are collected.
  // ignore: unawaited_futures, the body completes [done]
  runZonedGuarded(
    () async {
      try {
        await body().timeout(caseTimeout);
        // Whatever the call scheduled (a retry, a timer) runs now.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        done.complete();
      } catch (e, s) {
        if (!done.isCompleted) {
          done.completeError(e, s);
        }
      }
    },
    (Object error, StackTrace stackTrace) => uncaught.add((error, stackTrace)),
  );
  await done.future;
  if (uncaught.isNotEmpty) {
    final (Object error, StackTrace stackTrace) = uncaught.first;
    fail(
      'An error escaped: ${error.runtimeType}: $error\n'
      '${stackTrace.toString().split('\n').take(8).join('\n')}',
    );
  }
  expect(http.requests.length, lessThanOrEqualTo(maxRequests));
}

void expectGrpcError(Object error) {
  expect(error, isA<GrpcError>(), reason: '$error');
}

ChannelOptionsProvider options() => ChannelOptionsProvider(
  databaseId: databaseId,
  credentialsProvider: EmptyCredentialsProvider(),
);

Future<void> pump([int times = 5]) async {
  for (int i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> listenCase(Gen gen) async {
  final FakeHttpClient http = FakeHttpClient();
  final WebChannelTransport transport = WebChannelTransport(
    http,
    DatabaseInfo(databaseId, 'key', '127.0.0.1', port: 8080, sslEnabled: false),
    options(),
  );
  final List<proto.ListenResponse> responses = <proto.ListenResponse>[];
  final List<Object> errors = <Object>[];
  final StreamController<proto.ListenRequest> requests =
      StreamController<proto.ListenRequest>();
  await guarded(http, () async {
    final StreamSubscription<proto.ListenResponse> call = transport
        .startCall(FirestoreRpc.listen, requests.stream)
        .listen(responses.add, onError: errors.add);
    requests.add(
      proto.ListenRequest()
        ..database = database
        ..addTarget = (proto.Target()..targetId = 2),
    );
    final FakeRequest first = await http.next();
    first.respond(
      gen.chance(10) ? gen.pick(const <int>[0, 400, 500, 503]) : 200,
      body: gen.handshake(),
    );
    int arrayId = 1;
    for (int round = gen.between(1, 4); round > 0; round--) {
      await pump();
      if (!http.hasUnclaimed) {
        break;
      }
      final FakeRequest request = await http.next();
      if (request.aborted) {
        continue;
      }
      if (request.method != 'GET') {
        request.respond(200);
        continue;
      }
      request.stream(gen.chance(90) ? 200 : gen.pick(const <int>[0, 404, 503]));
      gen.pieces(gen.channelBody(arrayId)).forEach(request.add);
      arrayId += 10;
      switch (gen.below(3)) {
        case 0:
          request.cutBody();
          break;
        default:
          request.end();
      }
    }
    await pump();
    final Future<void> cancelled = call.cancel();
    await requests.close();
    final Future<void> shutdown = transport.shutdown();
    // Answer what the shutdown sent (the request that ends the session), so
    // that it does not wait for its release timeout.
    for (int i = 0; i < 3; i++) {
      await pump();
      while (http.hasUnclaimed) {
        final FakeRequest request = await http.next();
        if (!request.aborted) {
          request.respond(200);
        }
      }
    }
    await cancelled;
    await shutdown;
  });
  errors.forEach(expectGrpcError);
  for (final proto.ListenResponse response in responses) {
    acceptOrReject(() {
      remote.decodeVersionFromListenResponse(response);
      return remote.decodeWatchChange(response);
    }, () => '$response');
  }
}

Future<void> restCase(Gen gen) async {
  final FakeHttpClient http = FakeHttpClient();
  final RestTransport transport = RestTransport(
    http,
    DatabaseInfo(
      databaseId,
      'key',
      'example.test',
      port: 8443,
      sslEnabled: true,
    ),
    options(),
  );
  final List<proto.BatchGetDocumentsResponse> responses =
      <proto.BatchGetDocumentsResponse>[];
  final List<Object> errors = <Object>[];
  await guarded(http, () async {
    final Future<void> call = transport
        .startCall(
          FirestoreRpc.batchGetDocuments,
          Stream<proto.BatchGetDocumentsRequest>.value(
            proto.BatchGetDocumentsRequest()
              ..database = database
              ..documents.add('$documents/c/d'),
          ),
        )
        .listen(responses.add, onError: errors.add)
        .asFuture<void>()
        .catchError(errors.add);
    final FakeRequest request = await http.next();
    final String body;
    switch (gen.below(5)) {
      case 0:
        body = jsonEncode(<Object?>[
          for (int i = gen.below(4); i > 0; i--)
            <String, Object?>{
              'found': <String, Object?>{
                'name': gen.chance(70) ? '$documents/c/d' : gen.json(),
                'fields': <String, Object?>{'a': gen.json()},
                'updateTime': gen.chance(70)
                    ? '2020-01-01T00:00:00Z'
                    : gen.json(),
              },
              'readTime': gen.chance(70) ? '2020-01-01T00:00:00Z' : gen.json(),
            },
        ]);
        break;
      case 1:
        body = jsonEncode(<Object?>[
          <String, Object?>{'error': gen.json()},
        ]);
        break;
      case 2:
        final String text = jsonEncode(gen.json());
        body = text.substring(0, gen.below(text.length + 1));
        break;
      case 3:
        body = '${'[' * 5000}${']' * 5000}';
        break;
      default:
        body = jsonEncode(gen.json());
    }
    request.stream(
      gen.chance(70)
          ? 200
          : gen.pick(const <int>[0, 199, 204, 300, 400, 404, 500, 999, -1]),
    );
    gen.pieces(body).forEach(request.add);
    if (gen.chance(10)) {
      request.cutBody();
    } else {
      request.end();
    }
    await call;
    await transport.shutdown();
  });
  errors.forEach(expectGrpcError);
  for (final proto.BatchGetDocumentsResponse response in responses) {
    acceptOrReject(
      () => remote.decodeMaybeDocument(response),
      () => '$response',
    );
  }
}

/// The cases of one test take a few seconds per 300 by default; the timeout
/// grows with PROPERTY_SCALE.
final Timeout scaledTimeout = Timeout(Duration(seconds: 60 * cases(1)));

void main() {
  test('WebChannel Listen survives malformed bodies', () async {
    await forAllAsync<Gen>(
      'malformed WebChannel bodies',
      count: cases(300),
      generate: (Gen gen) => gen,
      show: (Gen gen) => 'seed ${gen.seed}',
      check: listenCase,
    );
  }, timeout: scaledTimeout);

  test('REST survives malformed bodies', () async {
    await forAllAsync<Gen>(
      'malformed REST bodies',
      count: cases(300),
      generate: (Gen gen) => gen,
      show: (Gen gen) => 'seed ${gen.seed}',
      check: restCase,
    );
  }, timeout: scaledTimeout);
}
