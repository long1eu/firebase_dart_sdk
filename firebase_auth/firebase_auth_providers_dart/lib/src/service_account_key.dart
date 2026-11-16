import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis_auth/googleapis_auth.dart' as gapi;

import 'oauth_token_provider.dart';
import 'rs256.dart' as rs256;

/// The private key of a service account, parsed from its key file, that signs data with RS256.
///
/// It uses the signer of [OAuthTokenProvider.serviceAccount], for code that needs to sign something else with
/// the same key: for example the custom tokens of `firebase_admin_dart`.
///
/// **A key file is a credential.** Whoever holds it acts as the service account. Keep it on machines you control,
/// never in an app, a web page or a repository.
///
/// The signature is RSASSA-PKCS1-v1_5 with SHA-256, in pure Dart (it works on the web too). The message is
/// blinded and every signature is checked with the public key before it is returned; see the notes on timing in
/// the source of the signer. [toString] does not show the key.
///
/// ```dart
/// import 'dart:convert';
///
/// import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
///
/// String signedBy(String keyFileContent, String text) {
///   final ServiceAccountKey key = ServiceAccountKey.fromJson(keyFileContent);
///   return base64Url.encode(key.signRs256(utf8.encode(text)));
/// }
/// ```
final class ServiceAccountKey {
  ServiceAccountKey._(
    this.clientEmail,
    this.projectId,
    this.privateKeyId, {
    required this.modulus,
    required this.publicExponent,
    required BigInt p,
    required BigInt q,
    required BigInt dmp1,
    required BigInt dmq1,
    required BigInt coeff,
  }) : _p = p,
       _q = q,
       _dmp1 = dmp1,
       _dmq1 = dmq1,
       _coeff = coeff;

  /// Parses [json]: the decoded content of a service account key file (a `Map`), or the content itself (a
  /// `String`), as [OAuthTokenProvider.serviceAccount] takes it.
  ///
  /// Throws an [ArgumentError] if [json] is not a service account key. The error does not quote the input.
  factory ServiceAccountKey.fromJson(Object json) {
    final gapi.ServiceAccountCredentials credentials;
    final Object? decoded;
    try {
      credentials = gapi.ServiceAccountCredentials.fromJson(json);
      decoded = json is String ? jsonDecode(json) : json;
    } on Object {
      // The original error may quote the input, which holds the private key.
      throw ArgumentError(
        'Not a service account key: expected the JSON of a key file with "type": "service_account", '
        '"client_email", "client_id" and "private_key".',
      );
    }
    String? field(String name) {
      final Object? value = decoded is Map ? decoded[name] : null;
      return value is String && value.isNotEmpty ? value : null;
    }

    // The type of the key is not exported by every supported version of googleapis_auth.
    // ignore: always_specify_types
    final key = credentials.privateRSAKey;
    return ServiceAccountKey._(
      credentials.email,
      field('project_id'),
      field('private_key_id'),
      modulus: key.n,
      publicExponent: key.e,
      p: key.p,
      q: key.q,
      dmp1: key.dmp1,
      dmq1: key.dmq1,
      coeff: key.coeff,
    );
  }

  /// The email address of the service account (`client_email` of the key file).
  final String clientEmail;

  /// The id of the project the service account belongs to (`project_id`), or null when the key file has none.
  final String? projectId;

  /// The id of the key (`private_key_id`), or null when the key file has none.
  final String? privateKeyId;

  /// The modulus of the public key.
  final BigInt modulus;

  /// The exponent of the public key.
  final BigInt publicExponent;

  final BigInt _p;
  final BigInt _q;
  final BigInt _dmp1;
  final BigInt _dmq1;
  final BigInt _coeff;

  /// Signs [data] with RSASSA-PKCS1-v1_5 and SHA-256 (the `RS256` algorithm of JWT) and returns the raw
  /// signature (as long as the modulus). Throws a [StateError] if the signature does not verify with the public
  /// key (a fault during the computation); nothing is returned then.
  Uint8List signRs256(List<int> data) => rs256.signRs256(
    data,
    n: modulus,
    e: publicExponent,
    p: _p,
    q: _q,
    dmp1: _dmp1,
    dmq1: _dmq1,
    coeff: _coeff,
  );

  @override
  String toString() => 'ServiceAccountKey($clientEmail, <redacted>)';
}
