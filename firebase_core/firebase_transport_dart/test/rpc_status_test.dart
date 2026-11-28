import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_transport_dart/firebase_transport_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// The gRPC codes in order, with their `FirebaseException` codes and wire names.
const List<({String kebab, String wire})> _codes =
    <({String kebab, String wire})>[
      (kebab: 'ok', wire: 'OK'),
      (kebab: 'cancelled', wire: 'CANCELLED'),
      (kebab: 'unknown', wire: 'UNKNOWN'),
      (kebab: 'invalid-argument', wire: 'INVALID_ARGUMENT'),
      (kebab: 'deadline-exceeded', wire: 'DEADLINE_EXCEEDED'),
      (kebab: 'not-found', wire: 'NOT_FOUND'),
      (kebab: 'already-exists', wire: 'ALREADY_EXISTS'),
      (kebab: 'permission-denied', wire: 'PERMISSION_DENIED'),
      (kebab: 'resource-exhausted', wire: 'RESOURCE_EXHAUSTED'),
      (kebab: 'failed-precondition', wire: 'FAILED_PRECONDITION'),
      (kebab: 'aborted', wire: 'ABORTED'),
      (kebab: 'out-of-range', wire: 'OUT_OF_RANGE'),
      (kebab: 'unimplemented', wire: 'UNIMPLEMENTED'),
      (kebab: 'internal', wire: 'INTERNAL'),
      (kebab: 'unavailable', wire: 'UNAVAILABLE'),
      (kebab: 'data-loss', wire: 'DATA_LOSS'),
      (kebab: 'unauthenticated', wire: 'UNAUTHENTICATED'),
    ];

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

/// An error body whose `details` nest arrays so that the whole document is [depth] levels deep.
Uint8List _bodyOfDepth(int depth) {
  final int arrays = depth - 2;
  return _utf8(
    '{"error":{"status":"NOT_FOUND","details":${'[' * arrays}${']' * arrays}}}',
  );
}

void main() {
  test('index equals gRPC code for all 17', () {
    expect(RpcStatus.values, <RpcStatus>[
      RpcStatus.ok,
      RpcStatus.cancelled,
      RpcStatus.unknown,
      RpcStatus.invalidArgument,
      RpcStatus.deadlineExceeded,
      RpcStatus.notFound,
      RpcStatus.alreadyExists,
      RpcStatus.permissionDenied,
      RpcStatus.resourceExhausted,
      RpcStatus.failedPrecondition,
      RpcStatus.aborted,
      RpcStatus.outOfRange,
      RpcStatus.unimplemented,
      RpcStatus.internal,
      RpcStatus.unavailable,
      RpcStatus.dataLoss,
      RpcStatus.unauthenticated,
    ]);
    for (int code = 0; code < 17; code++) {
      expect(RpcStatus.values[code].index, code);
      expect(RpcStatus.fromCode(code), RpcStatus.values[code]);
    }
  });

  test('kebab names', () {
    expect(
      <String>[for (final RpcStatus status in RpcStatus.values) status.kebab],
      <String>[
        for (final ({String kebab, String wire}) code in _codes) code.kebab,
      ],
    );
  });

  test('fromCode out of range is unknown', () {
    for (final int code in <int>[-1, 17, 18, 100, -2147483648, 2147483647]) {
      expect(RpcStatus.fromCode(code), RpcStatus.unknown, reason: 'code $code');
    }
  });

  test('fromWireName for each name', () {
    for (int code = 0; code < _codes.length; code++) {
      expect(RpcStatus.fromWireName(_codes[code].wire), RpcStatus.values[code]);
    }
  });

  test('fromWireName: a lowercase name, null and a number give null', () {
    for (final Object? name in <Object?>[
      'invalid_argument',
      'Invalid_Argument',
      'invalid-argument',
      ' INVALID_ARGUMENT',
      '',
      null,
      3,
      3.0,
    ]) {
      expect(RpcStatus.fromWireName(name), isNull, reason: 'name $name');
    }
  });

  test('every row of the HTTP table and three unmapped statuses', () {
    const Map<int, RpcStatus> table = <int, RpcStatus>{
      200: RpcStatus.ok,
      201: RpcStatus.ok,
      204: RpcStatus.ok,
      299: RpcStatus.ok,
      400: RpcStatus.invalidArgument,
      401: RpcStatus.unauthenticated,
      403: RpcStatus.permissionDenied,
      404: RpcStatus.notFound,
      409: RpcStatus.aborted,
      416: RpcStatus.outOfRange,
      429: RpcStatus.resourceExhausted,
      499: RpcStatus.cancelled,
      500: RpcStatus.internal,
      501: RpcStatus.unimplemented,
      503: RpcStatus.unavailable,
      504: RpcStatus.deadlineExceeded,
      // Unmapped: the three, and the edges of the 2xx range.
      402: RpcStatus.unknown,
      418: RpcStatus.unknown,
      502: RpcStatus.unknown,
      199: RpcStatus.unknown,
      300: RpcStatus.unknown,
    };
    table.forEach((int status, RpcStatus expected) {
      expect(
        RpcStatus.fromHttpStatus(status),
        expected,
        reason: 'HTTP $status',
      );
    });
  });

  test('failure table', () {
    final Uri url = Uri.parse('https://api.example.test/v1');
    final List<(Object, RpcStatus)> rows = <(Object, RpcStatus)>[
      (
        const TokenFetchException(TokenFailure.authProviderFailed),
        RpcStatus.unauthenticated,
      ),
      (
        const TokenFetchException(TokenFailure.authTimedOut),
        RpcStatus.unavailable,
      ),
      (
        const TokenFetchException(TokenFailure.authTokenTooLong),
        RpcStatus.failedPrecondition,
      ),
      (
        const TokenFetchException(TokenFailure.destinationRefused),
        RpcStatus.failedPrecondition,
      ),
      (
        TimeoutException('late', const Duration(seconds: 1)),
        RpcStatus.deadlineExceeded,
      ),
      (
        const TransportException(TransportFailure.cancelled),
        RpcStatus.cancelled,
      ),
      (
        const TransportException(TransportFailure.network),
        RpcStatus.unavailable,
      ),
      (
        const TransportException(TransportFailure.redirected),
        RpcStatus.unavailable,
      ),
      (http.ClientException('refused', url), RpcStatus.unavailable),
      (http.RequestAbortedException(url), RpcStatus.unavailable),
      (const CapExceededException(10), RpcStatus.internal),
      (StateError('other'), RpcStatus.unknown),
      (const FormatException('other'), RpcStatus.unknown),
      ('a string', RpcStatus.unknown),
    ];
    for (final (Object error, RpcStatus expected) in rows) {
      expect(rpcStatusOfFailure(error), expected, reason: '$error');
    }
  });

  test('parseRpcErrorBody: object form', () {
    final RpcErrorBody? body = parseRpcErrorBody(
      _utf8(
        '{"error":{"code":404,"status":"NOT_FOUND","message":"No such function.",'
        '"details":[{"@type":"x"}]}}',
      ),
    );

    expect(body, isNotNull);
    expect(body!.status, RpcStatus.notFound);
    expect(body.httpCode, 404);
    expect(body.message, 'No such function.');
    expect(body.details, <Object?>[
      <String, Object?>{'@type': 'x'},
    ]);
  });

  test('parseRpcErrorBody: list form', () {
    final RpcErrorBody? body = parseRpcErrorBody(
      _utf8(
        '[{"error":{"code":403,"status":"PERMISSION_DENIED","message":"Denied."}},'
        '{"error":{"code":500,"status":"INTERNAL"}}]',
      ),
    );

    expect(body, isNotNull);
    expect(body!.status, RpcStatus.permissionDenied);
    expect(body.httpCode, 403);
    expect(body.message, 'Denied.');
    expect(body.details, isNull);
  });

  test('parseRpcErrorBody: no error object gives null', () {
    for (final String json in <String>[
      '{}',
      '{"message":"x"}',
      '{"error":"NOT_FOUND"}',
      '{"error":null}',
      '{"error":[{"status":"NOT_FOUND"}]}',
      '[]',
      '[{"message":"x"}]',
      '"error"',
      '404',
      'null',
    ]) {
      expect(parseRpcErrorBody(_utf8(json)), isNull, reason: json);
    }
  });

  test('parseRpcErrorBody: not JSON gives null', () {
    for (final String text in <String>[
      '',
      'not json',
      '{"error":',
      '<html>503</html>',
    ]) {
      expect(parseRpcErrorBody(_utf8(text)), isNull, reason: text);
    }
  });

  test('parseRpcErrorBody: not UTF-8 gives null', () {
    final Uint8List body = Uint8List.fromList(<int>[
      ...utf8.encode('{"error":{"message":"'),
      0xff,
      0xfe,
      ...utf8.encode('"}}'),
    ]);

    expect(parseRpcErrorBody(body), isNull);
  });

  test('parseRpcErrorBody: refused at depth 33 and accepted at 32', () {
    final RpcErrorBody? accepted = parseRpcErrorBody(_bodyOfDepth(32));
    expect(accepted, isNotNull);
    expect(accepted!.status, RpcStatus.notFound);

    expect(parseRpcErrorBody(_bodyOfDepth(33)), isNull);
  });

  test('parseRpcErrorBody: depth 33 accepted with maxDepth: 64', () {
    final RpcErrorBody? body = parseRpcErrorBody(
      _bodyOfDepth(33),
      maxDepth: 64,
    );

    expect(body, isNotNull);
    expect(body!.status, RpcStatus.notFound);
    expect(parseRpcErrorBody(_bodyOfDepth(65), maxDepth: 64), isNull);
  });

  test('message is sanitized', () {
    final RpcErrorBody? controls = parseRpcErrorBody(
      _utf8(r'{"error":{"message":"bad\u0000 in\u001bput\n\u0085!"}}'),
    );
    expect(controls!.message, 'bad input!');

    final RpcErrorBody? long = parseRpcErrorBody(
      _utf8('{"error":{"message":"${'é' * 600}"}}'),
    );
    expect(long!.message, 'é' * 512);

    final RpcErrorBody? notText = parseRpcErrorBody(
      _utf8('{"error":{"message":42}}'),
    );
    expect(notText!.message, isNull);
  });

  test('httpCode out of range is null', () {
    final List<(Object?, int?)> cases = <(Object?, int?)>[
      (99, null),
      (100, 100),
      (404, 404),
      (404.0, 404),
      (599, 599),
      (600, null),
      (-404, null),
      (404.5, null),
      (double.nan, null),
      (double.infinity, null),
      ('404', null),
      (true, null),
      (null, null),
    ];
    for (final (Object? code, int? expected) in cases) {
      final RpcErrorBody? body = rpcErrorBodyOf(<String, Object?>{
        'error': <String, Object?>{'code': code},
      });
      expect(body!.httpCode, expected, reason: 'code $code');
    }
  });

  test('details untouched', () {
    final List<Object?> details = <Object?>[
      <String, Object?>{
        '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
        'reason': 'API_KEY_INVALID\u0000',
        'metadata': <String, Object?>{'service': 'x'},
      },
      42,
      null,
    ];
    final RpcErrorBody? body = rpcErrorBodyOf(<String, Object?>{
      'error': <String, Object?>{'details': details},
    });
    expect(body!.details, same(details));

    final RpcErrorBody? parsed = parseRpcErrorBody(
      _utf8(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{'details': details},
        }),
      ),
    );
    expect(parsed!.details, details);
  });

  test('a status that is not an exact wire name is null', () {
    for (final Object? status in <Object?>[
      'not_found',
      'NOT FOUND',
      'BOGUS',
      5,
    ]) {
      final RpcErrorBody? body = rpcErrorBodyOf(<String, Object?>{
        'error': <String, Object?>{'status': status},
      });
      expect(body!.status, isNull, reason: 'status $status');
    }
  });
}
