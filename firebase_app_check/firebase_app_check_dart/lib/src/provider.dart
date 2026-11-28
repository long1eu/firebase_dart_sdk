import 'dart:math';

import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:meta/meta.dart';

final RegExp _uuid4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// What produces App Check tokens for a `FirebaseAppCheck`: a [DebugAppCheckProvider] or a
/// [CustomAppCheckProvider].
///
/// It cannot be extended or implemented outside this package. More providers may be added in a
/// later release.
abstract final class AppCheckProvider {}

/// Exchanges a debug token for App Check tokens.
///
/// A debug token is a secret: whoever holds it gets App Check tokens for the app until the token
/// is deleted in the Firebase console. Do not ship it in a distributed build. This class has no
/// member that returns it, and [toString] does not print it.
final class DebugAppCheckProvider extends AppCheckProvider {
  /// A provider that exchanges [debugToken], which must be registered for the app in the Firebase
  /// console (App Check, Apps, Manage debug tokens).
  ///
  /// Throws an [ArgumentError] (without the value) unless [debugToken] is a version 4 UUID:
  /// `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`, ignoring case.
  DebugAppCheckProvider({required String debugToken})
    : _debugToken = _checked(debugToken);

  final String _debugToken;

  /// A new random version 4 UUID (lowercase) from [Random.secure].
  ///
  /// It is returned to the caller; this package never logs or stores it. Register it in the
  /// Firebase console, which accepts a token you supply.
  static String generateDebugToken() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final StringBuffer text = StringBuffer();
    for (int index = 0; index < bytes.length; index++) {
      if (index == 4 || index == 6 || index == 8 || index == 10) {
        text.write('-');
      }
      text.write(bytes[index].toRadixString(16).padLeft(2, '0'));
    }
    return text.toString();
  }

  static String _checked(String debugToken) {
    if (!isValidDebugToken(debugToken)) {
      throw ArgumentError('must be a version 4 UUID', 'debugToken');
    }
    return debugToken;
  }

  @override
  String toString() => 'DebugAppCheckProvider(<redacted>)';
}

/// Gets App Check tokens from the app's own function, for example one that asks the app's server.
///
/// The callback is called for every exchange, with a deadline of 7 s:
/// - `limitedUse`: the token is for `getLimitedUseToken` and must be minted for one use;
/// - `forceRefresh`: the previous token was rejected; return a different one.
///
/// The token must be 1 to 8192 printable ASCII characters without a space and must expire at
/// least 60 s from now; an expiry later than 7 days from now is treated as 7 days.
final class CustomAppCheckProvider extends AppCheckProvider {
  /// A provider that calls [getToken] for every exchange.
  CustomAppCheckProvider({
    required Future<AppCheckToken> Function({
      required bool limitedUse,
      required bool forceRefresh,
    })
    getToken,
  }) : _getToken = getToken;

  final Future<AppCheckToken> Function({
    required bool limitedUse,
    required bool forceRefresh,
  })
  _getToken;

  @override
  String toString() => 'CustomAppCheckProvider()';
}

/// True when [value] is a version 4 UUID, ignoring case.
@internal
bool isValidDebugToken(String value) => _uuid4Pattern.hasMatch(value);

/// The debug token of [provider], as it was given. The only reader of the private field: the
/// value goes to the exchange client and nowhere else.
@internal
String debugTokenOf(DebugAppCheckProvider provider) => provider._debugToken;

/// The callback of [provider].
@internal
Future<AppCheckToken> Function({
  required bool limitedUse,
  required bool forceRefresh,
})
customCallbackOf(CustomAppCheckProvider provider) => provider._getToken;
