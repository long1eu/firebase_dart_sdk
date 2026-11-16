import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'credential.dart';
import 'exception.dart';

/// One Firebase project as an administrator reaches it: the project id, the credential, the emulators to use,
/// and the HTTP client. The admin libraries take it: `FirebaseAuthAdmin(app)` of `auth.dart`, or `app.auth()`.
///
/// The Admin SDKs call this an app (`initializeApp` in Node.js); it is named [FirebaseAdminApp] so that it does
/// not collide with `FirebaseApp` of `firebase_app_dart` or FlutterFire when a file imports both.
///
/// **For trusted code only: servers, CLIs, CI jobs and integration tests.** Admin credentials bypass security
/// rules and can act as any user. Never put a service account key in an app, a web page, a Flutter asset of a
/// release build or a repository; on Google Cloud prefer Application Default Credentials with
/// [AdminCredential.iam], which holds no key.
///
/// ```dart
/// import 'package:firebase_admin_dart/auth.dart';
///
/// Future<void> main() async {
///   final FirebaseAdminApp app = FirebaseAdminApp.emulator(
///     projectId: 'demo-test',
///     authEmulatorHost: '127.0.0.1:9099',
///   );
///   final AdminUser user = await app.auth().createUser();
///   print(user.uid);
///   await app.close();
/// }
/// ```
class FirebaseAdminApp {
  /// Admin calls for the project [projectId] with [credential].
  ///
  /// [httpClient] is used for every request (Google APIs, OAuth, IAM, the metadata server, Google's public keys)
  /// and is not closed by [close]; without it one is created and closed. [clock] is for tests.
  FirebaseAdminApp({
    required String projectId,
    required AdminCredential credential,
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : this._(projectId, credential, null, httpClient, clock);

  /// Admin calls against the Firebase emulators, for the project [projectId] (any id; use a `demo-` id, which
  /// never reaches a real project). [authEmulatorHost] (`host:port`, or `http://host:port`) is the Auth
  /// emulator.
  ///
  /// No credential is used: requests carry `Authorization: Bearer owner`, custom tokens are unsigned, and the
  /// emulator's unsigned ID tokens are accepted. Only this constructor turns that on; no environment variable
  /// does. Pass `FirebaseUserAuth.emulatorHostFromEnvironment` yourself if you want the variable.
  ///
  /// The host is checked like the emulator host of `FirebaseUserAuth`: an [ArgumentError] is thrown for user
  /// info, a path, a query, a bad port or a Google host. A host off the loopback interface logs a warning.
  FirebaseAdminApp.emulator({
    required String projectId,
    required String authEmulatorHost,
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : this._(projectId, null, authEmulatorHost, httpClient, clock);

  FirebaseAdminApp._(
    this.projectId,
    this.credential,
    this.authEmulatorHost,
    http.Client? httpClient,
    DateTime Function()? clock,
  ) : _authEmulatorOrigin = authEmulatorHost == null
          ? null
          : FirebaseUserAuth.emulatorOrigin(authEmulatorHost),
      _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null,
      _clock = clock ?? DateTime.now {
    if (projectId.isEmpty || projectId.contains(RegExp(r'[/?#\s]'))) {
      throw ArgumentError.value(projectId, 'projectId', 'Not a project id');
    }
    _tokens = switch (credential) {
      ServiceAccountCredential(:final Object json) =>
        OAuthTokenProvider.serviceAccount(
          json,
          scopes: AdminCredential.scopes,
          httpClient: _http,
          clock: clock,
        ),
      IamCredential(:final OAuthTokenProvider tokens) => tokens,
      null => null,
    };
  }

  /// The project the calls are for.
  final String projectId;

  /// The credential, or null for [FirebaseAdminApp.emulator].
  final AdminCredential? credential;

  /// The Auth emulator as it was passed to [FirebaseAdminApp.emulator], or null.
  final String? authEmulatorHost;

  /// Whether the calls go to the emulators ([FirebaseAdminApp.emulator]).
  bool get isEmulator => credential == null;

  final String? _authEmulatorOrigin;
  final http.Client _http;
  final bool _ownsHttp;
  final DateTime Function() _clock;
  late final OAuthTokenProvider? _tokens;
  bool _closed = false;
  String? _metadataEmail;

  /// The issuer of the data signed in emulator mode, as the Node Admin SDK names it.
  static const String emulatorServiceAccount =
      'firebase-auth-emulator@example.com';

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Ends the use of this app and of the admin objects made from it: closes the HTTP client if the app created
  /// it. Calls after [close] throw a [StateError].
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsHttp) {
      _http.close();
    }
  }

  // ---------------------------------------------------------------------------------------------------------
  // For the admin libraries of this package.

  /// Throws a [StateError] after [close].
  @internal
  void checkOpen() {
    if (_closed) {
      throw StateError('This FirebaseAdminApp was closed.');
    }
  }

  /// The HTTP client of the app.
  @internal
  http.Client get httpClient => _http;

  /// The current time.
  @internal
  DateTime now() => _clock();

  /// `http://host:port` of the Auth emulator, or null.
  @internal
  String? get authEmulatorOrigin => _authEmulatorOrigin;

  /// The headers that authorize a request to a Google API: an access token of the credential (and
  /// `X-Goog-User-Project` when set), or `Bearer owner` for the emulators.
  @internal
  Future<Map<String, String>> authorizationHeaders(String plugin) async {
    final OAuthTokenProvider? tokens = _tokens;
    if (tokens == null) {
      return <String, String>{'Authorization': 'Bearer owner'};
    }
    final String token;
    try {
      token = (await tokens.getAccessToken(forceRefresh: false)).token;
    } on Object catch (e) {
      throw FirebaseAdminException(
        plugin: plugin,
        code: 'invalid-credential',
        message:
            'Could not get an access token for the admin calls: '
            '${e is FirebaseAuthException ? e.message : '$e'}',
      );
    }
    final AdminCredential? credential = this.credential;
    return <String, String>{
      'Authorization': 'Bearer $token',
      if (credential is IamCredential && credential.quotaProjectId != null)
        'X-Goog-User-Project': credential.quotaProjectId!,
    };
  }

  /// The email of the account that signs: the key's, the configured one, the metadata server's default
  /// account, or [emulatorServiceAccount].
  @internal
  Future<String> signerEmail(String plugin) async {
    switch (credential) {
      case null:
        return emulatorServiceAccount;
      case ServiceAccountCredential(:final ServiceAccountKey key):
        return key.clientEmail;
      case IamCredential(:final String? serviceAccountEmail):
        if (serviceAccountEmail != null) {
          return serviceAccountEmail;
        }
        return _metadataEmail ??= await _fetchMetadataEmail(plugin);
    }
  }

  Future<String> _fetchMetadataEmail(String plugin) async {
    final FirebaseAdminException failure = FirebaseAdminException(
      plugin: plugin,
      code: 'invalid-credential',
      message:
          'Could not get the service account email from the metadata server, so nothing can be signed. '
          'Pass serviceAccountEmail to AdminCredential.iam, or use AdminCredential.serviceAccount with a key.',
    );
    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse(
          'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email',
        ),
        headers: <String, String>{'Metadata-Flavor': 'Google'},
      );
    } on Object {
      throw failure;
    }
    final String email = response.body.trim();
    if (response.statusCode != 200 || !email.contains('@')) {
      throw failure;
    }
    return email;
  }

  /// Signs [data] with RS256 as [email] (from [signerEmail]): locally with a service account key, or by the IAM
  /// Credentials API (`signBlob`). Not for the emulators.
  @internal
  Future<List<int>> signRs256(
    List<int> data,
    String email,
    String plugin,
  ) async {
    switch (credential) {
      case ServiceAccountCredential(:final ServiceAccountKey key):
        return key.signRs256(data);
      case IamCredential():
        final Map<String, String> headers = await authorizationHeaders(plugin);
        final http.Response response;
        try {
          response = await _http.post(
            Uri(
              scheme: 'https',
              host: 'iamcredentials.googleapis.com',
              pathSegments: <String>[
                'v1',
                'projects',
                '-',
                'serviceAccounts',
                '$email:signBlob',
              ],
            ),
            headers: <String, String>{
              ...headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{'payload': base64.encode(data)}),
          );
        } on Object {
          throw FirebaseAdminException(
            plugin: plugin,
            code: 'network-error',
            message:
                'The request to iamcredentials.googleapis.com failed (network error).',
          );
        }
        Object? json;
        try {
          json = jsonDecode(response.body);
        } on FormatException {
          json = null;
        }
        final Object? signed = json is Map<String, Object?>
            ? json['signedBlob']
            : null;
        if (response.statusCode == 200 && signed is String) {
          try {
            return base64.decode(signed);
          } on FormatException {
            // Reported below.
          }
        }
        final Object? error = json is Map<String, Object?>
            ? json['error']
            : null;
        final Object? message = error is Map<String, Object?>
            ? error['message']
            : null;
        final Object? status = error is Map<String, Object?>
            ? error['status']
            : null;
        throw FirebaseAdminException(
          plugin: plugin,
          code: response.statusCode == 403
              ? 'insufficient-permission'
              : 'internal-error',
          message:
              'The IAM Credentials API did not sign (HTTP ${response.statusCode})'
              '${message is String ? ': $message' : ''}. It must be enabled, and the caller needs the role '
              'Service Account Token Creator (iam.serviceAccounts.signBlob) on the signing account.',
          serverCode: status is String ? status : null,
          httpStatus: response.statusCode,
        );
      case null:
        throw StateError('Nothing is signed in emulator mode.');
    }
  }

  @override
  String toString() =>
      'FirebaseAdminApp($projectId${isEmulator ? ', emulator' : ''})';
}
