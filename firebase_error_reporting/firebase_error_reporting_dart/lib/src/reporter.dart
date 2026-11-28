import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'format.dart';
import 'model.dart';
import 'store.dart';
import 'transport.dart';

/// Decides what happens to an event before it is queued: return it, a changed copy (see
/// [ErrorEvent.copyWith]), or null to drop it.
typedef BeforeSend = ErrorEvent? Function(ErrorEvent event);

/// Captures Dart errors and sends them to Google Cloud Error Reporting, in the project of a [FirebaseApp].
///
/// ```dart
/// final reporter = ErrorReporter(
///   app,
///   service: 'notes-desktop',
///   version: '1.4.0',
///   transport: ErrorReportingTransport.relay(Uri.parse('https://example.com/errors')),
/// );
/// await reporter.runGuarded(() async {
///   // The program. Errors that escape it are reported.
/// });
/// ```
///
/// Errors are formatted when they are recorded ([MessageFormat]), kept in the [ErrorReportingStore] and sent
/// one at a time, a short while after they are recorded, on [flush] and on [close], or at once when recorded
/// as fatal. Failed sends are retried with backoff; events the server refuses are dropped. The reporter never
/// throws into its caller: problems go to `onDiagnostic` (by default `dart:developer`'s `log`).
///
/// A rate limit keeps a loop of errors from using up the project's quota: by default at most 30 events a
/// minute, and 5 a minute of the same error type at the same place. The header of the next event of a kind
/// says how many like it were dropped.
class ErrorReporter {
  /// Creates a reporter for [app].
  ///
  /// * [service] is the `serviceContext.service` the console groups and filters by: the name of the program.
  /// * [version] is the `serviceContext.version`: the release (`1.4.0`), not a build number, because Error
  ///   Reporting keeps at most 10,000 pairs of a version and an error group.
  /// * [transport] says how events travel; see [ErrorReportingTransport].
  /// * [store] keeps the queue between runs; memory by default.
  /// * [collectionEnabledByDefault] applies until [setCollectionEnabled] is called.
  /// * [beforeSend] sees each event after it is formatted, to scrub or drop it. An exception it throws drops
  ///   the event.
  /// * [maxQueueLength] caps the queue; the oldest events go first.
  /// * [clock], [random] and [httpClient] are for tests. A client passed here is not closed by [close].
  ErrorReporter(
    this.app, {
    required this.service,
    this.version,
    required this.transport,
    ErrorReportingStore? store,
    this.messageFormat = MessageFormat.v8,
    bool collectionEnabledByDefault = true,
    BeforeSend? beforeSend,
    this.maxQueueLength = 100,
    this.maxEventsPerMinute = 30,
    this.maxSimilarEventsPerMinute = 5,
    this.sendDelay = const Duration(seconds: 2),
    http.Client? httpClient,
    DateTime Function()? clock,
    math.Random? random,
    void Function(String message)? onDiagnostic,
  }) : _store = store ?? ErrorReportingStore.memory(),
       _defaultEnabled = collectionEnabledByDefault,
       _beforeSend = beforeSend,
       _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _clock = clock ?? DateTime.now,
       _random = random ?? math.Random(),
       _log = onDiagnostic ?? _defaultLog {
    if (service.trim().isEmpty) {
      throw ArgumentError.value(service, 'service', 'must not be empty');
    }
    if (maxQueueLength < 1 ||
        maxEventsPerMinute < 1 ||
        maxSimilarEventsPerMinute < 1) {
      throw ArgumentError(
        'The queue length and the rate limits must be at least 1.',
      );
    }
    if (transport is DirectTransport) {
      final String projectId = app.options.projectId ?? '';
      if (!_projectIdPattern.hasMatch(projectId)) {
        throw ArgumentError(
          'The direct transport needs the projectId of the app options; it is missing or malformed.',
        );
      }
    }
    _ready = _load();
  }

  static final RegExp _projectIdPattern = RegExp(r'^[a-z][a-z0-9.:\-]{3,62}$');

  /// The app whose project receives the errors.
  final FirebaseApp app;

  /// The `serviceContext.service`.
  final String service;

  /// The `serviceContext.version`, or null.
  final String? version;

  /// How events are delivered.
  final ErrorReportingTransport transport;

  /// How errors become messages.
  final MessageFormat messageFormat;

  /// The most events kept in the queue.
  final int maxQueueLength;

  /// The most events recorded in a minute.
  final int maxEventsPerMinute;

  /// The most events of one kind (error type and top frame) recorded in a minute.
  final int maxSimilarEventsPerMinute;

  /// How long after an error is recorded the queue is sent.
  final Duration sendDelay;

  /// Events older than this are dropped from the queue: Error Reporting keeps 30 days and refuses an
  /// `eventTime` beyond the retention of the logs.
  static const Duration maxEventAge = Duration(days: 30);

  final ErrorReportingStore _store;
  final bool _defaultEnabled;
  final BeforeSend? _beforeSend;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  final math.Random _random;
  final void Function(String message) _log;

  late final Future<void> _ready;

  /// The zone the reporter was created in. Its timers and sends run there, not in the zone of the code that
  /// recorded an error, so a guarded zone of [runGuarded] never sees the reporter's own work.
  final Zone _zone = Zone.current;
  final List<ErrorEvent> _queue = <ErrorEvent>[];
  String? _user;
  bool? _enabledSetting;
  bool _closed = false;
  Timer? _timer;
  Future<void>? _pumping;
  int _attempt = 0;

  final List<DateTime> _recent = <DateTime>[];
  final Map<String, List<DateTime>> _recentByKind = <String, List<DateTime>>{};
  final Map<String, int> _droppedByKind = <String, int>{};

  /// Whether events are recorded and sent: the last [setCollectionEnabled], or `collectionEnabledByDefault`.
  bool get isCollectionEnabled => _enabledSetting ?? _defaultEnabled;

  /// The number of events waiting to be sent.
  int get pendingCount => _queue.length;

  /// Completes when the saved state is loaded.
  Future<void> get ready => _ready;

  Future<void> _load() async {
    ErrorReportingState state;
    try {
      state = await _store.load();
    } on Object catch (error) {
      _log(
        'The saved state could not be read (${error.runtimeType}); starting empty.',
      );
      state = ErrorReportingState.empty;
    }
    _user = state.user;
    _enabledSetting = state.collectionEnabled;
    _queue.addAll(state.queue);
    if (!isCollectionEnabled) {
      _queue.clear();
    }
    _trimQueue();
    if (_queue.isNotEmpty) {
      _schedule(Duration.zero);
    }
  }

  /// Records [error], thrown with [stack], and queues it.
  ///
  /// Without a [stack] (or with an empty one) the stack of this call is used. [reason] says what the program
  /// was doing; its first line goes into the header. [fatal] means the program is about to end: the event is
  /// sent at once and the header says `[fatal]`. [httpRequest] describes the request a server was handling.
  ///
  /// Completes when the event is stored. Never throws.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    Object? reason,
    bool fatal = false,
    HttpRequestContext? httpRequest,
  }) {
    final String typeName = error.runtimeType.toString();
    return _record(
      typeName,
      _describe(error),
      stack,
      reason: reason,
      fatal: fatal,
      httpRequest: httpRequest,
    );
  }

  /// Records an error known only as text: [description] and the text of its [stack], as an isolate's error
  /// listener receives them. [typeName] goes in front of the description.
  Future<void> recordErrorText(
    String description,
    String stack, {
    String typeName = 'Error',
    Object? reason,
    bool fatal = false,
  }) => _record(
    typeName,
    description,
    StackTrace.fromString(stack),
    reason: reason,
    fatal: fatal,
  );

  /// Runs [body] in a zone that records what escapes it, and completes with its result, or with null when it
  /// failed.
  ///
  /// Errors of work [body] started and nobody waits for are recorded too, without ending the program, as Dart
  /// does for errors in a guarded zone.
  Future<R?> runGuarded<R>(FutureOr<R> Function() body) {
    final Completer<R?> done = Completer<R?>();
    runZonedGuarded<void>(
      () {
        Future<R>.sync(body).then(
          done.complete,
          onError: (Object error, StackTrace stack) {
            recordError(error, stack);
            if (!done.isCompleted) {
              done.complete(null);
            }
          },
        );
      },
      (Object error, StackTrace stack) {
        recordError(error, stack);
      },
    );
    return done.future;
  }

  /// Sets the `context.user` of the events recorded from now on; null clears it. Saved in the store.
  ///
  /// The console shows it to everyone with access to the project. Send an opaque id, not an e-mail address.
  Future<void> setUser(String? user) async {
    await _ready;
    _user = user;
    await _save();
  }

  /// Turns recording and sending on or off. Off drops the queue. Saved in the store, and it outlasts
  /// `collectionEnabledByDefault`.
  Future<void> setCollectionEnabled(bool enabled) async {
    await _ready;
    _enabledSetting = enabled;
    if (!enabled) {
      _queue.clear();
      _timer?.cancel();
      _timer = null;
    }
    await _save();
    if (enabled && _queue.isNotEmpty) {
      _schedule(Duration.zero);
    }
  }

  /// Sends the queue now and completes when it is empty or a send failed. Never throws.
  Future<void> flush() async {
    await _ready;
    _timer?.cancel();
    _timer = null;
    await _pump();
  }

  /// Sends what it can within [timeout], saves the queue and releases the HTTP client. Events left over are
  /// sent by the next reporter on the same store. Later calls record nothing.
  Future<void> close({Duration timeout = const Duration(seconds: 10)}) async {
    if (_closed) {
      return;
    }
    try {
      await flush().timeout(timeout);
    } on TimeoutException {
      _log(
        'close: the queue was not sent within $timeout; it stays in the store.',
      );
    }
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await _save();
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<void> _record(
    String typeName,
    String description,
    StackTrace? stack, {
    Object? reason,
    bool fatal = false,
    HttpRequestContext? httpRequest,
  }) async {
    if (_closed) {
      _log('recordError after close: the error is not recorded.');
      return;
    }
    try {
      final StackTrace trace = stack == null || stack.toString().trim().isEmpty
          ? StackTrace.current
          : stack;
      await _ready;
      if (!isCollectionEnabled) {
        return;
      }
      final FormattedError formatted = formatError(
        typeName: typeName,
        description: description,
        stack: trace,
        format: messageFormat,
        reason: reason == null ? null : _describe(reason),
        fatal: fatal,
      );
      final String kind = formatted.fingerprint;
      if (!_admit(kind)) {
        _droppedByKind[kind] = (_droppedByKind[kind] ?? 0) + 1;
        return;
      }
      String message = formatted.message;
      final int dropped = _droppedByKind.remove(kind) ?? 0;
      if (dropped > 0) {
        message = _noteInHeader(message, '[+$dropped similar dropped]');
      }
      ErrorEvent? event = ErrorEvent(
        eventTime: _clock().toUtc(),
        message: message,
        fingerprint: kind,
        reportLocation: formatted.reportLocation,
        user: _user,
        httpRequest: httpRequest,
        fatal: fatal,
      );
      final BeforeSend? hook = _beforeSend;
      if (hook != null) {
        try {
          event = hook(event);
        } on Object catch (error) {
          _log('beforeSend threw ${error.runtimeType}; the event is dropped.');
          return;
        }
        if (event == null) {
          return;
        }
      }
      _queue.add(event);
      _trimQueue();
      await _save();
      _schedule(fatal ? Duration.zero : sendDelay);
    } on Object catch (error) {
      // Never report an error of the reporter: it could loop.
      _log('The error could not be recorded (${error.runtimeType}).');
    }
  }

  bool _admit(String kind) {
    final DateTime now = _clock();
    final DateTime since = now.subtract(const Duration(minutes: 1));
    _recent.removeWhere((DateTime t) => !t.isAfter(since));
    final List<DateTime> similar = _recentByKind.putIfAbsent(
      kind,
      () => <DateTime>[],
    );
    similar.removeWhere((DateTime t) => !t.isAfter(since));
    _recentByKind.removeWhere(
      (String key, List<DateTime> times) => times.isEmpty && key != kind,
    );
    if (_recent.length >= maxEventsPerMinute ||
        similar.length >= maxSimilarEventsPerMinute) {
      return false;
    }
    _recent.add(now);
    similar.add(now);
    return true;
  }

  void _trimQueue() {
    final DateTime oldest = _clock().toUtc().subtract(maxEventAge);
    _queue.removeWhere((ErrorEvent e) => e.eventTime.isBefore(oldest));
    if (_queue.length > maxQueueLength) {
      final int extra = _queue.length - maxQueueLength;
      _queue.removeRange(0, extra);
      _log('The queue is full: dropped the $extra oldest events.');
    }
  }

  void _schedule(Duration delay) {
    if (_closed || !isCollectionEnabled) {
      return;
    }
    final Timer? current = _timer;
    if (current != null && current.isActive && delay > Duration.zero) {
      // A send is already planned; an error recorded meanwhile goes with it.
      return;
    }
    current?.cancel();
    _timer = _zone.createTimer(delay, () {
      _timer = null;
      _pump();
    });
  }

  /// Sends the queue, one event at a time, until it is empty or a send fails.
  Future<void> _pump() {
    final Future<void>? running = _pumping;
    if (running != null) {
      return running;
    }
    final Future<void> pumping = _zone.run(_drain).whenComplete(() {
      _pumping = null;
    });
    _pumping = pumping;
    return pumping;
  }

  Future<void> _drain() async {
    while (!_closed && isCollectionEnabled && _queue.isNotEmpty) {
      _trimQueue();
      if (_queue.isEmpty) {
        break;
      }
      final ErrorEvent event = _queue.first;
      SendResult result;
      try {
        result = await transport.send(
          _client,
          app,
          event.toReportJson(service: service, version: version),
        );
      } on Object catch (error) {
        result = RetryLater('the transport threw ${error.runtimeType}');
      }
      switch (result) {
        case Delivered():
          _attempt = 0;
          _remove(event);
          await _save();
        case Dropped(:final int status, :final String body):
          _attempt = 0;
          _remove(event);
          await _save();
          _log(
            'Error Reporting refused an event (HTTP $status); it is dropped: ${_cap(body)}',
          );
        case RetryLater(:final String reason, :final Duration? after):
          _attempt++;
          final Duration wait = after ?? _backoff(_attempt);
          _log(
            'Sending failed ($reason); trying again in ${wait.inSeconds} s.',
          );
          _schedule(wait);
          return;
      }
    }
  }

  void _remove(ErrorEvent event) {
    if (_queue.isNotEmpty && identical(_queue.first, event)) {
      _queue.removeAt(0);
    } else {
      _queue.remove(event);
    }
  }

  Duration _backoff(int attempt) => backoffFor(attempt, _random.nextDouble());

  Future<void> _save() async {
    try {
      await _store.save(
        ErrorReportingState(
          user: _user,
          collectionEnabled: _enabledSetting,
          queue: List<ErrorEvent>.unmodifiable(_queue),
        ),
      );
    } on Object catch (error) {
      _log('The state could not be saved (${error.runtimeType}).');
    }
  }

  static String _describe(Object value) {
    try {
      return value.toString();
    } on Object {
      return 'Instance of ${value.runtimeType} (its toString threw)';
    }
  }

  static String _noteInHeader(String message, String note) {
    final int end = message.indexOf('\n');
    return end < 0
        ? '$message $note'
        : '${message.substring(0, end)} $note${message.substring(end)}';
  }

  static String _cap(String text) {
    final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 500 ? flat : '${flat.substring(0, 500)}…';
  }

  static void _defaultLog(String message) {
    developer.log(message, name: 'firebase_error_reporting');
  }
}

/// Exposed for tests: the backoff before attempt [attempt] with a jitter of [jitter] (0 to 1).
@visibleForTesting
Duration backoffFor(int attempt, double jitter) {
  final int exponent = math.min(attempt - 1, 10);
  final int base = math.min(2000 * (1 << exponent), 5 * 60 * 1000);
  return Duration(milliseconds: (base * (0.5 + jitter / 2)).round());
}
