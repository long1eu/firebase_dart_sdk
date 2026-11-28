import 'dart:async';
import 'dart:developer' as developer;

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/src/api/connector_config.dart'
    as core;
import 'package:firebase_data_connect_dart/src/api/data_connect.dart' as core;
import 'package:firebase_data_connect_dart/src/compat/cache_types.dart';
import 'package:firebase_data_connect_dart/src/compat/connector_config.dart';
import 'package:firebase_data_connect_dart/src/compat/errors.dart';
import 'package:firebase_data_connect_dart/src/compat/refs.dart';
import 'package:firebase_data_connect_dart/src/environment_stub.dart'
    if (dart.library.io) 'package:firebase_data_connect_dart/src/environment_io.dart';
import 'package:meta/meta.dart';

const String _subscribeWarning =
    'server push is not supported in 0.1.0; this stream shows results this app fetches';
const String _cacheWarning =
    'cache not supported in 0.1.0; queries go to the server';

/// The Data Connect client of one connector of one app, with the API of FlutterFire's
/// `FirebaseDataConnect` that generated code calls.
///
/// It wraps a core `DataConnect`, created at the first operation and replaced after
/// [useDataConnectEmulator].
class FirebaseDataConnect {
  /// The client of [connectorConfig] in [app], for the caller [sdkType]. For the override
  /// package; applications call [instanceFor].
  ///
  /// Throws an [ArgumentError] naming the part when a part of [connectorConfig] is not a host
  /// label (1 to 63 of `a-z`, `0-9` and `-`, not starting or ending with `-`). A non-null
  /// [cacheSettings] is ignored, with one warning.
  @protected
  FirebaseDataConnect.forApp(
    this.app,
    this.connectorConfig,
    CallerSDKType sdkType, {
    CacheSettings? cacheSettings,
  }) : _connector = _checkedConnector(connectorConfig),
       _callerSdkType = sdkType == CallerSDKType.generated
           ? core.CallerSdkType.generated
           : core.CallerSdkType.base {
    _logOnce = LogOnce(_log);
    if (cacheSettings != null) {
      _logOnce('cache', _cacheWarning);
    }
    _deletion = app.onDeleteApp.listen((String _) => _onAppDeleted());
  }

  /// The instances of [instanceFor]: per app object (by identity), then per
  /// `connectorConfig.toJson()`. FlutterFire caches per app name; a deleted app's entries are
  /// removed.
  static final Map<FirebaseApp, Map<String, FirebaseDataConnect>> _instances =
      Map<FirebaseApp, Map<String, FirebaseDataConnect>>.identity();

  /// The client of [connectorConfig] in [app] (by default `Firebase.app()`), created at the first
  /// call for that app object and configuration and returned by later calls.
  ///
  /// [sdkType] defaults to [CallerSDKType.core]. A non-null [cacheSettings] is ignored, with one
  /// warning: 0.1.0 has no cache. Throws an [ArgumentError] before any operation when a part of
  /// [connectorConfig] is not a host label.
  static FirebaseDataConnect instanceFor({
    FirebaseApp? app,
    CallerSDKType? sdkType,
    required ConnectorConfig connectorConfig,
    CacheSettings? cacheSettings,
  }) {
    final FirebaseApp resolved = app ?? Firebase.app();
    final String key = connectorConfig.toJson();
    final FirebaseDataConnect? existing = _instances[resolved]?[key];
    if (existing != null) {
      return existing;
    }
    final FirebaseDataConnect instance = FirebaseDataConnect.forApp(
      resolved,
      connectorConfig,
      sdkType ?? CallerSDKType.core,
      cacheSettings: cacheSettings,
    );
    _instances.putIfAbsent(
      resolved,
      () => <String, FirebaseDataConnect>{},
    )[key] = instance;
    return instance;
  }

  /// The app.
  final FirebaseApp app;

  /// The connector.
  final ConnectorConfig connectorConfig;

  final core.ConnectorConfig _connector;
  final core.CallerSdkType _callerSdkType;
  late final LogOnce _logOnce;
  late final StreamSubscription<String> _deletion;
  final Map<String, _TrackedQuery> _trackedQueries = <String, _TrackedQuery>{};
  String? _emulatorHost;
  bool _emulatorSecure = false;
  core.DataConnect? _core;

  core.DataConnect get _client => _core ??= core.DataConnect(
    app,
    connector: _connector,
    emulatorHost: _emulatorHost,
    emulatorSecure: _emulatorSecure,
    callerSdkType: _callerSdkType,
    logger: _log,
  );

  /// A reference to the query [operationName], whose data [dataDeserializer] reads and whose
  /// variables [vars] (null for none) [varsSerializer] writes.
  ///
  /// Returns the reference that is already subscribed to for an equal operation id, if any.
  QueryRef<Data, Variables> query<Data, Variables>(
    String operationName,
    Deserializer<Data> dataDeserializer,
    Serializer<Variables> varsSerializer,
    Variables? vars,
  ) {
    final QueryRef<Data, Variables> ref = QueryRef<Data, Variables>(
      this,
      operationName,
      dataDeserializer,
      varsSerializer,
      vars,
    );
    final QueryRef<Object?, Object?>? tracked =
        _trackedQueries[ref.operationId]?.ref;
    return tracked is QueryRef<Data, Variables> ? tracked : ref;
  }

  /// A reference to the mutation [operationName], whose data [dataDeserializer] reads and whose
  /// variables [vars] (null for none) [varsSerializer] writes.
  MutationRef<Data, Variables> mutation<Data, Variables>(
    String operationName,
    Deserializer<Data> dataDeserializer,
    Serializer<Variables> varsSerializer,
    Variables? vars,
  ) {
    return MutationRef<Data, Variables>(
      this,
      operationName,
      dataDeserializer,
      varsSerializer,
      vars,
    );
  }

  /// Targets the emulator at [host] and [port] (over TLS when [isSecure]) from the next operation
  /// on, including for references made before.
  ///
  /// With [automaticHostMapping] on Android, `localhost` and `127.0.0.1` become `10.0.2.2`. The
  /// current core client is closed: streams of [QueryRef.subscribe] made before end with an error
  /// whose cause has the code `client-closed`.
  void useDataConnectEmulator(
    String host,
    int port, {
    bool automaticHostMapping = true,
    bool isSecure = false,
  }) {
    final bool mapped =
        automaticHostMapping &&
        isAndroid &&
        (host == 'localhost' || host == '127.0.0.1');
    final String target = mapped ? '10.0.2.2' : host;
    _emulatorHost = target.contains(':') ? '[$target]:$port' : '$target:$port';
    _emulatorSecure = isSecure;
    _closeClient();
  }

  void _onAppDeleted() {
    final Map<String, FirebaseDataConnect>? perApp = _instances[app];
    final String key = connectorConfig.toJson();
    if (perApp != null && identical(perApp[key], this)) {
      perApp.remove(key);
      if (perApp.isEmpty) {
        _instances.remove(app);
      }
    }
    _closeClient();
    unawaited(_deletion.cancel());
  }

  void _closeClient() {
    final core.DataConnect? previous = _core;
    _core = null;
    if (previous != null) {
      unawaited(previous.close());
    }
  }

  static void _log(String message) =>
      developer.log(message, name: 'firebase_data_connect_dart');

  static core.ConnectorConfig _checkedConnector(ConnectorConfig config) {
    _checkLabel('location', config.location);
    _checkLabel('connector', config.connector);
    _checkLabel('serviceId', config.serviceId);
    return core.ConnectorConfig(
      location: config.location,
      serviceId: config.serviceId,
      connector: config.connector,
    );
  }

  static void _checkLabel(String part, String value) {
    if (!isHostLabel(value)) {
      throw ArgumentError(
        'ConnectorConfig.$part must be 1 to 63 of a-z, 0-9 and -, not starting or ending with -',
      );
    }
  }
}

/// A subscribed query reference and its number of listeners.
final class _TrackedQuery {
  _TrackedQuery(this.ref);

  final QueryRef<Object?, Object?> ref;
  int listeners = 0;
}

/// The core client of [dataConnect], created at its first operation. Internal to the compat
/// library.
core.DataConnect coreClientOf(FirebaseDataConnect dataConnect) =>
    dataConnect._client;

/// Records a listener of [ref]'s subscription and logs the one subscribe warning of
/// [dataConnect]. Internal to the compat library.
void addQueryListener(
  FirebaseDataConnect dataConnect,
  QueryRef<Object?, Object?> ref,
) {
  dataConnect._logOnce('subscribe', _subscribeWarning);
  dataConnect._trackedQueries
          .putIfAbsent(ref.operationId, () => _TrackedQuery(ref))
          .listeners +=
      1;
}

/// Removes a listener recorded by [addQueryListener]. Internal to the compat library.
void removeQueryListener(
  FirebaseDataConnect dataConnect,
  QueryRef<Object?, Object?> ref,
) {
  final _TrackedQuery? tracked = dataConnect._trackedQueries[ref.operationId];
  if (tracked == null) {
    return;
  }
  tracked.listeners -= 1;
  if (tracked.listeners <= 0) {
    dataConnect._trackedQueries.remove(ref.operationId);
  }
}
