// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:firebase_app_dart/internal.dart';
import 'package:firebase_app_dart/src/firebase_app.dart';

/// The configuration of a [FirebaseApp]: the identifiers and keys of the Firebase project it talks
/// to.
///
/// Take the values from the Firebase console (*Project settings*, *Your apps*); the values of a web
/// app work on every platform. On platforms Firebase does not register apps for (desktop, servers)
/// any unique application id of the form `1:<project number>:<platform>:<suffix>` works.
///
/// Two options are equal when all their values are equal. [toString] includes the [apiKey]: the
/// key identifies the project and is not a secret, but keep it out of logs you share.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// void main() {
///   const FirebaseOptions options = FirebaseOptions(
///     apiKey: '<YOUR_API_KEY>',
///     applicationId: '1:1234567890:dart:example',
///     projectId: 'my-project',
///   );
///   // The same options, read from a map (for example a decoded JSON file).
///   final FirebaseOptions fromJson = FirebaseOptions.fromJson(<String, dynamic>{
///     'google_api_key': '<YOUR_API_KEY>',
///     'google_app_id': '1:1234567890:dart:example',
///     'project_id': 'my-project',
///   });
///   print(fromJson == options); // true
///   FirebaseApp.withOptions(options);
/// }
/// ```
class FirebaseOptions {
  /// Creates the options. [apiKey] and [appId] are required; the other values are needed
  /// only by the services that use them (Firestore needs [projectId]). [dataCollectionEnabled]
  /// defaults to `true`.
  ///
  /// An empty [appId] fails an assert in debug mode; [FirebaseApp.withOptions] throws an
  /// [ArgumentError] for it in every mode. An empty [apiKey] is allowed: Firestore does not send
  /// it, which suits a server with a service account.
  const FirebaseOptions({
    required this.apiKey,
    required this.appId,
    this.databaseURL,
    this.trackingId,
    this.messagingSenderId,
    this.storageBucket,
    this.projectId,
    this.dataCollectionEnabled = true,
  }) : assert(appId != '', 'ApplicationId must be set.');

  /// Reads the options from [json], with the key names of the Android resource values (as written
  /// by [toJson]):
  ///
  /// | Key | Option |
  /// | --- | --- |
  /// | `google_api_key` | [apiKey] (required) |
  /// | `google_app_id` | [appId] (required) |
  /// | `project_id` | [projectId] |
  /// | `google_storage_bucket` | [storageBucket] |
  /// | `gcm_defaultSenderId` | [messagingSenderId] |
  /// | `firebase_database_url` | [databaseURL] |
  /// | `ga_trackingId` | [trackingId] |
  ///
  /// Other keys are ignored, and [dataCollectionEnabled] is always `true`. This is not the format
  /// of `google-services.json` or of the web config object (`apiKey`, `appId`, ...): map those
  /// yourself.
  ///
  /// Throws an [ArgumentError] if `google_api_key` or `google_app_id` is missing, and a
  /// [TypeError] if a value is not a string.
  factory FirebaseOptions.fromJson(Map<String, dynamic> json) {
    final String? applicationId = json[_appId] as String?;
    final String? apiKey = json[_apiKey] as String?;
    if (apiKey == null || applicationId == null) {
      throw ArgumentError(
        'The json must contain the keys $_apiKey and $_appId.',
      );
    }
    return FirebaseOptions(
      appId: applicationId,
      apiKey: apiKey,
      databaseURL: json[_databaseUrl] as String?,
      trackingId: json[_gaTrackingId] as String?,
      messagingSenderId: json[_gcmSenderId] as String?,
      storageBucket: json[_storageBucket] as String?,
      projectId: json[_projectId] as String?,
    );
  }

  static const String _apiKey = 'google_api_key';
  static const String _appId = 'google_app_id';
  static const String _databaseUrl = 'firebase_database_url';
  static const String _gaTrackingId = 'ga_trackingId';
  static const String _gcmSenderId = 'gcm_defaultSenderId';
  static const String _storageBucket = 'google_storage_bucket';
  static const String _projectId = 'project_id';

  /// The Web API key of the project, for example `AIzaSy...`. It identifies the project to Google
  /// servers; it is not a credential. `FirebaseUserAuth` of `package:firebase_auth_providers_dart`
  /// needs it, and Firestore sends it with each request when it is not empty.
  final String apiKey;

  /// The Google App ID that identifies the app in the project, for example
  /// `1:1234567890:web:0123456789abcdef`. Must not be empty.
  final String appId;

  /// The Realtime Database URL, for example `https://my-project.firebaseio.com`. Stored, not used:
  /// there is no Realtime Database client in this repository.
  final String? databaseURL;

  /// The Google Analytics tracking id, for example `UA-12345678-1`. Stored, not used.
  // TODO(long1eu): unhide once an API (AppInvite) starts reading it.
  final String? trackingId;

  /// The project number, for example `012345678901` (the sender id of Cloud Messaging). Stored,
  /// not used.
  final String? messagingSenderId;

  /// The Cloud Storage bucket, for example `my-project.appspot.com`. Stored, not used.
  final String? storageBucket;

  /// The Google Cloud project id, for example `my-project`. Firestore needs it.
  final String? projectId;

  /// Whether automatic data collection is enabled. Default `true`. Stored, not used: no service of
  /// this repository collects data, and [FirebaseApp.isAutomaticDataCollectionEnabled] does not read
  /// it. Not part of [toJson] and [FirebaseOptions.fromJson].
  final bool dataCollectionEnabled;

  /// A map with these options, in the shape read by [FirebaseOptions.fromJson]. Values that are not
  /// set are null; [dataCollectionEnabled] is not included.
  Map<String, String?> toJson() {
    return <String, String?>{
      _appId: appId,
      _apiKey: apiKey,
      _databaseUrl: databaseURL,
      _gaTrackingId: trackingId,
      _gcmSenderId: messagingSenderId,
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
          appId == other.appId &&
          databaseURL == other.databaseURL &&
          trackingId == other.trackingId &&
          messagingSenderId == other.messagingSenderId &&
          storageBucket == other.storageBucket &&
          projectId == other.projectId &&
          dataCollectionEnabled == other.dataCollectionEnabled;

  @override
  int get hashCode =>
      apiKey.hashCode ^
      appId.hashCode ^
      databaseURL.hashCode ^
      trackingId.hashCode ^
      messagingSenderId.hashCode ^
      storageBucket.hashCode ^
      projectId.hashCode ^
      dataCollectionEnabled.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('apiKey', apiKey)
          ..add('applicationId', appId)
          ..add('databaseUrl', databaseURL)
          ..add('gaTrackingId', trackingId)
          ..add('gcmSenderId', messagingSenderId)
          ..add('storageBucket', storageBucket)
          ..add('projectId', projectId))
        .toString();
  }
}
