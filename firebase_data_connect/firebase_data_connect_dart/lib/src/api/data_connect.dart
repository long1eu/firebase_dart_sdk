import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/src/api/connector_config.dart';
import 'package:firebase_data_connect_dart/src/api/refs.dart';
import 'package:firebase_data_connect_dart/src/api/subscriptions.dart';
import 'package:firebase_data_connect_dart/src/environment_stub.dart'
    if (dart.library.io) 'package:firebase_data_connect_dart/src/environment_io.dart'
    as environment;
import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/retry.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';
import 'package:firebase_data_connect_dart/src/transport/transport_factory.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

const String _productionHost = 'firebasedataconnect.googleapis.com';
const int _productionPort = 443;
const String _emulatorHostVariable = 'FIREBASE_DATA_CONNECT_EMULATOR_HOST';

/// One connector of one app.
///
/// There is no global cache: each constructor call makes a new instance with its own connection,
/// which is opened by the first call and closed by [close]. Operations run over gRPC on the VM and
/// over REST on the web.
///
/// Each call sends the Auth token of `app.authProvider` and the App Check token of
/// `app.appCheckProvider`, when the app has them. When the service refuses a call that carried an
/// Auth token as `unauthenticated`, the token is refreshed (at most once per minute) and the call
/// is sent once more if a token changed. That holds for mutations too.
final class DataConnect {
  /// An instance for the [connector] of the project of [app].
  ///
  /// [emulatorHost], `host:port` or `[ipv6]:port`, targets the emulator, over plaintext, or over
  /// TLS when [emulatorSecure]. Tokens are sent to it; when it is not on this machine and
  /// [emulatorSecure] is false, [logger] gets one warning that they travel in clear text.
  /// [emulatorHostFromEnvironment] reads the usual environment variable; the constructor does not.
  ///
  /// [requestTimeout] bounds each attempt of a call, including its wait for the tokens. A call
  /// that is sent a second time after an Auth refusal can take up to twice as long.
  ///
  /// [callerSdkType] is for generated code and changes only a client header. [httpClient] is used
  /// on the web only, and [close] does not close it. [logger] receives warnings: fixed text and
  /// type names, never a token or a URL. [elapsed] and [transportFactory] are for tests.
  ///
  /// Throws an [ArgumentError] when:
  /// - the project id of [app] is missing, has a `/`, or is not printable ASCII;
  /// - a part of [connector] is not 1 to 63 characters of `a-z`, `0-9` and `-`, or starts or
  ///   ends with `-`;
  /// - the app id or the API key of [app] is set and cannot be sent in a header;
  /// - [emulatorHost] is not a host and a port from 1 to 65535, or names a production host;
  /// - [emulatorSecure] is true without an [emulatorHost];
  /// - [requestTimeout] is zero or negative.
  ///
  /// The message of such an error names the option and never repeats its value. A missing app id
  /// or API key is not an error here: it is a [StateError] of the first call that needs it.
  factory DataConnect(
    FirebaseApp app, {
    required ConnectorConfig connector,
    String? emulatorHost,
    bool emulatorSecure = false,
    CallerSdkType callerSdkType = CallerSdkType.base,
    Duration requestTimeout = const Duration(seconds: 60),
    http.Client? httpClient,
    void Function(String message)? logger,
    @visibleForTesting Duration Function()? elapsed,
    @visibleForTesting
    OperationTransport Function(TransportConfig config)? transportFactory,
  }) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError('requestTimeout must be positive');
    }
    if (emulatorSecure && emulatorHost == null) {
      throw ArgumentError('emulatorSecure needs an emulatorHost');
    }
    connector.check();
    final FirebaseOptions options = app.options;
    final String projectId = _checkedProjectId(options.projectId);
    final String? appId = _checkedOption('appId', options.appId);
    final String? apiKey = _checkedOption('apiKey', options.apiKey);
    final EmulatorHost? emulator = emulatorHost == null
        ? null
        : EmulatorHost.parse(emulatorHost);
    final TransportConfig config = TransportConfig(
      host: emulator?.host ?? _productionHost,
      port: emulator?.port ?? _productionPort,
      secure: emulator == null || emulatorSecure,
      connectorResourceName: connector.resourceName(projectId),
      location: connector.location,
      projectId: projectId,
      serviceId: connector.serviceId,
      appId: appId,
      apiKey: apiKey,
      callerSdkType: callerSdkType,
      httpClient: httpClient,
    );
    final TokenSource tokenSource = TokenSource(
      app,
      origins: <Uri>[Uri(scheme: 'https', host: _productionHost)],
      emulator: emulator,
      onWarning: logger,
      // The shared package marks its clock argument as test-only; this passes on the test-only
      // argument of this constructor, which is null outside tests.
      // ignore: invalid_use_of_visible_for_testing_member
      elapsed: elapsed,
    );
    return DataConnect._(
      app,
      connector,
      config: config,
      tokenSource: tokenSource,
      requestTimeout: requestTimeout,
      elapsed: elapsed ?? _stopwatchClock(),
      transportFactory: transportFactory ?? createTransport,
      logger: logger,
    );
  }

  DataConnect._(
    this.app,
    this.connector, {
    required TransportConfig config,
    required TokenSource tokenSource,
    required Duration requestTimeout,
    required Duration Function() elapsed,
    required OperationTransport Function(TransportConfig config)
    transportFactory,
    required void Function(String message)? logger,
  }) : _config = config,
       _transportFactory = transportFactory,
       _logger = logger {
    _runner = OperationRunner(
      tokenSource: tokenSource,
      requestTimeout: requestTimeout,
      elapsed: elapsed,
      isClosed: () => isClosed,
    );
    _deleteSubscription = app.onDeleteApp.listen((String _) => _closeQuietly());
  }

  /// The value of the environment variable `FIREBASE_DATA_CONNECT_EMULATOR_HOST`, for the
  /// `emulatorHost` argument of the constructor; null on the web, and when the variable is unset
  /// or empty.
  static String? get emulatorHostFromEnvironment {
    return environment.environmentVariable(_emulatorHostVariable);
  }

  /// The app whose project and tokens this instance uses.
  final FirebaseApp app;

  /// The connector this instance calls.
  final ConnectorConfig connector;

  final TransportConfig _config;
  final OperationTransport Function(TransportConfig config) _transportFactory;
  final void Function(String message)? _logger;
  late final OperationRunner _runner;
  late final StreamSubscription<String> _deleteSubscription;

  /// The streams of `QueryRef.subscribe()` on this instance; [close] closes them.
  @internal
  late final SubscriptionHub subscriptions = SubscriptionHub(
    uid: () => app.authProvider.uid,
  );

  final Completer<void> _closeDone = Completer<void>();
  OperationTransport? _transport;
  bool _closed = false;

  /// Whether [close] was called or the app was deleted. A deleted app closes the instance.
  @internal
  bool get isClosed {
    if (_closed) {
      return true;
    }
    if (_isAppDeleted) {
      // `onDeleteApp` reports the deletion one event later; a call made in between must already
      // find the instance closed.
      _closeQuietly();
      return true;
    }
    return false;
  }

  /// Runs the query [operationName] with [variables] and gives the `data` map of the response.
  ///
  /// [variables] may hold `null`, `bool`, `int`, `double`, `String`, lists, and maps with
  /// `String` keys, nested up to 100 deep; a double must be finite and an `int` within
  /// ±(2^53 − 1). Anything else is an [ArgumentError] that names the path of the value.
  ///
  /// Throws a [DataConnectOperationException] when the response lists GraphQL errors, and a
  /// [DataConnectException] for every other failure; `client-closed` after [close]. Throws an
  /// [ArgumentError] when [operationName] is empty, and a [StateError] when the app has no app
  /// id, or on the web no API key.
  Future<Map<String, Object?>> executeQuery(
    String operationName, {
    Map<String, Object?>? variables,
  }) async {
    final QueryRef<Map<String, Object?>, Map<String, Object?>> ref =
        query<Map<String, Object?>, Map<String, Object?>>(
          operationName,
          decode: _sameMap,
          variables: variables,
          encodeVariables: _sameMap,
        );
    return (await ref.execute()).data;
  }

  /// Runs the mutation [operationName] with [variables] and gives the `data` map of the response.
  ///
  /// [variables] and the errors are those of [executeQuery]. A mutation whose response lists
  /// GraphQL errors may have written. A mutation that the service refused as `unauthenticated`
  /// is sent once more when the Auth token was refreshed.
  Future<Map<String, Object?>> executeMutation(
    String operationName, {
    Map<String, Object?>? variables,
  }) async {
    final MutationRef<Map<String, Object?>, Map<String, Object?>> ref =
        mutation<Map<String, Object?>, Map<String, Object?>>(
          operationName,
          decode: _sameMap,
          variables: variables,
          encodeVariables: _sameMap,
        );
    return (await ref.execute()).data;
  }

  /// A reference to the query [operationName] with [variables].
  ///
  /// [decode] turns the `data` map of a response into `Data`. [encodeVariables] turns [variables]
  /// into the map that is sent; without it, [variables] must be a map already, or null.
  ///
  /// Throws an [ArgumentError] when [operationName] is empty.
  QueryRef<Data, Variables> query<Data, Variables>(
    String operationName, {
    required Data Function(Map<String, Object?> data) decode,
    Variables? variables,
    Map<String, Object?> Function(Variables variables)? encodeVariables,
  }) {
    return QueryRef<Data, Variables>.internal(
      this,
      operationName,
      decode: decode,
      variables: variables,
      encodeVariables: encodeVariables,
    );
  }

  /// A reference to the mutation [operationName] with [variables].
  ///
  /// [decode] and [encodeVariables] are those of [query].
  ///
  /// Throws an [ArgumentError] when [operationName] is empty.
  MutationRef<Data, Variables> mutation<Data, Variables>(
    String operationName, {
    required Data Function(Map<String, Object?> data) decode,
    Variables? variables,
    Map<String, Object?> Function(Variables variables)? encodeVariables,
  }) {
    return MutationRef<Data, Variables>.internal(
      this,
      operationName,
      decode: decode,
      variables: variables,
      encodeVariables: encodeVariables,
    );
  }

  /// Sends the operation [operationName] of [kind] and gives the response of the service, with
  /// its GraphQL errors, if any, still in it.
  ///
  /// The references call it. [variables] must already follow the value rules: they are sent as
  /// they are. Each attempt gets its own tokens; see [OperationRunner] for the one retry.
  ///
  /// Throws a [DataConnectException]: `client-closed` during or after [close]; the status of a
  /// failed call in kebab case (`unauthenticated`, `not-found`, `unavailable`, …);
  /// `invalid-response` when the response could not be read; `deadline-exceeded` when an attempt
  /// ran out of time. No such exception has a `cause`, and its message names only the failure.
  /// Throws a [StateError] when the app has no app id, or on the web no API key; nothing is sent
  /// then.
  @internal
  Future<WireResponse> send(
    OperationKind kind,
    String operationName,
    Map<String, Object?>? variables,
  ) async {
    if (isClosed) {
      throw clientClosedException();
    }
    _checkOptionsPresent();
    final OperationTransport transport = _transport ??= _transportFactory(
      _config,
    );
    final WireResult result = await _runner.run(
      transport,
      kind,
      operationName,
      variables,
    );
    switch (result) {
      case WireResponse():
        return result;
      case WireFailure():
        throw exceptionOfFailure(result);
    }
  }

  /// Closes the connection.
  ///
  /// Calls in flight and later calls throw a [DataConnectException] with the code
  /// `client-closed`; the streams of `subscribe()` get that error and close. Calling it again
  /// returns the same future. It runs by itself when the app is deleted.
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _closeDone.complete(_close());
    }
    return _closeDone.future;
  }

  Future<void> _close() async {
    unawaited(_deleteSubscription.cancel());
    // Not awaited: the hub tells its streams before it returns.
    unawaited(subscriptions.close());
    await _transport?.close();
  }

  /// [close] for the callers that cannot wait for it. A failure to close the transport is
  /// logged by its type; its text is not kept.
  void _closeQuietly() {
    close().then<void>(
      (_) {},
      onError: (Object error) {
        _logger?.call(
          'Data Connect: closing the connection failed with '
          '${error.runtimeType}.',
        );
      },
    );
  }

  bool get _isAppDeleted {
    try {
      app.name;
      return false;
    } on StateError {
      return true;
    }
  }

  /// The app id goes out with every call and the API key with every web call; a call is never
  /// sent without them.
  void _checkOptionsPresent() {
    if (_config.appId == null) {
      throw StateError(
        'FirebaseOptions.appId is empty; Data Connect sends it with every '
        'call.',
      );
    }
    if (environment.isWeb && _config.apiKey == null) {
      throw StateError(
        'FirebaseOptions.apiKey is empty; Data Connect needs it on the web.',
      );
    }
  }

  /// The project id becomes a path segment on REST and part of a header on gRPC.
  static String _checkedProjectId(String? projectId) {
    if (projectId == null ||
        projectId.contains('/') ||
        !isHeaderValue(projectId)) {
      throw ArgumentError(
        'FirebaseOptions.projectId must be set, in printable ASCII and '
        'without "/"',
      );
    }
    return projectId;
  }

  /// [value] when it can be sent in a header, null when it is empty.
  static String? _checkedOption(String name, String value) {
    if (value.isEmpty) {
      return null;
    }
    if (!isHeaderValue(value)) {
      throw ArgumentError(
        'FirebaseOptions.$name cannot be sent in a header: it must be '
        'printable ASCII without a leading or trailing space',
      );
    }
    return value;
  }

  static Duration Function() _stopwatchClock() {
    final Stopwatch stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

Map<String, Object?> _sameMap(Map<String, Object?> map) => map;
