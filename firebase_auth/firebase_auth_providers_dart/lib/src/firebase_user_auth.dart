import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart' show Log;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'auth_exception.dart';
import 'auth_storage.dart';
import 'auth_user.dart';
import 'environment_stub.dart' if (dart.library.io) 'environment_io.dart';

/// Firebase Auth user sign-in over the Identity Toolkit and Secure Token REST APIs: anonymous, email and password,
/// and custom tokens.
///
/// It is the token provider of a [FirebaseApp]: Firestore sends the ID token of the signed-in user with every
/// request (so the security rules see `request.auth`), and follows sign-in, sign-out and a switch of users like the
/// official SDKs do (the streams restart with the new identity and the pending writes of each user stay with that
/// user).
///
/// ```dart
/// final app = FirebaseApp.withOptions(options);
/// final auth = await FirebaseUserAuth.forApp(app);     // before Firestore.instanceFor
/// final firestore = await Firestore.instanceFor(app: app);
/// await auth.signInWithEmailAndPassword('user@example.com', password);
/// ```
///
/// The ID token lives for an hour. It is refreshed with the refresh token when it is within five minutes of its
/// expiry: on demand when a token is requested, and ahead of time while somebody listens to [onTokenChanged]
/// (Firestore does). The session (the refresh token) is kept in an [AuthStorage]; the default forgets it when the
/// process ends.
///
/// This is not a port of the Firebase Auth SDK: there are no federated providers, no phone sign-in, no email
/// actions, no multi-factor and no account management.
class FirebaseUserAuth implements InternalTokenProvider {
  /// Creates an instance for the project of [apiKey] (the Web API key of the Firebase project).
  ///
  /// Call [restore] before using it to pick up a stored session. [forApp] does both and registers the instance
  /// with the app.
  ///
  /// * [storage] keeps the session; [storageKey] is the key it is stored under (by default derived from the API
  ///   key, so that two projects do not share a session).
  /// * [emulatorHost] (`host:port`) sends every request to the Firebase Auth emulator instead of Google, over plain
  ///   HTTP (or over HTTPS when given as `https://host:port`, like the URL of `connectAuthEmulator` in the JS SDK).
  ///   It is checked like the host of the Firestore settings: an [ArgumentError] is thrown for anything with user
  ///   info, a path, a query or a bad port, and for a Google host (`*.googleapis.com`, `*.google.com`), which is
  ///   never an emulator. An emulator that is not on the loopback interface gets a warning in the log, like the
  ///   JS SDK warns for every emulator: passwords and tokens travel unencrypted to it. See
  ///   [emulatorHostFromEnvironment].
  /// * [httpClient] is used for all requests and is not closed by [dispose]; without it one is created and closed.
  /// * [clock] and [createTimer] are for tests.
  FirebaseUserAuth({
    required this.apiKey,
    AuthStorage? storage,
    String? storageKey,
    this.emulatorHost,
    http.Client? httpClient,
    DateTime Function()? clock,
    Timer Function(Duration delay, void Function() callback)? createTimer,
  }) : _emulatorOrigin = emulatorHost == null
           ? null
           : _emulatorOriginOf(emulatorHost),
       _storage = storage ?? InMemoryAuthStorage(),
       _storageKey = storageKey ?? 'firebase_auth_providers_dart:$apiKey',
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _clock = clock ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new {
    // Synchronous: a listener (Firestore) hears about a new user before the sign-in call returns.
    _tokenChanges = StreamController<InternalTokenResult>.broadcast(
      sync: true,
      onListen: _scheduleProactiveRefresh,
      onCancel: _cancelProactiveRefresh,
    );
  }

  /// Creates the instance for [app] (with the API key of its options), restores a stored session and makes it the
  /// token provider of the app. Call it before the Firestore instance of the app is created.
  static Future<FirebaseUserAuth> forApp(
    FirebaseApp app, {
    AuthStorage? storage,
    String? emulatorHost,
    http.Client? httpClient,
  }) async {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: app.options.apiKey,
      storage: storage,
      storageKey:
          'firebase_auth_providers_dart:${app.options.apiKey}:${app.name}',
      emulatorHost: emulatorHost,
      httpClient: httpClient,
    );
    await auth.restore();
    app.authProvider = auth;
    return auth;
  }

  /// The `host:port` of the Firebase Auth emulator from the `FIREBASE_AUTH_EMULATOR_HOST` environment variable, or
  /// null when it is not set (always null on the web, which has no environment).
  static String? get emulatorHostFromEnvironment =>
      environmentVariable('FIREBASE_AUTH_EMULATOR_HOST');

  /// How long before its expiry an ID token is refreshed.
  static const Duration refreshBefore = Duration(minutes: 5);

  /// The Web API key of the project.
  final String apiKey;

  /// The `host:port` of the Auth emulator, or null for the real service.
  final String? emulatorHost;

  /// `http://host:port` (or `https://...`) of the Auth emulator, checked; null for the real service.
  final String? _emulatorOrigin;

  static final RegExp _notAuthorityCharacters = RegExp(r'[/@?#\\\s]');
  static final RegExp _scheme = RegExp(r'^(https?)://', caseSensitive: false);

  /// Checks [value], the `host:port` (optionally with an `http://` or `https://` scheme and a trailing `/`) of an
  /// Auth emulator, and returns the origin the requests go to.
  static String _emulatorOriginOf(String value) {
    Never invalid(String why) =>
        throw ArgumentError.value(value, 'emulatorHost', why);
    String authority = value.trim();
    String scheme = 'http';
    final RegExpMatch? match = _scheme.firstMatch(authority);
    if (match != null) {
      scheme = match.group(1)!.toLowerCase();
      authority = authority.substring(match.end);
    }
    if (authority.endsWith('/')) {
      authority = authority.substring(0, authority.length - 1);
    }
    if (authority.isEmpty || _notAuthorityCharacters.hasMatch(authority)) {
      invalid(
        'Must be host:port (or http://host:port), without user info, path or query',
      );
    }
    final String host;
    String? port;
    if (authority.startsWith('[')) {
      // An IPv6 address: [::1]:9099.
      final int end = authority.indexOf(']');
      if (end < 0) {
        invalid('The IPv6 address is not closed with "]"');
      }
      host = authority.substring(0, end + 1);
      final String rest = authority.substring(end + 1);
      if (rest.isNotEmpty) {
        if (!rest.startsWith(':')) {
          invalid('Must be host:port');
        }
        port = rest.substring(1);
      }
    } else {
      final List<String> parts = authority.split(':');
      if (parts.length > 2) {
        invalid('Must be host:port (an IPv6 address goes in brackets)');
      }
      host = parts[0];
      port = parts.length == 2 ? parts[1] : null;
    }
    if (host.isEmpty || host == '[]') {
      invalid('The host is empty');
    }
    if (port != null) {
      final int? number = int.tryParse(port);
      if (number == null || number < 1 || number > 65535) {
        invalid('The port must be a number from 1 to 65535');
      }
    }
    String normalized = host.toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized == 'googleapis.com' ||
        normalized.endsWith('.googleapis.com') ||
        normalized == 'google.com' ||
        normalized.endsWith('.google.com')) {
      invalid(
        'A Google host is not an emulator: requests to the emulator carry passwords and tokens without the '
        'protection of the real service',
      );
    }
    if (!_isLoopback(normalized)) {
      Log.w(
        'FirebaseUserAuth',
        'WARNING: You are using the Auth Emulator at $scheme://$authority, which is intended for local testing '
            'only. Do not use with production credentials.',
      );
    }
    return '$scheme://$authority';
  }

  static bool _isLoopback(String host) {
    if (host == 'localhost' || host.endsWith('.localhost')) {
      return true;
    }
    if (host == '[::1]') {
      return true;
    }
    final List<String> octets = host.split('.');
    return octets.length == 4 &&
        octets[0] == '127' &&
        octets.every((String o) {
          final int? n = int.tryParse(o);
          return n != null && n >= 0 && n <= 255;
        });
  }

  final AuthStorage _storage;
  final String _storageKey;
  final http.Client _http;
  final bool _ownsHttp;
  final DateTime Function() _clock;
  final Timer Function(Duration delay, void Function() callback) _createTimer;

  late final StreamController<InternalTokenResult> _tokenChanges;
  final StreamController<AuthUser?> _userChanges =
      StreamController<AuthUser?>.broadcast();

  _Session? _session;
  Future<String?>? _refreshing;
  Timer? _refreshTimer;
  int _refreshFailures = 0;
  bool _disposed = false;

  /// Counts the changes of the session, so that the result of a request that was overtaken by a sign-in or a
  /// sign-out is dropped.
  int _generation = 0;

  /// The signed-in user, or null.
  AuthUser? get currentUser => _session?.user;

  /// The id of the signed-in user, or null.
  @override
  String? get uid => _session?.user.uid;

  /// Emits the user after every sign-in and sign-out (null when signed out). It does not emit the current user
  /// when it is listened to: read [currentUser] for that.
  Stream<AuthUser?> get userChanges => _userChanges.stream;

  /// Emits the ID token after a sign-in, after every refresh, and an empty token after a sign-out.
  @override
  Stream<InternalTokenResult> get onTokenChanged => _tokenChanges.stream;

  /// Loads the session that an earlier instance stored. The ID token is fetched when it is first needed.
  Future<void> restore() async {
    final String? stored = await _storage.read(_storageKey);
    if (stored == null || _session != null) {
      return;
    }
    try {
      final Object? json = jsonDecode(stored);
      if (json is Map<String, Object?> &&
          json['refreshToken'] is String &&
          json['uid'] is String) {
        await _setSession(
          _Session(
            AuthUser(
              uid: json['uid']! as String,
              email: json['email'] as String?,
              isAnonymous: json['isAnonymous'] == true,
            ),
            json['refreshToken']! as String,
            null,
            null,
          ),
          persist: false,
        );
      }
    } on FormatException {
      // Not something this class wrote: start signed out.
    }
  }

  /// Signs in a new anonymous user.
  Future<AuthUser> signInAnonymously() =>
      _signIn('accounts:signUp', <String, Object?>{'returnSecureToken': true});

  /// Signs in with an email address and a password.
  ///
  /// Throws a [FirebaseAuthProviderException] with the code `wrong-password`, `user-not-found`,
  /// `invalid-credential` (projects with email enumeration protection), `user-disabled`, `too-many-requests`, ...
  Future<AuthUser> signInWithEmailAndPassword(String email, String password) =>
      _signIn('accounts:signInWithPassword', <String, Object?>{
        'email': email,
        'password': password,
        'returnSecureToken': true,
      });

  /// Creates an account with an email address and a password and signs it in.
  ///
  /// Throws a [FirebaseAuthProviderException] with the code `email-already-in-use`, `weak-password`,
  /// `invalid-email`, `operation-not-allowed`, ...
  Future<AuthUser> createUserWithEmailAndPassword(
    String email,
    String password,
  ) => _signIn('accounts:signUp', <String, Object?>{
    'email': email,
    'password': password,
    'returnSecureToken': true,
  });

  /// Signs in with a custom token minted by a server (for example with the Admin SDK).
  Future<AuthUser> signInWithCustomToken(String token) => _signIn(
    'accounts:signInWithCustomToken',
    <String, Object?>{'token': token, 'returnSecureToken': true},
  );

  /// Signs the user out: the session is forgotten, also in the storage. Does nothing when nobody is signed in.
  Future<void> signOut() async {
    if (_session == null) {
      return;
    }
    await _clearSession();
  }

  /// Deletes the account of the signed-in user and signs out. Meant for tests and for throwaway (anonymous)
  /// accounts; the backend refuses it (`requires-recent-login`) when the sign-in is too long ago.
  Future<void> deleteCurrentUser() async {
    final GetTokenResult token = await getAccessToken(forceRefresh: false);
    await _send(
      _identityToolkit('accounts:delete'),
      json: <String, Object?>{'idToken': token.token},
    );
    await _clearSession();
  }

  /// Returns the ID token of the signed-in user, refreshing it when it expires within five minutes or when
  /// [forceRefresh] is set.
  ///
  /// Throws a [FirebaseNoSignedInUserError] when nobody is signed in (Firestore then sends the request without
  /// a token), and a [FirebaseAuthProviderException] when the refresh fails. When the refresh fails because the
  /// session is no longer valid (the account was deleted or disabled, the refresh token revoked), the user is
  /// signed out.
  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    final _Session? session = _session;
    if (session == null) {
      throw FirebaseNoSignedInUserError('No user is signed in.');
    }
    final String? idToken = session.idToken;
    if (!forceRefresh && idToken != null && _isFresh(session)) {
      return GetTokenResult(idToken);
    }
    final String? refreshed = await _refresh();
    if (refreshed == null) {
      // The user changed while the token was refreshed: answer for the current session.
      return getAccessToken(forceRefresh: false);
    }
    return GetTokenResult(refreshed);
  }

  /// Stops the timers and closes the streams. The session stays in the storage.
  Future<void> dispose() async {
    _disposed = true;
    _cancelProactiveRefresh();
    await _tokenChanges.close();
    await _userChanges.close();
    if (_ownsHttp) {
      _http.close();
    }
  }

  // ---- implementation ----

  bool _isFresh(_Session session) {
    final DateTime? expiry = session.expiry;
    return expiry != null && _clock().add(refreshBefore).isBefore(expiry);
  }

  Uri _identityToolkit(String method) {
    final String? emulator = _emulatorOrigin;
    return emulator == null
        ? Uri.https(
            'identitytoolkit.googleapis.com',
            '/v1/$method',
            <String, String>{'key': apiKey},
          )
        : Uri.parse(
            '$emulator/identitytoolkit.googleapis.com/v1/$method?key=${Uri.encodeQueryComponent(apiKey)}',
          );
  }

  Uri get _secureToken {
    final String? emulator = _emulatorOrigin;
    return emulator == null
        ? Uri.https('securetoken.googleapis.com', '/v1/token', <String, String>{
            'key': apiKey,
          })
        : Uri.parse(
            '$emulator/securetoken.googleapis.com/v1/token?key=${Uri.encodeQueryComponent(apiKey)}',
          );
  }

  /// Sends a request and returns the decoded JSON object of the answer, or throws.
  Future<Map<String, Object?>> _send(
    Uri url, {
    Map<String, Object?>? json,
    Map<String, String>? form,
  }) async {
    final http.Response response;
    try {
      response = json != null
          ? await _http.post(
              url,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: jsonEncode(json),
            )
          : await _http.post(url, body: form);
    } on Object catch (_) {
      // The error of the HTTP client may quote the URL, which holds the API key.
      throw const FirebaseAuthProviderException(
        'network-request-failed',
        'The request to the authentication service failed (network error).',
      );
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (response.statusCode == 200 && body is Map<String, Object?>) {
      return body;
    }
    final Object? error = body is Map<String, Object?> ? body['error'] : null;
    final Object? message = error is Map<String, Object?>
        ? error['message']
        : null;
    if (message is String) {
      throw FirebaseAuthProviderException.fromServer(
        message,
        httpStatus: response.statusCode,
      );
    }
    throw FirebaseAuthProviderException(
      'internal-error',
      'The authentication service answered with HTTP ${response.statusCode}.',
      httpStatus: response.statusCode,
    );
  }

  Future<AuthUser> _signIn(String method, Map<String, Object?> request) async {
    _checkNotDisposed();
    final int generation = ++_generation;
    final Map<String, Object?> response = await _send(
      _identityToolkit(method),
      json: request,
    );
    final Object? idToken = response['idToken'];
    final Object? refreshToken = response['refreshToken'];
    if (idToken is! String || refreshToken is! String) {
      throw const FirebaseAuthProviderException(
        'internal-error',
        'The authentication service did not return tokens.',
      );
    }
    if (generation != _generation) {
      // Another sign-in or a sign-out happened meanwhile and wins.
      throw const FirebaseAuthProviderException(
        'cancelled',
        'The sign-in was overtaken by another sign-in or a sign-out.',
      );
    }
    final GetTokenResult token = GetTokenResult(idToken);
    final Object? localId = response['localId'];
    final Object? uid = localId is String
        ? localId
        : token.claims['user_id'] ?? token.claims['sub'];
    if (uid is! String) {
      throw const FirebaseAuthProviderException(
        'internal-error',
        'The authentication service did not return the id of the user.',
      );
    }
    final Object? email = response['email'] ?? token.claims['email'];
    final _Session session = _Session(
      AuthUser(
        uid: uid,
        email: email is String ? email : null,
        isAnonymous: token.signInProvider == 'anonymous',
      ),
      refreshToken,
      idToken,
      _expiry(token, response['expiresIn']),
    );
    await _setSession(session, persist: true);
    _userChanges.add(session.user);
    _tokenChanges.add(InternalTokenResult(idToken));
    await _letListenersReact();
    return session.user;
  }

  /// The expiry of an ID token: its `exp` claim, or now plus the `expiresIn` seconds of the response.
  DateTime _expiry(GetTokenResult token, Object? expiresIn) {
    if (token.claims['exp'] is num) {
      return token.expirationTimestamp;
    }
    final int seconds =
        int.tryParse('$expiresIn') ?? const Duration(hours: 1).inSeconds;
    return _clock().add(Duration(seconds: seconds));
  }

  /// Exchanges the refresh token for a new ID token. One request at a time. Completes with null when the session
  /// changed while the request was in flight (the token then belongs to the previous session and is dropped).
  Future<String?> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final _Session session = _session!;
    final int generation = _generation;
    final Map<String, Object?> response;
    try {
      response = await _send(
        _secureToken,
        form: <String, String>{
          'grant_type': 'refresh_token',
          'refresh_token': session.refreshToken,
        },
      );
    } on FirebaseAuthProviderException catch (e) {
      if (e.invalidatesSession && generation == _generation) {
        await _clearSession();
      }
      rethrow;
    }
    final Object? idToken = response['id_token'];
    final Object? refreshToken = response['refresh_token'];
    if (idToken is! String) {
      throw const FirebaseAuthProviderException(
        'internal-error',
        'The token service did not return an ID token.',
      );
    }
    if (generation != _generation) {
      return null;
    }
    final GetTokenResult token = GetTokenResult(idToken);
    final _Session refreshed = _Session(
      session.user,
      refreshToken is String ? refreshToken : session.refreshToken,
      idToken,
      _expiry(token, response['expires_in']),
    );
    await _setSession(
      refreshed,
      persist: refreshed.refreshToken != session.refreshToken,
    );
    _refreshFailures = 0;
    if (!_tokenChanges.isClosed) {
      _tokenChanges.add(InternalTokenResult(idToken));
    }
    return idToken;
  }

  Future<void> _setSession(_Session session, {required bool persist}) async {
    _session = session;
    if (persist) {
      await _storage.write(
        _storageKey,
        jsonEncode(<String, Object?>{
          'uid': session.user.uid,
          'email': session.user.email,
          'isAnonymous': session.user.isAnonymous,
          'refreshToken': session.refreshToken,
        }),
      );
    }
    if (_tokenChanges.hasListener) {
      _scheduleProactiveRefresh();
    }
  }

  Future<void> _clearSession() async {
    _generation++;
    _session = null;
    _cancelProactiveRefresh();
    await _storage.write(_storageKey, null);
    if (!_userChanges.isClosed) {
      _userChanges.add(null);
    }
    if (!_tokenChanges.isClosed) {
      _tokenChanges.add(const InternalTokenResult(''));
    }
    await _letListenersReact();
  }

  /// Gives the listeners of the token (and whatever they forward the change to) a turn of the event loop before a
  /// sign-in or sign-out call completes. Firestore queues the switch of the user when it hears about it; a write
  /// that the application issues right after `await signIn...()` must be queued behind that switch, or it would
  /// be recorded for the previous user.
  Future<void> _letListenersReact() => Future<void>.delayed(Duration.zero);

  /// While somebody follows the token, it is refreshed ahead of its expiry, so that a long-lived stream never
  /// holds an expired token.
  void _scheduleProactiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final _Session? session = _session;
    if (session == null || _disposed) {
      return;
    }
    final DateTime? expiry = session.expiry;
    Duration delay = expiry == null
        ? Duration.zero
        : expiry.subtract(refreshBefore).difference(_clock());
    if (_refreshFailures > 0) {
      // After a failed attempt: 30 s, 1 min, 2 min, ... up to 16 min.
      final int exponent = _refreshFailures > 6 ? 5 : _refreshFailures - 1;
      final Duration backoff = Duration(seconds: 30 * (1 << exponent));
      delay = delay > backoff ? delay : backoff;
    }
    if (delay.isNegative) {
      delay = Duration.zero;
    }
    _refreshTimer = _createTimer(delay, () {
      _refreshTimer = null;
      if (_session == null || _disposed || !_tokenChanges.hasListener) {
        return;
      }
      _refresh().then<void>(
        (String? _) {},
        onError: (Object error) {
          if (error is FirebaseAuthProviderException &&
              !error.invalidatesSession &&
              _session != null &&
              _tokenChanges.hasListener) {
            _refreshFailures++;
            _scheduleProactiveRefresh();
          }
        },
      );
    });
  }

  void _cancelProactiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('This FirebaseUserAuth was disposed.');
    }
  }

  /// When the proactive refresh is due, for tests.
  @visibleForTesting
  bool get hasRefreshTimer => _refreshTimer != null;
}

class _Session {
  const _Session(this.user, this.refreshToken, this.idToken, this.expiry);

  final AuthUser user;
  final String refreshToken;

  /// Null after [FirebaseUserAuth.restore], until the first refresh.
  final String? idToken;
  final DateTime? expiry;
}
