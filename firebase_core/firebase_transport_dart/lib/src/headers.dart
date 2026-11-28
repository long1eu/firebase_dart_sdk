import 'package:firebase_transport_dart/src/runtime_version.dart';

/// The names of the headers the Firebase backends read.
///
/// The package adds none of them by itself: which ones a product sends is that product's decision.
abstract final class FirebaseHeaders {
  /// Carries the Auth token as `Bearer <token>` or `Firebase <token>`.
  static const String authorization = 'Authorization';

  /// Carries the bare Auth token.
  static const String firebaseAuthToken = 'X-Firebase-Auth-Token';

  /// Carries the App Check token.
  static const String appCheck = 'X-Firebase-AppCheck';

  /// Carries the app id of the Firebase options.
  static const String gmpId = 'X-Firebase-GMPID';

  /// Carries the API key of the Firebase options.
  static const String apiKey = 'X-Goog-Api-Key';

  /// Carries the client description that [apiClientHeader] builds.
  static const String apiClient = 'X-Goog-Api-Client';
}

/// How a backend wants the Auth token of a request.
enum AuthHeaderStyle {
  /// `Authorization: Bearer <token>`.
  bearer,

  /// `Authorization: Firebase <token>`.
  firebase,

  /// `X-Firebase-Auth-Token: <token>`.
  firebaseAuthToken,
}

/// The longest token, and the longest header value, the package lets through.
///
/// The number is this package's own bound on what a provider can make the client put into a header;
/// it is not a server limit.
const int maxTokenLength = 8192;

final RegExp _clientPart = RegExp(r'^[A-Za-z0-9._/-]+$');

/// True for 1 to 8192 characters, each in U+0021 to U+007E: what may be sent as a token.
bool isTokenText(String value) =>
    value.isNotEmpty && _hasOnlyCodeUnits(value, from: 0x21);

/// True for 1 to 8192 characters, each in U+0020 to U+007E, without a leading or trailing space.
///
/// A product checks with it every header value it did not write itself, and refuses a failing one
/// with an `ArgumentError` that names the header and never the value.
bool isHeaderValue(String value) {
  if (value.isEmpty || value.startsWith(' ') || value.endsWith(' ')) {
    return false;
  }
  return _hasOnlyCodeUnits(value, from: 0x20);
}

/// Whether [value] has at most [maxTokenLength] characters, each from [from] to U+007E.
bool _hasOnlyCodeUnits(String value, {required int from}) {
  if (value.length > maxTokenLength) {
    return false;
  }
  for (int i = 0; i < value.length; i++) {
    final int unit = value.codeUnitAt(i);
    if (unit < from || unit > 0x7E) {
      return false;
    }
  }
  return true;
}

/// The value of [FirebaseHeaders.apiClient]: `gl-dart/<runtime> fire/<sdkVersion>` followed by the
/// parts of [extra], separated by spaces.
///
/// Throws an [ArgumentError] when [sdkVersion] or a part of [extra] does not match
/// `^[A-Za-z0-9._/-]+$`.
String apiClientHeader({
  required String sdkVersion,
  List<String> extra = const <String>[],
}) {
  if (!_clientPart.hasMatch(sdkVersion)) {
    throw ArgumentError('sdkVersion may hold only letters, digits and . _ / -');
  }
  final StringBuffer header = StringBuffer(
    'gl-dart/$dartRuntimeVersion fire/$sdkVersion',
  );
  for (final String part in extra) {
    if (!_clientPart.hasMatch(part)) {
      throw ArgumentError(
        'each part of extra may hold only letters, digits and . _ / -',
      );
    }
    header
      ..write(' ')
      ..write(part);
  }
  return header.toString();
}
