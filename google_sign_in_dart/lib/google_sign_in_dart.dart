library google_sign_in_dart;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    as platform;
import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

export 'src/platform_js.dart' if (dart.library.io) 'src/platform_io.dart';

part 'src/code_exchange_sing_in.dart';

part 'src/common.dart';

part 'src/crypto.dart';

part 'src/data_storage.dart';

part 'src/token_sign_in.dart';

/// Signature used by the [_codeExchangeSignIn] to allow opening a browser window
/// in a platform specific way.
typedef UrlPresenter = void Function(Uri uri);

/// Interface for persisting key/value pairs
abstract class Store {
  /// Persist the [value] at [key].
  void set(String key, String value);

  /// Remove the value at specified [key] if exists.
  void remove(String key);

  /// Get the value at specified [key] or nul if it doesn't exists.
  String get(String key);

  /// Remove all the values store.
  void clearAll();
}

/// Implementation of the google_sign_in plugin in pure dart.
class GoogleSignInPlatform extends platform.GoogleSignInPlatform {
  GoogleSignInPlatform._({
    @required DataStorage storage,
    @required String clientId,
    @required UrlPresenter presenter,
    String exchangeEndpoint,
  })  : assert(storage != null),
        assert(clientId != null),
        assert(presenter != null),
        _storage = storage,
        _clientId = clientId,
        _presenter = presenter,
        _exchangeEndpoint = exchangeEndpoint;

  /// Registers this implementation as default implementation for GoogleSignIn
  ///
  /// [storage] is used to persist tokens between sessions, make sure you save
  /// Your application should provide a [storage] implementation that can store
  /// the tokens is a secure, long-lived location that is accessible between
  /// different invocations of your application.
  /// see [GoogleSignInPlatform.presenter]
  static Future<void> register({
    @required String clientId,
    String exchangeEndpoint,
    DataStorage storage,
    UrlPresenter presenter,
  }) async {
    presenter ??= (Uri uri) => launch(uri.toString());

    if (storage == null) {
      WidgetsFlutterBinding.ensureInitialized();
      final SharedPreferences _preferences =
          await SharedPreferences.getInstance();
      final _SharedPreferencesStore store =
          _SharedPreferencesStore(_preferences);
      storage = DataStorage._(store: store, clientId: clientId);
    }

    // If tokenExchangeEndpoint is removed in a session after the user was
    // logged in, we need to clear the refresh token since we can non longer use
    // it.
    if (storage.refreshToken != null && exchangeEndpoint == null) {
      storage.refreshToken = null;
    }

    platform.GoogleSignInPlatform.instance = GoogleSignInPlatform._(
      presenter: presenter,
      storage: storage,
      exchangeEndpoint: exchangeEndpoint,
      clientId: clientId,
    );
  }

  final String _exchangeEndpoint;
  final String _clientId;
  final DataStorage _storage;

  UrlPresenter _presenter;
  List<String> _scopes;
  String _hostedDomain;

  platform.GoogleSignInTokenData _tokenData;
  String _refreshToken;
  DateTime _expiresAt;

  @override
  Future<void> init({
    @required String hostedDomain,
    List<String> scopes = const <String>[],
    platform.SignInOption signInOption = platform.SignInOption.standard,
    String clientId,
  }) async {
    assert(clientId == null || clientId == _clientId,
        'ClientID ($clientId) does not match the one used to register the plugin $_clientId.');
    assert(
        !scopes.any((String scope) => scope.contains(' ')),
        'OAuth 2.0 Scopes for Google APIs can\'t contain spaces.'
        'Check https://developers.google.com/identity/protocols/googlescopes '
        'for a list of valid OAuth 2.0 scopes.');

    _scopes = scopes;
    _hostedDomain = hostedDomain;
    _initFromStore();
  }

  /// Used by the sign in flow to allow opening of a browser in a platform
  /// specific way.
  ///
  /// You can open the link in a in-app WebView or you can open it in the system
  /// browser
  UrlPresenter get presenter => _presenter;

  set presenter(UrlPresenter value) {
    assert(value != null);
    _presenter = value;
  }

  @override
  Future<platform.GoogleSignInUserData> signIn() async {
    if (_haveValidToken) {
      return _storage.userData;
    } else {
      await _performSignIn();
      return _storage.userData;
    }
  }

  @override
  Future<platform.GoogleSignInUserData> signInSilently() async {
    if (_haveValidToken) {
      return _storage.userData;
    } else if (_refreshToken != null) {
      try {
        await _doTokenRefresh();
        return _storage.userData;
      } catch (e) {
        throw PlatformException(
            code: GoogleSignIn.kSignInFailedError, message: e.toString());
      }
    }

    throw PlatformException(code: GoogleSignIn.kSignInRequiredError);
  }

  @override
  Future<platform.GoogleSignInTokenData> getTokens(
      {String email, bool shouldRecoverAuth}) async {
    if (_haveValidToken) {
      return _tokenData;
    } else if (_refreshToken != null) {
      // if refreshing the token fails, and shouldRecoverAuth is true, then we
      // will prompt the user to login again
      try {
        await _doTokenRefresh();
        return _tokenData;
      } catch (_) {}
    }

    if (shouldRecoverAuth) {
      await _performSignIn();
      return _tokenData;
    } else {
      throw PlatformException(
          code: GoogleSignInAccount.kUserRecoverableAuthError);
    }
  }

  @override
  Future<bool> isSignedIn() async {
    if (_haveValidToken) {
      return true;
    } else if (_refreshToken != null) {
      try {
        await _doTokenRefresh();
        return _haveValidToken;
      } catch (_) {}
    }

    return false;
  }

  @override
  Future<void> signOut() async {
    _storage.clearAll();
    _initFromStore();
  }

  @override
  Future<void> disconnect() async {
    await _revokeToken();
    _storage.clear();
    _initFromStore();
  }

  @override
  Future<void> clearAuthCache({String token}) async {
    await _revokeToken();
    _storage.clear();
    _initFromStore();
  }

  Future<void> _revokeToken() async {
    if (_haveValidToken) {
      await get(
        'https://oauth2.googleapis.com/revoke?token=${_tokenData.accessToken}',
        headers: <String, String>{
          'content-type': 'application/x-www-form-urlencoded'
        },
      );
    }
  }

  Future<void> _fetchUserProfile() async {
    if (_haveValidToken) {
      final String token = _tokenData.accessToken;
      final Response response = await get(
        'https://openidconnect.googleapis.com/v1/userinfo',
        headers: <String, String>{
          'Authorization': 'Bearer $token',
        },
      );

      final Map<String, dynamic> result = jsonDecode(response.body);
      _storage.saveUserProfile(result);
    }
  }

  bool get _haveValidToken {
    return _expiresAt != null && DateTime.now().isBefore(_expiresAt);
  }

  Future<void> _performSignIn() async {
    Future<Map<String, dynamic>> future;
    if (_exchangeEndpoint != null) {
      future = _codeExchangeSignIn(
        scope: _scopes.join(' '),
        clientId: _clientId,
        hostedDomains: _hostedDomain,
        presenter: presenter,
        exchangeEndpoint: _exchangeEndpoint,
        uid: _storage.id,
      );
    } else {
      future = _tokenSignIn(
        scope: _scopes.join(' '),
        clientId: _clientId,
        hostedDomains: _hostedDomain,
        presenter: presenter,
        uid: _storage.id,
      );
    }

    final Map<String, dynamic> result = await future.catchError(
      (dynamic error, StackTrace s) {
        throw PlatformException(
            code: GoogleSignInAccount.kFailedToRecoverAuthError,
            message: error.toString());
      },
    );

    _storage.saveResult(result);
    _initFromStore();
    await _fetchUserProfile();
  }

  Future<void> _doTokenRefresh() async {
    assert(_exchangeEndpoint != null);
    assert(_refreshToken != null);

    final Uri uri = Uri.parse(_exchangeEndpoint).replace(
      queryParameters: <String, String>{
        'refreshToken': _refreshToken,
        'clientId': _clientId,
      },
    );

    final Response response = await get(uri);
    if (response.statusCode == 200) {
      final Map<String, dynamic> result =
          Map<String, dynamic>.from(jsonDecode(response.body));

      _storage.saveResult(result);
      _initFromStore();
      await _fetchUserProfile();
    } else {
      return Future<Map<String, dynamic>>.error(response.body);
    }
  }

  void _initFromStore() {
    _refreshToken = _storage.refreshToken;
    _expiresAt = _storage.expiresAt;
    _tokenData = _storage.tokenData;
  }
}

class _SharedPreferencesStore extends Store {
  _SharedPreferencesStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  String get(String key) {
    return _preferences.get(key);
  }

  @override
  void remove(String key) {
    _preferences.remove(key);
  }

  @override
  void set(String key, String value) {
    _preferences.setString(key, value);
  }

  @override
  void clearAll() {
    _preferences.clear();
  }
}
