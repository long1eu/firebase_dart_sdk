import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/platform.dart' show Visibility;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The start of fake time in every realtime test.
final DateTime rcEpoch = DateTime.utc(2026, 11, 28);

/// Options whose `appId` carries the project number `1234567890`.
const FirebaseOptions rcOptions = FirebaseOptions(
  apiKey: 'AIzaSyRealtimeTestKey0000000000000000000',
  appId: '1:1234567890:web:0123456789abcdef',
  projectId: 'demo-realtime',
  messagingSenderId: '1234567890',
);

/// The realtime origin the tests pass to the client.
final Uri rcRealtimeOrigin = Uri.parse('https://realtime.rc.test');

/// The fetch origin the tests pass to the client.
final Uri rcServerOrigin = Uri.parse('https://fetch.rc.test');

/// The first installation id of [FakeInstallations].
const String rcFirstFid = 'fAAAAAAAAAAAAAAAAAAAAA';

/// The id [FakeInstallations.changeId] usually switches to.
const String rcSecondFid = 'fBBBBBBBBBBBBBBBBBBBBB';

/// How the fake server answers one realtime request.
typedef RealtimeAnswer =
    Future<http.StreamedResponse> Function(RealtimeConnection connection);

/// How the fake server answers one fetch request.
typedef FetchAnswer = http.Response Function(FetchCall call);

/// One realtime request the fake server received, with a body the test feeds.
final class RealtimeConnection {
  RealtimeConnection._(this.request, this.body, this.openedAt) {
    final http.BaseRequest request = this.request;
    if (request is http.Abortable) {
      final Future<void>? trigger = request.abortTrigger;
      if (trigger != null) {
        unawaited(trigger.whenComplete(_onAbort));
      }
    }
  }

  /// The request as the client sent it.
  final http.BaseRequest request;

  /// The JSON body of the request.
  final Map<String, Object?> body;

  /// The fake time the request arrived.
  final DateTime openedAt;

  final StreamController<List<int>> _controller = StreamController<List<int>>();
  bool _accepted = false;
  bool _cancelled = false;

  /// True once the client completed the request's `abortTrigger`.
  bool aborted = false;

  /// True while the body was accepted and neither side ended it.
  bool get isOpen =>
      _accepted && !aborted && !_controller.isClosed && !_cancelled;

  /// Answers 200 with a body the test feeds through [send], [end] and [fail].
  Future<http.StreamedResponse> accept() {
    _accepted = true;
    _controller.onCancel = () {
      _cancelled = true;
    };
    return Future<http.StreamedResponse>.value(
      http.StreamedResponse(_controller.stream, 200, request: request),
    );
  }

  /// Answers 200 with a body that ends at once.
  Future<http.StreamedResponse> acceptAndClose() {
    final Future<http.StreamedResponse> response = accept();
    unawaited(_controller.close());
    return response;
  }

  /// Answers [status] with [text] as the body.
  Future<http.StreamedResponse> refuse(int status, [String text = '']) {
    return Future<http.StreamedResponse>.value(
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(text)),
        status,
        request: request,
      ),
    );
  }

  /// Fails the request without a response (a transport failure).
  Future<http.StreamedResponse> drop() {
    return Future<http.StreamedResponse>.error(
      http.ClientException('Connection refused (fake)', request.url),
    );
  }

  /// Sends [text] as one chunk of the body.
  void send(String text) {
    if (isOpen) {
      _controller.add(utf8.encode(text));
    }
  }

  /// Ends the body cleanly.
  void end() {
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  /// Ends the body with a transport error.
  void fail() {
    if (isOpen) {
      _controller.addError(http.ClientException('Connection reset (fake)'));
      unawaited(_controller.close());
    }
  }

  void _onAbort() {
    aborted = true;
    if (_accepted && !_controller.isClosed && !_cancelled) {
      _controller.addError(http.RequestAbortedException(request.url));
      unawaited(_controller.close());
    }
  }
}

/// One fetch request the fake server received.
final class FetchCall {
  FetchCall._(this.request, this.body, this.at);

  /// The request as the client sent it.
  final http.BaseRequest request;

  /// The JSON body of the request.
  final Map<String, Object?> body;

  /// The fake time the request arrived.
  final DateTime at;

  /// The `X-Firebase-RC-Fetch-Type` header.
  String? get fetchType => request.headers['X-Firebase-RC-Fetch-Type'];
}

/// A fetch answer of 200 with [entries] and [version].
http.Response templateResponse({
  required int version,
  Map<String, String> entries = const <String, String>{'welcome': 'hi'},
}) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'state': 'UPDATE',
      'entries': entries,
      'templateVersion': '$version',
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// A `MockClient` that plays both Remote Config servers: the realtime stream and the fetch endpoint.
///
/// Realtime bodies honour the request's `abortTrigger` (`PKG:http-1.6.0/lib/src/mock_client.dart:31-33`
/// leaves that to the handler): an abort ends an accepted body with `RequestAbortedException`.
final class RealtimeServer {
  /// Creates the server; [now] stamps each request with fake time.
  RealtimeServer(this.now) {
    client = MockClient.streaming(_handle);
  }

  /// The fake clock.
  final DateTime Function() now;

  /// The client to pass as `httpClient`.
  late final MockClient client;

  /// Every realtime request, in order.
  final List<RealtimeConnection> connections = <RealtimeConnection>[];

  /// Every fetch request, in order.
  final List<FetchCall> fetches = <FetchCall>[];

  /// How the next realtime requests are answered. Default: accept and hold.
  RealtimeAnswer realtimeAnswer = (RealtimeConnection connection) =>
      connection.accept();

  /// How the next fetch requests are answered. Default: version 1.
  FetchAnswer fetchAnswer = (FetchCall call) => templateResponse(version: 1);

  /// The last realtime request.
  RealtimeConnection get last => connections.last;

  /// The fake times of the realtime requests, as offsets from [rcEpoch].
  List<Duration> get connectionTimes => <Duration>[
    for (final RealtimeConnection connection in connections)
      connection.openedAt.difference(rcEpoch),
  ];

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream bodyStream,
  ) async {
    final String text = utf8.decode(await bodyStream.toBytes());
    final Map<String, Object?> body = text.isEmpty
        ? const <String, Object?>{}
        : (jsonDecode(text) as Map<String, Object?>);
    if (request.url.path.endsWith(':streamFetchInvalidations')) {
      final RealtimeConnection connection = RealtimeConnection._(
        request,
        body,
        now(),
      );
      connections.add(connection);
      return realtimeAnswer(connection);
    }
    final FetchCall call = FetchCall._(request, body, now());
    fetches.add(call);
    final http.Response response = fetchAnswer(call);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

/// A [FirebaseInstallations] with a fixed FID and token and scripted failures.
final class FakeInstallations implements FirebaseInstallations {
  /// Creates the fake; [app] is needed only when a caller reads it.
  FakeInstallations(this.now, {FirebaseApp? app}) : _app = app;

  /// The fake clock that stamps [callTimes].
  final DateTime Function() now;
  final FirebaseApp? _app;
  final StreamController<String> _idChanges =
      StreamController<String>.broadcast();

  @override
  final KeyValueStore store = MemoryKeyValueStore();

  @override
  final Map<String, String> headers = const <String, String>{};

  /// The FID [getIdAndToken] returns.
  String fid = rcFirstFid;

  /// The token [getIdAndToken] returns.
  String token = 'fake-installations-token';

  /// Thrown, in order, by the next calls of [getIdAndToken].
  final List<Exception> errors = <Exception>[];

  /// Thrown by every call of [getIdAndToken] while set (after [errors] is empty).
  Exception? alwaysThrow;

  /// The fake times of the calls of [getIdAndToken].
  final List<DateTime> callTimes = <DateTime>[];

  @override
  FirebaseApp get app =>
      _app ?? (throw StateError('FakeInstallations has no app'));

  @override
  Stream<String> get onIdChange => _idChanges.stream;

  @override
  Future<({String id, String token})> getIdAndToken({
    bool forceRefresh = false,
  }) async {
    callTimes.add(now());
    if (errors.isNotEmpty) {
      throw errors.removeAt(0);
    }
    final Exception? always = alwaysThrow;
    if (always != null) {
      throw always;
    }
    return (id: fid, token: token);
  }

  /// Switches to [id] and emits it on [onIdChange].
  void changeId(String id) {
    fid = id;
    _idChanges.add(id);
  }

  @override
  Future<void> close() async {
    await _idChanges.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A `bool` stream that replays its current value on listen, as the app's `BehaviorSubject`s do.
final class ReplayingBool {
  /// Starts at [value].
  ReplayingBool(this.value);

  /// The current value.
  bool value;

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  /// The stream: the current value, then each change.
  Stream<bool> get stream =>
      Stream<bool>.multi((MultiStreamController<bool> controller) {
        controller.add(value);
        final StreamSubscription<bool> subscription = _changes.stream.listen(
          controller.add,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      });

  /// Changes the value and emits it.
  void add(bool next) {
    value = next;
    _changes.add(next);
  }
}

/// A page visibility the test controls.
final class FakeVisibility implements Visibility {
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  bool isHidden = false;

  @override
  Stream<bool> get changes => _changes.stream;

  /// Sets [isHidden] and emits it.
  void setHidden(bool hidden) {
    isHidden = hidden;
    _changes.add(hidden);
  }
}

/// What a listener of `onConfigUpdated` received.
final class UpdateLog {
  /// The updates, in order.
  final List<RemoteConfigUpdate> updates = <RemoteConfigUpdate>[];

  /// The errors, in order.
  final List<Object> errors = <Object>[];

  /// True once the stream ended.
  bool done = false;

  /// The codes of the [errors] that are [FirebaseRemoteConfigException]s.
  List<String> get codes => <String>[
    for (final Object error in errors)
      if (error is FirebaseRemoteConfigException) error.code,
  ];

  /// The subscription made by [listen].
  StreamSubscription<RemoteConfigUpdate>? subscription;

  /// Listens to [stream] without `cancelOnError`.
  void listen(Stream<RemoteConfigUpdate> stream) {
    subscription = stream.listen(
      updates.add,
      onError: (Object error) => errors.add(error),
      onDone: () => done = true,
    );
  }

  /// Cancels the subscription made by [listen].
  void cancel() {
    unawaited(subscription?.cancel());
  }
}
