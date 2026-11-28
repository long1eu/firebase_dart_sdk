import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_http.dart';

final Uri _url = Uri.parse('https://api.example.test/v1/run?key=SENTINEL');
const Duration _deadline = Duration(seconds: 10);
const Duration _headersDeadline = Duration(seconds: 5);
const Duration _idle = Duration(seconds: 10);

/// The request builder every product writes: the abort future goes to the request.
http.BaseRequest Function(Future<void> abort) _get(
  Uri url, {
  Map<String, String>? headers,
}) {
  return (Future<void> abort) {
    final http.AbortableRequest request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort,
    );
    request.headers.addAll(headers ?? const <String, String>{});
    return request;
  };
}

List<int> _bytes(int count, [int value = 0x61]) =>
    List<int>.filled(count, value);

Outcome<CappedResponse> _sendCapped(
  FakeClient client, {
  Uri? url,
  Map<String, String>? headers,
  int successCap = 16,
  int errorCap = 8,
  Future<void>? cancel,
}) {
  return Outcome<CappedResponse>(
    sendCapped(
      client,
      _get(url ?? _url, headers: headers),
      successCap: successCap,
      errorCap: errorCap,
      deadline: _deadline,
      cancel: cancel,
    ),
  );
}

Outcome<http.StreamedResponse> _sendStreaming(
  FakeClient client, {
  Duration? idleTimeout,
  Future<void>? cancel,
}) {
  return Outcome<http.StreamedResponse>(
    sendStreaming(
      client,
      _get(_url),
      headersDeadline: _headersDeadline,
      idleTimeout: idleTimeout,
      cancel: cancel,
    ),
  );
}

Outcome<CappedResponse> _readCapped(
  FakeBody body, {
  int cap = 8,
  int statusCode = 200,
}) {
  final http.StreamedResponse response = http.StreamedResponse(
    body.stream,
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
  return Outcome<CappedResponse>(
    readCapped(response, cap: cap, deadline: _deadline),
  );
}

TypeMatcher<TransportException> _transportFailure(TransportFailure failure) {
  return isA<TransportException>().having(
    (TransportException e) => e.failure,
    'failure',
    failure,
  );
}

Matcher _timeoutAfter(Duration duration) {
  return isA<TimeoutException>().having(
    (TimeoutException e) => e.duration,
    'duration',
    duration,
  );
}

/// A URL as a browser may spell it: [scheme] and [host] exactly as given, which a Dart `Uri`
/// would lowercase. Only the members the origin check reads are implemented.
final class _SpelledUri implements Uri {
  _SpelledUri(this.scheme, this.host, this.port);

  @override
  final String scheme;

  @override
  final String host;

  @override
  final int port;

  @override
  String toString() => '$scheme://[$host]:$port';

  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('_SpelledUri implements only scheme, host and port');
  }
}

/// A stack trace that names the request URL, as a client's may.
final StackTrace _markedTrace = StackTrace.fromString(
  '#0 send (https://api.example.test/v1/run?key=TRACE_MARKER)',
);

http.ClientException _markedClientException() {
  return http.ClientException(
    'refused TRACE_MARKER',
    Uri.parse('https://api.example.test/v1/run?key=TRACE_MARKER'),
  );
}

void main() {
  // The names §8.1 cites (T3, row 11), at the top level so that they are exact.
  test('redirect is not followed', () {
    fakeAsync((FakeAsync async) {
      final FakeClient client = FakeClient(
        honourAbort: false,
        statusCode: 302,
        headers: const <String, String>{
          'location': 'https://elsewhere.example.test/',
        },
      );
      final Outcome<CappedResponse> outcome = _sendCapped(client);
      client.body.add(_bytes(5));
      async.flushMicrotasks();

      expect(outcome.error, _transportFailure(TransportFailure.redirected));
      expect(client.requests, hasLength(1));
      expect(client.requests.single.followRedirects, isFalse);
      expect(client.body.bytesRead, 0);
      expect(client.body.cancelled, isTrue);
      expect(client.aborted, isTrue);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('client that follows a redirect is caught', () {
    fakeAsync((FakeAsync async) {
      final FakeClient client = FakeClient(
        responseUrl: Uri.parse(
          'https://elsewhere.example.test/v1/run?key=SENTINEL',
        ),
      );
      final Outcome<CappedResponse> outcome = _sendCapped(client);
      client.body
        ..add(_bytes(5))
        ..close();
      async.flushMicrotasks();

      expect(outcome.error, _transportFailure(TransportFailure.redirected));
      expect(client.body.bytesRead, 0);
      expect(client.aborted, isTrue);
    });
  });

  group('sendCapped', () {
    test('a body under successCap is returned', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          headers: const <String, String>{'content-type': 'application/json'},
        );
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body
          ..add(_bytes(10))
          ..close();
        async.flushMicrotasks();

        final CappedResponse response = outcome.value!;
        expect(response.statusCode, 200);
        expect(response.isSuccess, isTrue);
        expect(response.body, _bytes(10));
        expect(response.truncated, isFalse);
        expect(response.headers, <String, String>{
          'content-type': 'application/json',
        });
        expect(client.requests.single.followRedirects, isFalse);
        expect(client.aborted, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a body at successCap is returned', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body
          ..add(_bytes(8))
          ..add(_bytes(8))
          ..close();
        async.flushMicrotasks();

        expect(outcome.error, isNull);
        expect(outcome.value!.body, _bytes(16));
        expect(outcome.value!.truncated, isFalse);
        expect(client.aborted, isFalse);
      });
    });

    test('a body over successCap aborts with CapExceededException', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(honourAbort: false);
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body.add(_bytes(17));
        async.flushMicrotasks();

        expect(
          outcome.error,
          isA<CapExceededException>().having(
            (CapExceededException e) => e.cap,
            'cap',
            16,
          ),
        );
        expect(client.aborted, isTrue);
        expect(client.body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an error body under errorCap is returned with its status', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(statusCode: 503);
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body
          ..add(_bytes(5, 0x62))
          ..close();
        async.flushMicrotasks();

        final CappedResponse response = outcome.value!;
        expect(response.statusCode, 503);
        expect(response.isSuccess, isFalse);
        expect(response.body, _bytes(5, 0x62));
        expect(response.truncated, isFalse);
      });
    });

    test('an error body over errorCap is cut, with its status kept', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          honourAbort: false,
          statusCode: 500,
        );
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body.add(utf8.encode('0123456789abcdef'));
        async.flushMicrotasks();

        final CappedResponse response = outcome.value!;
        expect(response.statusCode, 500);
        expect(response.body, utf8.encode('01234567'));
        expect(response.truncated, isTrue);
        expect(client.body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('the deadline passes before the headers', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(holdHeaders: true);
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        async.elapse(_deadline - const Duration(milliseconds: 1));
        expect(outcome.done, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(outcome.error, _timeoutAfter(_deadline));
        expect(client.aborted, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('the deadline passes during the body', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(honourAbort: false);
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body.add(_bytes(3));
        async.elapse(_deadline - const Duration(milliseconds: 1));
        expect(outcome.done, isFalse);
        expect(client.body.bytesRead, 3);

        async.elapse(const Duration(milliseconds: 1));
        expect(outcome.error, _timeoutAfter(_deadline));
        expect(client.aborted, isTrue);
        expect(client.body.cancelled, isTrue);
      });
    });

    test('the deadline counts from the call, not from the headers', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(holdHeaders: true);
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        async.elapse(const Duration(seconds: 6));
        client
          ..releaseHeaders()
          ..body.add(_bytes(2));
        async.elapse(const Duration(seconds: 3));
        expect(outcome.done, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(outcome.error, _timeoutAfter(_deadline));
      });
    });

    test('cancel aborts the request', () {
      fakeAsync((FakeAsync async) {
        final Completer<void> cancel = Completer<void>();
        final FakeClient client = FakeClient(honourAbort: false);
        final Outcome<CappedResponse> outcome = _sendCapped(
          client,
          cancel: cancel.future,
        );
        client.body.add(_bytes(3));
        async.flushMicrotasks();
        expect(outcome.done, isFalse);

        cancel.complete();
        async.flushMicrotasks();
        expect(outcome.error, _transportFailure(TransportFailure.cancelled));
        expect(client.aborted, isTrue);
        expect(client.body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('cancel before the headers aborts the request', () {
      fakeAsync((FakeAsync async) {
        final Completer<void> cancel = Completer<void>();
        final FakeClient client = FakeClient(holdHeaders: true);
        final Outcome<CappedResponse> outcome = _sendCapped(
          client,
          cancel: cancel.future,
        );
        async.flushMicrotasks();

        cancel.complete();
        async.flushMicrotasks();
        expect(outcome.error, _transportFailure(TransportFailure.cancelled));
        expect(client.aborted, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a cancel future that fails cancels too', () {
      fakeAsync((FakeAsync async) {
        final Completer<void> cancel = Completer<void>();
        final FakeClient client = FakeClient(holdHeaders: true);
        final Outcome<CappedResponse> outcome = _sendCapped(
          client,
          cancel: cancel.future,
        );
        async.flushMicrotasks();

        cancel.completeError(StateError('closed'));
        async.flushMicrotasks();
        expect(outcome.error, _transportFailure(TransportFailure.cancelled));
        expect(client.aborted, isTrue);
      });
    });

    test('the first failure wins', () {
      fakeAsync((FakeAsync async) {
        final Completer<void> cancel = Completer<void>();
        final FakeClient client = FakeClient(holdHeaders: true);
        final Outcome<CappedResponse> outcome = _sendCapped(
          client,
          cancel: cancel.future,
        );
        async.elapse(_deadline);
        expect(outcome.error, _timeoutAfter(_deadline));

        // The abort makes the client fail its send with RequestAbortedException, after the
        // timeout; then the caller cancels. Neither replaces the timeout or raises an error.
        async.flushMicrotasks();
        expect(client.aborted, isTrue);
        cancel.complete();
        async.flushMicrotasks();
        expect(outcome.error, _timeoutAfter(_deadline));
      });
    });
    for (final int status in <int>[300, 301, 307, 308, 399]) {
      test('a $status answer throws redirected, its body unread', () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(
            honourAbort: false,
            statusCode: status,
          );
          final Outcome<CappedResponse> outcome = _sendCapped(client);
          client.body.add(_bytes(5));
          async.flushMicrotasks();

          expect(outcome.error, _transportFailure(TransportFailure.redirected));
          expect(client.body.bytesRead, 0);
          expect(client.body.cancelled, isTrue);
          expect(client.aborted, isTrue);
        });
      });
    }

    for (final int status in <int>[201, 204, 299]) {
      test('a $status answer is a success under successCap', () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(statusCode: status);
          final Outcome<CappedResponse> outcome = _sendCapped(client);
          client.body
            ..add(_bytes(12))
            ..close();
          async.flushMicrotasks();

          final CappedResponse response = outcome.value!;
          expect(response.statusCode, status);
          expect(response.isSuccess, isTrue);
          expect(response.body, _bytes(12));
          expect(response.truncated, isFalse);
        });
      });
    }

    test('a 299 body over successCap, not errorCap, is refused', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(statusCode: 299);
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body.add(_bytes(17));
        async.flushMicrotasks();

        expect(outcome.error, isA<CapExceededException>());
      });
    });

    test(
      'a client RequestAbortedException before the headers is cancelled',
      () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(
            error: http.RequestAbortedException(_url),
          );
          final Outcome<CappedResponse> outcome = _sendCapped(client);
          async.flushMicrotasks();

          expect(outcome.error, _transportFailure(TransportFailure.cancelled));
        });
      },
    );

    test('a client RequestAbortedException in the body is cancelled', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body
          ..add(_bytes(2))
          ..addError(http.RequestAbortedException(_url));
        async.flushMicrotasks();

        expect(outcome.error, _transportFailure(TransportFailure.cancelled));
      });
    });
  });

  group('sendCapped origin check (review M6)', () {
    Outcome<CappedResponse> sendFrom(FakeClient client, Uri requestUrl) {
      final Outcome<CappedResponse> outcome = _sendCapped(
        client,
        url: requestUrl,
      );
      client.body
        ..add(_bytes(4))
        ..close();
      return outcome;
    }

    test('[::1] and [0:0:0:0:0:0:0:1] are one origin', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          responseUrl: Uri.parse('http://[0:0:0:0:0:0:0:1]:8080/v1'),
        );
        final Outcome<CappedResponse> outcome = sendFrom(
          client,
          Uri.parse('http://[::1]:8080/v1'),
        );
        async.flushMicrotasks();

        expect(outcome.error, isNull);
        expect(outcome.value!.body, _bytes(4));
      });
    });

    test('[0:0:0:0:0:0:0:1] and [::1] are one origin', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          responseUrl: Uri.parse('http://[::1]:8080/v1'),
        );
        final Outcome<CappedResponse> outcome = sendFrom(
          client,
          Uri.parse('http://[0:0:0:0:0:0:0:1]:8080/v1'),
        );
        async.flushMicrotasks();

        expect(outcome.error, isNull);
        expect(outcome.value!.body, _bytes(4));
      });
    });

    test(
      'a scheme and a host name that differ only in case are one origin',
      () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(
            responseUrl: _SpelledUri('HTTPS', 'API.Example.TEST', 443),
          );
          final Outcome<CappedResponse> outcome = sendFrom(
            client,
            Uri.parse('https://api.example.test/v1'),
          );
          async.flushMicrotasks();

          expect(outcome.error, isNull);
          expect(outcome.value!.body, _bytes(4));
        });
      },
    );

    test('an IPv6 host that differs only in case is one origin', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          responseUrl: _SpelledUri('http', '0:0:0:0:0:0:0:ABCD', 9000),
        );
        final Outcome<CappedResponse> outcome = sendFrom(
          client,
          Uri.parse('http://[::abcd]:9000/v1'),
        );
        async.flushMicrotasks();

        expect(outcome.error, isNull);
        expect(outcome.value!.body, _bytes(4));
      });
    });

    test('another port of the same IPv6 host is another origin', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          responseUrl: Uri.parse('http://[0:0:0:0:0:0:0:1]:8081/v1'),
        );
        final Outcome<CappedResponse> outcome = sendFrom(
          client,
          Uri.parse('http://[::1]:8080/v1'),
        );
        async.flushMicrotasks();

        expect(outcome.error, _transportFailure(TransportFailure.redirected));
      });
    });

    test('another scheme on the same host and port is another origin', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          responseUrl: Uri.parse('http://[::1]:8080/v1'),
        );
        final Outcome<CappedResponse> outcome = sendFrom(
          client,
          Uri.parse('https://[::1]:8080/v1'),
        );
        async.flushMicrotasks();

        expect(outcome.error, _transportFailure(TransportFailure.redirected));
      });
    });
  });

  group('late cancel', () {
    test(
      'a cancel future that completes after sendCapped returned runs nothing',
      () {
        fakeAsync((FakeAsync async) {
          final Completer<void> cancel = Completer<void>();
          final FakeClient client = FakeClient();
          final Outcome<CappedResponse> outcome = _sendCapped(
            client,
            cancel: cancel.future,
          );
          client.body
            ..add(_bytes(4))
            ..close();
          async.flushMicrotasks();
          expect(outcome.value!.body, _bytes(4));

          cancel.complete();
          async.flushMicrotasks();
          expect(client.aborted, isFalse);
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('a late cancel after a sendStreaming body ended does nothing', () {
      fakeAsync((FakeAsync async) {
        final Completer<void> cancel = Completer<void>();
        final FakeClient client = FakeClient();
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          cancel: cancel.future,
        );
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        client.body
          ..add(_bytes(4))
          ..close();
        async.flushMicrotasks();
        expect(recorder.done, isTrue);

        cancel.complete();
        async.flushMicrotasks();
        expect(client.aborted, isFalse);
        expect(recorder.errors, isEmpty);
        expect(recorder.bytes, _bytes(4));
      });
    });
  });

  group('readCapped', () {
    test('a body under the cap is returned', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(
          body,
          statusCode: 404,
        );
        body
          ..add(_bytes(5))
          ..close();
        async.flushMicrotasks();

        final CappedResponse response = outcome.value!;
        expect(response.statusCode, 404);
        expect(response.headers, <String, String>{
          'content-type': 'application/json',
        });
        expect(response.body, _bytes(5));
        expect(response.truncated, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a body at the cap is returned whole', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(body);
        body
          ..add(_bytes(8))
          ..close();
        async.flushMicrotasks();

        expect(outcome.value!.body, _bytes(8));
        expect(outcome.value!.truncated, isFalse);
      });
    });

    test('a body over the cap is cut and the stream is cancelled', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(body);
        body
          ..add(utf8.encode('01234'))
          ..add(utf8.encode('56789'));
        async.flushMicrotasks();

        final CappedResponse response = outcome.value!;
        expect(response.body, utf8.encode('01234567'));
        expect(response.truncated, isTrue);
        expect(response.statusCode, 200);
        expect(body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a stream error becomes a TransportException', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(body);
        body
          ..add(_bytes(2))
          ..addError(http.ClientException('connection reset', _url));
        async.flushMicrotasks();

        expect(
          outcome.error,
          _transportFailure(TransportFailure.network)
              .having(
                (TransportException e) => e.detail,
                'detail',
                'connection reset',
              )
              .having(
                (TransportException e) => e.causeType,
                'causeType',
                isNotNull,
              ),
        );
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a stream error that is not a ClientException has no detail', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(body);
        body.addError(const FormatException('bad header value SECRET'));
        async.flushMicrotasks();

        expect(
          outcome.error,
          _transportFailure(
            TransportFailure.network,
          ).having((TransportException e) => e.detail, 'detail', isNull),
        );
      });
    });

    test('the deadline cancels the stream and throws TimeoutException', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(body);
        body.add(_bytes(2));
        async.elapse(_deadline - const Duration(milliseconds: 1));
        expect(outcome.done, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(outcome.error, _timeoutAfter(_deadline));
        expect(body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('readCapped passes the failures of this package through (review M2)', () {
    final List<({String name, Object error})> failures =
        <({String name, Object error})>[
          (
            name: 'TransportException',
            error: const TransportException(TransportFailure.cancelled),
          ),
          (name: 'TimeoutException', error: TimeoutException('idle', _idle)),
          (name: 'CapExceededException', error: const CapExceededException(5)),
        ];
    for (final ({String name, Object error}) failure in failures) {
      test('a ${failure.name} from the body stream arrives unchanged', () {
        fakeAsync((FakeAsync async) {
          final FakeBody body = FakeBody();
          final Outcome<CappedResponse> outcome = _readCapped(body);
          body
            ..add(_bytes(2))
            ..addError(failure.error);
          async.flushMicrotasks();

          expect(outcome.error, same(failure.error));
          expect(async.pendingTimers, isEmpty);
        });
      });
    }

    test(
      'cancel during readCapped of a sendStreaming body gives cancelled',
      () {
        fakeAsync((FakeAsync async) {
          final Completer<void> cancel = Completer<void>();
          final FakeClient client = FakeClient(statusCode: 503);
          final Outcome<http.StreamedResponse> streaming = _sendStreaming(
            client,
            cancel: cancel.future,
          );
          async.flushMicrotasks();
          final Outcome<CappedResponse> outcome = Outcome<CappedResponse>(
            readCapped(streaming.value!, cap: 64, deadline: _deadline),
          );
          client.body.add(_bytes(3));
          async.flushMicrotasks();

          cancel.complete();
          async.flushMicrotasks();
          expect(outcome.error, _transportFailure(TransportFailure.cancelled));
          expect(rpcStatusOfFailure(outcome.error!), RpcStatus.cancelled);
          expect(client.aborted, isTrue);
        });
      },
    );

    test(
      'an idle timeout during readCapped of a sendStreaming body stays a timeout',
      () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(statusCode: 503);
          final Outcome<http.StreamedResponse> streaming = _sendStreaming(
            client,
            idleTimeout: _idle,
          );
          async.flushMicrotasks();
          final Outcome<CappedResponse> outcome = Outcome<CappedResponse>(
            readCapped(
              streaming.value!,
              cap: 64,
              deadline: const Duration(minutes: 1),
            ),
          );
          async.elapse(_idle);

          expect(outcome.error, _timeoutAfter(_idle));
          expect(
            rpcStatusOfFailure(outcome.error!),
            RpcStatus.deadlineExceeded,
          );
          expect(client.aborted, isTrue);
        });
      },
    );
  });

  group('sendStreaming', () {
    test('headers before headersDeadline return the response', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          headers: const <String, String>{'content-type': 'text/event-stream'},
          holdHeaders: true,
        );
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
        async.elapse(_headersDeadline - const Duration(milliseconds: 1));
        client.releaseHeaders();
        async.flushMicrotasks();

        final http.StreamedResponse response = outcome.value!;
        expect(response.statusCode, 200);
        expect(response.headers, <String, String>{
          'content-type': 'text/event-stream',
        });
        expect(response.request, same(client.requests.single));
        expect(
          response,
          isA<http.BaseResponseWithUrl>().having(
            (http.BaseResponseWithUrl r) => r.url,
            'url',
            _url,
          ),
        );
        expect(client.requests.single.followRedirects, isFalse);

        final BodyRecorder recorder = BodyRecorder(response.stream);
        client.body
          ..add(_bytes(3))
          ..close();
        async.elapse(const Duration(minutes: 1));
        expect(recorder.bytes, _bytes(3));
        expect(recorder.errors, isEmpty);
        expect(recorder.done, isTrue);
        expect(client.aborted, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('headers after headersDeadline throw TimeoutException', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(holdHeaders: true);
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
        async.elapse(_headersDeadline - const Duration(milliseconds: 1));
        expect(outcome.done, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(outcome.error, _timeoutAfter(_headersDeadline));
        expect(client.aborted, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('cancel ends the body with cancelled and aborts', () {
      fakeAsync((FakeAsync async) {
        final Completer<void> cancel = Completer<void>();
        final FakeClient client = FakeClient(honourAbort: false);
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          cancel: cancel.future,
        );
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        client.body.add(_bytes(2));
        async.flushMicrotasks();
        expect(recorder.bytes, _bytes(2));

        cancel.complete();
        async.flushMicrotasks();
        expect(
          recorder.errors.single,
          _transportFailure(TransportFailure.cancelled),
        );
        expect(recorder.done, isTrue);
        expect(client.aborted, isTrue);
        expect(client.body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('cancel before the headers throws cancelled and aborts', () {
      fakeAsync((FakeAsync async) {
        final Completer<void> cancel = Completer<void>();
        final FakeClient client = FakeClient(holdHeaders: true);
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          cancel: cancel.future,
        );
        async.flushMicrotasks();

        cancel.complete();
        async.flushMicrotasks();
        expect(outcome.error, _transportFailure(TransportFailure.cancelled));
        expect(client.aborted, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a cancelled subscription aborts the request', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(honourAbort: false);
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          idleTimeout: _idle,
        );
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        client.body.add(_bytes(2));
        async.flushMicrotasks();

        unawaited(recorder.subscription.cancel());
        async.flushMicrotasks();
        expect(client.aborted, isTrue);
        expect(client.body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a 302 answer throws redirected', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(statusCode: 302);
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
        client.body.add(_bytes(5));
        async.flushMicrotasks();

        expect(outcome.error, _transportFailure(TransportFailure.redirected));
        expect(client.body.bytesRead, 0);
        expect(client.aborted, isTrue);
      });
    });

    test('a client that follows a redirect is caught', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          honourAbort: false,
          responseUrl: Uri.parse(
            'https://elsewhere.example.test/v1/run?key=SENTINEL',
          ),
        );
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
        client.body.add(_bytes(5));
        async.flushMicrotasks();

        expect(outcome.error, _transportFailure(TransportFailure.redirected));
        expect(client.body.bytesRead, 0);
        expect(client.body.cancelled, isTrue);
        expect(client.aborted, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a client RequestAbortedException in the body is cancelled', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        client.body.addError(http.RequestAbortedException(_url));
        async.flushMicrotasks();

        expect(
          recorder.errors.single,
          _transportFailure(TransportFailure.cancelled),
        );
        expect(recorder.done, isTrue);
      });
    });

    test('idleTimeout fires when no bytes arrive', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(honourAbort: false);
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          idleTimeout: _idle,
        );
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        async.elapse(_idle - const Duration(milliseconds: 1));
        expect(recorder.errors, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        expect(recorder.errors.single, _timeoutAfter(_idle));
        expect(recorder.done, isTrue);
        expect(client.aborted, isTrue);
        expect(client.body.cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('the idle timer starts when the body is listened to', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          idleTimeout: _idle,
        );
        async.elapse(_idle * 3);
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        async.elapse(_idle - const Duration(milliseconds: 1));
        expect(recorder.errors, isEmpty);
        expect(client.aborted, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(recorder.errors.single, _timeoutAfter(_idle));
      });
    });

    test('idleTimeout restarts on a chunk', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          idleTimeout: _idle,
        );
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        async.elapse(const Duration(seconds: 8));
        client.body.add(utf8.encode(': ping\n'));
        async.elapse(const Duration(seconds: 8));
        expect(recorder.errors, isEmpty);
        expect(recorder.bytes, utf8.encode(': ping\n'));

        async.elapse(const Duration(seconds: 2));
        expect(recorder.errors.single, _timeoutAfter(_idle));
      });
    });

    test('idleTimeout stops while the subscription is paused', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(
          client,
          idleTimeout: _idle,
        );
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        async.elapse(const Duration(seconds: 5));
        recorder.subscription.pause();
        async.elapse(const Duration(minutes: 5));
        expect(recorder.errors, isEmpty);
        expect(client.body.paused, isTrue);
        expect(client.aborted, isFalse);

        recorder.subscription.resume();
        async.elapse(_idle - const Duration(milliseconds: 1));
        expect(recorder.errors, isEmpty);
        expect(client.body.paused, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(recorder.errors.single, _timeoutAfter(_idle));
      });
    });

    test('no idle timeout when idleTimeout is null', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        async.elapse(const Duration(hours: 1));

        expect(recorder.errors, isEmpty);
        expect(recorder.done, isFalse);
        expect(client.aborted, isFalse);
        expect(async.pendingTimers, isEmpty);

        client.body
          ..add(_bytes(1))
          ..close();
        async.flushMicrotasks();
        expect(recorder.bytes, _bytes(1));
        expect(recorder.done, isTrue);
      });
    });
  });

  group('stack traces (review M5)', () {
    test(
      'sendCapped: a client failure before the headers keeps no client trace',
      () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(
            error: _markedClientException(),
            errorTrace: _markedTrace,
          );
          final Outcome<CappedResponse> outcome = _sendCapped(client);
          async.flushMicrotasks();

          expect(outcome.error, _transportFailure(TransportFailure.network));
          expect(outcome.trace.toString(), isNot(contains('TRACE_MARKER')));
        });
      },
    );

    test('sendCapped: a body stream failure keeps no client trace', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<CappedResponse> outcome = _sendCapped(client);
        client.body.addError(_markedClientException(), _markedTrace);
        async.flushMicrotasks();

        expect(outcome.error, _transportFailure(TransportFailure.network));
        expect(outcome.trace.toString(), isNot(contains('TRACE_MARKER')));
      });
    });

    test(
      'sendStreaming: a client failure before the headers keeps no client trace',
      () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(
            error: _markedClientException(),
            errorTrace: _markedTrace,
          );
          final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
          async.flushMicrotasks();

          expect(outcome.error, _transportFailure(TransportFailure.network));
          expect(outcome.trace.toString(), isNot(contains('TRACE_MARKER')));
        });
      },
    );

    test('sendStreaming: a body stream failure keeps no client trace', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<http.StreamedResponse> outcome = _sendStreaming(client);
        async.flushMicrotasks();
        final BodyRecorder recorder = BodyRecorder(outcome.value!.stream);
        client.body.addError(_markedClientException(), _markedTrace);
        async.flushMicrotasks();

        expect(
          recorder.errors.single,
          _transportFailure(TransportFailure.network),
        );
        expect(
          recorder.traces.single.toString(),
          isNot(contains('TRACE_MARKER')),
        );
      });
    });

    test('readCapped: a stream failure keeps no client trace', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(body);
        body.addError(_markedClientException(), _markedTrace);
        async.flushMicrotasks();

        expect(outcome.error, _transportFailure(TransportFailure.network));
        expect(outcome.trace.toString(), isNot(contains('TRACE_MARKER')));
      });
    });
  });

  group('redaction of a ClientException message', () {
    String? detailOf(Uri url, String message, {Map<String, String>? headers}) {
      return fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(
          error: http.ClientException(message, url),
        );
        final Outcome<CappedResponse> outcome = _sendCapped(
          client,
          url: url,
          headers: headers,
        );
        async.flushMicrotasks();
        return (outcome.error! as TransportException).detail;
      });
    }

    test('overlapping secrets are redacted as one run', () {
      final String? detail = detailOf(
        Uri.parse('https://api.example.test/v1?a=abcd&b=cdSECRET'),
        'xxabcdSECRETyy',
      );

      expect(detail, 'xx<redacted>yy');
    });

    test('a request header value in the message is redacted', () {
      final String? detail = detailOf(
        Uri.parse('https://api.example.test/v1'),
        'refused HEADERSECRET!',
        headers: const <String, String>{'x-goog-api-key': 'HEADERSECRET'},
      );

      expect(detail, 'refused <redacted>!');
    });

    test('a query value with %0A is redacted in its decoded form', () {
      final String? detail = detailOf(
        Uri.parse('https://api.example.test/v1?k=ab%0Acd'),
        'value ab\ncd end',
      );

      expect(detail, 'value <redacted> end');
    });

    test('a query value with %0A is redacted as written', () {
      final String? detail = detailOf(
        Uri.parse('https://api.example.test/v1?k=ab%0Acd'),
        'value ab%0Acd end',
      );

      expect(detail, 'value <redacted> end');
    });
  });

  group('sanitizeServerText', () {
    test('control characters are removed', () {
      expect(
        sanitizeServerText('a\u0000b\u001fc\u007fd\u0080e\u009ff g h\n\r\t'),
        'abcdef g h',
      );
    });

    test('a cut inside a multi-byte character drops the whole character', () {
      expect(sanitizeServerText('${'a' * 1023}é'), 'a' * 1023);
      expect(sanitizeServerText('${'a' * 1022}€'), 'a' * 1022);
      expect(sanitizeServerText('${'a' * 1021}😀'), 'a' * 1021);
    });

    test('exactly 1024 bytes are kept', () {
      expect(sanitizeServerText('a' * 1024), 'a' * 1024);
      expect(sanitizeServerText('${'a' * 1022}é'), '${'a' * 1022}é');
      expect(sanitizeServerText('${'a' * 1020}😀'), '${'a' * 1020}😀');
      expect(sanitizeServerText('${'a' * 1024}b'), 'a' * 1024);
    });

    test('removed control characters do not count toward the cap', () {
      expect(sanitizeServerText('${'\u0000' * 10}${'a' * 1024}'), 'a' * 1024);
    });
  });

  group('caps', () {
    test('a cap crossed by many small chunks', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient();
        final Outcome<CappedResponse> outcome = _sendCapped(
          client,
          successCap: 10,
        );
        for (int i = 0; i < 4; i++) {
          client.body.add(<int>[1, 2, 3]);
        }
        client.body.close();
        async.flushMicrotasks();

        expect(
          outcome.error,
          isA<CapExceededException>().having(
            (CapExceededException e) => e.cap,
            'cap',
            10,
          ),
        );
        expect(client.aborted, isTrue);
      });
    });

    test(
      'an error body cut by many small chunks keeps exactly errorCap bytes',
      () {
        fakeAsync((FakeAsync async) {
          final FakeClient client = FakeClient(statusCode: 429);
          final Outcome<CappedResponse> outcome = _sendCapped(
            client,
            errorCap: 10,
          );
          for (int i = 0; i < 4; i++) {
            client.body.add(<int>[i, i, i]);
          }
          client.body.close();
          async.flushMicrotasks();

          expect(outcome.value!.body, <int>[0, 0, 0, 1, 1, 1, 2, 2, 2, 3]);
          expect(outcome.value!.truncated, isTrue);
          expect(outcome.value!.statusCode, 429);
        });
      },
    );

    test('readCapped: a cap crossed by many one-byte chunks', () {
      fakeAsync((FakeAsync async) {
        final FakeBody body = FakeBody();
        final Outcome<CappedResponse> outcome = _readCapped(body, cap: 10);
        for (int i = 0; i < 25; i++) {
          body.add(<int>[i]);
        }
        async.flushMicrotasks();

        expect(outcome.value!.body, <int>[for (int i = 0; i < 10; i++) i]);
        expect(outcome.value!.truncated, isTrue);
        expect(body.cancelled, isTrue);
      });
    });

    test('an endless body is aborted at the cap', () {
      fakeAsync((FakeAsync async) {
        final FakeClient client = FakeClient(honourAbort: false);
        client.body.feedForever(_bytes(100));
        final Outcome<CappedResponse> outcome = _sendCapped(
          client,
          successCap: 1000,
        );
        async.elapse(const Duration(seconds: 1));

        expect(
          outcome.error,
          isA<CapExceededException>().having(
            (CapExceededException e) => e.cap,
            'cap',
            1000,
          ),
        );
        expect(client.aborted, isTrue);
        expect(client.body.cancelled, isTrue);
        expect(client.body.bytesRead, lessThanOrEqualTo(1100));
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
