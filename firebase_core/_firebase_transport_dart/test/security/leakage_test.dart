// Shared specification v3, section 10 and threats T5 and T5b: no warning, toString or thrown
// error holds a token, the text of a provider's error, a rejected input or a URL's query.
//
// Every secret below contains the word SENTINEL, so a partial copy is caught too. None is a real
// token or key.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/fake_providers.dart';

const String _marker = 'SENTINEL';
const String _authToken = 'SENTINEL-AUTH-TOKEN';
const String _appCheckToken = 'SENTINEL-APPCHECK-TOKEN';
const String _limitedToken = 'SENTINEL-LIMITED-TOKEN';
const Duration _deadline = Duration(seconds: 5);

/// A provider error whose text quotes the tokens, as a careless provider's would.
final class _LeakyError implements Exception {
  const _LeakyError(this.where);

  final String where;

  @override
  String toString() =>
      '_LeakyError in $where: the request carried $_authToken and '
      '$_appCheckToken to https://api.example.test/?key=$_marker';
}

/// Everything a caller can print of [object].
List<String> _textsOf(Object? object) => <String>[
  '$object',
  if (object is TokenFetchException) '${object.causeType}',
  if (object is TransportException) ...<String>[
    '${object.detail}',
    '${object.causeType}',
  ],
  if (object is ArgumentError) ...<String>[
    '${object.message}',
    '${object.invalidValue}',
    '${object.name}',
  ],
  if (object is StateError) object.message,
  if (object is TimeoutException) '${object.message}',
  if (object is RequestTokens) '${object.origin}',
];

void _expectClean(String scenario, Iterable<Object?> objects) {
  for (final Object? object in objects) {
    for (final String text in _textsOf(object)) {
      expect(text, isNot(contains(_marker)), reason: scenario);
    }
  }
}

/// What [call] throws.
Object _thrownBy(void Function() call) {
  try {
    call();
  } on Object catch (error) {
    return error;
  }
  fail('expected a throw');
}

FakeAuthProvider _auth() => FakeAuthProvider(_authToken);

FakeLimitedUseProvider _appCheck() =>
    FakeLimitedUseProvider(token: _appCheckToken, limitedToken: _limitedToken);

/// A rig whose providers both give sentinel tokens.
TokenRig _rig(FakeAsync async) =>
    TokenRig(async, auth: _auth(), appCheck: _appCheck());

/// A client whose `send` is [_send]; it never touches the network.
final class _FakeClient extends http.BaseClient {
  _FakeClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}

void main() {
  test('sentinel never appears', () {
    fakeAsync((FakeAsync async) {
      _authThrows(async);
      _authTokenIsNotTokenText(async);
      _authTimesOut(async);
      for (final bool limited in <bool>[false, true]) {
        _appCheckSentPlaceholder(async, limited: limited);
        _appCheckEmpty(async, limited: limited);
        _appCheckProviderFailed(async, limited: limited);
        _appCheckTimedOutThenSkipped(async, limited: limited);
      }
      _appCheckUnsupported(async);
      _destinationRefused(async);
      _headersForMisuse(async);
      _rejectedInputs();
      _formatExceptionFromClient(async);
    });
  });

  test('transport failure never shows the query', _transportFailures);

  test(
    'a client that throws a FormatException quoting a header value: '
    'detail is null',
    _formatExceptions,
  );

  test(
    'reading 23: the request body dart:io quotes never reaches detail',
    _quotedBody,
  );

  _redactionRuleTests();
}

void _authThrows(FakeAsync async) {
  for (final bool atOnce in <bool>[false, true]) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider.answering(
        atOnce
            ? (bool _) => throw const _LeakyError('getAccessToken')
            : (bool _) async => throw const _LeakyError('getAccessToken'),
      ),
      appCheck: _appCheck(),
    );
    final Object error = rig.ask().error;
    expect(error, isTokenFailure(TokenFailure.authProviderFailed));
    expect((error as TokenFetchException).causeType, '$_LeakyError');
    _expectClean('Auth provider throws', <Object?>[
      error,
      rig.source,
      ...rig.warnings,
    ]);
  }
}

void _authTokenIsNotTokenText(FakeAsync async) {
  final Map<String, TokenFailure> tokens = <String, TokenFailure>{
    '$_authToken with a space': TokenFailure.authProviderFailed,
    '$_authToken\r\nSet-Cookie: $_marker': TokenFailure.authProviderFailed,
    '$_authToken\u0000': TokenFailure.authProviderFailed,
    _authToken * 500: TokenFailure.authTokenTooLong,
  };
  tokens.forEach((String token, TokenFailure failure) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(token),
      appCheck: _appCheck(),
    );
    final Object error = rig.ask().error;
    expect(error, isTokenFailure(failure));
    _expectClean('Auth token not token text', <Object?>[
      error,
      rig.source,
      ...rig.warnings,
    ]);
  });
}

void _authTimesOut(FakeAsync async) {
  final FakeAuthProvider auth = _auth()..holdCalls();
  final TokenRig rig = TokenRig(async, auth: auth, appCheck: _appCheck());
  final Probe<RequestTokens> probe = rig.ask();
  async.elapse(TokenSource.providerWait);
  expect(probe.error, isTokenFailure(TokenFailure.authTimedOut));
  // The pause: the next request fails at once.
  final Object paused = rig.ask().error;
  expect(paused, isTokenFailure(TokenFailure.authTimedOut));
  auth.waiting.single.completeError(const _LeakyError('a late answer'));
  async.flushMicrotasks();
  _expectClean('Auth timeout', <Object?>[
    probe.error,
    paused,
    rig.source,
    ...rig.warnings,
  ]);

  // The call's own deadline.
  final FakeAuthProvider slow = _auth()..holdCalls();
  final TokenRig hurried = TokenRig(async, auth: slow, appCheck: _appCheck());
  final Probe<RequestTokens> outOfTime = hurried.ask(
    timeLeft: const Duration(seconds: 1),
  );
  async.elapse(const Duration(seconds: 1));
  expect(outOfTime.error, isA<TimeoutException>());
  slow.waiting.single.complete(GetTokenResult(_authToken));
  async.flushMicrotasks();
  _expectClean('timeLeft ran out', <Object?>[
    outOfTime.error,
    ...hurried.warnings,
  ]);
}

void _appCheckSentPlaceholder(FakeAsync async, {required bool limited}) {
  final List<AppCheckTokenResult> results = <AppCheckTokenResult>[
    const AppCheckTokenResult.failure(_LeakyError('the exchange')),
    const AppCheckTokenResult(
      _appCheckToken,
      error: _LeakyError('the refresh'),
    ),
  ];
  for (final AppCheckTokenResult result in results) {
    final TokenRig rig = TokenRig(
      async,
      auth: _auth(),
      appCheck: FakeLimitedUseProvider.bothAnswering(() async => result),
    );
    final RequestTokens tokens = rig.ask(limitedUse: limited).value;
    expect(tokens.appCheck, AppCheckOutcome.sentPlaceholder);
    expect(rig.warnings, hasLength(1));
    _expectClean('App Check sentPlaceholder', <Object?>[
      tokens,
      result,
      rig.source,
      ...rig.warnings,
    ]);
  }
}

void _appCheckEmpty(FakeAsync async, {required bool limited}) {
  final List<AppCheckTokenResult> results = <AppCheckTokenResult>[
    const AppCheckTokenResult('', error: _LeakyError('a closed provider')),
    const AppCheckTokenResult('$_appCheckToken is not token text'),
    const AppCheckTokenResult('$_appCheckToken\r\nX-Injected: $_marker'),
    AppCheckTokenResult(_appCheckToken * 500),
  ];
  for (final AppCheckTokenResult result in results) {
    final TokenRig rig = TokenRig(
      async,
      auth: _auth(),
      appCheck: FakeLimitedUseProvider.bothAnswering(() async => result),
    );
    final RequestTokens tokens = rig.ask(limitedUse: limited).value;
    expect(tokens.appCheck, AppCheckOutcome.empty);
    expect(rig.warnings, hasLength(1));
    _expectClean('App Check empty', <Object?>[
      tokens,
      result,
      rig.source,
      ...rig.warnings,
    ]);
  }
}

void _appCheckProviderFailed(FakeAsync async, {required bool limited}) {
  final TokenRig rig = TokenRig(
    async,
    auth: _auth(),
    appCheck: FakeLimitedUseProvider.bothAnswering(
      () async => throw const _LeakyError('getToken'),
    ),
  );
  final RequestTokens tokens = rig.ask(limitedUse: limited).value;
  expect(tokens.appCheck, AppCheckOutcome.providerFailed);
  expect(rig.warnings, hasLength(1));
  _expectClean('App Check providerFailed', <Object?>[
    tokens,
    rig.source,
    ...rig.warnings,
  ]);
}

void _appCheckTimedOutThenSkipped(FakeAsync async, {required bool limited}) {
  final FakeLimitedUseProvider appCheck = _appCheck()
    ..holdCalls()
    ..holdLimitedCalls();
  final TokenRig rig = TokenRig(async, auth: _auth(), appCheck: appCheck);
  final Probe<RequestTokens> probe = rig.ask(limitedUse: limited);
  async.elapse(TokenSource.providerWait);
  final RequestTokens timedOut = probe.value;
  expect(timedOut.appCheck, AppCheckOutcome.timedOut);
  final RequestTokens skipped = rig.ask(limitedUse: limited).value;
  expect(skipped.appCheck, AppCheckOutcome.skipped);
  expect(rig.warnings, hasLength(1));

  final List<Completer<AppCheckTokenResult>> held = limited
      ? appCheck.limitedWaiting
      : appCheck.waiting;
  held.single.completeError(const _LeakyError('a late answer'));
  async.flushMicrotasks();
  _expectClean('App Check timedOut and skipped', <Object?>[
    timedOut,
    skipped,
    rig.source,
    ...rig.warnings,
  ]);
}

void _appCheckUnsupported(FakeAsync async) {
  final TokenRig rig = TokenRig(
    async,
    auth: _auth(),
    appCheck: FakeAppCheckProvider(_appCheckToken),
  );
  final RequestTokens tokens = rig.ask(limitedUse: true).value;
  expect(tokens.appCheck, AppCheckOutcome.unsupported);
  expect(rig.warnings, hasLength(1));
  _expectClean('App Check unsupported', <Object?>[
    tokens,
    rig.source,
    ...rig.warnings,
  ]);
}

void _destinationRefused(FakeAsync async) {
  final TokenRig rig = _rig(async);
  final List<Uri> refused = <Uri>[
    Uri.parse('https://other.example.test/$_marker?key=$_marker#$_marker'),
    Uri.parse('https://user:$_marker@api.example.test/v1/call'),
    Uri.parse('http://api.example.test/$_marker?key=$_marker'),
    Uri.parse('wss://api.example.test/$_marker?key=$_marker'),
  ];
  for (final Uri url in refused) {
    final Object error = rig.ask(url: url).error;
    expect(error, isTokenFailure(TokenFailure.destinationRefused));
    _expectClean('destination refused', <Object?>[error, ...rig.warnings]);
  }
}

void _headersForMisuse(FakeAsync async) {
  final TokenRig rig = _rig(async);
  final RequestTokens tokens = rig.ask().value;
  final Object anotherOrigin = _thrownBy(
    () => headersOf(
      tokens,
      Uri.parse('https://other.example.test/$_marker?key=$_marker'),
    ),
  );
  expect(anotherOrigin, isStateError);
  final Object userInfo = _thrownBy(
    () => headersOf(
      tokens,
      Uri.parse('https://user:$_marker@api.example.test/v1/call'),
    ),
  );
  expect(userInfo, isStateError);
  final http.Request sent = http.Request('GET', apiUrl)..finalize();
  final Object finalised = _thrownBy(
    () => applyTokens(sent, tokens, auth: AuthHeaderStyle.bearer),
  );
  expect(finalised, isStateError);

  // The tokens really are the sentinels: the one legitimate use shows them.
  expect(headersOf(tokens), <String, String>{
    'Authorization': 'Bearer $_authToken',
    'X-Firebase-AppCheck': _appCheckToken,
  });
  final Object secondUse = _thrownBy(() => headersOf(tokens));
  expect(secondUse, isStateError);
  _expectClean('headersFor with another origin and on second use', <Object?>[
    tokens,
    anotherOrigin,
    userInfo,
    finalised,
    secondUse,
    ...rig.warnings,
  ]);

  final RequestTokens limited = rig.ask(limitedUse: true).value;
  _expectClean('limited-use tokens', <Object?>[limited, ...rig.warnings]);
  expect(headersOf(limited)['X-Firebase-AppCheck'], _limitedToken);
}

void _rejectedInputs() {
  final FirebaseApp app = newTransportApp();
  final Uri leakyOrigin = Uri.parse(
    'https://user:$_marker@api.example.test/$_marker?key=$_marker#$_marker',
  );
  final List<Object> errors = <Object>[
    _thrownBy(() => EmulatorHost.parse('user:$_marker@10.0.0.5:9099')),
    _thrownBy(() => EmulatorHost.parse('$_marker:99999')),
    _thrownBy(() => EmulatorHost.parse('$_marker.googleapis.com:443')),
    _thrownBy(() => EmulatorHost.parse('$_marker..test:443')),
    _thrownBy(() => EmulatorHost('user:$_marker@host', 9099)),
    _thrownBy(() => EmulatorHost(_marker, 0)),
    _thrownBy(() => checkOrigin(leakyOrigin)),
    _thrownBy(
      () => checkOrigin(Uri.parse('http://user:$_marker@remote.example.test')),
    ),
    _thrownBy(
      () => tokenOrigin(
        Uri.parse('wss://user:$_marker@api.example.test/$_marker?k=$_marker'),
      ),
    ),
    _thrownBy(() => TokenSource(app, origins: <Uri>[leakyOrigin])),
    _thrownBy(
      () => RequestTokens.forTesting(
        origin: apiOrigin,
        authToken: '$_authToken not token text',
      ),
    ),
    _thrownBy(
      () => RequestTokens.forTesting(
        origin: apiOrigin,
        appCheckToken: '$_appCheckToken\r\nX-Injected: $_marker',
      ),
    ),
    _thrownBy(() => apiClientHeader(sdkVersion: '$_marker not a version')),
  ];
  for (final Object error in errors) {
    expect(error, isArgumentError);
  }
  _expectClean('rejected inputs', errors);
}

/// The request of the transport cases: both sentinel tokens as headers.
http.BaseRequest Function(Future<void> abort) _requestWithTokens() {
  final RequestTokens tokens = RequestTokens.forTesting(
    origin: apiOrigin,
    authToken: _authToken,
    appCheckToken: _appCheckToken,
    appCheck: AppCheckOutcome.sent,
  );
  return (Future<void> abort) {
    final http.AbortableRequest request = http.AbortableRequest(
      'POST',
      apiUrl,
      abortTrigger: abort,
    );
    applyTokens(request, tokens, auth: AuthHeaderStyle.bearer);
    return request;
  };
}

/// What `dart:io` throws for a header value with a control character: its text quotes the value.
FormatException _headerFormatException(http.BaseRequest request) =>
    FormatException(
      'Invalid HTTP header field value: '
      '"${request.headers['Authorization']}" and '
      '"${request.headers['X-Firebase-AppCheck']}"',
      request.url,
    );

void _expectNoHeaderValue(String scenario, Object error, StackTrace trace) {
  expect(
    error,
    isA<TransportException>().having(
      (TransportException e) => e.failure,
      'failure',
      TransportFailure.network,
    ),
    reason: scenario,
  );
  final TransportException failure = error as TransportException;
  expect(failure.detail, isNull, reason: scenario);
  expect(failure.causeType, '$FormatException', reason: scenario);
  expect('$failure', 'TransportException: network', reason: scenario);
  _expectClean(scenario, <Object?>[failure, trace]);
}

void _formatExceptionFromClient(FakeAsync async) {
  final _FakeClient client = _FakeClient(
    (http.BaseRequest request) => throw _headerFormatException(request),
  );
  final Probe<CappedResponse> probe = Probe<CappedResponse>(
    sendCapped(
      client,
      _requestWithTokens(),
      successCap: 1024,
      errorCap: 1024,
      deadline: _deadline,
    ),
  );
  async.flushMicrotasks();
  _expectNoHeaderValue(
    'a client that throws a FormatException',
    probe.error,
    probe.stackTrace,
  );
  expect(async.pendingTimers, isEmpty);
}

Future<void> _formatExceptions() async {
  final _FakeClient throwing = _FakeClient(
    (http.BaseRequest request) => throw _headerFormatException(request),
  );
  final _FakeClient failing = _FakeClient(
    (http.BaseRequest request) => Future<http.StreamedResponse>.error(
      _headerFormatException(request),
      StackTrace.fromString('$_marker client frame'),
    ),
  );
  final _FakeClient failingBody = _FakeClient(
    (http.BaseRequest request) async => http.StreamedResponse(
      Stream<List<int>>.error(
        _headerFormatException(request),
        StackTrace.fromString('$_marker client frame'),
      ),
      200,
      request: request,
    ),
  );
  for (final _FakeClient client in <_FakeClient>[throwing, failing]) {
    final (Object capped, StackTrace cappedTrace) = await _failureOf(
      sendCapped(
        client,
        _requestWithTokens(),
        successCap: 1024,
        errorCap: 1024,
        deadline: _deadline,
      ),
    );
    _expectNoHeaderValue('sendCapped', capped, cappedTrace);
    final (Object streaming, StackTrace streamingTrace) = await _failureOf(
      sendStreaming(client, _requestWithTokens(), headersDeadline: _deadline),
    );
    _expectNoHeaderValue('sendStreaming', streaming, streamingTrace);
  }

  final (Object body, StackTrace bodyTrace) = await _failureOf(
    sendCapped(
      failingBody,
      _requestWithTokens(),
      successCap: 1024,
      errorCap: 1024,
      deadline: _deadline,
    ),
  );
  _expectNoHeaderValue('sendCapped, from the body', body, bodyTrace);
  final http.StreamedResponse response = await sendStreaming(
    failingBody,
    _requestWithTokens(),
    headersDeadline: _deadline,
  );
  final (Object read, StackTrace readTrace) = await _failureOf(
    readCapped(response, cap: 1024, deadline: _deadline),
  );
  _expectNoHeaderValue('readCapped over sendStreaming', read, readTrace);
}

/// The error and the stack trace [future] fails with.
Future<(Object, StackTrace)> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (error, stackTrace) {
    return (error, stackTrace);
  }
  fail('expected a failure');
}

final Uri _secretUrl = Uri.parse(
  'https://api.example.test/v1/call?key=SENTINEL&x=SENTINEL2',
);

http.BaseRequest _secretRequest(Future<void> abort) =>
    http.AbortableRequest('GET', _secretUrl, abortTrigger: abort);

/// The stack trace the fake clients raise their exception with; it must not be passed on.
StackTrace _clientTrace() => StackTrace.fromString('$_marker client frame');

/// The client's exceptions: the one 11.4 names, and one whose message quotes the URL too.
List<http.ClientException> _clientExceptions() => <http.ClientException>[
  http.ClientException('refused', _secretUrl),
  http.ClientException(
    'Connection refused: GET $_secretUrl (key=SENTINEL, x=SENTINEL2)',
    _secretUrl,
  ),
];

/// A body that gives one chunk and then fails with [cause].
Stream<List<int>> _failingBody(Object cause) =>
    Stream<List<int>>.multi((MultiStreamController<List<int>> controller) {
      controller
        ..add(<int>[1, 2, 3])
        ..addError(cause, _clientTrace())
        ..close();
    });

void _expectNoQuery(
  String scenario,
  (Object, StackTrace) thrown,
  http.ClientException cause,
) {
  final (Object error, StackTrace trace) = thrown;
  expect(
    error,
    isA<TransportException>().having(
      (TransportException e) => e.failure,
      'failure',
      TransportFailure.network,
    ),
    reason: scenario,
  );
  final TransportException failure = error as TransportException;
  // Nothing of the client's exception is kept: not the object, not its stack trace.
  expect(failure.runtimeType, TransportException, reason: scenario);
  expect(identical(failure, cause), isFalse, reason: scenario);
  expect('$failure', 'TransportException: network', reason: scenario);
  expect(failure.causeType, '${cause.runtimeType}', reason: scenario);
  expect(failure.detail, isNotNull, reason: scenario);
  if (cause.message == 'refused') {
    expect(failure.detail, 'refused', reason: scenario);
  }
  _expectClean(scenario, <Object?>[failure, trace]);
}

Future<void> _transportFailures() async {
  for (final http.ClientException cause in _clientExceptions()) {
    final _FakeClient throwing = _FakeClient(
      (http.BaseRequest _) => Error.throwWithStackTrace(cause, _clientTrace()),
    );
    final _FakeClient failing = _FakeClient(
      (http.BaseRequest _) =>
          Future<http.StreamedResponse>.error(cause, _clientTrace()),
    );
    for (final _FakeClient client in <_FakeClient>[throwing, failing]) {
      _expectNoQuery(
        'sendCapped, the client throws',
        await _failureOf(
          sendCapped(
            client,
            _secretRequest,
            successCap: 1024,
            errorCap: 1024,
            deadline: _deadline,
          ),
        ),
        cause,
      );
      _expectNoQuery(
        'sendStreaming, before the headers',
        await _failureOf(
          sendStreaming(client, _secretRequest, headersDeadline: _deadline),
        ),
        cause,
      );
    }
    await _bodyFailures(cause);
  }
}

/// The cases where the body stream raises [cause] after the headers arrived.
Future<void> _bodyFailures(http.ClientException cause) async {
  final _FakeClient client = _FakeClient(
    (http.BaseRequest request) async =>
        http.StreamedResponse(_failingBody(cause), 200, request: request),
  );
  _expectNoQuery(
    'sendCapped, the body stream raises',
    await _failureOf(
      sendCapped(
        client,
        _secretRequest,
        successCap: 1024,
        errorCap: 1024,
        deadline: _deadline,
      ),
    ),
    cause,
  );

  final http.StreamedResponse streamed = await sendStreaming(
    client,
    _secretRequest,
    headersDeadline: _deadline,
  );
  _expectNoQuery(
    'sendStreaming, during the body',
    await _failureOf(streamed.stream.drain<void>()),
    cause,
  );

  final http.StreamedResponse forRead = await sendStreaming(
    client,
    _secretRequest,
    headersDeadline: _deadline,
  );
  _expectNoQuery(
    'readCapped over the body of sendStreaming',
    await _failureOf(readCapped(forRead, cap: 1024, deadline: _deadline)),
    cause,
  );

  // readCapped on a client's own response: with its request, and without one (the exception's
  // own URL is then the only one known).
  for (final http.BaseRequest? request in <http.BaseRequest?>[
    http.Request('GET', _secretUrl),
    null,
  ]) {
    final http.StreamedResponse plain = http.StreamedResponse(
      _failingBody(cause),
      200,
      request: request,
    );
    _expectNoQuery(
      'readCapped, the body stream raises',
      await _failureOf(readCapped(plain, cap: 1024, deadline: _deadline)),
      cause,
    );
  }
}

/// What `dart:io` says when a request writes more than its content length: the message ends with
/// a chunk of the request body in brackets.
Future<void> _quotedBody() async {
  const String kept =
      'Content size exceeds specified contentLength. 9 bytes written while '
      'expected 4.';
  final http.ClientException cause = http.ClientException(
    '$kept [$_marker-BODY]',
    apiUrl,
  );
  final List<_FakeClient> clients = <_FakeClient>[
    _FakeClient(
      (http.BaseRequest _) => Error.throwWithStackTrace(cause, _clientTrace()),
    ),
    _FakeClient(
      (http.BaseRequest _) =>
          Future<http.StreamedResponse>.error(cause, _clientTrace()),
    ),
    _FakeClient(
      (http.BaseRequest request) async =>
          http.StreamedResponse(_failingBody(cause), 200, request: request),
    ),
  ];
  for (final _FakeClient client in clients) {
    final (Object error, StackTrace trace) = await _failureOf(
      sendCapped(
        client,
        (Future<void> abort) =>
            http.AbortableRequest('POST', apiUrl, abortTrigger: abort)
              ..body = '$_marker-BODY',
        successCap: 1024,
        errorCap: 1024,
        deadline: _deadline,
      ),
    );
    expect(error, isA<TransportException>());
    final TransportException failure = error as TransportException;
    expect(failure.failure, TransportFailure.network);
    expect(failure.detail, kept);
    expect(failure.causeType, '${cause.runtimeType}');
    expect('$failure', 'TransportException: network');
    _expectClean('a quoted request body', <Object?>[failure, trace]);
  }
}

/// The `detail` of the failure [sendCapped] throws when the client fails a request to [url] with
/// an `http.ClientException` of [message], after checking that nothing printable of the failure
/// or of its stack trace holds the marker.
Future<String?> _detailFor(
  Uri url,
  String message, {
  Uri? errorUri,
  Map<String, String> headers = const <String, String>{},
}) async {
  final http.ClientException cause = http.ClientException(message, errorUri);
  final _FakeClient client = _FakeClient(
    (http.BaseRequest _) =>
        Future<http.StreamedResponse>.error(cause, _clientTrace()),
  );
  final (Object error, StackTrace trace) = await _failureOf(
    sendCapped(
      client,
      (Future<void> abort) =>
          http.AbortableRequest('GET', url, abortTrigger: abort)
            ..headers.addAll(headers),
      successCap: 1024,
      errorCap: 1024,
      deadline: _deadline,
    ),
  );
  expect(error, isA<TransportException>());
  final TransportException failure = error as TransportException;
  expect('$failure', 'TransportException: network');
  expect(failure.causeType, '${cause.runtimeType}');
  _expectClean('redaction of "$message"', <Object?>[failure, trace]);
  return failure.detail;
}

/// One test per redaction rule of `TransportException.detail` (5.13): each message holds a
/// secret in a form that only the rule under test covers, so the test fails when that rule goes.
void _redactionRuleTests() {
  final Uri plainUrl = Uri.parse('https://api.example.test/v1/call');

  group('redaction rules', () {
    test('the URL itself', () async {
      final Uri url = Uri.parse('https://api.example.test/$_marker-PATH/call');
      expect(
        await _detailFor(url, 'Connection refused: GET $url failed'),
        'Connection refused: GET <redacted> failed',
      );
    });

    test('the query', () async {
      // The marker is a query key: keys are covered only by the query as a whole.
      final Uri url = Uri.parse('$plainUrl?${_marker}KEY=1&x=2');
      expect(
        await _detailFor(url, 'bad query ${_marker}KEY=1&x=2 in the request'),
        'bad query <redacted> in the request',
      );
    });

    test('a query value as written', () async {
      final Uri url = Uri.parse('$plainUrl?key=$_marker%20a+b%2Fc');
      expect(
        await _detailFor(url, 'bad value $_marker%20a+b%2Fc here'),
        'bad value <redacted> here',
      );
    });

    test('a query value percent-decoded', () async {
      final Uri url = Uri.parse('$plainUrl?key=$_marker%20a+b%2Fc');
      expect(
        await _detailFor(url, 'bad value $_marker a+b/c here'),
        'bad value <redacted> here',
      );
    });

    test('a query value query-decoded', () async {
      final Uri url = Uri.parse('$plainUrl?key=$_marker%20a+b%2Fc');
      expect(
        await _detailFor(url, 'bad value $_marker a b/c here'),
        'bad value <redacted> here',
      );
    });

    test('each query value, not only the first', () async {
      final Uri url = Uri.parse('$plainUrl?a=$_marker-ONE&b=$_marker-TWO');
      expect(
        await _detailFor(url, 'saw $_marker-TWO then $_marker-ONE'),
        'saw <redacted> then <redacted>',
      );
    });

    test('the uri of the ClientException', () async {
      final Uri elsewhere = Uri.parse(
        'https://other.example.test/$_marker-PATH?token=$_marker-URI',
      );
      expect(
        await _detailFor(
          plainUrl,
          'redirected to $elsewhere',
          errorUri: elsewhere,
        ),
        'redirected to <redacted>',
      );
      expect(
        await _detailFor(
          plainUrl,
          'the token $_marker-URI was refused',
          errorUri: elsewhere,
        ),
        'the token <redacted> was refused',
      );
    });

    test('a request header value of 4 or more characters', () async {
      expect(
        await _detailFor(
          plainUrl,
          'Invalid header value $_marker-KEY for the request',
          headers: <String, String>{'X-Goog-Api-Key': '$_marker-KEY'},
        ),
        'Invalid header value <redacted> for the request',
      );
    });

    test('a value of 4 characters is redacted, one of 3 is not', () async {
      final Uri url = Uri.parse('$plainUrl?a=zq9&b=zq84');
      expect(
        await _detailFor(
          url,
          'values zq9 | zq84 | hx7 | hx64',
          headers: <String, String>{'X-Short': 'hx7', 'X-Long': 'hx64'},
        ),
        'values zq9 | <redacted> | hx7 | <redacted>',
      );
    });

    test('the ". [" cut', () async {
      expect(
        await _detailFor(
          plainUrl,
          'Content size exceeds specified contentLength. 9 bytes written '
          'while expected 4. [$_marker-BODY]',
        ),
        'Content size exceeds specified contentLength. 9 bytes written '
        'while expected 4.',
      );
      // A message without the bracketed chunk is kept whole.
      expect(await _detailFor(plainUrl, 'refused. Retry'), 'refused. Retry');
    });
  });
}
