import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'client_identity.dart';
import 'device.dart';
import 'exception.dart';
import 'limits.dart';
import 'state.dart';
import 'store.dart';
import 'transport.dart';
import 'validation.dart';

final RegExp _measurementIdPattern = RegExp(r'^G-[A-Z0-9]{4,20}$');

/// Google Analytics for Firebase over the GA4 Measurement Protocol.
///
/// The client records events, user properties and the user id the way Firebase Analytics does, queues them
/// in an [AnalyticsStore] and sends them in batches to a GA4 **web** data stream: a few seconds after the
/// first event of a batch, when a batch is full, on [flush] and on [close].
///
/// ```dart
/// final analytics = FirebaseAnalytics(
///   app,
///   measurementId: 'G-XXXXXXXXXX',
///   transport: AnalyticsTransport.relay(Uri.parse('https://example.com/collect')),
/// );
/// await analytics.logEvent(name: 'level_up', parameters: {'level': 3});
/// await analytics.close();
/// ```
///
/// What it cannot do, compared with the native SDKs: automatic events (`first_open`, `session_start`,
/// screen tracking), install attribution, audiences, and anything that needs an app stream. Sessions are
/// carried by the `session_id` and `engagement_time_msec` parameters on every event, and screens are sent as
/// `page_view` ([logScreenView]).
///
/// Invalid events throw a [FirebaseAnalyticsException] instead of being dropped; delivery problems never
/// throw, and the events stay queued.
///
/// The configuration is fixed at construction. The collection switch, consent, the user id, user properties
/// and default parameters are state, kept in the store across runs.
class FirebaseAnalytics {
  /// Creates a client for [app] that sends to the web stream [measurementId] over [transport].
  ///
  /// - [measurementId]: the `G-…` id of a GA4 web data stream; defaults to `app.options.measurementId`.
  /// - [store]: where the state and the queue are kept; [AnalyticsStore.memory] by default.
  /// - [region]: the collection endpoint of [AnalyticsTransport.direct].
  /// - [sessionTimeout]: a new session starts when no event was logged for this long.
  /// - [collectionEnabledByDefault]: whether events are collected until [setAnalyticsCollectionEnabled] is
  ///   called; the value passed there is kept in the store and wins from then on.
  /// - [batchDelay]: how long the first event of a batch waits for others.
  /// - [maxQueuedEvents]: the most events kept unsent; when it is reached the oldest go first.
  /// - [device]: sent with every request when set; none by default. The validation server in strict mode
  ///   refused a block without `model` and `browser` (docs/analytics_protocol.md, section 7), which a program
  ///   cannot read, so pass one only when you can fill it. [AnalyticsDevice.detect] gives what the platform
  ///   tells.
  /// - [userLocation]: sent with every request when set; the client never guesses a location.
  /// - [onWarning]: receives what the client cannot throw (a store that fails, a refused request); by
  ///   default it goes to `dart:developer`'s `log`.
  /// - [httpClient], [clock] and [random]: for tests. A client passed in is not closed by [close].
  FirebaseAnalytics(
    this.app, {
    String? measurementId,
    required this.transport,
    AnalyticsStore? store,
    this.region = AnalyticsRegion.global,
    this.sessionTimeout = const Duration(minutes: 30),
    this.collectionEnabledByDefault = true,
    this.batchDelay = const Duration(seconds: 5),
    this.maxQueuedEvents = 1000,
    this.device,
    this.userLocation,
    void Function(String message)? onWarning,
    http.Client? httpClient,
    DateTime Function()? clock,
    Random? random,
  }) : measurementId = measurementId ?? app.options.measurementId ?? '',
       store = store ?? AnalyticsStore.memory(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       _warn = _safeWarning(onWarning ?? _defaultWarning) {
    if (!_measurementIdPattern.hasMatch(this.measurementId)) {
      throw ArgumentError.value(
        this.measurementId,
        'measurementId',
        'Must be the Measurement ID of a GA4 web data stream (G- followed by letters and digits); none was '
            'given and app.options.measurementId is not one',
      );
    }
    if (sessionTimeout <= Duration.zero) {
      throw ArgumentError.value(
        sessionTimeout,
        'sessionTimeout',
        'Must be positive',
      );
    }
    if (maxQueuedEvents < AnalyticsLimits.maxEventsPerRequest) {
      throw ArgumentError.value(
        maxQueuedEvents,
        'maxQueuedEvents',
        'Must be at least ${AnalyticsLimits.maxEventsPerRequest}',
      );
    }
    if (batchDelay < Duration.zero) {
      throw ArgumentError.value(
        batchDelay,
        'batchDelay',
        'Must not be negative',
      );
    }
    _sender = AnalyticsSender(
      transport: transport,
      app: app,
      measurementId: this.measurementId,
      region: region,
      warn: _warn,
      httpClient: httpClient,
    );
    _activeSince = _clock();
  }

  /// The app whose tokens a relay request carries and whose app id is the `X-Firebase-GMPID` header.
  final FirebaseApp app;

  /// The Measurement ID of the GA4 web data stream.
  final String measurementId;

  /// How events reach Google Analytics.
  final AnalyticsTransport transport;

  /// Where the state and the queue are kept.
  final AnalyticsStore store;

  /// The collection endpoint of [AnalyticsTransport.direct].
  final AnalyticsRegion region;

  /// A new session starts when no event was logged for this long.
  final Duration sessionTimeout;

  /// Whether events are collected before [setAnalyticsCollectionEnabled] is first called.
  final bool collectionEnabledByDefault;

  /// How long the first event of a batch waits for others.
  final Duration batchDelay;

  /// The most events kept unsent.
  final int maxQueuedEvents;

  /// The `device` block of every request, when set.
  final AnalyticsDevice? device;

  /// The `user_location` block of every request, when set.
  final AnalyticsUserLocation? userLocation;

  final DateTime Function() _clock;
  final Random _random;
  final void Function(String) _warn;
  late final AnalyticsSender _sender;

  static const Duration _firstRetry = Duration(seconds: 2);
  static const Duration _maxRetry = Duration(minutes: 5);
  static const Duration _queueSaveDelay = Duration(seconds: 1);

  /// Events older than this are dropped rather than sent: the documented limit, less a margin for clocks.
  static final Duration _sendableAge =
      AnalyticsLimits.maxEventAge - const Duration(minutes: 10);

  late AnalyticsState _state;

  /// Set when the stored state could not be read: until the user decides again (the collection switch,
  /// consent or a reset), nothing is collected and the stored state is not overwritten, since it may hold an
  /// opt-out.
  bool _stateUnreadable = false;
  final List<QueuedEvent> _queue = <QueuedEvent>[];
  Future<void>? _loading;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  /// Bumped whenever the queue is emptied by the user, so a batch in flight does not remove other events.
  int _queueGeneration = 0;
  bool _queueDirty = false;
  bool _warnedQueueFull = false;
  Timer? _queueSaveTimer;
  Timer? _batchTimer;
  Timer? _retryTimer;
  int _failures = 0;
  Future<void>? _sending;
  bool _sendAgain = false;

  bool _active = true;
  DateTime? _activeSince;
  int _engagedMicros = 0;

  String get _stateKey => '${app.name}/$measurementId/state';
  String get _queueKey => '${app.name}/$measurementId/queue';

  /// [warn], made safe to call from timers: a handler that throws is ignored rather than escaping as an
  /// unhandled error.
  static void Function(String) _safeWarning(void Function(String) warn) =>
      (String message) {
        try {
          warn(message);
        } on Object {
          // The warning is lost; the client goes on.
        }
      };

  static void _defaultWarning(String message) =>
      developer.log(message, name: 'firebase_analytics_dart', level: 900);

  // ---------------------------------------------------------------------------------------------------------
  // Events

  /// Logs the event [name] with [parameters].
  ///
  /// [name] has 1 to 40 letters, digits or underscores and starts with a letter; it is not one of the names
  /// the Measurement Protocol reserves (`first_open`, `session_start`, `screen_view` and others) and does not
  /// start with `firebase_`, `google_`, `ga_` or `_`. Parameter values are `String` (at most 100 characters),
  /// `int`, `double` or `bool` (sent as `1` or `0`); a null value leaves the parameter out. `items` is a list
  /// of maps, as in GA4's e-commerce events. With the default parameters, an event has at most 23
  /// parameters: the client adds `session_id` and `engagement_time_msec`.
  ///
  /// Throws a [FirebaseAnalyticsException] when a rule is broken; nothing is queued then. While collection is
  /// disabled or analytics storage is denied, a valid event is dropped.
  Future<void> logEvent({
    required String name,
    Map<String, Object?>? parameters,
  }) async {
    checkEventName(name);
    final Map<String, Object> checked = normalizeParameters(
      parameters ?? const <String, Object?>{},
    );
    return _locked(() async {
      if (!_collecting) {
        return;
      }
      final Map<String, Object> merged = <String, Object>{
        ..._state.defaultParameters,
        ...checked,
      };
      checkParameterCount(merged.length);
      final DateTime now = _clock();
      final int nowMicros = now.microsecondsSinceEpoch;
      final int? last = _state.lastEventMicros;
      final bool newSession =
          _state.sessionId == null ||
          last == null ||
          (nowMicros - last).abs() > sessionTimeout.inMicroseconds;
      final int sessionId = newSession
          ? max(now.millisecondsSinceEpoch ~/ 1000, (_state.sessionId ?? 0) + 1)
          : _state.sessionId!;
      final QueuedEvent event = QueuedEvent(
        name: name,
        parameters: <String, Object>{
          ...merged,
          'session_id': sessionId,
          'engagement_time_msec': _engagementMs(now, peek: true),
        },
        timestampMicros: nowMicros,
        context: _context(),
      );
      final String clientId = await _clientId();
      if (encodedSize(_requestBody(clientId, <QueuedEvent>[event])) >=
          AnalyticsLimits.maxBodyBytes) {
        throw FirebaseAnalyticsException(
          code: 'event-too-large',
          message:
              'Event "$name" alone is larger than one request may be (${AnalyticsLimits.maxBodyBytes} bytes).',
        );
      }
      _engagementMs(now, peek: false);
      _state
        ..sessionId = sessionId
        ..lastEventMicros = nowMicros;
      _enqueue(event);
      await _saveState();
      _scheduleSend();
    });
  }

  /// Logs a screen view as `page_view`, since the Measurement Protocol allows `screen_view` for app streams
  /// only: `page_title` is [screenName], `page_location` is `app://<app id>/<screenName>`, and [screenClass]
  /// goes in `screen_class`. [parameters] are added as in [logEvent].
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
    Map<String, Object?>? parameters,
  }) async {
    if (screenName.isEmpty ||
        measuredLength(screenName) > AnalyticsLimits.maxParameterValueLength) {
      throw FirebaseAnalyticsException(
        code: 'invalid-parameter',
        message:
            'The screen name must be 1 to ${AnalyticsLimits.maxParameterValueLength} characters, counted in its '
            'percent-encoded form.',
      );
    }
    return logEvent(
      name: 'page_view',
      parameters: <String, Object?>{
        ...?parameters,
        'page_title': screenName,
        'page_location':
            'app://${app.options.appId}/${Uri.encodeComponent(screenName)}',
        'screen_class': ?screenClass,
      },
    );
  }

  /// Sets parameters added to every event logged from now on; an event's own value of the same name wins.
  ///
  /// The entries of [parameters] are merged into the current defaults: a null value removes that default.
  /// Null clears them all. They follow the rules of [logEvent] and are kept in the store.
  Future<void> setDefaultEventParameters(
    Map<String, Object?>? parameters,
  ) async {
    final Map<String, Object> checked = normalizeParameters(
      parameters ?? const <String, Object?>{},
    );
    return _locked(() async {
      final Map<String, Object> next = parameters == null
          ? <String, Object>{}
          : <String, Object>{..._state.defaultParameters};
      parameters?.forEach((String key, Object? value) {
        if (value == null) {
          next.remove(key);
        }
      });
      next.addAll(checked);
      checkParameterCount(next.length);
      _state.defaultParameters = next;
      await _saveState();
    });
  }

  // ---------------------------------------------------------------------------------------------------------
  // The user

  /// Sets the user id sent with events logged from now on; null clears it. Kept in the store.
  ///
  /// At most 256 characters, counted in its percent-encoded form. Do not use personal data such as an email
  /// address.
  Future<void> setUserId(String? id) async {
    checkUserId(id);
    return _locked(() async {
      _state.userId = id;
      await _saveState();
    });
  }

  /// Sets the user property [name] to [value] for events logged from now on; a null [value] removes it. Kept
  /// in the store.
  ///
  /// [name] has 1 to 24 letters, digits or underscores and starts with a letter; [value] has at most 36
  /// characters. A user has at most 25 properties.
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    checkUserProperty(name, value);
    return _locked(() async {
      if (value == null) {
        _state.userProperties.remove(name);
      } else {
        if (!_state.userProperties.containsKey(name) &&
            _state.userProperties.length >= AnalyticsLimits.maxUserProperties) {
          throw FirebaseAnalyticsException(
            code: 'too-many-user-properties',
            message:
                'A user has at most ${AnalyticsLimits.maxUserProperties} properties; remove one before adding '
                '"$name".',
          );
        }
        _state.userProperties[name] = value;
      }
      await _saveState();
    });
  }

  /// Sets the A/B testing experiment properties of the user: each name is `firebase_exp_` followed by the
  /// experiment id, each value the variant id, and a null value removes the property. Kept in the store and
  /// sent with the other user properties of later events.
  ///
  /// **For integrations, not for apps.** Remote Config's A/B testing hand-off calls it on an activate that
  /// changes the template, then logs `set_firebase_experiment_state`, as the Firebase JS SDK does. These
  /// names break two rules [setUserProperty] enforces (the `firebase_` prefix and the 24-character limit),
  /// and whether a GA4 web stream keeps them is not verified (docs/analytics_protocol.md, section 10).
  ///
  /// Names match `firebase_exp_[A-Za-z0-9_]{1,24}`; values have 1 to 36 characters. The properties count
  /// toward the limit of 25 user properties. The whole map is checked before anything changes: a bad entry,
  /// or more properties than the limit allows, throws [FirebaseAnalyticsException] and changes nothing.
  Future<void> setExperimentProperties(Map<String, String?> properties) async {
    final Map<String, String?> copy = Map<String, String?>.of(properties);
    copy.forEach(checkExperimentProperty);
    return _locked(() async {
      final Map<String, String> next = Map<String, String>.of(
        _state.userProperties,
      );
      copy.forEach((String name, String? value) {
        if (value == null) {
          next.remove(name);
        } else {
          next[name] = value;
        }
      });
      if (next.length > AnalyticsLimits.maxUserProperties &&
          next.length > _state.userProperties.length) {
        throw FirebaseAnalyticsException(
          code: 'too-many-user-properties',
          message:
              'A user has at most ${AnalyticsLimits.maxUserProperties} properties; these experiment properties '
              'would make ${next.length}.',
        );
      }
      _state.userProperties
        ..clear()
        ..addAll(next);
      await _saveState();
    });
  }

  // ---------------------------------------------------------------------------------------------------------
  // Consent and collection

  /// Sets consent; a null argument leaves that consent as it is. Kept in the store.
  ///
  /// - [adUserData] and [adPersonalization] are sent as the `consent` of each request logged afterwards.
  ///   Until one of them is set, no `consent` is sent and Google Analytics keeps what it has for the client.
  /// - [analyticsStorage]: while denied, nothing is queued or sent, the queue is dropped, and
  ///   [appInstanceId] and [sessionId] are null. The protocol has no field for it, and gtag's cookieless
  ///   pings have no equivalent here.
  /// - [adStorage] is kept but changes nothing: the client collects no advertising identifier.
  Future<void> setConsent({
    bool? adUserData,
    bool? adPersonalization,
    bool? analyticsStorage,
    bool? adStorage,
  }) {
    return _locked(() async {
      _stateUnreadable = false;
      _state.consent = _state.consent.merge(
        adUserData: adUserData,
        adPersonalization: adPersonalization,
        analyticsStorage: analyticsStorage,
        adStorage: adStorage,
      );
      if (_state.consent.analyticsStorage == false) {
        _dropQueue();
        await _saveQueueNow();
      }
      await _saveState();
    });
  }

  /// Turns collection on or off, kept in the store. Turning it off drops the queued events and stops
  /// sending; events logged while it is off are dropped.
  Future<void> setAnalyticsCollectionEnabled(bool enabled) {
    return _locked(() async {
      _stateUnreadable = false;
      _state.collectionEnabled = enabled;
      if (!enabled) {
        _dropQueue();
        await _saveQueueNow();
      }
      await _saveState();
    });
  }

  /// Starts over as a new installation: a new client id, no user id, no user properties, no session and no
  /// queued events. Default parameters, consent and the collection switch stay.
  Future<void> resetAnalyticsData() {
    return _locked(() async {
      _state
        ..clientId = ClientIdentity.generate(_random, _clock())
        ..userId = null
        ..userProperties = <String, String>{}
        ..sessionId = null
        ..lastEventMicros = null;
      _stateUnreadable = false;
      // The queue first: after a crash between the two writes, the old user's events must not go out
      // under the new client id.
      _dropQueue();
      await _saveQueueNow();
      await _saveState();
    });
  }

  /// The client id of this installation, made on first use and kept in the store; null while analytics
  /// storage is denied.
  Future<String?> get appInstanceId => _locked(() async {
    if (_state.consent.analyticsStorage == false) {
      return null;
    }
    return _clientId();
  });

  /// The id of the current session (its start time in Unix seconds); null when there is none, when it
  /// expired, while collection is disabled or while analytics storage is denied.
  Future<int?> get sessionId => _locked(() async {
    final int? id = _state.sessionId;
    final int? last = _state.lastEventMicros;
    if (!_collecting || id == null || last == null) {
      return null;
    }
    final int age = _clock().microsecondsSinceEpoch - last;
    return age.abs() > sessionTimeout.inMicroseconds ? null : id;
  });

  // ---------------------------------------------------------------------------------------------------------
  // Lifecycle

  /// Tells the client whether the app is in use: in the foreground and focused. Engagement time counts only
  /// while it is, and going inactive sends the queue. Without calls the app counts as active, which suits a
  /// command-line tool or a server.
  void setAppActive(bool active) {
    if (_closed || active == _active) {
      return;
    }
    final DateTime now = _clock();
    if (active) {
      _activeSince = now;
    } else {
      final DateTime? since = _activeSince;
      if (since != null) {
        _engagedMicros += max(0, now.difference(since).inMicroseconds);
      }
      _activeSince = null;
      unawaited(flush().catchError((Object _) {}));
    }
    _active = active;
  }

  /// Sends every queued event now, without waiting for the batch delay or a retry. Completes when the queue
  /// is empty or a request failed in a way worth retrying; the events of that request stay queued and are
  /// retried later with backoff. Never throws; does nothing once [close] was called.
  Future<void> flush() async {
    if (_closed) {
      return;
    }
    _batchTimer?.cancel();
    _batchTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _send();
    await _locked(_saveQueueNow, allowClosed: true);
  }

  /// Sends what is queued, as [flush] does, saves the state and releases the HTTP client. Later calls throw a
  /// [StateError]; [flush] and [setAppActive] do nothing.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await flush();
    await _locked(() async {
      _closed = true;
      _batchTimer?.cancel();
      _retryTimer?.cancel();
      _queueSaveTimer?.cancel();
      await _saveQueueNow();
      _sender.close();
    }, allowClosed: true);
  }

  // ---------------------------------------------------------------------------------------------------------
  // Internals

  bool get _collecting =>
      !_stateUnreadable &&
      (_state.collectionEnabled ?? collectionEnabledByDefault) &&
      _state.consent.analyticsStorage != false;

  /// Runs [action] after every earlier action, with the stored state loaded.
  Future<T> _locked<T>(
    Future<T> Function() action, {
    bool allowClosed = false,
  }) {
    if (_closed && !allowClosed) {
      return Future<T>.error(StateError('This FirebaseAnalytics was closed.'));
    }
    final Future<T> result = _tail.then((_) async {
      await (_loading ??= _load());
      if (_closed && !allowClosed) {
        throw StateError('This FirebaseAnalytics was closed.');
      }
      return action();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _load() async {
    final DateTime now = _clock();
    AnalyticsState? state;
    try {
      state = AnalyticsState.decode(
        await store.read(_stateKey),
        (String message) => _warn('Analytics: $message'),
        now,
      );
    } on Object catch (error) {
      _warn(
        'Analytics: the stored state could not be read (${error.runtimeType}).',
      );
    }
    if (state == null) {
      _stateUnreadable = true;
      _state = AnalyticsState();
      _warn(
        'Analytics: the stored state could not be read, so it may hold an opt-out. Nothing is collected '
        'and the store is left as it is until setAnalyticsCollectionEnabled, setConsent or '
        'resetAnalyticsData is called.',
      );
    } else {
      _state = state;
    }
    String? queueText;
    try {
      queueText = await store.read(_queueKey);
    } on Object catch (error) {
      _warn(
        'Analytics: the stored queue could not be read (${error.runtimeType}); its events are not sent in '
        'this run.',
      );
    }
    if (queueText != null) {
      int dropped = 0;
      try {
        final Object? json = jsonDecode(queueText);
        if (json is List) {
          for (final Object? item in json) {
            final QueuedEvent? event = QueuedEvent.fromJson(item, now);
            if (event == null) {
              dropped++;
            } else {
              _queue.add(event);
            }
          }
        } else {
          dropped++;
        }
      } on FormatException {
        dropped++;
      }
      if (dropped > 0) {
        _warn(
          'Analytics: $dropped stored events could not be read and were dropped.',
        );
      }
      while (_queue.length > maxQueuedEvents) {
        _queue.removeAt(0);
      }
      if (!_collecting && _queue.isNotEmpty) {
        _queue.clear();
        _markQueueDirty();
      }
      if (_queue.isNotEmpty) {
        _scheduleSend();
      }
    }
  }

  Future<String> _clientId() async {
    final String? existing = _state.clientId;
    if (existing != null) {
      return existing;
    }
    final String created = ClientIdentity.generate(_random, _clock());
    _state.clientId = created;
    await _saveState();
    return created;
  }

  EventContext _context() => EventContext(
    userId: _state.userId,
    userProperties: Map<String, String>.unmodifiable(_state.userProperties),
    consent: _state.consent.toRequest(),
  );

  /// The engagement since the previous event, in milliseconds: the time the app was active, at least 1 and
  /// at most the session timeout. With [peek] false the count starts again from [now].
  int _engagementMs(DateTime now, {required bool peek}) {
    final DateTime? since = _activeSince;
    final int micros =
        _engagedMicros +
        (since == null ? 0 : max(0, now.difference(since).inMicroseconds));
    if (!peek) {
      _engagedMicros = 0;
      if (_active) {
        _activeSince = now;
      }
    }
    return min(max(micros ~/ 1000, 1), sessionTimeout.inMilliseconds);
  }

  void _enqueue(QueuedEvent event) {
    _queue.add(event);
    if (_queue.length > maxQueuedEvents) {
      _queue.removeAt(0);
      if (!_warnedQueueFull) {
        _warnedQueueFull = true;
        _warn(
          'Analytics: more than $maxQueuedEvents events are waiting to be sent; the oldest are dropped.',
        );
      }
    }
    _markQueueDirty();
  }

  void _dropQueue() {
    _queue.clear();
    _queueGeneration++;
    _batchTimer?.cancel();
    _batchTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _failures = 0;
    _markQueueDirty();
  }

  void _markQueueDirty() {
    _queueDirty = true;
    _queueSaveTimer ??= Timer(_queueSaveDelay, () {
      _queueSaveTimer = null;
      unawaited(_locked(_saveQueueNow, allowClosed: true).catchError((_) {}));
    });
  }

  Future<void> _saveQueueNow() async {
    if (!_queueDirty) {
      return;
    }
    if (_stateUnreadable) {
      return;
    }
    _queueDirty = false;
    try {
      await store.write(
        _queueKey,
        _queue.isEmpty
            ? null
            : jsonEncode(<Object>[
                for (final QueuedEvent e in _queue) e.toJson(),
              ]),
      );
    } on Object catch (error) {
      _queueDirty = true;
      _warn('Analytics: the queue could not be saved (${error.runtimeType}).');
    }
  }

  Future<void> _saveState() async {
    if (_stateUnreadable) {
      return;
    }
    try {
      await store.write(_stateKey, _state.encode());
    } on Object catch (error) {
      _warn('Analytics: the state could not be saved (${error.runtimeType}).');
    }
  }

  void _scheduleSend() {
    if (_closed || _retryTimer != null) {
      return;
    }
    if (_queue.length >= AnalyticsLimits.maxEventsPerRequest) {
      _batchTimer?.cancel();
      _batchTimer = null;
      unawaited(_send());
      return;
    }
    _batchTimer ??= Timer(batchDelay, () {
      _batchTimer = null;
      unawaited(_send());
    });
  }

  /// Sends batches until the queue is empty or a request fails in a way worth retrying; a failure schedules
  /// the next attempt with exponential backoff and jitter.
  Future<void> _send() {
    final Future<void>? running = _sending;
    if (running != null) {
      _sendAgain = true;
      return running;
    }
    final Future<void> run = _sendLoop()
        .catchError((Object error) {
          // Sends run from timers; nothing may escape as an unhandled error.
          _warn(
            'Analytics: sending stopped (${error.runtimeType}); the events stay queued.',
          );
        })
        .whenComplete(() => _sending = null);
    _sending = run;
    return run;
  }

  Future<void> _sendLoop() async {
    do {
      _sendAgain = false;
      while (true) {
        final _Batch? batch = await _locked(_nextBatch, allowClosed: true);
        if (batch == null) {
          break;
        }
        final SendOutcome outcome = await _sender.send(
          batch.body,
          // Asked just before the request leaves, after the tokens were read: a switch turned off, a
          // consent denied, a queue dropped or a close meanwhile stops it.
          stillWanted: () => _locked(
            () async =>
                !_closed && _collecting && batch.generation == _queueGeneration,
            allowClosed: true,
          ),
        );
        final bool keepGoing = await _locked(() async {
          if (outcome == SendOutcome.skipped) {
            return false;
          }
          if (outcome == SendOutcome.retry) {
            _failures++;
            if (!_closed) {
              _scheduleRetry();
            }
            return false;
          }
          _failures = 0;
          if (batch.generation == _queueGeneration) {
            for (final QueuedEvent event in batch.events) {
              _queue.remove(event);
            }
            _markQueueDirty();
          }
          return true;
        }, allowClosed: true);
        if (!keepGoing) {
          return;
        }
      }
    } while (_sendAgain);
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final int exponent = min(_failures - 1, 16);
    final int ceiling = min(
      _maxRetry.inMilliseconds,
      _firstRetry.inMilliseconds * (1 << exponent),
    );
    // Half fixed, half random: spread retries without ever retrying at once.
    final int delay = ceiling ~/ 2 + _random.nextInt(ceiling ~/ 2 + 1);
    _retryTimer = Timer(Duration(milliseconds: delay), () {
      _retryTimer = null;
      unawaited(_send());
    });
  }

  /// The next request: the oldest events that share a user context, up to the event and size limits. Events
  /// too old to be dated correctly are dropped first.
  Future<_Batch?> _nextBatch() async {
    if (_closed || !_collecting) {
      return null;
    }
    final int oldest =
        _clock().microsecondsSinceEpoch - _sendableAge.inMicroseconds;
    final int before = _queue.length;
    _queue.removeWhere((QueuedEvent e) => e.timestampMicros < oldest);
    if (_queue.length != before) {
      _warn(
        'Analytics: ${before - _queue.length} events older than 72 hours were dropped; the Measurement '
        'Protocol would date them 72 hours ago.',
      );
      _markQueueDirty();
    }
    if (_queue.isEmpty) {
      return null;
    }
    final String clientId = await _clientId();
    // An event read from the store was never size-checked; one that cannot fit a request alone is dropped.
    while (_queue.isNotEmpty &&
        encodedSize(_requestBody(clientId, <QueuedEvent>[_queue.first])) >=
            AnalyticsLimits.maxBodyBytes) {
      _queue.removeAt(0);
      _markQueueDirty();
      _warn('Analytics: a stored event too large for one request was dropped.');
    }
    if (_queue.isEmpty) {
      return null;
    }
    final EventContext context = _queue.first.context;
    final List<QueuedEvent> events = <QueuedEvent>[];
    final int baseSize = encodedSize(
      _requestBody(clientId, const <QueuedEvent>[], context),
    );
    int size = baseSize;
    for (final QueuedEvent event in _queue) {
      if (events.length == AnalyticsLimits.maxEventsPerRequest ||
          event.context != context) {
        break;
      }
      final int eventSize =
          encodedSize(event.toRequest()) + (events.isEmpty ? 0 : 1);
      if (events.isNotEmpty &&
          size + eventSize >= AnalyticsLimits.maxBodyBytes) {
        break;
      }
      events.add(event);
      size += eventSize;
    }
    final List<int> body = utf8.encode(
      jsonEncode(_requestBody(clientId, events, context)),
    );
    return _Batch(events, body, _queueGeneration);
  }

  Map<String, Object> _requestBody(
    String clientId,
    List<QueuedEvent> events, [
    EventContext? context,
  ]) {
    final EventContext ctx =
        context ?? (events.isEmpty ? _context() : events.first.context);
    return <String, Object>{
      ...ClientIdentity.bodyFields(clientId),
      'user_id': ?ctx.userId,
      if (ctx.userProperties.isNotEmpty)
        'user_properties': <String, Object>{
          for (final MapEntry<String, String> e in ctx.userProperties.entries)
            e.key: <String, String>{'value': e.value},
        },
      'consent': ?ctx.consent,
      'device': ?device?.toRequest(),
      'user_location': ?userLocation?.toRequest(),
      'events': <Object>[for (final QueuedEvent e in events) e.toRequest()],
    };
  }

  /// The number of events waiting to be sent.
  @visibleForTesting
  Future<int> get queuedEventCount => _locked(() async => _queue.length);
}

class _Batch {
  _Batch(this.events, this.body, this.generation);

  final List<QueuedEvent> events;
  final List<int> body;
  final int generation;
}
