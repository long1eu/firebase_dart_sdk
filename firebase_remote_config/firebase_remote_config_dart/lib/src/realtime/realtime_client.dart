import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_remote_config_dart/src/exception.dart';
import 'package:firebase_remote_config_dart/src/fetch_client.dart';
import 'package:firebase_remote_config_dart/src/http_rules.dart';
import 'package:firebase_remote_config_dart/src/logger.dart';
import 'package:firebase_remote_config_dart/src/platform.dart';
import 'package:firebase_remote_config_dart/src/realtime/auto_fetch.dart';
import 'package:firebase_remote_config_dart/src/realtime/framer.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/types.dart';
import 'package:firebase_remote_config_dart/src/version.dart';
import 'package:http/http.dart' as http;

/// The realtime client of 5.9: opens the invalidation stream while someone listens, backs off on
/// failures (5.9.1), runs the auto-fetch (5.9.2), and honours `featureDisabled` (5.9.3).
///
/// It takes every collaborator through its constructor so it can run on its own.
final class RealtimeClient {
  /// Creates the client. [backgroundChanged] and [networkConnected] replay their current value on
  /// listen (as the app's `BehaviorSubject`s do). The first event of [backgroundChanged] is skipped:
  /// the client reads the current state through [isInBackground] and acts on each later event. The
  /// first event of [networkConnected] is kept as the starting value: only a later `false` to `true`
  /// change acts (A11, A20); a stream that replays nothing makes its first real event the seed.
  /// [delay] replaces the auto-fetch wait (see [AutoFetcher]).
  ///
  /// When [ready] is given, a connect waits for it (its error too), so the backoff that
  /// [restoreBackoff] brings back applies to the first connect. [onBackoffChanged] receives each
  /// change of the failure counts and waits, to persist it.
  RealtimeClient({
    required FirebaseOptions options,
    required FirebaseInstallations installations,
    required Future<FetchResult> Function(int attempt) fetchForRealtime,
    required TemplateRecords Function() templates,
    required bool Function() isInBackground,
    required Stream<bool> backgroundChanged,
    required Stream<bool> networkConnected,
    required Visibility visibility,
    required http.Client httpClient,
    required Uri origin,
    required DateTime Function() clock,
    required double Function() random,
    Future<void> Function(Duration duration)? delay,
    RemoteConfigLogger? logger,
    Future<void>? ready,
    void Function(RealtimeBackoffRecord record)? onBackoffChanged,
  }) : _options = options,
       _ready = ready,
       _isReady = ready == null,
       _onBackoffChanged = onBackoffChanged,
       _installations = installations,
       _templates = templates,
       _isInBackground = isInBackground,
       _visibility = visibility,
       _client = httpClient,
       _origin = origin,
       _clock = clock,
       _random = random,
       _logger = logger,
       _projectNumber = projectNumberOf(options) {
    _autoFetcher = AutoFetcher(
      fetchForRealtime: fetchForRealtime,
      templates: templates,
      random: random,
      delay: delay,
      clock: clock,
      closed: _closedSignal.future,
      onUpdate: _emitUpdate,
      onError: _emitError,
    );
    if (ready != null) {
      unawaited(
        ready.then<void>(
          (void _) => _isReady = true,
          onError: (Object _) => _isReady = true,
        ),
      );
    }
    _subscriptions.addAll(<StreamSubscription<bool>>[
      backgroundChanged.skip(1).listen((bool _) => _evaluate()),
      // Not skipped: the seed is the value a later `true` is compared with.
      networkConnected.listen(_onNetwork),
      visibility.changes.listen((bool _) => _evaluate()),
    ]);
  }

  /// The waits of server failures, in minutes (entry `min(n, 8)`).
  static const List<int> serverWaitMinutes = <int>[
    2,
    4,
    8,
    16,
    32,
    64,
    128,
    256,
  ];

  /// The waits of transport failures, in seconds (entry `min(n, 9)`).
  static const List<int> transportWaitSeconds = <int>[
    1,
    2,
    4,
    8,
    16,
    32,
    60,
    120,
    300,
  ];

  /// How long a connection stays open, from sending the request, to count as a success.
  static const Duration successAfter = Duration(seconds: 60);

  /// A connection without a byte for this long, counted from sending the request (the headers count as
  /// bytes), ends as a clean end; during an error body it ends with that status's outcome.
  static const Duration watchdog = Duration(seconds: 330);

  /// Consecutive failures after which listeners get one `stream-error`.
  static const int failuresBeforeError = 8;

  /// The latest a timer is scheduled ahead.
  static const Duration maxTimer = Duration(hours: 24);

  final FirebaseOptions _options;
  final FirebaseInstallations _installations;
  final TemplateRecords Function() _templates;
  final bool Function() _isInBackground;
  final Visibility _visibility;
  final http.Client _client;
  final Uri _origin;
  final DateTime Function() _clock;
  final double Function() _random;
  final RemoteConfigLogger? _logger;
  final String? _projectNumber;
  final Future<void>? _ready;
  final void Function(RealtimeBackoffRecord record)? _onBackoffChanged;
  final Completer<void> _closedSignal = Completer<void>();
  final List<StreamSubscription<bool>> _subscriptions =
      <StreamSubscription<bool>>[];
  final Set<MultiStreamController<RemoteConfigUpdate>> _listeners =
      <MultiStreamController<RemoteConfigUpdate>>{};
  late final AutoFetcher _autoFetcher;

  bool _closed = false;
  bool _disabled = false;
  bool _stopped = false;
  bool _ended = false;
  _Connection? _connection;
  Timer? _reconnectTimer;
  DateTime? _serverBackoffUntil;
  DateTime? _transportBackoffUntil;
  DateTime? _floorUntil;
  DateTime? _serverRetryUntil;
  int _serverFailures = 0;
  int _transportFailures = 0;
  bool _failureErrorSent = false;
  bool? _networkConnected;
  bool _isReady;
  RealtimeBackoffRecord _persisted = const RealtimeBackoffRecord();

  /// The stream of `onConfigUpdated`. Each listen counts; the connection is open while at least one
  /// listener remains (and the other rules of 5.9 allow it).
  Stream<RemoteConfigUpdate> get stream =>
      Stream<RemoteConfigUpdate>.multi(_onListen, isBroadcast: true);

  /// Reconnects a connection whose body names another FID than [fid] (5.9.5). A connection still
  /// waiting for Installations is left alone: it gets the current id when that call returns.
  void onInstallationIdChanged(String fid) {
    final String? used = _connection?.installationId;
    if (used == null || used == fid) {
      return;
    }
    _abortConnection();
    _evaluate();
  }

  /// Takes the failure counts and waits of [record], as stored by an earlier run. Call it before
  /// the `ready` future of the constructor completes; it replaces the current counts and waits.
  void restoreBackoff(RealtimeBackoffRecord record) {
    _serverFailures = record.serverFailures;
    _transportFailures = record.transportFailures;
    _serverBackoffUntil = record.serverUntil;
    _transportBackoffUntil = record.transportUntil;
    _serverRetryUntil = record.retryUntil;
    _persisted = record;
  }

  /// Ends every listener's stream, aborts the connection and cancels every timer. Idempotent.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _closedSignal.complete();
    _abortConnection();
    _cancelTimer();
    // Not awaited: cancelling takes effect at once, and the returned futures can complete outside the
    // caller's zone (fake_async tests never see them complete).
    for (final StreamSubscription<bool> subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _closeListeners();
  }

  void _onListen(MultiStreamController<RemoteConfigUpdate> controller) {
    if (_closed || _ended) {
      controller.closeSync();
      return;
    }
    if (_disabled) {
      controller
        ..addErrorSync(_unavailable())
        ..closeSync();
      return;
    }
    _listeners.add(controller);
    // A listen made after a stop starts the stream again.
    _stopped = false;
    controller.onCancel = () {
      _listeners.remove(controller);
      _evaluate();
    };
    _evaluate();
  }

  bool get _shouldConnect =>
      !_closed &&
      !_disabled &&
      !_stopped &&
      !_ended &&
      _listeners.isNotEmpty &&
      !_isInBackground() &&
      !_visibility.isHidden;

  void _evaluate() {
    if (!_shouldConnect) {
      _abortConnection();
      _cancelTimer();
      return;
    }
    if (_connection != null || _reconnectTimer != null) {
      return;
    }
    _schedule();
  }

  void _schedule() {
    final DateTime now = _clock();
    DateTime at = now;
    for (final DateTime? limit in <DateTime?>[
      _serverBackoffUntil,
      _transportBackoffUntil,
      _floorUntil,
      _serverRetryUntil,
    ]) {
      if (limit != null && limit.isAfter(at)) {
        at = limit;
      }
    }
    Duration wait = at.difference(now);
    final bool capped = wait > maxTimer;
    if (capped) {
      wait = maxTimer;
    }
    _reconnectTimer = Timer(wait, () {
      _reconnectTimer = null;
      if (!_shouldConnect) {
        return;
      }
      if (capped) {
        _schedule();
        return;
      }
      unawaited(_connect());
    });
  }

  void _cancelTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _onNetwork(bool connected) {
    final bool? previous = _networkConnected;
    _networkConnected = connected;
    // The first event is the seed; repeated `true`s are not a change.
    if (previous == null || previous || !connected) {
      return;
    }
    // A regained network allows a connect at once, subject to the floor (5.9.1): the failure backoffs
    // are cleared. The server failure count stays, so the next server failure waits longer, and the
    // server's own `retryIntervalSeconds` wait stays, because the server asked for it.
    _transportFailures = 0;
    _transportBackoffUntil = null;
    _serverBackoffUntil = null;
    _persistBackoff();
    _cancelTimer();
    _evaluate();
  }

  Future<void> _connect() async {
    final _Connection connection = _Connection();
    _connection = connection;
    final String? project = _projectNumber;
    if (project == null) {
      _finish(connection, _Stop(_missingProjectNumber()));
      return;
    }
    if (!await _waitUntilReady(connection)) {
      return;
    }
    final ({String id, String token}) installation;
    try {
      installation = await _installations.getIdAndToken();
    } on FirebaseInstallationsException catch (error) {
      if (!connection.finished) {
        _finish(connection, _installationsOutcome(error));
      }
      return;
    } catch (error) {
      if (!connection.finished) {
        _finish(connection, const _Transport());
      }
      return;
    }
    if (connection.finished) {
      return;
    }
    connection.installationId = installation.id;
    await _send(connection, project, installation);
  }

  Future<void> _send(
    _Connection connection,
    String project,
    ({String id, String token}) installation,
  ) async {
    final http.StreamedResponse response;
    // The success clock and the watchdog both start when the request is sent: the server holds the
    // headers until it has a message, and a half-open socket must not leave the wait without a timer.
    connection.sentAt = _clock();
    _resetWatchdog(connection);
    try {
      response = await sendStreaming(
        _client,
        (Future<void> abort) => _build(abort, project, installation),
        connection.abort.future,
      );
    } catch (error) {
      if (!connection.finished) {
        _finish(connection, const _Transport());
      }
      return;
    }
    if (connection.finished) {
      _discard(response);
      return;
    }
    _resetWatchdog(connection);
    if (response.statusCode != 200) {
      await _refused(connection, response);
      return;
    }
    _open(connection, response);
  }

  http.BaseRequest _build(
    Future<void> abort,
    String project,
    ({String id, String token}) installation,
  ) {
    final int known = knownVersion(_templates());
    final Uri url = _origin.replace(
      pathSegments: <String>[
        'v1',
        'projects',
        project,
        'namespaces',
        'firebase:streamFetchInvalidations',
      ],
    );
    return http.AbortableRequest('POST', url, abortTrigger: abort)
      ..headers.addAll(<String, String>{
        ..._installations.headers,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Goog-Api-Key': _options.apiKey,
        'X-Goog-Firebase-Installations-Auth': installation.token,
      })
      ..bodyBytes = utf8.encode(
        jsonEncode(<String, String>{
          'project': project,
          'namespace': 'firebase',
          'lastKnownVersionNumber': '$known',
          'appId': _options.appId,
          'sdkVersion': packageVersion,
          'appInstanceId': installation.id,
        }),
      );
  }

  Future<void> _refused(
    _Connection connection,
    http.StreamedResponse response,
  ) async {
    final int status = response.statusCode;
    // A body that stalls is ended by the watchdog with this status's outcome, without the server's text.
    connection.silentOutcome = _refusalOutcome(status, (
      status: null,
      message: null,
    ));
    final CappedResponse body;
    try {
      body = await readCapped(response, cap: errorBodyCap);
    } catch (error) {
      if (!connection.finished) {
        _finish(connection, const _Transport());
      }
      return;
    }
    if (connection.finished) {
      return;
    }
    if (_isRetryableStatus(status)) {
      _log(RemoteConfigLogLevel.warning, 'Realtime refused with HTTP $status.');
    }
    _finish(connection, _refusalOutcome(status, parseServerError(body)));
  }

  static _Outcome _refusalOutcome(int status, ServerError server) {
    if (_isRetryableStatus(status)) {
      return const _Server();
    }
    return _Stop(
      FirebaseRemoteConfigException(
        code: 'stream-error',
        message:
            'The realtime stream was refused with HTTP $status; it stops until a new listener '
            'subscribes.',
        httpStatus: status,
        serverStatus: server.status,
        serverMessage: server.message,
      ),
    );
  }

  void _open(_Connection connection, http.StreamedResponse response) {
    _log(RemoteConfigLogLevel.debug, 'Realtime connection open.');
    final Duration opened = _clock().difference(connection.sentAt);
    final Duration untilSuccess = opened >= successAfter
        ? Duration.zero
        : successAfter - opened;
    connection.successTimer = Timer(untilSuccess, () => _succeed(connection));
    final RealtimeFramer framer = RealtimeFramer();
    final ByteConversionSink decoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(
          _TextSink((String text) {
            _onText(connection, framer, text);
          }),
        );
    _resetWatchdog(connection);
    connection.body = response.stream.listen(
      (List<int> bytes) {
        if (connection.finished) {
          return;
        }
        _resetWatchdog(connection);
        decoder.add(bytes);
      },
      onError: (Object error) {
        if (!connection.finished) {
          _finish(connection, const _Transport());
        }
      },
      onDone: () {
        if (connection.finished) {
          return;
        }
        decoder.close();
        // Decided from the clock too: the zero-length success timer may not have run yet.
        if (!connection.succeeded &&
            _clock().difference(connection.sentAt) >= successAfter) {
          _succeed(connection);
        }
        if (!connection.finished) {
          _finish(
            connection,
            connection.succeeded ? const _Clean() : const _Transport(),
          );
        }
      },
      cancelOnError: true,
    );
  }

  void _succeed(_Connection connection) {
    connection.succeeded = true;
    _serverFailures = 0;
    _transportFailures = 0;
    _serverBackoffUntil = null;
    _transportBackoffUntil = null;
    _failureErrorSent = false;
    _persistBackoff();
  }

  /// Waits for the stored records when they are still loading. Returns false when [connection] must not
  /// go on: it was ended meanwhile, or a restored wait has not ended (the connection is then dropped
  /// without counting a failure, and a timer is set for the end of the wait).
  Future<bool> _waitUntilReady(_Connection connection) async {
    final Future<void>? ready = _ready;
    if (_isReady || ready == null) {
      return true;
    }
    try {
      await ready;
    } catch (error) {
      // A failed load leaves nothing restored; the connect goes on.
    }
    if (connection.finished) {
      return false;
    }
    final DateTime now = _clock();
    final bool waiting = <DateTime?>[
      _serverBackoffUntil,
      _transportBackoffUntil,
      _serverRetryUntil,
    ].any((DateTime? limit) => limit != null && limit.isAfter(now));
    if (!waiting) {
      return true;
    }
    connection.end();
    if (identical(_connection, connection)) {
      _connection = null;
    }
    _evaluate();
    return false;
  }

  /// Hands the failure counts and waits to [_onBackoffChanged] when they differ from the last ones.
  void _persistBackoff() {
    final RealtimeBackoffRecord record = RealtimeBackoffRecord(
      serverFailures: math.min(_serverFailures, RealtimeBackoffRecord.maxCount),
      transportFailures: math.min(
        _transportFailures,
        RealtimeBackoffRecord.maxCount,
      ),
      serverUntil: _serverBackoffUntil,
      transportUntil: _transportBackoffUntil,
      retryUntil: _serverRetryUntil,
    );
    if (record == _persisted) {
      return;
    }
    _persisted = record;
    _onBackoffChanged?.call(record);
  }

  void _resetWatchdog(_Connection connection) {
    connection.watchdogTimer?.cancel();
    connection.watchdogTimer = Timer(watchdog, () {
      if (!connection.finished) {
        _log(
          RemoteConfigLogLevel.debug,
          'Realtime connection silent; recycled.',
        );
        _finish(connection, connection.silentOutcome);
      }
    });
  }

  void _onText(_Connection connection, RealtimeFramer framer, String text) {
    for (final FramerEvent event in framer.add(text)) {
      if (connection.finished) {
        return;
      }
      switch (event) {
        case FramedMessage(:final RealtimeMessage message):
          _onMessage(connection, message);
        case FramedInvalid():
          _emitError(_invalidMessage());
          connection.invalidMessages++;
          if (connection.invalidMessages >= 3) {
            _finish(connection, const _Transport());
          }
        case FramedOverflow():
          _emitError(_invalidMessage());
          _finish(connection, const _Transport());
      }
    }
  }

  void _onMessage(_Connection connection, RealtimeMessage message) {
    if (message.featureDisabled) {
      _disable(connection);
      return;
    }
    final int? version = message.latestTemplateVersion;
    if (version != null) {
      if (version > knownVersion(_templates())) {
        _autoFetcher.invalidate(version);
      }
    }
    final int? retry = message.retryIntervalSeconds;
    if (retry != null) {
      final DateTime until = _clock().add(
        Duration(seconds: math.min(retry, maxRetryIntervalSeconds)),
      );
      final DateTime? current = _serverRetryUntil;
      if (current == null || until.isAfter(current)) {
        _serverRetryUntil = until;
        _persistBackoff();
      }
    }
  }

  void _disable(_Connection connection) {
    _log(RemoteConfigLogLevel.warning, 'Realtime is disabled for this app.');
    _disabled = true;
    _finish(connection, const _Clean());
    for (final MultiStreamController<RemoteConfigUpdate> listener
        in _listeners.toList()) {
      listener
        ..addError(_unavailable())
        ..close();
    }
    _listeners.clear();
  }

  _Outcome _installationsOutcome(FirebaseInstallationsException error) {
    switch (error.code) {
      case 'too-many-requests':
        return const _Server();
      case 'bad-config' || 'storage-error':
        return _Stop(
          FirebaseRemoteConfigException(
            code: 'stream-error',
            message:
                'Installations refused to give a token (${error.code}); the realtime stream stops '
                'until a new listener subscribes.',
            cause: error,
          ),
        );
      case 'installations-closed':
        return const _End();
      default:
        return const _Transport();
    }
  }

  void _finish(_Connection connection, _Outcome outcome) {
    connection.end();
    if (identical(_connection, connection)) {
      _connection = null;
    }
    switch (outcome) {
      case _Clean():
        break;
      case _Transport():
        _transportFailure();
      case _Server():
        _serverFailure();
      case _Stop(:final FirebaseRemoteConfigException error):
        _stopped = true;
        _emitError(error);
      case _End():
        _ended = true;
        _closeListeners();
    }
    _setFloor();
    _evaluate();
  }

  void _abortConnection() {
    final _Connection? connection = _connection;
    if (connection == null) {
      return;
    }
    _connection = null;
    connection.end();
    _setFloor();
  }

  void _setFloor() {
    _floorUntil = _clock().add(_jittered(const Duration(seconds: 1)));
  }

  void _transportFailure() {
    _transportFailures++;
    final int index = math.min(_transportFailures, transportWaitSeconds.length);
    _transportBackoffUntil = _later(
      _transportBackoffUntil,
      Duration(seconds: transportWaitSeconds[index - 1]),
    );
    _persistBackoff();
    _reportRepeatedFailures();
  }

  void _serverFailure() {
    _serverFailures++;
    final int index = math.min(_serverFailures, serverWaitMinutes.length);
    _serverBackoffUntil = _later(
      _serverBackoffUntil,
      Duration(minutes: serverWaitMinutes[index - 1]),
    );
    _persistBackoff();
    _reportRepeatedFailures();
  }

  /// The later of [current] and now plus [base] with jitter: a backoff is extended, never shortened.
  DateTime _later(DateTime? current, Duration base) {
    final DateTime until = _clock().add(_jittered(base));
    return current == null || until.isAfter(current) ? until : current;
  }

  void _reportRepeatedFailures() {
    if (_serverFailures + _transportFailures >= failuresBeforeError &&
        !_failureErrorSent) {
      _failureErrorSent = true;
      _emitError(
        const FirebaseRemoteConfigException(
          code: 'stream-error',
          message:
              'The realtime stream failed 8 times in a row; it keeps reconnecting.',
        ),
      );
    }
  }

  Duration _jittered(Duration base) =>
      Duration(microseconds: (base.inMicroseconds * (0.5 + _random())).round());

  void _emitUpdate(RemoteConfigUpdate update) {
    for (final MultiStreamController<RemoteConfigUpdate> listener
        in _listeners.toList()) {
      listener.add(update);
    }
  }

  void _emitError(FirebaseRemoteConfigException error) {
    for (final MultiStreamController<RemoteConfigUpdate> listener
        in _listeners.toList()) {
      listener.addError(error);
    }
  }

  void _closeListeners() {
    final List<MultiStreamController<RemoteConfigUpdate>> listeners = _listeners
        .toList();
    _listeners.clear();
    for (final MultiStreamController<RemoteConfigUpdate> listener
        in listeners) {
      listener.close();
    }
  }

  void _log(RemoteConfigLogLevel level, String message) {
    _logger?.call(level, message);
  }

  static bool _isRetryableStatus(int status) =>
      status == 408 ||
      status == 429 ||
      status == 502 ||
      status == 503 ||
      status == 504;

  static void _discard(http.StreamedResponse response) {
    unawaited(
      response.stream
          .listen(null, onError: (Object _) {}, cancelOnError: true)
          .cancel(),
    );
  }

  static FirebaseRemoteConfigException _unavailable() =>
      const FirebaseRemoteConfigException(
        code: 'realtime-unavailable',
        message: 'The server disabled realtime updates for this app.',
      );

  static FirebaseRemoteConfigException _invalidMessage() =>
      const FirebaseRemoteConfigException(
        code: 'update-message-invalid',
        message: 'A realtime message could not be read.',
      );

  static FirebaseRemoteConfigException
  _missingProjectNumber() => const FirebaseRemoteConfigException(
    code: 'stream-error',
    message:
        'Realtime needs the project number: an appId whose second field is all digits, or a '
        'messagingSenderId of digits.',
  );
}

/// The project number of 5.9: the second `:`-separated field of `appId` when all digits, else
/// `messagingSenderId` when all digits, else null.
String? projectNumberOf(FirebaseOptions options) {
  final List<String> fields = options.appId.split(':');
  if (fields.length > 1 && _allDigits(fields[1])) {
    return fields[1];
  }
  final String? sender = options.messagingSenderId;
  if (sender != null && _allDigits(sender)) {
    return sender;
  }
  return null;
}

bool _allDigits(String text) {
  if (text.isEmpty || text.length > 32) {
    return false;
  }
  for (final int unit in text.codeUnits) {
    if (unit < 0x30 || unit > 0x39) {
      return false;
    }
  }
  return true;
}

/// One connection attempt and its timers.
final class _Connection {
  /// Set when the request is sent, after Installations returns.
  late DateTime sentAt;

  /// The FID the request carries, once Installations returned it.
  String? installationId;

  /// How the watchdog ends this connection: a clean end, or the outcome of the status whose error body
  /// is being read.
  _Outcome silentOutcome = const _Clean();
  final Completer<void> abort = Completer<void>();
  bool finished = false;
  bool succeeded = false;
  int invalidMessages = 0;
  Timer? successTimer;
  Timer? watchdogTimer;
  StreamSubscription<List<int>>? body;

  /// Marks the connection finished, cancels its timers and body, and aborts the request.
  void end() {
    finished = true;
    successTimer?.cancel();
    watchdogTimer?.cancel();
    final StreamSubscription<List<int>>? subscription = body;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (!abort.isCompleted) {
      abort.complete();
    }
  }
}

/// How a connection ended.
sealed class _Outcome {
  const _Outcome();
}

final class _Clean extends _Outcome {
  const _Clean();
}

final class _Transport extends _Outcome {
  const _Transport();
}

final class _Server extends _Outcome {
  const _Server();
}

final class _Stop extends _Outcome {
  const _Stop(this.error);

  final FirebaseRemoteConfigException error;
}

final class _End extends _Outcome {
  const _End();
}

/// Passes each decoded piece of text to a callback.
final class _TextSink implements Sink<String> {
  _TextSink(this._onText);

  final void Function(String text) _onText;

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}
}
