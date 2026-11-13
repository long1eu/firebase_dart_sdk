// File created by
// Lung Razvan <long1eu>
// on 01/12/2019

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/platform_info.dart';
import 'package:grpc/service_api.dart' show CallOptions, MetadataProvider;

import '../firestore_call_credentials.dart';

/// Helper class to provide the headers that gRPC needs
class ChannelOptionsProvider {
  const ChannelOptionsProvider({
    required DatabaseId databaseId,
    required CredentialsProvider credentialsProvider,
    AppCheckTokenProvider? appCheckProvider,
    String? apiKey,
  }) : _databaseId = databaseId,
       _credentialsProvider = credentialsProvider,
       _appCheckProvider = appCheckProvider,
       _apiKey = apiKey;

  /// The header of the API key of the app, see [DatabaseInfo.apiKey].
  static const String apiKeyHeader = 'x-goog-api-key';

  final DatabaseId _databaseId;
  final CredentialsProvider _credentialsProvider;
  final AppCheckTokenProvider? _appCheckProvider;
  final String? _apiKey;

  /// The API key sent with the requests, or null.
  String? get apiKey {
    final String? key = _apiKey;
    return key == null || key.isEmpty ? null : key;
  }

  CallOptions get callOptions {
    return CallOptions(
      providers: <MetadataProvider>[
        _callCredentials.getRequestMetadata,
        (Map<String, String> map, String url) {
          map['x-goog-api-client'] = _xGoogApiClientValue;
          // These headers are used to improve routing and project isolation by
          // the backend. The resource prefix header is kept until emulators
          // support x-goog-request-params (see upstream firebase-android-sdk
          // #3498).
          map['google-cloud-resource-prefix'] = _resourcePrefix;
          map['x-goog-request-params'] = _resourcePrefix;
          // As the JS SDK (the Android SDK sends no API key).
          final String? key = apiKey;
          if (key != null) {
            map[apiKeyHeader] = key;
          }
        },
      ],
    );
  }

  void invalidateToken() {
    _credentialsProvider.invalidateToken();
    _appCheckProvider?.invalidateToken();
  }

  FirestoreCallCredentials get _callCredentials => FirestoreCallCredentials(
    _credentialsProvider,
    appCheckProvider: _appCheckProvider,
  );

  // This header is used to improve routing and project isolation by the backend.
  String get _resourcePrefix =>
      'projects/${_databaseId.projectId}/databases/${_databaseId.databaseId}';

  static final String _xGoogApiClientValue =
      'gl-dart/$dartRuntimeVersion fire/${Version.sdkVersion} grpc/${Version.grpcVersion}';
}
