import 'dart:async';
import 'dart:developer' as developer;

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:cloud_functions_dart/src/https_callable.dart';
import 'package:cloud_functions_dart/src/request.dart';
import 'package:cloud_functions_dart/src/urls.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

const String _closedMessage = 'This FirebaseFunctions was closed.';
const String _emulatorHostVariable = 'FIREBASE_FUNCTIONS_EMULATOR_HOST';

/// The callable Cloud Functions of one Firebase project, in one region or behind one custom
/// domain.
///
/// The settings are fixed when the instance is created. Each instance is independent: create one
/// per region or domain, and [close] it when it is no longer needed.
///
/// A call carries the ID token of the app's signed-in user and the app's App Check token when the
/// app has providers for them. Tokens are sent only over `https`, to the configured emulator and
/// to this machine; an `https` custom domain and an `httpsCallableFromUrl` target receive them
/// too, so use only hosts you control.
final class FirebaseFunctions {
  /// The functions of [app]'s project.
  ///
  /// [region] is the region the functions are deployed in: one DNS label such as `europe-west1`.
  ///
  /// [customDomain] is the URL the functions are served from instead of
  /// `https://<region>-<projectId>.cloudfunctions.net`. It must be absolute, without user info, a
  /// query or a fragment, and use `https`, or `http` to a loopback host. A path is kept, without
  /// its trailing slashes.
  ///
  /// [emulatorHost] is the `host:port` of the Functions emulator (an IPv6 host in brackets); calls
  /// by name then go to it over `http`, and it wins over [customDomain]. A scheme, a path, a
  /// missing port and a production host of Google are refused. Tokens sent to an emulator that is
  /// not on this machine travel in clear text; that is reported once through [onWarning].
  ///
  /// [timeout] is the timeout of every callable that does not set its own: any positive duration,
  /// clamped to 2147483647 ms.
  ///
  /// [httpClient] sends the requests and is not closed by [close]. Without it the instance
  /// creates a client and closes it in [close].
  ///
  /// [onWarning] receives warnings about tokens (for example an App Check provider that failed).
  /// They hold fixed text and type names, never a token, a URL or text of the server. By default
  /// they go to `dart:developer`'s `log` under the name `cloud_functions_dart`; pass `print` to
  /// see them on the console.
  ///
  /// [elapsed] is a monotonic clock for tests.
  ///
  /// Throws an [ArgumentError] for a [region], [customDomain], [emulatorHost] or [timeout] that
  /// breaks these rules.
  FirebaseFunctions(
    FirebaseApp app, {
    String region = 'us-central1',
    Uri? customDomain,
    String? emulatorHost,
    Duration timeout = const Duration(seconds: 70),
    http.Client? httpClient,
    void Function(String message)? onWarning,
    @visibleForTesting Duration Function()? elapsed,
  }) : this._(
         app,
         region: checkRegion(region),
         customDomain: customDomain == null
             ? null
             : checkCustomDomain(customDomain),
         emulatorHost: emulatorHost,
         emulator: emulatorHost == null
             ? null
             : EmulatorHost.parse(emulatorHost),
         timeout: checkTimeout(timeout),
         httpClient: httpClient,
         onWarning: onWarning ?? _logWarning,
         elapsed: elapsed ?? _stopwatchClock(),
       );

  FirebaseFunctions._(
    this.app, {
    required this.region,
    required this.customDomain,
    required this.emulatorHost,
    required EmulatorHost? emulator,
    required this.timeout,
    required http.Client? httpClient,
    required void Function(String message) onWarning,
    required Duration Function() elapsed,
  }) : _emulator = emulator,
       _projectId = app.options.projectId,
       _ownsClient = httpClient == null,
       _client = httpClient ?? http.Client(),
       _elapsed = elapsed,
       _tokenSource = TokenSource(
         app,
         origins: _tokenOrigins(
           projectId: app.options.projectId,
           region: region,
           customDomain: customDomain,
         ),
         emulator: emulator,
         onWarning: onWarning,
         // The clock is passed on so that the call's start times and the token source's
         // intervals are measured by one source, the instance's own.
         // ignore: invalid_use_of_visible_for_testing_member
         elapsed: elapsed,
       ) {
    _appDeleted = app.onDeleteApp.listen((String _) => unawaited(close()));
  }

  /// The `host:port` of the Functions emulator from the `FIREBASE_FUNCTIONS_EMULATOR_HOST`
  /// environment variable, or null when it is not set (always null on the web).
  ///
  /// The instance never reads it by itself: pass it as `emulatorHost`. The Firebase CLI does not
  /// set this variable.
  static String? get emulatorHostFromEnvironment =>
      environmentVariable(_emulatorHostVariable);

  /// The app whose project and tokens the calls use.
  final FirebaseApp app;

  /// The region of the functions.
  final String region;

  /// The custom domain, without trailing slashes in its path; null when none was given.
  final Uri? customDomain;

  /// The `host:port` of the emulator as it was given; null when none was given.
  final String? emulatorHost;

  /// The timeout of a callable that does not set its own.
  final Duration timeout;

  final EmulatorHost? _emulator;
  final String? _projectId;
  final bool _ownsClient;
  final http.Client _client;
  final Duration Function() _elapsed;
  final TokenSource _tokenSource;
  final Set<InFlightCall> _inFlight = <InFlightCall>{};
  late final StreamSubscription<String> _appDeleted;
  Future<void>? _closing;

  /// A callable of this project by its [name]: 1 to 63 characters, not `.` or `..`, and none of
  /// `/`, `?`, `#`, `%`, `:`, whitespace or control characters.
  ///
  /// It goes to the emulator when one is configured, else to the custom domain when one is
  /// configured, else to `https://<region>-<projectId>.cloudfunctions.net/<name>`.
  ///
  /// Throws an [ArgumentError] for a bad [name], a timeout in [options] that is zero or negative,
  /// or a project id that cannot be part of the production host; a [StateError] when the URL
  /// needs the project id and the app's options have none, and after [close].
  HttpsCallable httpsCallable(
    String name, {
    HttpsCallableOptions options = const HttpsCallableOptions(),
  }) {
    _throwIfClosed();
    final Uri url = callableUrl(
      projectId: _projectId,
      region: region,
      name: checkName(name),
      customDomain: customDomain,
      emulator: _emulator,
    );
    return HttpsCallable.internal(
      this,
      url: url,
      options: options,
      timeout: _timeoutOf(options),
      originChosenByApplication: false,
    );
  }

  /// A callable at [url], used as given: the emulator setting does not rewrite it.
  ///
  /// [url] must be absolute, without user info, a query or a fragment, and use `https`, or `http`
  /// when its host is loopback or is the configured emulator. It receives the user's tokens, so
  /// pass only a URL of a host you control.
  ///
  /// Throws an [ArgumentError] for a [url] that breaks these rules or a timeout in [options] that
  /// is zero or negative, and a [StateError] after [close].
  HttpsCallable httpsCallableFromUrl(
    Uri url, {
    HttpsCallableOptions options = const HttpsCallableOptions(),
  }) {
    _throwIfClosed();
    return HttpsCallable.internal(
      this,
      url: checkCallableUrl(url, emulator: _emulator),
      options: options,
      timeout: _timeoutOf(options),
      originChosenByApplication: true,
    );
  }

  /// Aborts every call and stream in flight, waits until each has settled, then closes the HTTP
  /// client when the instance created it.
  ///
  /// The aborted calls fail with the code `cancelled`. Afterwards [httpsCallable],
  /// [httpsCallableFromUrl] and the callables made before throw a [StateError]. A second call
  /// returns the same future. It also runs when [app] is deleted.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // Not awaited: the cancel future of a subscription made in another zone may never complete
    // under a fake clock.
    unawaited(_appDeleted.cancel());
    final List<Future<void>> settlements = <Future<void>>[
      for (final InFlightCall call in _inFlight.toList())
        (call..abort(AbortReason.closed)).settled,
    ];
    await Future.wait<void>(settlements);
    if (_ownsClient) {
      _client.close();
    }
  }

  /// The client the requests are sent with.
  @internal
  http.Client get httpClient => _client;

  /// The monotonic clock of this instance, the one its token source uses.
  @internal
  Duration Function() get elapsed => _elapsed;

  /// Whether [close] was called.
  @internal
  bool get isClosed => _closing != null;

  /// Registers a call or a stream that is about to start and watches [abortTrigger] for it.
  ///
  /// The caller must call [InFlightCall.settle] exactly when the call ended, whatever its outcome:
  /// [close] waits for it.
  ///
  /// Throws a [StateError] after [close].
  @internal
  InFlightCall startCall([Future<void>? abortTrigger]) {
    _throwIfClosed();
    final InFlightCall call = InFlightCall(
      elapsed: _elapsed,
      onSettled: _inFlight.remove,
    );
    _inFlight.add(call);
    return call..watch(abortTrigger);
  }

  /// The tokens of the one request [call] makes to [url], fetched within what is left of
  /// [timeout].
  ///
  /// [originChosenByApplication] is true only for a callable made by [httpsCallableFromUrl]. When
  /// the future completes with tokens, [call] was not aborted meanwhile and the request may be
  /// sent at once.
  ///
  /// Throws, through the future:
  /// - a [TransportException] with [TransportFailure.cancelled] when [call] was aborted before or
  ///   during the wait; [InFlightCall.reason] says why. The token result is then ignored and
  ///   nothing may be sent;
  /// - a [TimeoutException] when the time of the call ran out before or during the wait; the
  ///   reason [AbortReason.deadline] is recorded;
  /// - a [TokenFetchException] and a [StateError] (a deleted app) as [TokenSource.tokensFor]
  ///   throws them.
  @internal
  Future<RequestTokens> tokensFor(
    InFlightCall call,
    Uri url, {
    required Duration timeout,
    required bool limitedUseAppCheck,
    required bool originChosenByApplication,
  }) async {
    const TransportException cancelled = TransportException(
      TransportFailure.cancelled,
    );
    if (call.isAborted) {
      throw cancelled;
    }
    final Duration timeLeft = call.timeLeft(timeout);
    if (timeLeft <= Duration.zero) {
      call.abort(AbortReason.deadline);
      throw TimeoutException('The call ran out of time.', timeout);
    }
    final Completer<RequestTokens> result = Completer<RequestTokens>();
    unawaited(
      _tokenSource
          .tokensFor(
            url,
            limitedUseAppCheck: limitedUseAppCheck,
            originChosenByApplication: originChosenByApplication,
            timeLeft: timeLeft,
          )
          .then<void>(
            (RequestTokens tokens) {
              if (!result.isCompleted) {
                result.complete(tokens);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              // After an abort the late failure of a provider is dropped here.
              if (!result.isCompleted) {
                result.completeError(error, stackTrace);
              }
            },
          ),
    );
    unawaited(
      call.aborted.then<void>((_) {
        if (!result.isCompleted) {
          result.completeError(cancelled);
        }
      }),
    );
    try {
      return await result.future;
    } on TimeoutException {
      call.abort(AbortReason.deadline);
      rethrow;
    }
  }

  /// Records that the transport itself answered HTTP 401, without a callable error body, to the
  /// request that carried [tokens].
  ///
  /// When that request carried an Auth token, the next call forces a refresh of it, at most once
  /// per [TokenSource.authForcedRefreshMinInterval]. Never call it for an `UNAUTHENTICATED`
  /// envelope or stream event: that is the answer of the callable layer or of the function. The
  /// App Check token is never invalidated, and the failed call is not sent again.
  @internal
  void bareUnauthorized(RequestTokens tokens) {
    if (tokens.hasAuthToken) {
      _tokenSource.invalidate(TokenKind.auth);
    }
  }

  void _throwIfClosed() {
    if (isClosed) {
      throw StateError(_closedMessage);
    }
  }

  Duration _timeoutOf(HttpsCallableOptions options) {
    final Duration? own = options.timeout;
    return own == null ? timeout : checkTimeout(own, parameter: 'options');
  }

  /// The origins that may receive tokens without the application naming them per call: the
  /// production origin, when the project id forms its host, and the custom domain's.
  static List<Uri> _tokenOrigins({
    required String? projectId,
    required String region,
    required Uri? customDomain,
  }) {
    final String? host = productionHost(projectId: projectId, region: region);
    return <Uri>[
      if (host != null) Uri(scheme: 'https', host: host),
      if (customDomain != null) tokenOrigin(customDomain),
    ];
  }

  static void _logWarning(String message) {
    developer.log(message, name: 'cloud_functions_dart');
  }

  static Duration Function() _stopwatchClock() {
    final Stopwatch stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
