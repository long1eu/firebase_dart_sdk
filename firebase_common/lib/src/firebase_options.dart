// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/util/to_string_helper.dart';
import 'package:meta/meta.dart';

class FirebaseOptions {
  static const String _apiKeyResourceName = 'google_api_key';
  static const String _appIdResourceName = 'google_app_id';
  static const String _databaseUrlResourceName = 'firebase_database_url';
  static const String _gaTrackingIdResourceName = 'ga_trackingId';
  static const String _gcmSenderIdResourceName = 'gcm_defaultSenderId';
  static const String _storageBucketResourceName = 'google_storage_bucket';
  static const String _projectIdResourceName = 'project_id';

  /// API key used for authenticating requests from your app, e.g.
  /// AIzaSyDdVgKwhZl0sTTTLZ7iTmt1r3N2cJLnaDk, used to identify your app to
  /// Google servers.
  @publicApi
  final String apiKey;

  /// The Google App ID that is used to uniquely identify an instance of an app.
  @publicApi
  final String applicationId;

  /// The database root URL, e.g. http://abc-xyz-123.firebaseio.com.
  @publicApi
  final String databaseUrl;

  /// The tracking ID for Google Analytics, e.g. UA-12345678-1, used to
  /// configure Google Analytics.
  // TODO: unhide once an API (AppInvite) starts reading it.
  @keepForSdk
  final String gaTrackingId;

  /// The Project Number from the Google Developer's console, for example
  /// 012345678901, used to configure Google Cloud Messaging.
  @publicApi
  final String gcmSenderId;

  /// The Google Cloud Storage bucket name, e.g.
  /// abc-xyz-123.storage.firebase.com.
  @publicApi
  final String storageBucket;

  /// The Google Cloud project ID, e.g. my-project-1234
  @publicApi
  final String projectId;

  /// Determine whether automatic data collection is enabled or disabled in all
  /// SDKs.
  /// * Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  @publicApi
  final bool dataCollectionEnabled;

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
    final String applicationId = json[_appIdResourceName];

    if (applicationId == null || applicationId.trim().isEmpty) {
      return null;
    }

    return FirebaseOptions(
      applicationId: applicationId,
      apiKey: json[_apiKeyResourceName],
      databaseUrl: json[_databaseUrlResourceName],
      gaTrackingId: json[_gaTrackingIdResourceName],
      gcmSenderId: json[_gcmSenderIdResourceName],
      storageBucket: json[_storageBucketResourceName],
      projectId: json[_projectIdResourceName],
    );
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
      apiKey.hashCode * 31 ^
      applicationId.hashCode * 31 ^
      databaseUrl.hashCode * 31 ^
      gaTrackingId.hashCode * 31 ^
      gcmSenderId.hashCode * 31 ^
      storageBucket.hashCode * 31 ^
      projectId.hashCode * 31;

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
