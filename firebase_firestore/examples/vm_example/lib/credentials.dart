import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_common/firebase_common.dart';
import 'package:googleapis_auth/auth_io.dart';

class ServiceCredential extends InternalTokenProvider {
  ServiceCredential([this.tokenPath = 'token.dat']);

  final String _tag = 'ServiceCredential';
  final ServiceAccountCredentials _accountCredentials =
      ServiceAccountCredentials.fromJson(<String, dynamic>{
    'type': '',
    'project_id': '',
    'private_key_id': '',
    'private_key': '',
    'client_email': '',
    'client_id': '',
    'auth_uri': '',
    'token_uri': '',
    'auth_provider_x509_cert_url': '',
    'client_x509_cert_url': '',
  });
  final List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/datastore',
  ];

  final String tokenPath;
  String _uid;

  String _tokenData;
  DateTime _tokenExpiry;

  @override
  Future<GetTokenResult> getAccessToken(bool forceRefresh) async {
    if (!forceRefresh) {
      final Map<String, dynamic> savedToken = await _fetch();
      if (savedToken != null) {
        final DateTime now = DateTime.now();
        final DateTime expiry = savedToken['expiry'];
        final dynamic tokenData = savedToken['token'];
        if (now.isBefore(expiry)) {
          return GetTokenResult(tokenData);
        } else {
          Log.w(_tag, 'Saved token is expired');
        }
      }
    }
    try {
      final AutoRefreshingAuthClient result =
          await clientViaServiceAccount(_accountCredentials, _scopes);
      final AccessToken token = result.credentials.accessToken;
      await _flush(token.data, token.expiry);
      result.close();
      return GetTokenResult(token.data);
    } catch (e) {
      Log.e(_tag, 'getAccessToken error $e');
    }
    return null;
  }

  @override
  Stream<InternalTokenResult> get onTokenChanged => null;

  @override
  String get uid => _uid;

  /// Flush token to file
  /// [token] string token
  /// [expiry] token expiry date
  Future<void> _flush(String token, DateTime expiry) async {
    final File file = File(tokenPath);
    final String json = jsonEncode(<String, dynamic>{
      'token': token,
      'expiry': expiry.toString(),
    });
    file.writeAsStringSync(json);
  }

  ///Fetch token from file
  Future<Map<String, dynamic>> _fetch() async {
    if (_tokenExpiry != null && _tokenData != null) {
      return <String, dynamic>{'token': _tokenData, 'expiry': _tokenExpiry};
    }
    final File file = File(tokenPath);
    if (file.existsSync()) {
      try {
        final dynamic json = jsonDecode(file.readAsStringSync());
        json['expiry'] = DateTime.parse(json['expiry']);
        _tokenExpiry = json['expiry'];
        _tokenData = json['token'];
        return json;
      } catch (e) {
        Log.e(_tag, '_fetch error $e');
      }
    }
    return null;
  }
}
