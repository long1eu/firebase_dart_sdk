// File created by
// Lung Razvan <long1eu>
// on 01/12/2019

import 'dart:io';

import 'package:firebase_firestore/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';

import '../firestore_call_credentials.dart';

/// Helper class to provide the headers that gRPC needs
class ChannelOptionsProvider {
  const ChannelOptionsProvider({@required DatabaseId databaseId, @required CredentialsProvider credentialsProvider})
      : assert(databaseId != null),
        assert(credentialsProvider != null),
        _databaseId = databaseId,
        _credentialsProvider = credentialsProvider;

  final DatabaseId _databaseId;
  final CredentialsProvider _credentialsProvider;

  CallOptions get callOptions {
    return CallOptions(
      providers: <MetadataProvider>[
        FirestoreCallCredentials(_credentialsProvider).getRequestMetadata,
        (Map<String, String> map, String url) {
          map['x-goog-api-client'] = _xGoogApiClientValue;
          map['google-cloud-resource-prefix'] = _resourcePrefix;
        }
      ],
    );
  }

  void invalidateToken() => _credentialsProvider.invalidateToken();

  // This header is used to improve routing and project isolation by the backend.
  String get _resourcePrefix => 'projects/${_databaseId.projectId}/databases/${_databaseId.databaseId}';

  static final String _xGoogApiClientValue =
      'gl-dart/${Platform.version} fire/${Version.sdkVersion} grpc/${Version.grpcVersion}';
}
