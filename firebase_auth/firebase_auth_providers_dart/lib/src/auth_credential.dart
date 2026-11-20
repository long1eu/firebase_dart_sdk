// The provider ids and sign-in method names are FlutterFire's (and the JS SDK's) constants, in their upper case.
// ignore_for_file: constant_identifier_names

import 'dart:convert';

import 'action_code.dart';
import 'auth_exception.dart';
import 'auth_user.dart';
import 'firebase_user_auth.dart';

/// Proof of an identity that [FirebaseUserAuth.signInWithCredential], [FirebaseUserAuth.linkWithCredential] and
/// [FirebaseUserAuth.reauthenticateWithCredential] take (`AuthCredential` of FlutterFire and of the JS SDK). Make one
/// with a provider: [EmailAuthProvider].
///
/// A credential holds a secret (a password, an email link, a token): [toString] shows only the provider and the
/// sign-in method.
abstract class AuthCredential {
  /// Constructor for subclasses. Only the credentials of this package can be used to sign in.
  const AuthCredential({required this.providerId, required this.signInMethod});

  /// The provider: `password`, `google.com`, `oidc.<name>`, ...
  final String providerId;

  /// How the credential signs in: `password`, `emailLink`, or the provider id for the federated providers.
  final String signInMethod;

  @override
  String toString() =>
      '$runtimeType(providerId: $providerId, signInMethod: $signInMethod)';
}

/// A credential of the email and password provider: an email address with a password, or with an email link
/// (FlutterFire's `EmailAuthCredential`). Make it with [EmailAuthProvider.credential] or
/// [EmailAuthProvider.credentialWithLink].
class EmailAuthCredential extends AuthCredential {
  const EmailAuthCredential._(
    String signInMethod, {
    required this.email,
    this.password,
    this.emailLink,
  }) : super(
         providerId: EmailAuthProvider.PROVIDER_ID,
         signInMethod: signInMethod,
       );

  /// The email address.
  final String email;

  /// The password, for [EmailAuthProvider.EMAIL_PASSWORD_SIGN_IN_METHOD]. Not part of [toString].
  final String? password;

  /// The sign-in link of the email, for [EmailAuthProvider.EMAIL_LINK_SIGN_IN_METHOD]. Not part of [toString].
  final String? emailLink;

  /// The credential in the JSON shape of the JS SDK's `toJSON`, which [fromJson] here and `fromJSON` of the JS SDK
  /// read back: `email`, `password`, `signInMethod` and `tenantId` (null when there is none).
  ///
  /// For an email link, as in the JS SDK, `password` is the code of the link (`oobCode`) and `tenantId` its tenant;
  /// the rest of the link is not kept. Throws an [ArgumentError] when [emailLink] is not the link of an action email
  /// ([ActionCodeURL.parseLink]).
  ///
  /// The map holds the password or the code of the link: keep it as secret as they are.
  Map<String, Object?> toJson() {
    final String? link = emailLink;
    if (link == null) {
      return <String, Object?>{
        'email': email,
        'password': password,
        'signInMethod': signInMethod,
        'tenantId': null,
      };
    }
    final ActionCodeURL? url = ActionCodeURL.parseLink(link);
    if (url == null) {
      throw ArgumentError(
        'The email link of the credential is not the link of an action email',
      );
    }
    return <String, Object?>{
      'email': email,
      'password': url.code,
      'signInMethod': signInMethod,
      'tenantId': url.tenantId,
    };
  }

  /// Reads the JSON of [toJson] or of the JS SDK's `toJSON` (`EmailAuthCredential.fromJSON`): [json] is the map, or
  /// its JSON text.
  ///
  /// As in the JS SDK, returns null when it is not the JSON of an email credential: not a map, an empty or missing
  /// `email` or `password`, or a `signInMethod` other than `password` and `emailLink`; and text that is not JSON
  /// throws (a [FormatException] here, as `JSON.parse` throws there). Unlike the JS SDK, a value that is not a string
  /// counts as missing.
  ///
  /// The JSON of an email link holds only the code of the link and its tenant: the [emailLink] of the credential is
  /// then a link made of them, `https://localhost/?apiKey=none&mode=signIn&oobCode=<code>[&tenantId=<tenant>]`.
  static EmailAuthCredential? fromJson(Object json) {
    final Map<Object?, Object?>? map = _jsonMap(json);
    final Object? email = map?['email'];
    final Object? password = map?['password'];
    if (email is! String ||
        email.isEmpty ||
        password is! String ||
        password.isEmpty) {
      return null;
    }
    final Object? tenantId = map!['tenantId'];
    return switch (map['signInMethod']) {
      EmailAuthProvider.EMAIL_PASSWORD_SIGN_IN_METHOD =>
        EmailAuthProvider.credential(email: email, password: password),
      EmailAuthProvider.EMAIL_LINK_SIGN_IN_METHOD =>
        EmailAuthProvider.credentialWithLink(
          email: email,
          emailLink: _signInLinkOf(
            password,
            tenantId is String ? tenantId : null,
          ),
        ),
      _ => null,
    };
  }
}

/// [json] as a map: a map as it is, and a string decoded first (a [FormatException] when it is not JSON); null for
/// anything else.
Map<Object?, Object?>? _jsonMap(Object json) {
  final Object? value = json is String ? jsonDecode(json) : json;
  return value is Map ? value : null;
}

/// A sign-in link with only the [code] and the [tenantId], for an email link credential read from JSON.
String _signInLinkOf(String code, String? tenantId) {
  final String tenant = tenantId == null
      ? ''
      : '&tenantId=${Uri.encodeComponent(tenantId)}';
  return 'https://localhost/?apiKey=none&mode=signIn'
      '&oobCode=${Uri.encodeComponent(code)}$tenant';
}

/// The email and password provider (`EmailAuthProvider` of FlutterFire and of the JS SDK): makes the credentials of
/// an email address with a password or with an email link.
///
/// ```dart
/// final AuthCredential credential = EmailAuthProvider.credential(
///   email: 'ada@example.com',
///   password: 'correct horse',
/// );
/// await auth.reauthenticateWithCredential(credential);
/// ```
abstract final class EmailAuthProvider {
  /// The provider id: `password`.
  static const String PROVIDER_ID = 'password';

  /// The sign-in method of an email address with a password: `password`.
  static const String EMAIL_PASSWORD_SIGN_IN_METHOD = 'password';

  /// The sign-in method of an email link: `emailLink`.
  static const String EMAIL_LINK_SIGN_IN_METHOD = 'emailLink';

  /// The credential of [email] and [password].
  static EmailAuthCredential credential({
    required String email,
    required String password,
  }) => EmailAuthCredential._(
    EMAIL_PASSWORD_SIGN_IN_METHOD,
    email: email,
    password: password,
  );

  /// The credential of [email] and the sign-in link of the email [FirebaseUserAuth.sendSignInLinkToEmail] sent
  /// to it ([emailLink], the whole link, as the app received it).
  ///
  /// The link is checked when the credential is used: one that is not a sign-in link
  /// ([ActionCodeURL.parseLink]) fails with `argument-error`.
  static EmailAuthCredential credentialWithLink({
    required String email,
    required String emailLink,
  }) => EmailAuthCredential._(
    EMAIL_LINK_SIGN_IN_METHOD,
    email: email,
    emailLink: emailLink,
  );
}

/// A credential of a federated identity provider (`OAuthCredential` of FlutterFire and of the JS SDK): the ID token
/// or the access token (with the secret, for Twitter's OAuth 1.0a) that the app obtained from the provider by other
/// means (a platform sign-in SDK, a browser flow of its own). Make it with a provider: [GoogleAuthProvider],
/// [AppleAuthProvider], [FacebookAuthProvider], [GithubAuthProvider], [TwitterAuthProvider],
/// [MicrosoftAuthProvider], [YahooAuthProvider], or [OAuthProvider] for any other provider id (`oidc.<name>`, ...).
///
/// [FirebaseUserAuth.signInWithCredential] exchanges it through `accounts:signInWithIdp`, as the JS SDK does; the
/// backend checks the token with the provider and against the provider's configuration in the project (for an ID
/// token, its audience must be a client id configured for the provider).
///
/// The tokens are secrets: [toString] leaves them out.
class OAuthCredential extends AuthCredential {
  /// Creates the credential. Use a provider instead; this constructor is for the package and for tests.
  const OAuthCredential({
    required super.providerId,
    required super.signInMethod,
    this.idToken,
    this.accessToken,
    this.secret,
    this.rawNonce,
    this.pendingToken,
    this.appleFullPersonName,
  });

  /// The OpenID Connect ID token of the provider.
  final String? idToken;

  /// The OAuth access token of the provider (for Twitter, the OAuth 1.0a token).
  final String? accessToken;

  /// The OAuth 1.0a token secret, for Twitter.
  final String? secret;

  /// The nonce whose SHA-256 hash the ID token carries (Apple, and OpenID Connect providers that the app asked
  /// for a nonce). Sent as it is; the backend hashes it.
  final String? rawNonce;

  /// A token of the backend that stands for the provider's credential, in the credentials of
  /// [UserCredential.credential] and [FirebaseAuthException.credential] when the backend returned one instead of the
  /// provider's tokens. When set, it is sent instead of the tokens.
  final String? pendingToken;

  /// The name of the user, for [AppleAuthProvider.credentialWithIDToken] (Apple sends it only to the app, once).
  /// Kept for FlutterFire compatibility; like the JS SDK, it is not sent to the backend: set it with
  /// `updateProfile` after the first sign-in if you want it.
  final AppleFullPersonName? appleFullPersonName;

  /// The credential in the JSON shape of the JS SDK's `toJSON` (as `JSON.stringify` writes it), which [fromJson]
  /// and [OAuthProvider.credentialFromJson] here and `fromJSON` and `OAuthProvider.credentialFromJSON` of the JS SDK
  /// read back: `idToken`, `accessToken`, `secret` and `nonce` ([rawNonce]) when they are set, `pendingToken` (null
  /// when there is none), `providerId` and `signInMethod`. [appleFullPersonName] has no key in the JS SDK and is
  /// left out.
  ///
  /// The map holds the provider's tokens: keep it as secret as they are.
  Map<String, Object?> toJson() => <String, Object?>{
    'idToken': ?idToken,
    'accessToken': ?accessToken,
    'secret': ?secret,
    'nonce': ?rawNonce,
    'pendingToken': pendingToken,
    'providerId': providerId,
    'signInMethod': signInMethod,
  };

  /// Reads the JSON of [toJson] or of the JS SDK's `toJSON` (`OAuthCredential.fromJSON`): [json] is the map, or its
  /// JSON text.
  ///
  /// As in the JS SDK, returns null when it is not the JSON of a credential: not a map, or an empty or missing
  /// `providerId` or `signInMethod`; and text that is not JSON throws (a [FormatException] here, as `JSON.parse`
  /// throws there). Unlike the JS SDK, a field that is there and not a string also gives null. Like the JS SDK, it
  /// needs no token (an empty `idToken`, `accessToken` or `pendingToken` counts as none):
  /// [OAuthProvider.credentialFromJson] checks that there is one.
  static OAuthCredential? fromJson(Object json) {
    final Map<Object?, Object?>? map = _jsonMap(json);
    if (map == null) {
      return null;
    }
    final Object? providerId = map['providerId'];
    final Object? signInMethod = map['signInMethod'];
    if (providerId is! String ||
        providerId.isEmpty ||
        signInMethod is! String ||
        signInMethod.isEmpty ||
        _oauthTokenKeys.any((String key) => map[key] is! String?)) {
      return null;
    }
    return OAuthCredential(
      providerId: providerId,
      signInMethod: signInMethod,
      idToken: _nonEmpty(map['idToken']),
      accessToken: _nonEmpty(map['accessToken']),
      secret: map['secret'] as String?,
      rawNonce: map['nonce'] as String?,
      pendingToken: _nonEmpty(map['pendingToken']),
    );
  }
}

/// The keys of the JSON of an [OAuthCredential] that hold an optional string.
const List<String> _oauthTokenKeys = <String>[
  'idToken',
  'accessToken',
  'secret',
  'nonce',
  'pendingToken',
];

/// [value], a string or null, with an empty string as null (`value || undefined` of the JS SDK).
String? _nonEmpty(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// The name Sign in with Apple gives the app on the first sign-in (FlutterFire's `AppleFullPersonName`).
class AppleFullPersonName {
  /// Creates the name.
  const AppleFullPersonName({
    this.givenName,
    this.familyName,
    this.middleName,
    this.nickname,
    this.namePrefix,
    this.nameSuffix,
  });

  /// The given name.
  final String? givenName;

  /// The family name.
  final String? familyName;

  /// The middle name.
  final String? middleName;

  /// The nickname.
  final String? nickname;

  /// The name prefix.
  final String? namePrefix;

  /// The name suffix.
  final String? nameSuffix;
}

OAuthCredential _oauth(
  String providerId, {
  String? idToken,
  String? accessToken,
  String? secret,
  String? rawNonce,
  String? pendingToken,
  AppleFullPersonName? appleFullPersonName,
}) {
  if ((idToken == null || idToken.isEmpty) &&
      (accessToken == null || accessToken.isEmpty) &&
      (pendingToken == null || pendingToken.isEmpty)) {
    // OAuthCredential._fromParams of the JS SDK.
    throw ArgumentError(
      'A credential of $providerId needs an ID token or an access token',
    );
  }
  return OAuthCredential(
    providerId: providerId,
    signInMethod: providerId,
    idToken: idToken,
    accessToken: accessToken,
    secret: secret,
    rawNonce: rawNonce,
    pendingToken: pendingToken,
    appleFullPersonName: appleFullPersonName,
  );
}

/// Any federated provider by its id (`OAuthProvider` of FlutterFire and of the JS SDK): `oidc.<name>` for an
/// OpenID Connect provider configured in Identity Platform, `microsoft.com`, `yahoo.com`, `apple.com`, ...
///
/// ```dart
/// final OAuthCredential credential = OAuthProvider('oidc.my-idp').credential(
///   idToken: idTokenFromTheProvider,
/// );
/// await auth.signInWithCredential(credential);
/// ```
///
/// There is no popup or redirect flow in this package: the app gets the token from the provider itself.
class OAuthProvider {
  /// The provider [providerId].
  OAuthProvider(this.providerId);

  /// The provider id.
  final String providerId;

  /// A credential with the provider's [idToken] and/or [accessToken] (FlutterFire's and the JS SDK's
  /// `credential`). [rawNonce] is the nonce whose hash the ID token carries, if the app asked for one; [secret]
  /// is an OAuth 1.0a token secret. Throws an [ArgumentError] without a token.
  OAuthCredential credential({
    String? accessToken,
    String? secret,
    String? idToken,
    String? rawNonce,
    String? signInMethod,
  }) {
    final OAuthCredential credential = _oauth(
      providerId,
      idToken: idToken,
      accessToken: accessToken,
      secret: secret,
      rawNonce: rawNonce,
    );
    return signInMethod == null
        ? credential
        : OAuthCredential(
            providerId: providerId,
            signInMethod: signInMethod,
            idToken: idToken,
            accessToken: accessToken,
            secret: secret,
            rawNonce: rawNonce,
          );
  }

  /// Reads the JSON of [OAuthCredential.toJson] or of the JS SDK's `toJSON` into a credential to sign in with
  /// (`OAuthProvider.credentialFromJSON` of the JS SDK): [json] is the map, or its JSON text.
  ///
  /// Unlike [OAuthCredential.fromJson], it throws when the JSON is not that of a usable credential, as the JS SDK
  /// does: an [ArgumentError] (the JS SDK's `argument-error`) when it is not a map, when [OAuthCredential.fromJson]
  /// would return null, or when there is neither an `idToken` nor an `accessToken`; a [FormatException] for text that
  /// is not JSON. As in the JS SDK, `nonce` is dropped when there is a `pendingToken`. Unlike the JS SDK, which drops
  /// it here, `secret` is kept, so that a Twitter credential still signs in.
  static OAuthCredential credentialFromJson(Object json) {
    final Map<Object?, Object?>? map = _jsonMap(json);
    final OAuthCredential? read = map == null
        ? null
        : OAuthCredential.fromJson(map);
    if (read == null) {
      throw ArgumentError(
        'Not the JSON of an OAuth credential: it needs a providerId and a signInMethod',
      );
    }
    if (read.idToken == null && read.accessToken == null) {
      throw ArgumentError(
        'A credential of ${read.providerId} needs an ID token or an access token',
      );
    }
    return OAuthCredential(
      providerId: read.providerId,
      signInMethod: read.signInMethod,
      idToken: read.idToken,
      accessToken: read.accessToken,
      secret: read.secret,
      rawNonce: read.pendingToken == null ? read.rawNonce : null,
      pendingToken: read.pendingToken,
    );
  }
}

/// Google (`GoogleAuthProvider` of FlutterFire and of the JS SDK).
abstract final class GoogleAuthProvider {
  /// The provider id: `google.com`.
  static const String PROVIDER_ID = 'google.com';

  /// The sign-in method: `google.com`.
  static const String GOOGLE_SIGN_IN_METHOD = 'google.com';

  /// A credential with Google's [idToken] (from Google Sign-In; its audience must be a client id of the project)
  /// and/or [accessToken]. Throws an [ArgumentError] without a token.
  static OAuthCredential credential({String? idToken, String? accessToken}) =>
      _oauth(PROVIDER_ID, idToken: idToken, accessToken: accessToken);
}

/// Sign in with Apple (`AppleAuthProvider` of FlutterFire; `OAuthProvider('apple.com')` of the JS SDK).
abstract final class AppleAuthProvider {
  /// The provider id: `apple.com`.
  static const String PROVIDER_ID = 'apple.com';

  /// The sign-in method: `apple.com`.
  static const String APPLE_SIGN_IN_METHOD = 'apple.com';

  /// A credential with an access token of Apple.
  static OAuthCredential credential(String accessToken) =>
      _oauth(PROVIDER_ID, accessToken: accessToken);

  /// A credential with Apple's [idToken] and the [rawNonce] whose SHA-256 hash the app put in the authorization
  /// request. [appleFullPersonName] is kept on the credential and not sent (see
  /// [OAuthCredential.appleFullPersonName]).
  static OAuthCredential credentialWithIDToken(
    String idToken,
    String rawNonce, [
    AppleFullPersonName? appleFullPersonName,
  ]) => _oauth(
    PROVIDER_ID,
    idToken: idToken,
    rawNonce: rawNonce,
    appleFullPersonName: appleFullPersonName,
  );
}

/// Facebook (`FacebookAuthProvider` of FlutterFire and of the JS SDK).
abstract final class FacebookAuthProvider {
  /// The provider id: `facebook.com`.
  static const String PROVIDER_ID = 'facebook.com';

  /// The sign-in method: `facebook.com`.
  static const String FACEBOOK_SIGN_IN_METHOD = 'facebook.com';

  /// A credential with a Facebook access token.
  static OAuthCredential credential(String accessToken) =>
      _oauth(PROVIDER_ID, accessToken: accessToken);
}

/// GitHub (`GithubAuthProvider` of FlutterFire and of the JS SDK).
abstract final class GithubAuthProvider {
  /// The provider id: `github.com`.
  static const String PROVIDER_ID = 'github.com';

  /// The sign-in method: `github.com`.
  static const String GITHUB_SIGN_IN_METHOD = 'github.com';

  /// A credential with a GitHub OAuth access token.
  static OAuthCredential credential(String accessToken) =>
      _oauth(PROVIDER_ID, accessToken: accessToken);
}

/// Twitter, now X (`TwitterAuthProvider` of FlutterFire and of the JS SDK): OAuth 1.0a.
abstract final class TwitterAuthProvider {
  /// The provider id: `twitter.com`.
  static const String PROVIDER_ID = 'twitter.com';

  /// The sign-in method: `twitter.com`.
  static const String TWITTER_SIGN_IN_METHOD = 'twitter.com';

  /// A credential with the OAuth 1.0a [accessToken] and token [secret].
  static OAuthCredential credential({
    required String accessToken,
    required String secret,
  }) => _oauth(PROVIDER_ID, accessToken: accessToken, secret: secret);
}

/// Microsoft (`MicrosoftAuthProvider` of FlutterFire; `OAuthProvider('microsoft.com')` of the JS SDK).
abstract final class MicrosoftAuthProvider {
  /// The provider id: `microsoft.com`.
  static const String PROVIDER_ID = 'microsoft.com';

  /// The sign-in method: `microsoft.com`.
  static const String MICROSOFT_SIGN_IN_METHOD = 'microsoft.com';

  /// A credential with Microsoft's [idToken] and/or [accessToken] (`OAuthProvider('microsoft.com').credential`;
  /// FlutterFire has no such method). The audience of the ID token must be the application id configured for the
  /// provider in the project.
  static OAuthCredential credential({String? idToken, String? accessToken}) =>
      _oauth(PROVIDER_ID, idToken: idToken, accessToken: accessToken);
}

/// Yahoo (`YahooAuthProvider` of FlutterFire; `OAuthProvider('yahoo.com')` of the JS SDK).
abstract final class YahooAuthProvider {
  /// The provider id: `yahoo.com`.
  static const String PROVIDER_ID = 'yahoo.com';

  /// The sign-in method: `yahoo.com`.
  static const String YAHOO_SIGN_IN_METHOD = 'yahoo.com';

  /// A credential with a Yahoo access token (FlutterFire's shape). For an ID token use
  /// `OAuthProvider('yahoo.com').credential(idToken: ...)`.
  static OAuthCredential credential(String accessToken) =>
      _oauth(PROVIDER_ID, accessToken: accessToken);
}
