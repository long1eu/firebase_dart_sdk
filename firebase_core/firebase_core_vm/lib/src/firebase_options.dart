// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:meta/meta.dart';

class FirebaseOptions {
  FirebaseOptions({
    @required this.apiKey,
    @required this.applicationId,
    this.databaseUrl,
    this.gaTrackingId,
    this.gcmSenderId,
    this.storageBucket,
    this.projectId,
    this.dataCollectionEnabled = true,
  })  : assert(apiKey != null),
        assert(applicationId != null, 'ApplicationId must be set.'),
        assert(applicationId.trim().isNotEmpty, 'ApplicationId must be set.');

  /// Creates a new [FirebaseOptions] instance that is populated from a map.
  /// Returns the populated options or null if applicationId is missing from
  /// the map.
  factory FirebaseOptions.fromJson(Map<String, String> json) {
    if (json == null && !json.containsKey(_apiKey)) {
      return null;
    }
    return FirebaseOptions(
      applicationId: json[_appId],
      apiKey: json[_apiKey],
      databaseUrl: json[_databaseUrl],
      gaTrackingId: json[_gaTrackingId],
      gcmSenderId: json[_gcmSenderId],
      storageBucket: json[_storageBucket],
      projectId: json[_projectId],
    );
  }

  static const String _apiKey = 'google_api_key';
  static const String _appId = 'google_app_id';
  static const String _databaseUrl = 'firebase_database_url';
  static const String _gaTrackingId = 'ga_trackingId';
  static const String _gcmSenderId = 'gcm_defaultSenderId';
  static const String _storageBucket = 'google_storage_bucket';
  static const String _projectId = 'project_id';

  /// API key used for authenticating requests from your app, e.g.
  /// AIzaSyDdVgKwhZl0sTTTLZ7iTmt1r3N2cJLnaDk, used to identify your app to
  /// Google servers.
  final String apiKey;

  /// The Google App ID that is used to uniquely identify an instance of an app.
  final String applicationId;

  /// The database root URL, e.g. http://abc-xyz-123.firebaseio.com.
  final String databaseUrl;

  /// The tracking ID for Google Analytics, e.g. UA-12345678-1, used to
  /// configure Google Analytics.
  // TODO(long1eu): unhide once an API (AppInvite) starts reading it.
  final String gaTrackingId;

  /// The Project Number from the Google Developer's console, for example
  /// 012345678901, used to configure Google Cloud Messaging.
  final String gcmSenderId;

  /// The Google Cloud Storage bucket name, e.g.
  /// abc-xyz-123.storage.firebase.com.
  final String storageBucket;

  /// The Google Cloud project ID, e.g. my-project-1234
  final String projectId;

  /// Determine whether automatic data collection is enabled or disabled in all
  /// SDKs.
  /// Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  final bool dataCollectionEnabled;

  Map<String, String> toJson() {
    return <String, String>{
      _appId: applicationId,
      _apiKey: apiKey,
      _databaseUrl: databaseUrl,
      _gaTrackingId: gaTrackingId,
      _gcmSenderId: gcmSenderId,
      _storageBucket: storageBucket,
      _projectId: projectId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseOptions &&
          runtimeType == other.runtimeType &&
          apiKey == other.apiKey &&
          applicationId == other.applicationId &&
          databaseUrl == other.databaseUrl &&
          gaTrackingId == other.gaTrackingId &&
          gcmSenderId == other.gcmSenderId &&
          storageBucket == other.storageBucket &&
          projectId == other.projectId;

  @override
  int get hashCode =>
      apiKey.hashCode ^
      applicationId.hashCode ^
      databaseUrl.hashCode ^
      gaTrackingId.hashCode ^
      gcmSenderId.hashCode ^
      storageBucket.hashCode ^
      projectId.hashCode ^
      dataCollectionEnabled.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('apiKey', apiKey)
          ..add('applicationId', applicationId)
          ..add('databaseUrl', databaseUrl)
          ..add('gaTrackingId', gaTrackingId)
          ..add('gcmSenderId', gcmSenderId)
          ..add('storageBucket', storageBucket)
          ..add('projectId', projectId))
        .toString();
  }
}
