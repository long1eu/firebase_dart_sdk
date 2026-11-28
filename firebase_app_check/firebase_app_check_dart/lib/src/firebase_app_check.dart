import 'dart:async';
import 'dart:math';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_check_dart/src/app_check_seam.dart';
import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:firebase_app_check_dart/src/exception.dart';
import 'package:firebase_app_check_dart/src/exchange_client.dart';
import 'package:firebase_app_check_dart/src/logger.dart';
import 'package:firebase_app_check_dart/src/provider.dart';
import 'package:firebase_app_check_dart/src/refresher.dart';
import 'package:firebase_app_check_dart/src/token_manager.dart';
import 'package:firebase_app_check_dart/src/token_record.dart';
import 'package:firebase_app_check_dart/src/token_store.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// App Check for one [FirebaseApp]: gets App Check tokens from a provider, caches the session
/// token, refreshes it before it expires, and hands it to the Firebase services of the app.
///
/// Create it before the services of the app. Firestore, Auth and the Realtime Database read the
/// app's token provider once, when they are created; one created earlier sends no App Check
/// token until it is created again. The other services ask at each request.
///
/// There is no static instance and no global switch: the provider is a constructor argument.
/// Call [close] when you are done; a program that must exit calls it, because the refresh timer
/// keeps the process alive.
///
/// ```dart
/// import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// Future<void> useAppCheck(FirebaseApp app, String debugToken) async {
///   final FirebaseAppCheck appCheck = FirebaseAppCheck(
///     app,
///     provider: DebugAppCheckProvider(debugToken: debugToken),
///   );
///   final AppCheckToken token = await appCheck.getToken();
///   print('The token expires at ${token.expireTime}.');
///   await appCheck.close();
/// }
/// ```
class FirebaseAppCheck {
  /// Creates App Check for [app] with [provider]. Reads nothing and sends nothing: the first
  /// token is fetched by the first request that needs one.
  ///
  /// - [store]: where the session token is kept across restarts and shared between the instances
  ///   that use the same store. Null keeps the token in memory only. Pass the store object that
  ///   `FirebaseInstallations` uses, if the app has one. It is never closed here.
  /// - [autoRefresh]: refresh the session token before it stops being usable. See
  ///   [setTokenAutoRefreshEnabled].
  /// - [install]: set [tokenProvider] as `app.appCheckProvider`, so the services of the app use
  ///   it. Pass false for a second instance of an app.
  /// - [httpClient]: the client of the debug provider's requests. It is not closed here; one
  ///   created here is closed by [close].
  /// - [logger]: receives the log lines. Without it nothing is logged or printed.
  ///
  /// [serverOrigin], [clock] (the wall clock), [elapsed] (the time since an arbitrary start, which
  /// never goes back) and [random] (a number in [0, 1), for jitter) are for tests.
  ///
  /// Throws an [ArgumentError], which never holds the rejected value, when [serverOrigin] is not
  /// an `https` origin (or `http` to a loopback host) and, with a [DebugAppCheckProvider], when
  /// the `apiKey`, `appId` or `projectId` of the app is present but malformed. A missing or empty
  /// one is a [StateError] at the first token request instead; a [CustomAppCheckProvider] needs
  /// none of them.
  ///
  /// Throws a [StateError] when [install] is true and the app already has a token provider that
  /// is not the one a closed [FirebaseAppCheck] left behind.
  factory FirebaseAppCheck(
    FirebaseApp app, {
    required AppCheckProvider provider,
    KeyValueStore? store,
    bool autoRefresh = true,
    bool install = true,
    http.Client? httpClient,
    AppCheckLogger? logger,
    @visibleForTesting Uri? serverOrigin,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting Duration Function()? elapsed,
    @visibleForTesting double Function()? random,
  }) {
    final Uri origin = checkOrigin(serverOrigin ?? _defaultOrigin);
    final FirebaseOptions options = app.options;
    final bool debug = provider is DebugAppCheckProvider;
    if (debug) {
      ExchangeClient.checkOptions(options);
    }
    final AppCheckSeam? leftBehind = install ? _seamLeftOn(app) : null;

    final String appName = app.name;
    final Completer<void> closeSignal = Completer<void>();
    final Clocks clocks = _clocksOf(clock, elapsed);
    final double Function() draw = random ?? Random().nextDouble;
    final http.Client? ownedClient = debug && httpClient == null
        ? http.Client()
        : null;
    final TokenManager manager = TokenManager(
      provider: provider,
      exchangeClient: _exchangeClientOf(
        debug ? httpClient ?? ownedClient : null,
        options,
        origin: origin,
        clocks: clocks,
        closed: closeSignal.future,
      ),
      tokenStore: _tokenStoreOf(
        store,
        app,
        clocks: clocks,
        logger: logger,
        appName: appName,
      ),
      clocks: clocks,
      random: draw,
      logger: logger,
      appName: appName,
    );
    final TokenRefresher refresher = TokenRefresher(
      manager: manager,
      clocks: clocks,
      random: draw,
      enabled: autoRefresh,
      logger: logger,
      appName: appName,
    );
    final AppCheckSeam seam = leftBehind ?? AppCheckSeam(app);
    if (install) {
      app.appCheckProvider = seam;
    }
    seam.bind(
      manager: manager,
      events: manager.events,
      clocks: clocks,
      logger: logger,
      appName: appName,
    );
    if (debug && logger != null) {
      logger(AppCheckLogLevel.warning, debugProviderInUseText(appName));
    }
    return FirebaseAppCheck._(
      app: app,
      appName: appName,
      manager: manager,
      refresher: refresher,
      seam: seam,
      closeSignal: closeSignal,
      ownedClient: ownedClient,
    );
  }

  FirebaseAppCheck._({
    required this.app,
    required String appName,
    required TokenManager manager,
    required TokenRefresher refresher,
    required AppCheckSeam seam,
    required Completer<void> closeSignal,
    required http.Client? ownedClient,
  }) : _appName = appName,
       _manager = manager,
       _refresher = refresher,
       _seam = seam,
       _closeSignal = closeSignal,
       _ownedClient = ownedClient {
    _events = manager.events.listen(_onEvent);
    _appDeleted = app.onDeleteApp.listen((String _) => unawaited(close()));
  }

  static final Uri _defaultOrigin = Uri.https(
    'firebaseappcheck.googleapis.com',
  );

  /// The app this instance belongs to.
  final FirebaseApp app;

  final String _appName;
  final TokenManager _manager;
  final TokenRefresher _refresher;
  final AppCheckSeam _seam;
  final Completer<void> _closeSignal;
  final http.Client? _ownedClient;
  final StreamController<AppCheckToken> _changes =
      StreamController<AppCheckToken>.broadcast();
  late final StreamSubscription<TokenEvent> _events;
  late final StreamSubscription<String> _appDeleted;

  String? _lastAnnounced;
  Future<void>? _closing;

  /// The object through which Firebase services ask this instance for tokens. With
  /// `install: true` it is also `app.appCheckProvider`.
  ///
  /// It never throws: a failed request gives a result with an error. It stays on the app after
  /// [close] and then answers with an empty token, so services send no App Check header; a later
  /// [FirebaseAppCheck] of the same app takes it over.
  AppCheckTokenProvider get tokenProvider => _seam;

  /// The current session token; a new one is fetched when the cached one has under 5 minutes
  /// left (or under half its lifetime, for a lifetime under 10 minutes).
  ///
  /// Pass [forceRefresh] only when a backend rejected the cached token. A forced call still gets
  /// the cached token while it is younger than 30 s: that bounds how often a backend that rejects
  /// every token can cause a request.
  ///
  /// Throws a [FirebaseAppCheckException] when no token could be had; see its codes. When the
  /// request fails while the cached token has not expired, a call that is not forced gets that
  /// token and a forced one gets the exception. Throws a [StateError] when the debug provider
  /// lacks the `apiKey`, `appId` or `projectId` of the app.
  Future<AppCheckToken> getToken({bool forceRefresh = false}) async {
    final Outcome outcome = await _manager.obtain(forceRefresh: forceRefresh);
    final SessionToken? token = outcome.token;
    final FirebaseAppCheckException? failure = outcome.failure;
    if (failure != null && (token == null || forceRefresh)) {
      throw failure;
    }
    if (token == null) {
      throw appCheckClosed();
    }
    return token.toPublic();
  }

  /// A new limited-use token, for one request to a backend that consumes App Check tokens
  /// (replay protection). Every call fetches one; it is never cached, stored or announced on
  /// [onTokenChanged].
  ///
  /// Throws a [FirebaseAppCheckException], or a [StateError] as [getToken] does.
  Future<AppCheckToken> getLimitedUseToken() async {
    final SessionToken token = await _manager.limitedUse();
    return token.toPublic();
  }

  /// Emits each new session token: from a request, from the store, or from another instance on
  /// the same store. A broadcast stream: it does not replay the current token to a new listener,
  /// never emits an error, and is done after [close].
  Stream<AppCheckToken> get onTokenChanged => _changes.stream;

  /// Whether the session token is refreshed before it stops being usable. Kept in memory only.
  bool get isTokenAutoRefreshEnabled => _refresher.enabled;

  /// Switches the proactive refresh on or off, at any time. Off, every token is fetched inside
  /// some request. Does nothing after [close].
  void setTokenAutoRefreshEnabled(bool enabled) {
    _refresher.setEnabled(enabled);
  }

  /// Closes this instance: every waiting call is answered (with `app-check-closed`; a service's
  /// call with an empty token), the refresh timer and a request in flight are cancelled, and
  /// [onTokenChanged] ends. A custom provider's callback that is running cannot be cancelled; its
  /// answer is dropped.
  ///
  /// [tokenProvider] stays on the app, so that a later [FirebaseAppCheck] reaches the services
  /// that kept it. The store is not closed and the stored token stays until it expires. An
  /// `http.Client` passed to the constructor is not closed.
  ///
  /// Idempotent. It also runs when the app is deleted.
  Future<void> close() => _closing ??= _close();

  @override
  String toString() => 'FirebaseAppCheck(app: $_appName)';

  Future<void> _close() async {
    _closeSignal.complete();
    _manager.close();
    _refresher.close();
    _seam.unbind();
    unawaited(_events.cancel());
    unawaited(_appDeleted.cancel());
    unawaited(_changes.close());
    // The close signal aborts a request in flight in a microtask; the client goes after that.
    await Future<void>.value();
    _ownedClient?.close();
  }

  void _onEvent(TokenEvent event) {
    final String token = event.token.token;
    if (!event.announce || token == _lastAnnounced || _changes.isClosed) {
      return;
    }
    _lastAnnounced = token;
    _changes.add(event.token.toPublic());
  }

  /// The seam object that a closed instance left on [app], or null when the app has no provider.
  ///
  /// Throws a [StateError] for any other provider, a bound seam object included: two instances
  /// would otherwise answer for one app.
  static AppCheckSeam? _seamLeftOn(FirebaseApp app) {
    final AppCheckTokenProvider? installed = app.appCheckProvider;
    if (installed == null) {
      return null;
    }
    if (installed is AppCheckSeam && !installed.isBound) {
      return installed;
    }
    throw StateError(
      'This app already has an App Check provider. Close the other '
      'FirebaseAppCheck first, or pass install: false.',
    );
  }

  /// The injected clocks, or the defaults: the system's wall clock and a stopwatch started now.
  static Clocks _clocksOf(
    DateTime Function()? clock,
    Duration Function()? elapsed,
  ) {
    final Stopwatch stopwatch = Stopwatch()..start();
    return Clocks(
      wall: clock ?? () => DateTime.now().toUtc(),
      elapsed: elapsed ?? () => stopwatch.elapsed,
    );
  }

  /// The exchange client of a debug provider; [client] is null for a custom provider, which sends
  /// no request. A missing `projectId` is passed on empty: the first exchange refuses it.
  static ExchangeClient? _exchangeClientOf(
    http.Client? client,
    FirebaseOptions options, {
    required Uri origin,
    required Clocks clocks,
    required Future<void> closed,
  }) {
    if (client == null) {
      return null;
    }
    return ExchangeClient(
      client: client,
      origin: origin,
      projectId: options.projectId ?? '',
      appId: options.appId,
      apiKey: options.apiKey,
      clocks: clocks,
      closed: closed,
    );
  }

  static TokenStore? _tokenStoreOf(
    KeyValueStore? store,
    FirebaseApp app, {
    required Clocks clocks,
    required AppCheckLogger? logger,
    required String appName,
  }) {
    if (store == null) {
      return null;
    }
    return TokenStore(
      store: store,
      key: recordKey(app),
      clocks: clocks,
      logger: logger,
      appName: appName,
    );
  }
}
