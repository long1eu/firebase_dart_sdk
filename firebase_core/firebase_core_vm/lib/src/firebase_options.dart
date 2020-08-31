// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:meta/meta.dart';

/// The options used to configure a [FirebaseApp].
///
/// ```dart
/// FirebaseApp.withOptions(
///   const FirebaseOptions(
///     apiKey: '...',
///     appId: '...',
///     messagingSenderId: '...',
///     projectId: '...',
///   ),
///   name: 'SecondaryApp',
/// );
/// ```
class FirebaseOptions {
  const FirebaseOptions({
    @required this.apiKey,
    @required this.appId,
    @required this.messagingSenderId,
    @required this.projectId,
    this.databaseUrl,
    this.gaTrackingId,
    this.storageBucket,
    this.authDomain,
    this.measurementId,
    this.trackingId,
    this.clientId,
    bool dataCollectionEnabled = true,
  })  : assert(apiKey != null),
        assert(appId != null && appId.length > 0, 'ApplicationId must be set.'),
        dataCollectionEnabled = dataCollectionEnabled ?? true;

  /// Creates a new [FirebaseOptions] instance that is populated from a map.
  /// Returns the populated options or null if applicationId is missing from
  /// the map.
  factory FirebaseOptions.fromJson(Map<String, dynamic> json) {
    if (json == null && !json.containsKey(_apiKey)) {
      return null;
    }
    return FirebaseOptions(
      apiKey: json[_apiKey],
      appId: json[_appId],
      messagingSenderId: json[_messagingSenderId],
      databaseUrl: json[_databaseUrl],
      gaTrackingId: json[_gaTrackingId],
      storageBucket: json[_storageBucket],
      projectId: json[_projectId],
      authDomain: json[_authDomain],
      measurementId: json[_measurementId],
      trackingId: json[_trackingId],
      clientId: json[_clientId],
      dataCollectionEnabled: json[_dataCollectionEnabled],
    );
  }

  static const String _apiKey = 'api_key';
  static const String _appId = 'app_id';
  static const String _messagingSenderId = 'messaging_sender_id';
  static const String _databaseUrl = 'database_url';
  static const String _gaTrackingId = 'ga_tracking_id';
  static const String _storageBucket = 'storage_bucket';
  static const String _projectId = 'project_id';
  static const String _authDomain = 'auth_domain';
  static const String _measurementId = 'measurement_id';
  static const String _trackingId = 'tracking_id';
  static const String _clientId = 'client_id';
  static const String _dataCollectionEnabled = 'data_collection_enabled';

  /// API key used for authenticating requests from your app, e.g.
  /// AIzaSyDdVgKwhZl0sTTTLZ7iTmt1r3N2cJLnaDk, used to identify your app to
  /// Google servers.
  final String apiKey;

  /// The Google App ID that is used to uniquely identify an instance of an app.
  final String appId;

  /// The unique sender ID value used in messaging to identify your app.
  ///
  /// This property is required cannot be `null`.
  final String messagingSenderId;

  /// The database root URL, e.g. http://abc-xyz-123.firebaseio.com.
  final String databaseUrl;

  /// The Google Cloud project ID, e.g. my-project-1234
  final String projectId;

  /// The tracking ID for Google Analytics, e.g. UA-12345678-1, used to
  /// configure Google Analytics.
  final String gaTrackingId;

  /// The Google Cloud Storage bucket name, e.g.
  /// abc-xyz-123.storage.firebase.com.
  final String storageBucket;

  /// The auth domain used to handle redirects from OAuth provides on web
  /// platforms, for example "my-awesome-app.firebaseapp.com".
  final String authDomain;

  /// The project measurement ID value used on web platforms with analytics.
  final String measurementId;

  /// The tracking ID for Google Analytics, for example "UA-12345678-1", used to
  /// configure Google Analytics.
  final String trackingId;

  /// The iOS client ID from the Firebase Console, for example
  /// "12345.apps.googleusercontent.com."
  final String clientId;

  /// Determine whether automatic data collection is enabled or disabled in all
  /// SDKs.
  /// Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  final bool dataCollectionEnabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      _apiKey: apiKey,
      _appId: appId,
      _messagingSenderId: messagingSenderId,
      _databaseUrl: databaseUrl,
      _gaTrackingId: gaTrackingId,
      _storageBucket: storageBucket,
      _projectId: projectId,
      _authDomain: authDomain,
      _measurementId: measurementId,
      _trackingId: trackingId,
      _clientId: clientId,
      _dataCollectionEnabled: dataCollectionEnabled,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseOptions &&
          runtimeType == other.runtimeType &&
          apiKey == other.apiKey &&
          appId == other.appId &&
          messagingSenderId == other.messagingSenderId &&
          databaseUrl == other.databaseUrl &&
          projectId == other.projectId &&
          gaTrackingId == other.gaTrackingId &&
          storageBucket == other.storageBucket &&
          authDomain == other.authDomain &&
          measurementId == other.measurementId &&
          trackingId == other.trackingId &&
          clientId == other.clientId &&
          dataCollectionEnabled == other.dataCollectionEnabled;

  @override
  int get hashCode =>
      apiKey.hashCode ^
      appId.hashCode ^
      messagingSenderId.hashCode ^
      databaseUrl.hashCode ^
      projectId.hashCode ^
      gaTrackingId.hashCode ^
      storageBucket.hashCode ^
      authDomain.hashCode ^
      measurementId.hashCode ^
      trackingId.hashCode ^
      clientId.hashCode ^
      dataCollectionEnabled.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('apiKey', apiKey)
          ..add('appId', appId)
          ..add('messagingSenderId', messagingSenderId)
          ..add('databaseUrl', databaseUrl)
          ..add('gaTrackingId', gaTrackingId)
          ..add('storageBucket', storageBucket)
          ..add('projectId', projectId)
          ..add('authDomain', authDomain)
          ..add('measurementId', measurementId)
          ..add('trackingId', trackingId)
          ..add('clientId', clientId)
          ..add('dataCollectionEnabled', dataCollectionEnabled))
        .toString();
  }
}
