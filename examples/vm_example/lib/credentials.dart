import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:firebase_common/firebase_common.dart';
import 'package:googleapis_auth/auth_io.dart';

class ServiceCredential extends InternalTokenProvider {
  final _tag = 'ServiceCredential';
  final _accountCredentials = new ServiceAccountCredentials.fromJson({
    "type": "",
    "project_id": "",
    "private_key_id": "",
    "private_key": "",
    "client_email": "",
    "client_id": "",
    "auth_uri": "",
    "token_uri": "",
    "auth_provider_x509_cert_url": "",
    "client_x509_cert_url": ""
  });
  var _scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/datastore",
  ];

  final String tokenPath;
  String _uid;

  String _tokenData;
  DateTime _tokenExpiry;

  ServiceCredential([this.tokenPath = 'token.dat']);

  @override
  Future<GetTokenResult> getAccessToken(bool forceRefresh) async {
    if (!forceRefresh) {
      var savedToken = await _fetch();
      if (savedToken != null) {
        var now = DateTime.now();
        DateTime expiry = savedToken['expiry'];
        var tokenData = savedToken['token'];
        if (now.isBefore(expiry)) {
          return GetTokenResult(tokenData);
        } else {
          Log.w(_tag, 'Saved token is expired');
        }
      }
    }
    try {
      var result = await clientViaServiceAccount(_accountCredentials, _scopes);
      var token = result.credentials.accessToken;
      _flush(token.data, token.expiry);
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

  ///Flush token to file
  ///[token] string token
  ///[expiry] token expiry date
  _flush(String token, DateTime expiry) async {
    var file = File(tokenPath);
    var json = jsonEncode({'token': token, 'expiry': expiry.toString()});
    file.writeAsStringSync(json);
  }

  ///Fetch token from file
  Future<Map> _fetch() async {
    if (_tokenExpiry != null && _tokenData != null) {
      return {'token': _tokenExpiry, 'expiry': _tokenExpiry};
    }
    var file = File(tokenPath);
    if (file.existsSync()) {
      try {
        var json = jsonDecode(file.readAsStringSync());
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
