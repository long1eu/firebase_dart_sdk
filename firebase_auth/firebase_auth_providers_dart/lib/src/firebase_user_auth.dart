import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart' show Log;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:firebase_auth_providers_dart/src/auth_constants.dart';
import 'package:firebase_auth_providers_dart/src/phone_auth.dart';
import 'package:firebase_auth_providers_dart/src/secure_flow_errors.dart';
import 'package:secure_flow/secure_flow.dart'
    show CodeEntryFlow, SecureEnvironment, SecurePresenter;

import 'action_code.dart';
import 'app_verification.dart';
import 'auth_credential.dart';
import 'auth_emulator_config.dart';
import 'auth_exception.dart';
import 'auth_storage.dart';
import 'auth_user.dart';
import 'multi_factor.dart';
import 'multi_factor_api.dart';
import 'oauth_loopback/oauth_loopback.dart';
import 'oauth_loopback/oauth_loopback_stub.dart'
    if (dart.library.io) 'oauth_loopback/oauth_loopback_io.dart';
import 'user_record.dart';
import 'password_policy.dart';
import 'environment_stub.dart'
    if (dart.library.io) 'environment_io.dart'
    if (dart.library.js_interop) 'environment_web.dart';

/// Firebase Auth user sign-in over the Identity Toolkit and Secure Token REST APIs: anonymous, email and password,
/// email link, custom tokens, and federated providers by token exchange.
///
/// It is the token provider of a [FirebaseApp]: Firestore sends the ID token of the signed-in user with every
/// request (so the security rules see `request.auth`), and follows sign-in, sign-out and a switch of users like the
/// official SDKs do (the streams restart with the new identity and the pending writes of each user stay with that
/// user).
///
/// ```dart
/// import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<the Web API key of the project>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///     ),
///   );
///   // Before FirebaseFirestore.instanceFor: it becomes the token provider of the app.
///   final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
///   final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
///
///   final AuthUser user = await auth.signInAnonymously();
///   await firestore.doc('users/${user.uid}').set(<String, Object?>{'seen': true});
///   await auth.signOut();
/// }
/// ```
///
/// **Sign-in.** [signInAnonymously], [createUserWithEmailAndPassword], [signInWithEmailAndPassword],
/// [signInWithEmailLink], [signInWithCustomToken] and [signInWithCredential] each replace the current user (if any)
/// and return a [UserCredential]: the new user (read from the backend with `accounts:lookup`, like the JS SDK) with
/// [AdditionalUserInfo]. They complete after [userChanges], [authStateChanges], [idTokenChanges] and
/// [onTokenChanged] have emitted and their listeners had a turn of the event loop, so a Firestore write issued
/// right after belongs to the new user. When two sign-ins overlap, the later one wins and the earlier one throws
/// `cancelled`. [linkWithCredential], [reauthenticateWithCredential] and [unlink] act on the signed-in user.
///
/// **Token refresh.** The ID token lives for an hour. It is refreshed with the refresh token when it is within
/// five minutes ([refreshBefore]) of its expiry: on demand when a token is requested ([getAccessToken]), and
/// ahead of time while somebody listens to [onTokenChanged] (FirebaseFirestore does). A failed refresh ahead of time is
/// retried after 30 seconds, then 1, 2, 4, 8 and 16 minutes. A refresh that the backend refuses because the
/// session ended (the account was deleted or disabled, the refresh token revoked) signs the user out.
///
/// **Sign-out.** [signOut] removes the session from this instance and from the storage. It does not revoke the
/// refresh token on the backend, like the other Firebase SDKs; and, like the user objects of the JS SDK, an
/// [AuthUser] or [UserCredential] handed out before keeps its session: [updateCurrentUser] with it signs that user
/// in again. Drop those objects to forget the session in memory.
///
/// **Session.** The session (the refresh token) is kept in an [AuthStorage]; the default, [InMemoryAuthStorage],
/// forgets it when the process ends. [restore] (called by [forApp]) loads a stored session. When the storage fails
/// to write a new session, the operation throws the error of the storage but the session in memory is the new one,
/// and the next token refresh writes it again; a failing storage never signs the user out. When it fails to delete
/// the session at [signOut], the user is signed out all the same and [signOut] throws the error of the storage;
/// [restore] on that instance deletes it again instead of loading it, but a new instance still finds it.
///
/// **Errors.** Requests fail with a [FirebaseAuthException]; its [FirebaseAuthException.code] lists
/// the codes. Any request can fail with `network-request-failed`, `too-many-requests`, `invalid-api-key` or
/// `internal-error`. The operations of the signed-in user throw `null-user` when nobody is signed in, and sign the
/// user out when the backend answers `user-disabled` or `user-token-expired`. After [dispose] the operations
/// throw a [StateError].
///
/// **Emulator.** Pass `emulatorHost` (for example from [emulatorHostFromEnvironment]) to talk to the Firebase
/// Auth emulator. Only Google sign-in through [signInWithOAuthLoopback] with a "Desktop app" client was run against
/// a real Firebase project (on 2026-11-20); the rest was tested with unit tests and against the emulator.
///
/// Account management follows the REST-backed operations of the JS SDK: password reset, email verification and
/// action codes, email, password and profile updates, reauthentication, account deletion, the sign-in methods of
/// an email address, and [validatePassword]. [tenantId] and [languageCode] are sent like the JS SDK sends them.
/// This is not a port of the whole Firebase Auth SDK: a federated provider's token comes from the app (there are
/// no popup and redirect flows).
///
/// **Phone.** [verifyPhoneNumber] sends an SMS code and returns a verification id;
/// [PhoneAuthProvider.credential] pairs it with the code the user typed in, for
/// [signInWithCredential], [linkWithCredential], [reauthenticateWithCredential] and
/// [updatePhoneNumber]. The request needs a proof that it comes from a real app ([AppVerification]:
/// a reCAPTCHA token, or none for the emulator). There is no instant verification and no automatic
/// reading of the SMS: the user types the code in. [verifyPhoneNumberInteractively] does both steps
/// for a program without a code field of its own.
///
/// **Multi-factor authentication** works with authenticator apps (TOTP) and SMS (it needs Identity
/// Platform with the factor enabled for the project): [startTotpEnrollment] and
/// [finalizeTotpEnrollment], or [startPhoneEnrollment] and [finalizePhoneEnrollment], enrol one,
/// [unenrollMultiFactor] removes a factor, and [AuthUser.enrolledFactors] lists them. A sign-in or
/// reauthentication of an account with a second factor throws a [FirebaseAuthMultiFactorException]
/// (`multi-factor-auth-required`) whose [FirebaseAuthMultiFactorException.resolver] finishes it
/// with a code of the app or of an SMS.
class FirebaseUserAuth implements AuthTokenProvider {
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
  ///   JS SDK warns for every emulator: passwords and tokens travel unencrypted to it;
  ///   `emulatorOptions: AuthEmulatorOptions(disableWarnings: true)` leaves that warning out. See
  ///   [emulatorHostFromEnvironment] and [emulatorConfig].
  ///
  ///   The JS SDK throws a `FirebaseAuthException` (`invalid-emulator-scheme`) only for a URL without `http://`
  ///   or `https://` (`packages/auth/src/core/auth/emulator.ts:51-55`) and does not check the rest. Here a
  ///   scheme is optional (`host:port` is the form of `FIREBASE_AUTH_EMULATOR_HOST`), every invalid value is a
  ///   programming error thrown before any request, and [emulatorOrigin] shares the check with
  ///   `firebase_admin_dart`, so it stays an [ArgumentError]; an `ftp://` scheme is one.
  /// * [appId] (the `appId` of the app's options) is sent as `X-Firebase-gmpid`, and the token of [appCheck]
  ///   as `X-Firebase-AppCheck`, with every request, like the JS SDK does. [forApp] takes both from the app.
  /// * [httpClient] is used for all requests and is not closed by [dispose]; without it one is created and closed.
  /// * [requestTimeout] bounds every request: one that takes longer fails with `network-request-failed`.
  /// * [clock] and [createTimer] are for tests.
  FirebaseUserAuth({
    required this.apiKey,
    this.appId,
    AppCheckTokenProvider? appCheck,
    AuthStorage? storage,
    String? storageKey,
    String? emulatorHost,
    AuthEmulatorOptions emulatorOptions = const AuthEmulatorOptions(),
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 30),
    DateTime Function()? clock,
    Timer Function(Duration delay, void Function() callback)? createTimer,
  }) : _emulatorHost = emulatorHost,
       _emulatorConfig = emulatorHost == null
           ? null
           : _emulatorConfigOf(emulatorHost, emulatorOptions),
       _appCheck = appCheck,
       _storage = storage ?? InMemoryAuthStorage(),
       _storageKey = storageKey ?? 'firebase_auth_providers_dart:$apiKey',
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _requestTimeout = requestTimeout,
       _clock = clock ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new {
    // Synchronous: a listener (FirebaseFirestore) hears about a new user before the sign-in call returns.
    _tokenChanges = StreamController<AuthTokenChange>.broadcast(
      sync: true,
      onListen: _scheduleProactiveRefresh,
      onCancel: _cancelProactiveRefresh,
    );
  }

  /// Creates the instance for [app] (with the API key and the application id of its options, and its App Check
  /// provider), restores a stored session and makes it the token provider of the app (`app.authProvider`). Call
  /// it before the Firestore instance of the app is created, and after the App Check provider is set on the app.
  ///
  /// The session is stored in [storage] (default: in memory) under a key made of the API key and the name of the
  /// app, so that two apps keep two sessions. [emulatorHost], [emulatorOptions] and [httpClient] are those of the
  /// constructor.
  ///
  /// Throws an [ArgumentError] for an invalid [emulatorHost], and whatever the `read` of [storage] throws. In the
  /// second case the instance is the token provider of the app all the same, signed out, and the stored session is
  /// kept: call [restore] on it (`app.authProvider as FirebaseUserAuth`) to try again.
  ///
  /// ```dart
  /// final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
  ///   app,
  ///   emulatorHost: FirebaseUserAuth.emulatorHostFromEnvironment,
  /// );
  /// print(auth.currentUser?.uid); // the restored user, or null
  /// ```
  static Future<FirebaseUserAuth> forApp(
    FirebaseApp app, {
    AuthStorage? storage,
    String? emulatorHost,
    AuthEmulatorOptions emulatorOptions = const AuthEmulatorOptions(),
    http.Client? httpClient,
  }) async {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: app.options.apiKey,
      appId: app.options.appId,
      appCheck: app.appCheckProvider,
      storage: storage,
      storageKey:
          'firebase_auth_providers_dart:${app.options.apiKey}:${app.name}',
      emulatorHost: emulatorHost,
      emulatorOptions: emulatorOptions,
      httpClient: httpClient,
    ).._app = app;
    try {
      await auth.restore();
    } finally {
      app.authProvider = auth;
    }
    return auth;
  }

  /// The `host:port` of the Firebase Auth emulator from the `FIREBASE_AUTH_EMULATOR_HOST` environment variable, or
  /// null when it is not set (always null on the web, which has no environment).
  static String? get emulatorHostFromEnvironment =>
      environmentVariable('FIREBASE_AUTH_EMULATOR_HOST');

  /// Checks [emulatorHost] the way the constructor does and returns the origin requests to the Auth emulator go
  /// to: `http://host:port`, or `https://host:port` when given with that scheme.
  ///
  /// For other clients of the Auth emulator (for example `firebase_admin_dart`), so that they accept the
  /// same values. Throws an [ArgumentError] for user info, a path, a query, a bad port or a Google host, and logs
  /// a warning for a host off the loopback interface.
  ///
  /// ```dart
  /// print(FirebaseUserAuth.emulatorOrigin('127.0.0.1:9099')); // http://127.0.0.1:9099
  /// ```
  static String emulatorOrigin(String emulatorHost) =>
      _originOf(_emulatorConfigOf(emulatorHost, const AuthEmulatorOptions()));

  /// How long before its expiry an ID token is refreshed.
  static const Duration refreshBefore = Duration(minutes: 5);

  /// The Web API key of the project.
  final String apiKey;

  /// The app this instance was created for by [forApp] (`Auth.app` of the JS SDK; its `name` is `Auth.name`), or
  /// null for an instance made with the constructor.
  ///
  /// The rest of the JS SDK's `Auth.config` is here as separate members: [apiKey], [appId], [emulatorConfig] (the
  /// host and scheme requests go to, when not the real service) and [clientVersion].
  FirebaseApp? get app => _app;
  FirebaseApp? _app;

  /// The Auth emulator as it was passed to the constructor or to [useEmulator] (`host:port`, or with a scheme), or
  /// null for the real service.
  String? get emulatorHost => _emulatorHost;
  String? _emulatorHost;

  /// Sends the requests from now on to the Firebase Auth emulator at [emulatorHost] (`host:port`, or
  /// `https://host:port`), like the `emulatorHost` of the constructor (FlutterFire's `useAuthEmulator`, the JS SDK's
  /// `connectAuthEmulator`). For an instance that is created before the emulator is known, such as the one of a
  /// FlutterFire platform implementation.
  ///
  /// Call it before the first request: a request in flight keeps the service it was sent to, and a session restored
  /// from the real service stays signed in until its first token refresh fails against the emulator. Throws an
  /// [ArgumentError] for an invalid [emulatorHost], as the constructor does, and changes nothing then.
  void useEmulator(
    String emulatorHost, {
    AuthEmulatorOptions options = const AuthEmulatorOptions(),
  }) {
    final AuthEmulatorConfig config = _emulatorConfigOf(emulatorHost, options);
    _emulatorHost = emulatorHost;
    _emulatorConfig = config;
  }

  /// The parsed [emulatorHost] and the options it was given with, or null for the real service: the
  /// `emulatorConfig` of the JS SDK (`packages/auth/src/core/auth/emulator.ts:65-70`).
  ///
  /// The JS SDK's `emulator-config-failed` (`connectAuthEmulator` called after the first request, or with another
  /// configuration, `emulator.ts:72-89`) does not exist here: [useEmulator] may be called at any time and the later
  /// requests follow it.
  AuthEmulatorConfig? get emulatorConfig => _emulatorConfig;
  AuthEmulatorConfig? _emulatorConfig;

  /// The id of the Firebase app, sent as `X-Firebase-gmpid`; null sends none.
  final String? appId;

  /// The language of the emails and SMS messages the backend sends (password reset, email verification, email
  /// link sign-in), as a BCP 47 tag such as `fr` or `pt-BR`; null lets the project's default apply. Sent as
  /// `X-Firebase-Locale` with every request of the Identity Toolkit API, like the JS SDK does. Set it, or call
  /// [setLanguageCode] or [useDeviceLanguage].
  String? languageCode;

  /// Sets [languageCode] (FlutterFire's `setLanguageCode`); null takes the language of the device, like
  /// [useDeviceLanguage] (FlutterFire does that on the web).
  Future<void> setLanguageCode(String? languageCode) async {
    if (languageCode == null) {
      useDeviceLanguage();
    } else {
      this.languageCode = languageCode;
    }
  }

  /// Sets [languageCode] to the language of the device (the JS SDK's `useDeviceLanguage`): on the Dart VM the
  /// locale of the process (`Platform.localeName`, for example `en_US.UTF-8` becomes `en-US`; the POSIX locale `C`
  /// gives null), in a browser the first of `navigator.languages`.
  void useDeviceLanguage() => languageCode = deviceLanguage();

  /// The tenant to sign in to (Identity Platform multi-tenancy), or null for the users of the project itself
  /// (FlutterFire's and the JS SDK's `tenantId`).
  ///
  /// It is sent with the sign-ins, the action code requests (password reset, email verification, email link) and
  /// the other requests the JS SDK sends it with. A sign-in (or [updateCurrentUser]) whose user belongs to another
  /// tenant than this one throws a [FirebaseAuthException] with the code `tenant-id-mismatch`. Changing it does not
  /// sign the current user out.
  String? tenantId;

  final AppCheckTokenProvider? _appCheck;

  /// The value of `X-Client-Version`, in the format of the JS SDK (`Chrome/JsCore/<version>/FirebaseCore-web`):
  /// platform, implementation, version of the package, framework.
  static const String clientVersion = 'Dart/DartCore/0.3.2/FirebaseCore-dart';

  /// `http://host:port` (or `https://...`) of the Auth emulator; null for the real service.
  String? get _emulatorOrigin {
    final AuthEmulatorConfig? config = emulatorConfig;
    return config == null ? null : _originOf(config);
  }

  static String _originOf(AuthEmulatorConfig config) {
    final int? port = config.port;
    return '${config.protocol}://${config.host}${port == null ? '' : ':$port'}';
  }

  static final RegExp _notAuthorityCharacters = RegExp(r'[/@?#\\\s]');
  static final RegExp _scheme = RegExp(
    r'^([a-z][a-z0-9+.-]*)://',
    caseSensitive: false,
  );

  /// Checks [value], the `host:port` (optionally with an `http://` or `https://` scheme and a trailing `/`) of an
  /// Auth emulator, and returns it parsed.
  static AuthEmulatorConfig _emulatorConfigOf(
    String value,
    AuthEmulatorOptions options,
  ) {
    Never invalid(String why) =>
        throw ArgumentError.value(value, 'emulatorHost', why);
    String authority = value.trim();
    String scheme = 'http';
    final RegExpMatch? match = _scheme.firstMatch(authority);
    if (match != null) {
      scheme = match.group(1)!.toLowerCase();
      if (scheme != 'http' && scheme != 'https') {
        invalid(
          'The scheme must be http or https (invalid-emulator-scheme in the JS SDK)',
        );
      }
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
    String? portText;
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
        portText = rest.substring(1);
      }
    } else {
      final List<String> parts = authority.split(':');
      if (parts.length > 2) {
        invalid('Must be host:port (an IPv6 address goes in brackets)');
      }
      host = parts[0];
      portText = parts.length == 2 ? parts[1] : null;
    }
    if (host.isEmpty || host == '[]') {
      invalid('The host is empty');
    }
    final int? port = portText == null ? null : int.tryParse(portText);
    if (portText != null && (port == null || port < 1 || port > 65535)) {
      invalid('The port must be a number from 1 to 65535');
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
    if (!_isLoopback(normalized) && !options.disableWarnings) {
      Log.w(
        'FirebaseUserAuth',
        'WARNING: You are using the Auth Emulator at $scheme://$authority, which is intended for local testing '
            'only. Do not use with production credentials.',
      );
    }
    return AuthEmulatorConfig(
      protocol: scheme,
      host: host,
      port: port,
      options: options,
    );
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

  AuthStorage _storage;
  final String _storageKey;
  final http.Client _http;
  final bool _ownsHttp;
  final Duration _requestTimeout;
  final DateTime Function() _clock;
  final Timer Function(Duration delay, void Function() callback) _createTimer;

  late final StreamController<AuthTokenChange> _tokenChanges;
  final StreamController<AuthUser?> _userChanges =
      StreamController<AuthUser?>.broadcast();

  // Synchronous, so that the stream of authStateChanges() and idTokenChanges() knows at once that a change replaces
  // the current user it still has to emit; those streams deliver asynchronously.
  final StreamController<AuthUser?> _authStateChanges =
      StreamController<AuthUser?>.broadcast(sync: true);
  final StreamController<AuthUser?> _idTokenChanges =
      StreamController<AuthUser?>.broadcast(sync: true);

  /// The uid authStateChanges() last emitted (the JS SDK's `lastNotifiedUid`); an instance starts signed out.
  String? _lastNotifiedUid;

  /// The [restore] in progress.
  Future<void>? _restoring;

  MultiFactorApi get _multiFactor => MultiFactorApi.json(
    MultiFactorTransport(
      postJson: (String method, Map<String, Object?> body) =>
          _send(_identityToolkit(method, version: 'v2'), json: body),
    ),
  );

  /// The password policies fetched by [validatePassword], by tenant (null for the project).
  final Map<String?, PasswordPolicy> _passwordPolicies =
      <String?, PasswordPolicy>{};

  final List<_BeforeStateCallback> _beforeStateCallbacks =
      <_BeforeStateCallback>[];

  /// The session behind each user this class handed out (for [updateCurrentUser]), with the API key of its
  /// instance. Weak: it does not keep a user alive.
  static final Expando<(String, _Session)> _sessionOfUser =
      Expando<(String, _Session)>('FirebaseUserAuth session');

  _Session? _session;
  Future<String?>? _refreshing;
  Timer? _refreshTimer;
  int _refreshFailures = 0;

  /// Whether the stored session differs from the one in memory (or from none, after a sign-out) because its write
  /// failed.
  bool _unsaved = false;
  bool _disposed = false;

  /// Counts the sessions: it changes when a session is installed for a sign-in, [updateCurrentUser] or [restore],
  /// and when the session is cleared. An operation of the signed-in user (a token refresh, an update, a link)
  /// records it when it starts and drops its result when it changed, so that a result of the previous session is
  /// never written into the next one or its storage.
  int _generation = 0;

  /// Counts the sign-ins, [updateCurrentUser] and [signOut] calls, so that when they overlap the later one wins and
  /// the earlier one throws `cancelled`. A sign-in that fails does not affect the operations of the signed-in user.
  int _signInAttempt = 0;

  /// The signed-in user, or null. After [restore] it is the user of the stored session, as it was when it was
  /// stored; [reload] reads it from the backend again.
  AuthUser? get currentUser => _session?.user;

  /// The id of the signed-in user, or null.
  @override
  String? get uid => _session?.user.uid;

  /// The refresh token of the signed-in user's session, or null when signed out. It changes when the server
  /// rotates it, and outlives the ID tokens it mints: treat it as a credential and never log it. Unlike the JS SDK,
  /// it is not a field of [AuthUser], so a user that is printed or serialized never carries it.
  String? get refreshToken => _session?.refreshToken;

  /// Emits the user after every sign-in and sign-out (null when signed out), and after a change of the data of the
  /// signed-in user ([updateProfile], [updateEmail], [reload], ...). It does not emit the current user when it is
  /// listened to: read [currentUser] for that.
  Stream<AuthUser?> userChanges() => _userChanges.stream;

  /// Emits the ID token after a sign-in, after every refresh, and an empty token after a sign-out. [updateCurrentUser]
  /// with a user whose session has no ID token yet (one from [restore]) emits an empty token too: read [uid] for the
  /// user, the token comes with the first refresh.
  @override
  Stream<AuthTokenChange> get onTokenChanged => _tokenChanges.stream;

  /// Emits the current user (null when signed out) when it is listened to, once a [restore] in progress has
  /// finished, and then the user after every sign-in of another user and after a sign-out (FlutterFire's
  /// `authStateChanges()`, the JS SDK's `onAuthStateChanged`). A sign-in of the user who is already signed in, a
  /// token refresh or a change of the user's data does not emit: see [idTokenChanges] and [userChanges].
  ///
  /// ```dart
  /// auth.authStateChanges().listen((AuthUser? user) {
  ///   print(user == null ? 'signed out' : 'signed in as ${user.uid}');
  /// });
  /// ```
  Stream<AuthUser?> authStateChanges() =>
      _startingWithCurrentUser(_authStateChanges.stream);

  /// Like [authStateChanges], and also after every new ID token of the signed-in user: a token refresh, a
  /// password change, a link (FlutterFire's `idTokenChanges()`, the JS SDK's `onIdTokenChanged`).
  Stream<AuthUser?> idTokenChanges() =>
      _startingWithCurrentUser(_idTokenChanges.stream);

  /// Completes when the initial state is known (the JS SDK's `authStateReady`): when the [restore] in progress has
  /// finished (with its error, if it failed), or at once when none is in progress. [forApp] has restored the session
  /// before it returns.
  Future<void> authStateReady() => _restoring ?? Future<void>.value();

  /// Registers [callback] to run before the signed-in user changes (the JS SDK's `beforeAuthStateChanged`): before
  /// a sign-in completes (with the new user), before [signOut] (with null), and before [updateCurrentUser]. It may
  /// be asynchronous; the change waits for it. When it throws, the change does not happen: the operation throws a
  /// [FirebaseAuthException] with the code `login-blocked`, and the [onAbort] of the callbacks that ran before it
  /// are called, in reverse order. A session that ends on the backend (the user is signed out after a refused token
  /// refresh) does not run the callbacks. Returns a function that removes the callback.
  ///
  /// ```dart
  /// final void Function() remove = auth.beforeAuthStateChanged((AuthUser? user) {
  ///   if (user != null && !user.emailVerified && !user.isAnonymous) {
  ///     throw StateError('verify your email address first');
  ///   }
  /// });
  /// ```
  void Function() beforeAuthStateChanged(
    FutureOr<void> Function(AuthUser? user) callback, {
    void Function()? onAbort,
  }) {
    final _BeforeStateCallback entry = _BeforeStateCallback(callback, onAbort);
    _beforeStateCallbacks.add(entry);
    return () => _beforeStateCallbacks.remove(entry);
  }

  /// Makes [user] the signed-in user of this instance (the JS SDK's `updateCurrentUser`), or signs out for null.
  /// [user] must come from a [FirebaseUserAuth] with the same API key (its [currentUser], or the result of one of
  /// its sign-ins): this instance continues that session with its own copy of the tokens, and stores it.
  ///
  /// Runs the [beforeAuthStateChanged] callbacks. Throws a [FirebaseAuthException] with the code
  /// `invalid-user-token` for a user of another API key or one this package did not hand out, and
  /// `tenant-id-mismatch` when the tenant of the user is not [tenantId].
  Future<void> updateCurrentUser(AuthUser? user) async {
    _checkNotDisposed();
    if (user == null) {
      await signOut();
      return;
    }
    final (String, _Session)? source =
        _sessionOfUser[user] ??
        (user is UserCredential ? _sessionOfUser[user.user!] : null);
    if (source == null || source.$1 != apiKey) {
      throw const FirebaseAuthException(
        code: 'invalid-user-token',
        message:
            "This user's credential isn't valid for this project: it does not come from a FirebaseUserAuth "
            'with the same API key.',
      );
    }
    final _Session session = source.$2;
    if (identical(session.user, _session?.user)) {
      return;
    }
    _checkTenant(session.user);
    final int attempt = ++_signInAttempt;
    await _runBeforeStateCallbacks(session.user);
    if (attempt != _signInAttempt || _disposed) {
      throw _overtaken;
    }
    final int generation = await _installSession(session);
    if (generation != _generation) {
      throw _overtaken;
    }
    if (!_userChanges.isClosed) {
      _userChanges.add(session.user);
    }
    // A restored session has no ID token until its first refresh; the empty token tells the token listeners
    // (Firestore) that the user changed, as after a sign-out.
    final String? idToken = session.idToken;
    _emitToken(idToken ?? '');
    _notifyAuthState();
    await _letListenersReact();
  }

  /// Loads the session that an earlier instance stored. The ID token is fetched when it is first needed.
  ///
  /// Does nothing when a user is already signed in or nothing is stored; a stored value that this class did not
  /// write is ignored. Sessions stored by 0.1 and 0.2 are read too; their user has empty [AuthUser.providerData]
  /// and [AuthUser.metadata] until [reload]. It does not check the session with the backend: a session that ended there signs the user
  /// out at the first token refresh. [userChanges] does not emit for a restored user; [authStateChanges] and
  /// [idTokenChanges] do. Throws whatever the `read` of the storage throws.
  Future<void> restore() {
    final Future<void> restoring = _restore();
    _restoring = restoring;
    return restoring.whenComplete(() {
      if (identical(_restoring, restoring)) {
        _restoring = null;
      }
    });
  }

  Future<void> _restore() async {
    if (_unsaved && _session == null) {
      // A sign-out failed to delete the stored session: delete it, never load it.
      await _storage.write(_storageKey, null);
      // A sign-in during the write may have been stored before it: store that session again.
      _unsaved = _session != null;
      return;
    }
    final String? stored = await _storage.read(_storageKey);
    if (stored == null || _session != null) {
      return;
    }
    // Any version of the stored format: a session stored by 0.2 has no provider data, metadata, phone number or
    // tenant until the first reload.
    final ({AuthUser user, String refreshToken})? decoded = decodeSession(
      stored,
    );
    if (decoded == null) {
      // Not something this class wrote: start signed out.
      return;
    }
    _generation++;
    await _setSession(
      _Session(decoded.user, decoded.refreshToken, null, null),
      persist: false,
    );
    // authStateChanges() and idTokenChanges() tell listeners that came before; userChanges() does not emit.
    if (!_idTokenChanges.isClosed) {
      _idTokenChanges.add(decoded.user);
    }
    _notifyAuthState();
  }

  /// Keeps the session in [storage] from now on, and moves the current one there (`setPersistence` of the JS
  /// SDK): it is written to [storage] first, then deleted from the storage used until now.
  ///
  /// Waits for a [restore] in progress, so that the restored session moves too. A session that changes during the
  /// move (a token refresh, a sign-in) is written to [storage] again before the switch.
  ///
  /// Throws whatever the `write` of either storage throws. When writing to [storage] fails, nothing changes; when
  /// deleting from the old storage fails, [storage] is in use and the old storage may still hold the session.
  ///
  /// ```dart
  /// // "Remember me" unticked: keep the session for this run only.
  /// await auth.setStorage(InMemoryAuthStorage());
  /// ```
  Future<void> setStorage(AuthStorage storage) async {
    _checkNotDisposed();
    final Future<void>? restoring = _restoring;
    if (restoring != null) {
      // Its error reaches the caller of restore(); the move goes on with whatever session there is.
      await restoring.then<void>((_) {}, onError: (Object _) {});
    }
    if (identical(storage, _storage)) {
      return;
    }
    final AuthStorage previous = _storage;
    _Session? moved;
    do {
      moved = _session;
      await storage.write(
        _storageKey,
        moved == null ? null : encodeSession(moved.user, moved.refreshToken),
      );
    } while (!identical(moved, _session));
    _storage = storage;
    // The session is stored now, also when an earlier write to the old storage had failed.
    _unsaved = false;
    await previous.write(_storageKey, null);
  }

  /// Signs in a new anonymous user, a new account every time (`signInAnonymously`).
  ///
  /// Throws a [FirebaseAuthException] with the code `operation-not-allowed` (anonymous sign-in is not
  /// enabled for the project), `admin-restricted-operation`, `cancelled` (overtaken by another sign-in or a
  /// sign-out), ...
  Future<UserCredential> signInAnonymously() =>
      _signIn('accounts:signUp', <String, Object?>{'returnSecureToken': true});

  /// Signs in with an email address and a password (`signInWithEmailAndPassword`).
  ///
  /// Throws a [FirebaseAuthException] with the code `wrong-password`, `user-not-found`,
  /// `invalid-credential` (projects with email enumeration protection), `invalid-email`, `user-disabled`,
  /// `operation-not-allowed` (email sign-in is not enabled), `too-many-requests`, `cancelled`, ...; and a
  /// [FirebaseAuthMultiFactorException] (`multi-factor-auth-required`) when the account has a second factor.
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _recachePasswordPolicyOnFailure(
    _signIn('accounts:signInWithPassword', <String, Object?>{
      'email': email,
      'password': password,
      'returnSecureToken': true,
    }),
  );

  /// Creates an account with an email address and a password and signs it in
  /// (`createUserWithEmailAndPassword`). The new user is not anonymous, and its email address is not verified:
  /// see [sendEmailVerification].
  ///
  /// Throws a [FirebaseAuthException] with the code `email-already-in-use`, `weak-password`,
  /// `invalid-email`, `missing-password`, `operation-not-allowed`, `cancelled`, ...
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) => _recachePasswordPolicyOnFailure(
    _signIn('accounts:signUp', <String, Object?>{
      'email': email,
      'password': password,
      'returnSecureToken': true,
    }),
  );

  /// Signs in with a custom token minted by a server (for example with `createCustomToken` of the Admin SDK),
  /// for users that your own backend authenticates (`signInWithCustomToken`). The custom claims of the token are
  /// in the claims of the ID token ([getAccessToken]) and in `request.auth.token` of the security rules.
  ///
  /// Throws a [FirebaseAuthException] with the code `invalid-custom-token`, `custom-token-mismatch` (a
  /// token for another project), `user-disabled`, `cancelled`, ...; and a [FirebaseAuthMultiFactorException]
  /// (`multi-factor-auth-required`) if the backend asks for a second factor.
  Future<UserCredential> signInWithCustomToken(String token) => _signIn(
    'accounts:signInWithCustomToken',
    <String, Object?>{'token': token, 'returnSecureToken': true},
  );

  /// Signs the user out: the session is forgotten, also in the storage, [userChanges], [authStateChanges] and
  /// [idTokenChanges] emit null and [onTokenChanged] an empty token. Does nothing when nobody is signed in. Runs the
  /// [beforeAuthStateChanged] callbacks first, and throws `login-blocked` when one of them throws.
  ///
  /// When the storage fails to delete the session, the user is signed out all the same (the streams emit) and the
  /// error of the storage is thrown; [restore] on this instance deletes the session again instead of loading it.
  ///
  /// It makes no request: the refresh token is not revoked on the backend (as in the other Firebase SDKs).
  /// Firestore continues without a token; the pending writes of the user stay with that user.
  Future<void> signOut() async {
    _checkNotDisposed();
    if (_session == null) {
      return;
    }
    final int attempt = _signInAttempt;
    await _runBeforeStateCallbacks(null);
    if (attempt != _signInAttempt || _session == null || _disposed) {
      // Another sign-in or sign-out started while the callbacks ran.
      return;
    }
    // A sign-in that started before and is still in flight is overtaken.
    _signInAttempt++;
    await _clearSession();
  }

  /// Deletes the account of the signed-in user and signs out (`user.delete()` of the JS SDK). The backend refuses
  /// it with `requires-recent-login` when the sign-in is too long ago: reauthenticate first.
  ///
  /// Throws a [FirebaseAuthException] with the code `null-user` (nobody is signed in),
  /// `requires-recent-login`, `user-token-expired`, ...
  Future<void> deleteCurrentUser() async {
    await _forUser((String idToken, int generation) async {
      await _send(
        _identityToolkit('accounts:delete'),
        json: <String, Object?>{'idToken': idToken},
      );
      if (generation == _generation) {
        await _clearSession();
      }
    });
  }

  /// Revokes the Sign in with Apple token of the signed-in user with the [authorizationCode] that Apple returned
  /// (`revokeToken(withAuthorizationCode:)` of the iOS SDK; `v2/accounts:revokeToken`). Apple asks apps that let
  /// users delete their account to revoke the token first. The user stays signed in. The [tenantId], when set, is
  /// sent with it, as the JS SDK's `revokeToken` request does.
  ///
  /// Throws a [FirebaseAuthException] with the code `null-user` (nobody is signed in), `invalid-credential`,
  /// `user-token-expired`, ...
  Future<void> revokeToken(String authorizationCode) async {
    await _forUser((String idToken, int generation) async {
      await _send(
        _identityToolkit('accounts:revokeToken', version: 'v2'),
        json: <String, Object?>{
          'providerId': 'apple.com',
          'tokenType': '3',
          'token': authorizationCode,
          'idToken': idToken,
        },
        tenant: true,
      );
    });
  }

  /// Revokes the Sign in with Apple access [token] of the signed-in user (`revokeAccessToken` of the JS SDK;
  /// `v2/accounts:revokeToken` with the token type `ACCESS_TOKEN`). The user stays signed in.
  ///
  /// Throws a [FirebaseAuthException] with the code `null-user` (nobody is signed in; the JS SDK does nothing
  /// then), `invalid-credential`, `user-token-expired`, ...
  Future<void> revokeAccessToken(String token) async {
    await _forUser((String idToken, int generation) async {
      await _send(
        _identityToolkit('accounts:revokeToken', version: 'v2'),
        json: <String, Object?>{
          'providerId': 'apple.com',
          'tokenType': 'ACCESS_TOKEN',
          'token': token,
          'idToken': idToken,
        },
        tenant: true,
      );
    });
  }

  // ---- account management (the REST-backed operations of the JS SDK) ----

  /// Sends a password reset email to [email] (`sendPasswordResetEmail`). The link carries the code that
  /// [confirmPasswordReset] takes.
  ///
  /// Throws `user-not-found` (projects without email enumeration protection), `invalid-email`,
  /// `too-many-requests`, `invalid-continue-uri`, ...
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    _checkNotDisposed();
    await _send(
      _identityToolkit('accounts:sendOobCode'),
      json: <String, Object?>{
        'requestType': ActionCodeOperation.passwordReset.serverName,
        'email': email,
        ...?actionCodeSettings?.toRequest(),
      },
      tenant: true,
    );
  }

  /// Sets [newPassword] with the [code] of a password reset email (`confirmPasswordReset`).
  ///
  /// Throws `expired-action-code`, `invalid-action-code`, `weak-password`, `user-disabled`, ...
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    _checkNotDisposed();
    await _recachePasswordPolicyOnFailure(
      _send(
        _identityToolkit('accounts:resetPassword'),
        json: <String, Object?>{'oobCode': code, 'newPassword': newPassword},
        tenant: true,
      ),
    );
  }

  /// What the action [code] is for and which email address it is about, without applying it (`checkActionCode`).
  ///
  /// Throws `expired-action-code`, `invalid-action-code`, and `internal-error` when the answer lacks the fields
  /// the operation needs.
  Future<ActionCodeInfo> checkActionCode(String code) async {
    _checkNotDisposed();
    return ActionCodeInfo.fromResponse(
      await _send(
        _identityToolkit('accounts:resetPassword'),
        json: <String, Object?>{'oobCode': code},
        tenant: true,
      ),
    );
  }

  /// The email address of the password reset [code], which is not used up (`verifyPasswordResetCode`).
  ///
  /// Throws like [checkActionCode].
  Future<String> verifyPasswordResetCode(String code) async {
    final ActionCodeInfo info = await checkActionCode(code);
    final String? email = info.email;
    if (email == null) {
      throw const FirebaseAuthException(
        code: 'internal-error',
        message: 'The action code has no email address.',
      );
    }
    return email;
  }

  /// Applies the action [code] of an email: verifies the email address, or changes it for
  /// [verifyBeforeUpdateEmail], or undoes a change (`applyActionCode`). The signed-in user is not reloaded, like
  /// in the JS SDK: call [reload] to see the change.
  ///
  /// Throws `expired-action-code`, `invalid-action-code`, `user-disabled`, `user-not-found`, ...
  Future<void> applyActionCode(String code) async {
    _checkNotDisposed();
    await _send(
      _identityToolkit('accounts:update'),
      json: <String, Object?>{'oobCode': code},
      tenant: true,
    );
  }

  /// The sign-in methods of the account of [email], for example `['password']` (`fetchSignInMethodsForEmail`).
  ///
  /// Projects with email enumeration protection (the default for new projects) always answer with an empty list;
  /// the JS SDK documents the method as deprecated for that reason.
  Future<List<String>> fetchSignInMethodsForEmail(String email) async {
    _checkNotDisposed();
    // Like the JS SDK: the current page when there is one, else http://localhost.
    final Uri base = Uri.base;
    final String continueUri = base.scheme == 'http' || base.scheme == 'https'
        ? base.toString()
        : 'http://localhost';
    final Map<String, Object?> response = await _send(
      _identityToolkit('accounts:createAuthUri'),
      json: <String, Object?>{'identifier': email, 'continueUri': continueUri},
      tenant: true,
    );
    final Object? methods = response['signinMethods'];
    return methods is List ? methods.whereType<String>().toList() : <String>[];
  }

  /// Sends an email to the signed-in user to verify the email address (`sendEmailVerification`). The user is
  /// reloaded when the backend knows another address than [currentUser]. The link carries the code that
  /// [applyActionCode] takes.
  ///
  /// Throws `null-user`, `too-many-requests`, `invalid-continue-uri`, ...
  Future<void> sendEmailVerification({
    ActionCodeSettings? actionCodeSettings,
  }) => _forUser((String idToken, int generation) async {
    final Map<String, Object?> response = await _send(
      _identityToolkit('accounts:sendOobCode'),
      json: <String, Object?>{
        'requestType': ActionCodeOperation.verifyEmail.serverName,
        'idToken': idToken,
        ...?actionCodeSettings?.toRequest(),
      },
      tenant: true,
    );
    if (response['email'] != _session?.user.email) {
      await _reloadAfterChange(generation);
    }
  });

  /// Sends an email to [newEmail]; the address of the account changes when the link in it is used
  /// (`verifyBeforeUpdateEmail`). This is what projects with email enumeration protection allow instead of
  /// [updateEmail].
  ///
  /// Throws `null-user`, `requires-recent-login`, `invalid-email`, `email-already-in-use`, ...
  Future<void> verifyBeforeUpdateEmail(
    String newEmail, {
    ActionCodeSettings? actionCodeSettings,
  }) => _forUser((String idToken, int generation) async {
    final Map<String, Object?> response = await _send(
      _identityToolkit('accounts:sendOobCode'),
      json: <String, Object?>{
        'requestType': ActionCodeOperation.verifyAndChangeEmail.serverName,
        'idToken': idToken,
        'newEmail': newEmail,
        ...?actionCodeSettings?.toRequest(),
      },
      tenant: true,
    );
    if (response['email'] != _session?.user.email) {
      await _reloadAfterChange(generation);
    }
  });

  /// Changes the email address of the signed-in user (`updateEmail`).
  ///
  /// Throws `requires-recent-login`, `email-already-in-use`, `invalid-email`, and `operation-not-allowed` on
  /// projects with email enumeration protection (use [verifyBeforeUpdateEmail] there).
  Future<void> updateEmail(String newEmail) =>
      _updateEmailOrPassword(<String, Object?>{'email': newEmail});

  /// Changes the password of the signed-in user (`updatePassword`). The session continues with the new tokens
  /// the backend returns.
  ///
  /// Throws `requires-recent-login`, `weak-password`, ...
  Future<void> updatePassword(String newPassword) =>
      _updateEmailOrPassword(<String, Object?>{'password': newPassword});

  /// Changes the display name and the photo URL of the signed-in user (`updateProfile`). A null argument keeps the
  /// value; an empty string removes it (the JS SDK takes null for that, which the REST API does not honour: the
  /// attribute is deleted with `deleteAttribute`). With both null it does nothing, not even check that somebody
  /// is signed in.
  ///
  /// Throws `null-user`, `user-token-expired`, ...
  Future<void> updateProfile({String? displayName, String? photoUrl}) async {
    if (displayName == null && photoUrl == null) {
      return;
    }
    await _forUser((String idToken, int generation) async {
      final List<String> delete = <String>[
        if (displayName != null && displayName.isEmpty) 'DISPLAY_NAME',
        if (photoUrl != null && photoUrl.isEmpty) 'PHOTO_URL',
      ];
      final Map<String, Object?> response = await _send(
        _identityToolkit('accounts:update'),
        json: <String, Object?>{
          'idToken': idToken,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
          if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
          if (delete.isNotEmpty) 'deleteAttribute': delete,
          'returnSecureToken': true,
        },
      );
      final AuthUser? user = _session?.user;
      if (user == null) {
        return;
      }
      final Object? newName = response['displayName'];
      final Object? newPhoto = response['photoUrl'];
      await _updateSession(
        response,
        generation,
        user: copyUser(
          user,
          displayName: newName is String && newName.isNotEmpty ? newName : null,
          clearDisplayName: newName is! String || newName.isEmpty,
          photoUrl: newPhoto is String && newPhoto.isNotEmpty ? newPhoto : null,
          clearPhotoUrl: newPhoto is! String || newPhoto.isEmpty,
        ),
      );
    });
  }

  /// Signs the signed-in user in again with [email] and [password]: [reauthenticateWithCredential] with an
  /// [EmailAuthProvider.credential], which operations such as [updatePassword] and [deleteCurrentUser] need when
  /// the last sign-in is too long ago.
  ///
  /// Throws `user-mismatch` when the credentials are those of another account (or of none), `wrong-password`,
  /// `invalid-credential`, ...; and a [FirebaseAuthMultiFactorException] (`multi-factor-auth-required`) when the
  /// account has a second factor (the signed-in user stays signed in).
  Future<UserCredential> reauthenticateWithEmailAndPassword({
    required String email,
    required String password,
  }) => reauthenticateWithCredential(
    EmailAuthProvider.credential(email: email, password: password),
  );

  // ---- password policy ----

  /// Checks [password] against the password policy of the project, or of [tenantId] (`validatePassword` of the
  /// JS SDK and of FlutterFire), for example to show what a new password still lacks before
  /// [createUserWithEmailAndPassword] or [updatePassword].
  ///
  /// The policy is fetched once (`v2/passwordPolicy`) per tenant and cached; it is fetched again after the backend
  /// refuses a password with `password-does-not-meet-requirements` (as the JS SDK does). An empty password is not
  /// an error: it fails the minimum length.
  ///
  /// Throws a [FirebaseAuthException] when the policy cannot be fetched (`network-request-failed`, ...), and
  /// `unsupported-password-policy-schema-version` for a policy of a schema this package does not know.
  ///
  /// ```dart
  /// final PasswordValidationStatus status = await auth.validatePassword('hunter2');
  /// if (!status.isValid) {
  ///   print('at least ${status.passwordPolicy.minPasswordLength} characters');
  /// }
  /// ```
  Future<PasswordValidationStatus> validatePassword(String password) async {
    _checkNotDisposed();
    final PasswordPolicy policy =
        _passwordPolicies[tenantId] ?? await _fetchPasswordPolicy();
    if (policy.schemaVersion != PasswordPolicy.supportedSchemaVersion) {
      throw const FirebaseAuthException(
        code: 'unsupported-password-policy-schema-version',
        message:
            'The password policy received from the backend uses a schema version that is not supported by this '
            'version of the package.',
      );
    }
    return policy.validate(password);
  }

  /// Fetches the policy of [tenantId] and caches it (`_updatePasswordPolicy` of the JS SDK).
  Future<PasswordPolicy> _fetchPasswordPolicy() async {
    final String? tenant = tenantId;
    final PasswordPolicy policy = PasswordPolicy.fromResponse(
      await _send(
        _identityToolkit(
          'passwordPolicy',
          version: 'v2',
          query: <String, String>{'tenantId': ?tenant},
        ),
        get: true,
      ),
    );
    _passwordPolicies[tenant] = policy;
    return policy;
  }

  // ---- app verification ----

  /// The reCAPTCHA v2 site key of the project (`v1/recaptchaParams`, `getRecaptchaParams` of the JS
  /// SDK): the key a reCAPTCHA v2 widget renders with, for example in a `RecaptchaFlow` of
  /// `package:secure_flow` or in a WebView of yours.
  ///
  /// The request goes to the Auth emulator when one is set; the emulator answers with a fake key,
  /// and phone requests to it need no proof ([AppVerification.none]). No tenant is sent, as in the
  /// JS SDK: the key belongs to the project. The key is fetched on every call.
  ///
  /// Throws a [FirebaseAuthException] when the request fails (`network-request-failed`, ...), and
  /// `internal-error` when the answer has no site key.
  Future<String> getRecaptchaSiteKey() async {
    _checkNotDisposed();
    final Map<String, Object?> response = await _send(
      _identityToolkit('recaptchaParams'),
      get: true,
    );
    final Object? siteKey = response['recaptchaSiteKey'];
    if (siteKey is! String || siteKey.isEmpty) {
      throw const FirebaseAuthException(
        code: 'internal-error',
        message: 'The authentication service returned no reCAPTCHA site key.',
      );
    }
    return siteKey;
  }

  /// Like `recachePasswordPolicy` of the JS SDK: when [operation] fails with `password-does-not-meet-requirements`
  /// and a policy was fetched before, it is fetched again in the background.
  Future<T> _recachePasswordPolicyOnFailure<T>(
    Future<T> operation,
  ) => operation.catchError((Object error, StackTrace stackTrace) {
    if (error is FirebaseAuthException &&
        error.code == 'password-does-not-meet-requirements' &&
        _passwordPolicies.containsKey(tenantId) &&
        !_disposed) {
      unawaited(
        _fetchPasswordPolicy().then<void>(
          (_) {},
          onError: (Object _) {
            // The policy stays as it was; the next validatePassword uses it.
          },
        ),
      );
    }
    return Future<T>.error(error, stackTrace);
  });

  // ---- email link sign-in ----

  /// Sends an email with a sign-in link to [email] (`sendSignInLinkToEmail`). The link opens the URL of
  /// [actionCodeSettings], whose [ActionCodeSettings.handleCodeInApp] must be true: the app receives the link and
  /// passes it to [signInWithEmailLink], with the address (keep it, for example in local storage, until then).
  ///
  /// The sign-in method "Email link (passwordless sign-in)" must be enabled for the project. Throws
  /// `argument-error` when `handleCodeInApp` is not true, and `invalid-email`, `operation-not-allowed`,
  /// `unauthorized-continue-uri`, `invalid-continue-uri`, ...
  ///
  /// ```dart
  /// await auth.sendSignInLinkToEmail(
  ///   email: 'ada@example.com',
  ///   actionCodeSettings: const ActionCodeSettings(
  ///     url: 'https://my-project.web.app/finish-sign-in',
  ///     handleCodeInApp: true,
  ///   ),
  /// );
  /// ```
  Future<void> sendSignInLinkToEmail({
    required String email,
    required ActionCodeSettings actionCodeSettings,
  }) async {
    _checkNotDisposed();
    if (actionCodeSettings.handleCodeInApp != true) {
      throw const FirebaseAuthException(
        code: 'argument-error',
        message:
            'An email link sign-in needs ActionCodeSettings with handleCodeInApp: true.',
      );
    }
    await _send(
      _identityToolkit('accounts:sendOobCode'),
      json: <String, Object?>{
        'requestType': ActionCodeOperation.emailSignIn.serverName,
        'email': email,
        ...actionCodeSettings.toRequest(),
      },
      tenant: true,
    );
  }

  /// Whether [emailLink] is a sign-in link of [sendSignInLinkToEmail] (`isSignInWithEmailLink`): see
  /// [ActionCodeURL.parseLink].
  bool isSignInWithEmailLink(String emailLink) =>
      ActionCodeURL.parseLink(emailLink)?.operation ==
      ActionCodeOperation.emailSignIn;

  /// Signs in with the sign-in link of the email [sendSignInLinkToEmail] sent to [email] (`signInWithEmailLink`):
  /// [signInWithCredential] with [EmailAuthProvider.credentialWithLink]. The account is created if there is none,
  /// and its address counts as verified.
  ///
  /// Throws `argument-error` for a link that is not the link of an action email, `tenant-id-mismatch` when the
  /// link is for another tenant than [tenantId], `invalid-action-code` or `expired-action-code` for a used or old
  /// link, `invalid-email` when [email] is not the address the link was sent to, ...
  ///
  /// ```dart
  /// if (auth.isSignInWithEmailLink(link)) {
  ///   final UserCredential result = await auth.signInWithEmailLink(
  ///     email: 'ada@example.com',
  ///     emailLink: link,
  ///   );
  ///   print(result.user?.emailVerified); // true
  /// }
  /// ```
  Future<UserCredential> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    _checkNotDisposed();
    if (_parseEmailLink(emailLink).tenantId != tenantId) {
      throw const FirebaseAuthException(
        code: 'tenant-id-mismatch',
        message:
            "The provided tenant ID does not match the Auth instance's tenant ID.",
      );
    }
    return signInWithCredential(
      EmailAuthProvider.credentialWithLink(email: email, emailLink: emailLink),
    );
  }

  // ---- credentials ----

  /// Signs in with [credential] (`signInWithCredential`), replacing the current user like the other sign-ins:
  /// an [EmailAuthProvider] credential signs in with the password or the email link, an [OAuthCredential] (of
  /// [GoogleAuthProvider], [AppleAuthProvider], [OAuthProvider], ...) exchanges the provider's token through
  /// `accounts:signInWithIdp`; the account is created when it does not exist
  /// ([AdditionalUserInfo.isNewUser]). The result's [UserCredential.credential] holds the provider's tokens the
  /// backend returned.
  ///
  /// Throws `invalid-credential` (the backend refused the token), `account-exists-with-different-credential` (an
  /// account with the email address of the credential exists with another sign-in method:
  /// [FirebaseAuthException.email] and [FirebaseAuthException.credential] let the app sign in with that method and
  /// link the credential), `operation-not-allowed` (the provider is not enabled), `missing-or-invalid-nonce`,
  /// `user-disabled`, ...
  ///
  /// The email credentials throw what their sign-ins throw (`wrong-password`, `invalid-action-code`, ...); all
  /// throw a [FirebaseAuthMultiFactorException] when the account has a second factor.
  ///
  /// ```dart
  /// // The ID token comes from Google Sign-In (or any other way the app signs the user in with Google).
  /// final UserCredential result = await auth.signInWithCredential(
  ///   GoogleAuthProvider.credential(idToken: googleIdToken),
  /// );
  /// print(result.additionalUserInfo?.isNewUser);
  /// ```
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    _checkNotDisposed();
    final _CredentialRequest request = _requestFor(credential);
    return _withoutSecretsOf(
      credential,
      () => _signIn(request.method, request.body),
    );
  }

  /// Signs in with [provider] in the system browser (desktop apps and command line tools, VM only): runs
  /// [authorizeWithOAuthLoopback] and then [signInWithCredential] with the credential of the provider's tokens. On
  /// the web it throws an [UnsupportedError].
  ///
  /// [presenter] runs the browser part (when null, the presenter of [environment] that an
  /// `OAuthFlow` ranks best: a provider app registered there for this provider, the system browser,
  /// an in-app browser, the console), [timeout] bounds the wait for the
  /// redirect, and [httpClient] is used for the code exchange (the client of this instance by default). It throws
  /// what both steps throw: `timeout`, `user-cancelled`, `invalid-oauth-response`, `invalid-credential`, ...
  ///
  /// To link or reauthenticate instead, use [linkWithOAuthLoopback] or [reauthenticateWithOAuthLoopback].
  ///
  /// ```dart
  /// final UserCredential result = await auth.signInWithOAuthLoopback(
  ///   OAuthLoopbackProvider.google(
  ///     clientId: '<the client id of a Desktop OAuth client>',
  ///     clientSecret: '<its client secret>',
  ///   ),
  /// );
  /// ```
  Future<UserCredential> signInWithOAuthLoopback(
    OAuthLoopbackProvider provider, {
    SecurePresenter? presenter,
    SecureEnvironment? environment,
    Duration timeout = const Duration(minutes: 5),
    http.Client? httpClient,
  }) async {
    _checkNotDisposed();
    final OAuthLoopbackResult result = await authorizeWithOAuthLoopback(
      provider,
      presenter: presenter,
      environment: environment,
      timeout: timeout,
      httpClient: httpClient ?? _http,
    );
    return signInWithCredential(result.credential);
  }

  /// Links [provider] to the signed-in user through the system browser (VM only): runs [authorizeWithOAuthLoopback]
  /// and then [linkWithCredential] with the credential of the provider's tokens. On the web it throws an
  /// [UnsupportedError].
  ///
  /// The parameters are those of [signInWithOAuthLoopback]. It throws `null-user` before the browser opens when
  /// nobody is signed in, then what both steps throw: `timeout`, `user-cancelled`, `provider-already-linked`,
  /// `credential-already-in-use`, ...
  Future<UserCredential> linkWithOAuthLoopback(
    OAuthLoopbackProvider provider, {
    SecurePresenter? presenter,
    SecureEnvironment? environment,
    Duration timeout = const Duration(minutes: 5),
    http.Client? httpClient,
  }) async {
    _checkNotDisposed();
    _requireSession();
    final OAuthLoopbackResult result = await authorizeWithOAuthLoopback(
      provider,
      presenter: presenter,
      environment: environment,
      timeout: timeout,
      httpClient: httpClient ?? _http,
    );
    return linkWithCredential(result.credential);
  }

  /// Signs the signed-in user in again with [provider] through the system browser (VM only): runs
  /// [authorizeWithOAuthLoopback] and then [reauthenticateWithCredential] with the credential of the provider's
  /// tokens. On the web it throws an [UnsupportedError].
  ///
  /// The parameters are those of [signInWithOAuthLoopback]. It throws `null-user` before the browser opens when
  /// nobody is signed in, then what both steps throw: `timeout`, `user-cancelled`, `user-mismatch` (the user signed
  /// in to the provider with another account), ...
  Future<UserCredential> reauthenticateWithOAuthLoopback(
    OAuthLoopbackProvider provider, {
    SecurePresenter? presenter,
    SecureEnvironment? environment,
    Duration timeout = const Duration(minutes: 5),
    http.Client? httpClient,
  }) async {
    _checkNotDisposed();
    _requireSession();
    final OAuthLoopbackResult result = await authorizeWithOAuthLoopback(
      provider,
      presenter: presenter,
      environment: environment,
      timeout: timeout,
      httpClient: httpClient ?? _http,
    );
    return reauthenticateWithCredential(result.credential);
  }

  /// Links [credential] to the signed-in user (`linkWithCredential`): the account can then sign in with it too. An
  /// anonymous user linked to an email address and a password, or to a federated provider, is no longer anonymous.
  ///
  /// Throws `null-user`, `provider-already-linked` (the user has a credential of this provider already: the
  /// account is read first), `credential-already-in-use` (another account has it; [FirebaseAuthException.credential]
  /// may carry it back), `email-already-in-use`, `requires-recent-login`, ...
  Future<UserCredential> linkWithCredential(AuthCredential credential) =>
      _withoutSecretsOf(credential, () => _linkWithCredential(credential));

  Future<UserCredential> _linkWithCredential(
    AuthCredential credential,
  ) => _forUser((String idToken, int generation) async {
    // _assertLinkedStatus of the JS SDK.
    await _reload(generation);
    final AuthUser? user = _session?.user;
    if (user == null || generation != _generation) {
      throw _overtaken;
    }
    if (user.providerData.any(
      (UserInfo info) => info.providerId == credential.providerId,
    )) {
      throw const FirebaseAuthException(
        code: 'provider-already-linked',
        message:
            'User can only be linked to one identity for the given provider.',
      );
    }
    final _CredentialRequest request = _requestFor(
      credential,
      userIdToken: await _idTokenOf(generation),
    );
    final Map<String, Object?> response = await _send(
      _identityToolkit(request.method),
      json: request.body,
      tenant: request.tenant,
    );
    _throwIfPhoneNumberInUse(response);
    _throwIfSecondFactorRequired(response);
    if (generation != _generation) {
      throw _overtaken;
    }
    await _updateSession(response, generation);
    await _reloadAfterChange(generation);
    return _result(response, _session?.user ?? user, OperationType.link);
  });

  /// Signs the signed-in user in again with [credential] (`reauthenticateWithCredential`), which operations such
  /// as [updatePassword] and [deleteCurrentUser] need when the last sign-in is too long ago. The user stays the
  /// same; the session continues with the new tokens.
  ///
  /// Throws `null-user`, `user-mismatch` when the credential is that of another account (or of none),
  /// `wrong-password`, `invalid-credential`, ...; and a [FirebaseAuthMultiFactorException]
  /// (`multi-factor-auth-required`) when the account has a second factor (the signed-in user stays signed in).
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) => _withoutSecretsOf(
    credential,
    () => _reauthenticateWithCredential(credential),
  );

  Future<UserCredential> _reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    _checkNotDisposed();
    final _Session session = _requireSession();
    final int generation = _generation;
    final _CredentialRequest request = _requestFor(
      credential,
      reauthenticate: true,
    );
    final Map<String, Object?> response;
    try {
      response = await _send(
        _identityToolkit(request.method),
        json: request.body,
        tenant: request.tenant,
      );
    } on FirebaseAuthException catch (e) {
      // VERIFY_PHONE_NUMBER_FOR_EXISTING_ERROR_MAP_ of the JS SDK: for a phone credential the
      // backend answers USER_NOT_FOUND when the number belongs to no account.
      if (e.code == 'user-not-found' ||
          (credential is PhoneAuthCredential &&
              e.serverCode == 'USER_NOT_FOUND')) {
        throw _userMismatch;
      }
      rethrow;
    }
    _throwIfSecondFactorRequired(
      response,
      finish: (Future<Map<String, Object?>> finalized) async =>
          _completeReauthentication(await finalized, session, generation),
    );
    return _completeReauthentication(response, session, generation);
  }

  /// Takes the tokens of a reauthentication [response] into the [session] of [generation], when they are those of
  /// its user.
  Future<UserCredential> _completeReauthentication(
    Map<String, Object?> response,
    _Session session,
    int generation,
  ) async {
    final Object? idToken = response['idToken'];
    if (idToken is! String) {
      throw const FirebaseAuthException(
        code: 'internal-error',
        message: 'The authentication service did not return tokens.',
      );
    }
    final GetTokenResult token = GetTokenResult(idToken);
    if ((token.claims['sub'] ?? response['localId']) != session.user.uid) {
      throw _userMismatch;
    }
    if (generation != _generation) {
      throw const FirebaseAuthException(
        code: 'cancelled',
        message:
            'The reauthentication was overtaken by another sign-in or a sign-out.',
      );
    }
    await _updateSession(response, generation);
    await _reload(generation);
    return _result(
      response,
      _session?.user ?? session.user,
      OperationType.reauthenticate,
    );
  }

  /// Removes the sign-in method of [providerId] (`password`, `google.com`, ...) from the account of the signed-in
  /// user (`unlink`), and returns the user without it. The account is read first; [userChanges] emits the new user.
  ///
  /// Throws `null-user`, `no-such-provider` (the user has no such method), `requires-recent-login`, ...
  Future<AuthUser> unlink(String providerId) => _forUser((
    String idToken,
    int generation,
  ) async {
    // _assertLinkedStatus of the JS SDK.
    await _reload(generation);
    final AuthUser? user = _session?.user;
    if (user == null || generation != _generation) {
      throw _overtaken;
    }
    if (!user.providerData.any(
      (UserInfo info) => info.providerId == providerId,
    )) {
      throw const FirebaseAuthException(
        code: 'no-such-provider',
        message: 'User was not linked to an account with the given provider.',
      );
    }
    final Map<String, Object?> response = await _send(
      _identityToolkit('accounts:update'),
      json: <String, Object?>{
        'idToken': await _idTokenOf(generation),
        'deleteProvider': <String>[providerId],
      },
    );
    final AuthUser? current = _session?.user;
    if (current == null || generation != _generation) {
      throw _overtaken;
    }
    final Set<String> left = <String>{
      for (final UserInfo info in providerDataOf(response['providerUserInfo']))
        info.providerId,
    };
    final AuthUser updated = copyUser(
      current,
      providerData: List<UserInfo>.unmodifiable(<UserInfo>[
        for (final UserInfo info in current.providerData)
          if (left.contains(info.providerId)) info,
      ]),
      clearPhoneNumber: !left.contains('phone'),
    );
    await _updateSession(const <String, Object?>{}, generation, user: updated);
    return updated;
  });

  // ---- phone ----

  /// Sends an SMS code to [phoneNumber] (`v1/accounts:sendVerificationCode`; `verifyPhoneNumber` of
  /// the iOS SDK's `FIRPhoneAuthProvider`) and returns the verification id. Pair the id with the
  /// code the user types in ([PhoneAuthProvider.credential]) and sign in, link, reauthenticate or
  /// update the phone number with that credential. The code field is the app's own: nothing here
  /// opens a browser for it.
  ///
  /// [phoneNumber] is in E.164 form (`+15555550100`). [appVerification] proves that the request
  /// comes from a real app: a reCAPTCHA v2 token (the site key is fetched with
  /// [getRecaptchaSiteKey] first), a reCAPTCHA Enterprise token, or [AppVerification.none] for the
  /// Auth emulator. [tenantId] and [languageCode] (the language of the SMS) go with the request.
  ///
  /// Throws a [FirebaseAuthException]: `missing-phone-number` (empty, before anything is sent),
  /// `invalid-phone-number`, `missing-app-credential`, `invalid-app-credential`,
  /// `captcha-check-failed`, `quota-exceeded`, `too-many-requests`, `operation-not-allowed` (phone
  /// sign-in is not enabled), and what the source of the token throws. No error, message or log
  /// line holds the phone number, the verification id or the reCAPTCHA token.
  ///
  /// ```dart
  /// final String verificationId = await auth.verifyPhoneNumber(
  ///   '+15555550100',
  ///   appVerification: AppVerification.recaptchaV2Loopback(),
  /// );
  /// final UserCredential result = await auth.signInWithCredential(
  ///   PhoneAuthProvider.credential(
  ///     verificationId: verificationId,
  ///     verificationCode: codeFromYourTextField,
  ///   ),
  /// );
  /// ```
  Future<String> verifyPhoneNumber(
    String phoneNumber, {
    required AppVerification appVerification,
  }) async {
    _checkNotDisposed();
    _requirePhoneNumber(phoneNumber);
    final List<String?> secrets = <String?>[phoneNumber];
    return _withoutPhoneSecrets(secrets, () async {
      final Map<String, Object?> proof = await _proofOf(
        appVerification,
        RecaptchaAction.sendVerificationCode,
        secrets,
      );
      final Map<String, Object?> response = await _send(
        _identityToolkit('accounts:sendVerificationCode'),
        json: <String, Object?>{'phoneNumber': phoneNumber, ...proof},
        tenant: true,
      );
      final String verificationId = _sessionInfoOf(response['sessionInfo']);
      secrets.add(verificationId);
      return verificationId;
    });
  }

  /// Sends the SMS code and asks for it, for programs without a code field of their own (command
  /// line tools, desktop apps without a UI for it; VM only): [verifyPhoneNumber] with
  /// [appVerification] (by default the reCAPTCHA v2 page of `package:secure_flow`,
  /// [AppVerification.recaptchaV2Loopback] with [codePresenter], [environment] and [timeout]), then
  /// a `CodeEntryFlow` of `package:secure_flow` that asks for the code with [prompt]: on the
  /// terminal, or on a small page in the system browser, through [codePresenter] (when null, the
  /// presenter of [environment] that the flow ranks best).
  ///
  /// Returns the credential; sign in, link, reauthenticate or update the phone number with it.
  ///
  /// Throws what [verifyPhoneNumber] throws, and for the code: `timeout` (no code within
  /// [timeout]), `operation-not-supported-in-this-environment` (no presenter fits),
  /// `argument-error` ([codePresenter] cannot ask for a code).
  ///
  /// ```dart
  /// final PhoneAuthCredential credential =
  ///     await auth.verifyPhoneNumberInteractively('+15555550100');
  /// await auth.signInWithCredential(credential);
  /// ```
  Future<PhoneAuthCredential> verifyPhoneNumberInteractively(
    String phoneNumber, {
    AppVerification? appVerification,
    SecurePresenter? codePresenter,
    SecureEnvironment? environment,
    Duration timeout = const Duration(minutes: 5),
    String prompt = 'Enter the code of the SMS:',
  }) async {
    final String verificationId = await verifyPhoneNumber(
      phoneNumber,
      appVerification:
          appVerification ??
          AppVerification.recaptchaV2Loopback(
            presenter: codePresenter,
            environment: environment,
            timeout: timeout,
          ),
    );
    final String code = await runSecureFlow<String>(
      CodeEntryFlow(prompt: prompt),
      presenter: codePresenter,
      environment: environment,
      timeout: timeout,
      timeoutMessage:
          'No SMS code was entered within ${timeout.inSeconds} seconds.',
    );
    return PhoneAuthProvider.credential(
      verificationId: verificationId,
      verificationCode: code,
    );
  }

  /// Sets the phone number of the signed-in user to the one [credential] verified
  /// (`v1/accounts:signInWithPhoneNumber` with the ID token, as `updatePhoneNumber` of the JS SDK
  /// sends it; `updatePhoneNumber` of the iOS SDK's `FIRUser`). It adds the phone provider when the
  /// user has none and replaces the number when it has one.
  ///
  /// The session continues with the new tokens the backend returns, and the account is read again:
  /// [userChanges] emits a user whose [AuthUser.phoneNumber] is the new number.
  ///
  /// Throws `null-user`, `missing-verification-id` and `missing-verification-code` (an empty part
  /// of the credential, before anything is sent), `invalid-verification-code`,
  /// `invalid-verification-id`, `code-expired`, `credential-already-in-use` (another account has
  /// the number), `requires-recent-login`, ...
  Future<void> updatePhoneNumber(PhoneAuthCredential credential) =>
      _withoutSecretsOf(
        credential,
        () => _forUser((String idToken, int generation) async {
          final _CredentialRequest request = _requestFor(
            credential,
            userIdToken: idToken,
          );
          final Map<String, Object?> response = await _send(
            _identityToolkit(request.method),
            json: request.body,
            tenant: request.tenant,
          );
          _throwIfPhoneNumberInUse(response);
          await _updateSession(response, generation);
          await _reloadAfterChange(generation);
        }),
      );

  /// Throws `missing-phone-number` for an empty [phoneNumber], before a reCAPTCHA is asked for.
  static void _requirePhoneNumber(String phoneNumber) {
    if (phoneNumber.trim().isEmpty) {
      throw const FirebaseAuthException(
        code: AuthErrorCode.missingPhoneNumber,
        message:
            'To send verification codes, provide a phone number for the recipient.',
      );
    }
  }

  /// The fields of [verification] for a request of [action]; the token goes into [secrets].
  Future<Map<String, Object?>> _proofOf(
    AppVerification verification,
    RecaptchaAction action,
    List<String?> secrets,
  ) async {
    final Map<String, Object?> fields = await appVerificationFields(
      verification,
      action: action,
      siteKey: getRecaptchaSiteKey,
      languageCode: languageCode,
    );
    secrets
      ..add(fields['recaptchaToken'] as String?)
      ..add(fields['captchaResponse'] as String?);
    return fields;
  }

  /// The `sessionInfo` of an answer (the verification id), or `internal-error`.
  static String _sessionInfoOf(Object? sessionInfo) {
    if (sessionInfo is! String || sessionInfo.isEmpty) {
      throw const FirebaseAuthException(
        code: AuthErrorCode.internalError,
        message: 'The authentication service did not return a verification id.',
      );
    }
    return sessionInfo;
  }

  /// Runs [body] and rethrows its [FirebaseAuthException]s without [secrets]
  /// ([redactPhoneSecrets]). [secrets] is read when the error is thrown, so that a value added
  /// meanwhile (a token, a verification id) is left out too.
  static Future<T> _withoutPhoneSecrets<T>(
    List<String?> secrets,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on FirebaseAuthException catch (e, stackTrace) {
      Error.throwWithStackTrace(redactPhoneSecrets(e, secrets), stackTrace);
    }
  }

  /// [body], without the secrets of [credential] in its errors when it is a phone credential.
  static Future<T> _withoutSecretsOf<T>(
    AuthCredential credential,
    Future<T> Function() body,
  ) => credential is PhoneAuthCredential
      ? _withoutPhoneSecrets(<String?>[
          credential.verificationId,
          credential.verificationCode,
          credential.temporaryProof,
          credential.phoneNumber,
        ], body)
      : body();

  /// Like `linkWithPhoneNumber` of the JS SDK: an answer of `accounts:signInWithPhoneNumber` with a
  /// `temporaryProof` (and no tokens) means that another account has the number. The JS SDK throws
  /// `account-exists-with-different-credential`; the iOS and Android SDKs, and so FlutterFire on
  /// them, throw `credential-already-in-use`, which this follows. As in the iOS SDK, the error's
  /// [FirebaseAuthException.credential] is a [PhoneAuthCredential] of the proof and the number,
  /// which signs in to that account; its `toString` and the message show neither.
  static void _throwIfPhoneNumberInUse(Map<String, Object?> response) {
    final Object? proof = response['temporaryProof'];
    if (proof is String && proof.isNotEmpty) {
      throw FirebaseAuthException(
        code: AuthErrorCode.credentialAlreadyInUse,
        message:
            'This phone number is already associated with a different user account.',
        credential: phoneCredentialFromProof(response),
      );
    }
  }

  // ---- multi-factor authentication ----

  /// Starts enrolling an authenticator app (TOTP) as a second factor of the signed-in user
  /// (`v2/accounts/mfaEnrollment:start`; FlutterFire's `multiFactor.getSession()` and
  /// `TotpMultiFactorGenerator.generateSecret`). The user adds the returned [TotpSecret] to the app
  /// ([TotpSecret.otpauthUri] as a QR code, or [TotpSecret.secretKey] by hand), and [finalizeTotpEnrollment] finishes
  /// with a code of the app before [TotpSecret.enrollmentCompletionDeadline].
  ///
  /// The project must use Identity Platform with TOTP enabled, and the account needs a verified email address.
  /// Throws a [FirebaseAuthException] with the code `null-user`, `unverified-email`, `requires-recent-login`,
  /// `operation-not-allowed` (TOTP is not enabled), `maximum-second-factor-count-exceeded`, `unsupported-first-factor`
  /// (for example an anonymous user), ..., and `internal-error` when the answer has no secret.
  ///
  /// ```dart
  /// final TotpSecret secret = await auth.startTotpEnrollment();
  /// final Uri uri = secret.otpauthUri(issuer: 'My App'); // show it as a QR code
  /// await auth.finalizeTotpEnrollment(secret, code: codeFromTheApp, displayName: 'Phone');
  /// print(auth.currentUser?.enrolledFactors); // [MultiFactorInfo(totp, ...)]
  /// ```
  Future<TotpSecret> startTotpEnrollment() =>
      _forUser((String idToken, int generation) async {
        final String? email = _session?.user.email;
        final Map<String, Object?> response = await _multiFactor
            .startTotpEnrollment(idToken: idToken, tenantId: tenantId);
        final TotpSecret? secret = TotpSecret.fromResponse(
          response['totpSessionInfo'],
          accountName: email,
        );
        if (secret == null) {
          throw const FirebaseAuthException(
            code: 'internal-error',
            message: 'The authentication service did not return a TOTP secret.',
          );
        }
        return secret;
      });

  /// Finishes the enrolment of [secret] with [code], a code the authenticator app shows for it
  /// (`v2/accounts/mfaEnrollment:finalize`; FlutterFire's `multiFactor.enroll` with
  /// `TotpMultiFactorGenerator.getAssertionForEnrollment`). [displayName] names the factor for the user; the
  /// backend refuses an enrolment without one (`missing-display-name`).
  ///
  /// The session continues with the new tokens the backend returns, and the account is read again: [userChanges]
  /// and [idTokenChanges] emit, the session is stored, and [AuthUser.enrolledFactors] lists the new factor. From
  /// now on every sign-in of the account throws a [FirebaseAuthMultiFactorException].
  ///
  /// Throws `null-user`, `invalid-verification-code` (or another code the backend gives for a wrong code),
  /// `requires-recent-login`, `second-factor-already-in-use`, ...; and `argument-error` for a [secret] without the
  /// session information of the backend.
  Future<void> finalizeTotpEnrollment(
    TotpSecret secret, {
    required String code,
    required String displayName,
  }) => _forUser((String idToken, int generation) async {
    final String? sessionInfo = totpSessionInfoOf(secret);
    if (sessionInfo == null) {
      throw const FirebaseAuthException(
        code: 'argument-error',
        message:
            'The TOTP secret has no session information: start the enrolment with startTotpEnrollment.',
      );
    }
    final Map<String, Object?> response = await _multiFactor
        .finalizeTotpEnrollment(
          idToken: idToken,
          sessionInfo: sessionInfo,
          code: code,
          displayName: displayName,
          tenantId: tenantId,
        );
    await _updateSession(response, generation);
    await _reloadAfterChange(generation);
  });

  /// Starts enrolling [phoneNumber] as an SMS second factor of the signed-in user
  /// (`v2/accounts/mfaEnrollment:start` with `phoneEnrollmentInfo`; `verifyPhoneNumber` with the
  /// session of `multiFactor.getSession` in the iOS SDK): sends an SMS code to the number and
  /// returns the verification id. Pair it with the code the user types in
  /// ([PhoneAuthProvider.credential]) and finish with [finalizePhoneEnrollment].
  ///
  /// [phoneNumber] is in E.164 form; [appVerification] is the proof of [verifyPhoneNumber]. The
  /// project must use Identity Platform with SMS multi-factor authentication enabled, and the
  /// account needs a verified email address.
  ///
  /// Throws `null-user`, `missing-phone-number` (empty, before anything is sent),
  /// `invalid-phone-number`, `unverified-email`, `requires-recent-login`, `operation-not-allowed`,
  /// `second-factor-already-in-use`, `maximum-second-factor-count-exceeded`,
  /// `unsupported-first-factor`, `invalid-app-credential`, `quota-exceeded`, ... No error holds the
  /// phone number, the verification id or the reCAPTCHA token.
  ///
  /// ```dart
  /// final String verificationId = await auth.startPhoneEnrollment(
  ///   '+15555550100',
  ///   appVerification: AppVerification.recaptchaV2Loopback(),
  /// );
  /// await auth.finalizePhoneEnrollment(
  ///   PhoneAuthProvider.credential(
  ///     verificationId: verificationId,
  ///     verificationCode: codeFromYourTextField,
  ///   ),
  ///   displayName: 'Work phone',
  /// );
  /// ```
  Future<String> startPhoneEnrollment(
    String phoneNumber, {
    required AppVerification appVerification,
  }) async {
    _checkNotDisposed();
    _requireSession();
    _requirePhoneNumber(phoneNumber);
    final List<String?> secrets = <String?>[phoneNumber];
    // The proof is asked for once, before _forUser, which runs its operation again after a
    // rejected ID token: a second run must not show the reCAPTCHA again.
    return _withoutPhoneSecrets(secrets, () async {
      final Map<String, Object?> proof = await _proofOf(
        appVerification,
        RecaptchaAction.mfaSmsEnrollment,
        secrets,
      );
      return _forUser((String idToken, int generation) async {
        final Map<String, Object?> response = await _multiFactor
            .startPhoneEnrollment(
              idToken: idToken,
              phoneNumber: phoneNumber,
              appVerification: proof,
              tenantId: tenantId,
            );
        final String verificationId = _sessionInfoOf(
          _fieldOf(response['phoneSessionInfo'], 'sessionInfo'),
        );
        secrets.add(verificationId);
        return verificationId;
      });
    });
  }

  /// Finishes the SMS enrolment that [startPhoneEnrollment] started, with [credential]: its
  /// verification id and the code of the SMS (`v2/accounts/mfaEnrollment:finalize` with
  /// `phoneVerificationInfo`; `multiFactor.enroll` with `PhoneMultiFactorGenerator.assertion` in
  /// the iOS SDK). [displayName] names the factor for the user; it may be left out for an SMS
  /// factor.
  ///
  /// The session continues with the new tokens the backend returns, and the account is read again,
  /// like after [finalizeTotpEnrollment]: [AuthUser.enrolledFactors] lists the new factor, and from
  /// now on every sign-in of the account throws a [FirebaseAuthMultiFactorException].
  ///
  /// Throws `null-user`, `missing-verification-id` and `missing-verification-code` (an empty part,
  /// before anything is sent), `invalid-verification-code`, `code-expired`,
  /// `invalid-verification-id`, `requires-recent-login`, `second-factor-already-in-use`, ...
  Future<void> finalizePhoneEnrollment(
    PhoneAuthCredential credential, {
    String? displayName,
  }) => _withoutSecretsOf(
    credential,
    () => _forUser((String idToken, int generation) async {
      final (String verificationId, String code) = _checkPhoneCredential(
        credential,
      );
      final Map<String, Object?> response = await _multiFactor
          .finalizePhoneEnrollment(
            idToken: idToken,
            sessionInfo: verificationId,
            code: code,
            displayName: displayName,
            tenantId: tenantId,
          );
      await _updateSession(response, generation);
      await _reloadAfterChange(generation);
    }),
  );

  /// Removes the second factor [uid] (a [MultiFactorInfo.uid] of [AuthUser.enrolledFactors]) from the account of the
  /// signed-in user (`v2/accounts/mfaEnrollment:withdraw`; FlutterFire's `multiFactor.unenroll`). Works for SMS
  /// factors too.
  ///
  /// The session continues with the new tokens the backend returns, and the account is read again, like after
  /// [finalizeTotpEnrollment].
  ///
  /// Throws `null-user`, `multi-factor-info-not-found` (no such factor), `requires-recent-login`, ...
  Future<void> unenrollMultiFactor(String uid) =>
      _forUser((String idToken, int generation) async {
        final Map<String, Object?> response = await _multiFactor.withdraw(
          idToken: idToken,
          enrollmentId: uid,
          tenantId: tenantId,
        );
        await _updateSession(response, generation);
        await _reloadAfterChange(generation);
      });

  /// The request that signs in with [credential] (`_getIdTokenResponse` of the JS SDK's credentials), links it to
  /// the user of [userIdToken] (`_linkToIdToken`), or reauthenticates with it (`_getReauthenticationResolver`).
  _CredentialRequest _requestFor(
    AuthCredential credential, {
    String? userIdToken,
    bool reauthenticate = false,
  }) {
    switch (credential) {
      case EmailAuthCredential(
        signInMethod: EmailAuthProvider.EMAIL_PASSWORD_SIGN_IN_METHOD,
        :final String email,
        :final String password?,
      ):
        if (userIdToken != null) {
          // linkEmailPassword: accounts:signUp with the ID token, without the tenant.
          return _CredentialRequest('accounts:signUp', <String, Object?>{
            'idToken': userIdToken,
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }, tenant: false);
        }
        return _CredentialRequest(
          'accounts:signInWithPassword',
          <String, Object?>{
            'email': email,
            'password': password,
            'returnSecureToken': true,
          },
        );
      case EmailAuthCredential(
        signInMethod: EmailAuthProvider.EMAIL_LINK_SIGN_IN_METHOD,
        :final String email,
        :final String emailLink?,
      ):
        return _CredentialRequest(
          'accounts:signInWithEmailLink',
          <String, Object?>{
            'idToken': ?userIdToken,
            'email': email,
            'oobCode': _parseEmailLink(emailLink).code,
          },
        );
      case OAuthCredential(
        :final String providerId,
        :final String? idToken,
        :final String? accessToken,
        :final String? secret,
        :final String? rawNonce,
        :final String? pendingToken,
      ):
        // OAuthCredential.buildRequest of the JS SDK: the provider's tokens in a form-encoded postBody, for the
        // requestUri http://localhost; a pending token of the backend instead when there is one.
        final Map<String, Object?> body = <String, Object?>{
          'requestUri': 'http://localhost',
          'returnSecureToken': true,
        };
        if (pendingToken != null && pendingToken.isNotEmpty) {
          body['pendingToken'] = pendingToken;
        } else {
          body['postBody'] = <String>[
            if (idToken != null && idToken.isNotEmpty)
              'id_token=${Uri.encodeComponent(idToken)}',
            if (accessToken != null && accessToken.isNotEmpty)
              'access_token=${Uri.encodeComponent(accessToken)}',
            if (secret != null && secret.isNotEmpty)
              'oauth_token_secret=${Uri.encodeComponent(secret)}',
            'providerId=${Uri.encodeComponent(providerId)}',
            if (rawNonce != null && rawNonce.isNotEmpty)
              'nonce=${Uri.encodeComponent(rawNonce)}',
          ].join('&');
        }
        return _CredentialRequest('accounts:signInWithIdp', <String, Object?>{
          ...body,
          'idToken': ?userIdToken,
          if (reauthenticate) 'autoCreate': false,
        });
      case PhoneAuthCredential():
        return _phoneRequest(
          credential,
          userIdToken: userIdToken,
          reauthenticate: reauthenticate,
        );
      default:
        throw ArgumentError.value(
          credential,
          'credential',
          'Not a credential of this package',
        );
    }
  }

  /// `accounts:signInWithPhoneNumber` with the verification id and code of [credential], or its
  /// temporary proof and number (`signInWithPhoneNumber`, `linkWithPhoneNumber` with the ID token,
  /// and `verifyPhoneNumberForExisting` with the operation `REAUTH` of the JS SDK). Empty values
  /// fail before anything is sent, as in the iOS SDK.
  static _CredentialRequest _phoneRequest(
    PhoneAuthCredential credential, {
    required String? userIdToken,
    required bool reauthenticate,
  }) {
    final String? proof = credential.temporaryProof;
    final String? number = credential.phoneNumber;
    final Map<String, Object?> fields;
    if (proof != null && number != null) {
      fields = <String, Object?>{
        'temporaryProof': proof,
        'phoneNumber': number,
      };
    } else {
      final (String verificationId, String code) = _checkPhoneCredential(
        credential,
      );
      fields = <String, Object?>{'sessionInfo': verificationId, 'code': code};
    }
    return _CredentialRequest(
      'accounts:signInWithPhoneNumber',
      <String, Object?>{
        'idToken': ?userIdToken,
        ...fields,
        if (reauthenticate) 'operation': 'REAUTH',
      },
    );
  }

  /// The verification id and the code of [credential]; throws `missing-verification-id` or
  /// `missing-verification-code` when one is empty or missing (a temporary proof has neither).
  static (String, String) _checkPhoneCredential(
    PhoneAuthCredential credential,
  ) {
    final String? verificationId = credential.verificationId;
    final String? code = credential.verificationCode;
    if (verificationId == null || verificationId.isEmpty) {
      throw const FirebaseAuthException(
        code: AuthErrorCode.missingVerificationId,
        message:
            'The phone auth credential was created with an empty verification ID.',
      );
    }
    if (code == null || code.isEmpty) {
      throw const FirebaseAuthException(
        code: AuthErrorCode.missingVerificationCode,
        message:
            'The phone auth credential was created with an empty SMS verification code.',
      );
    }
    return (verificationId, code);
  }

  /// The parts of an email link, or `argument-error` (`EmailAuthProvider.credentialWithLink` of the JS SDK).
  static ActionCodeURL _parseEmailLink(String emailLink) {
    final ActionCodeURL? url = ActionCodeURL.parseLink(emailLink);
    if (url == null) {
      throw const FirebaseAuthException(
        code: 'argument-error',
        message: 'The email link is not the link of an action email.',
      );
    }
    return url;
  }

  /// The result of a sign-in, a link or a reauthentication [response] for [user].
  UserCredential _result(
    Map<String, Object?> response,
    AuthUser user,
    OperationType operationType,
  ) {
    final UserCredential result = UserCredential(
      user,
      operationType: operationType,
      additionalUserInfo: additionalUserInfoOf(response),
      credential: credentialFromResponse(response),
    );
    final _Session? session = _session;
    if (session != null && identical(session.user, user)) {
      _sessionOfUser[result] = (apiKey, session);
    }
    return result;
  }

  /// Reads the data of the signed-in user from the backend again (`reload`): email address, verification, display
  /// name and photo. [userChanges] emits when something changed. Signs out when the account is disabled or the
  /// session ended.
  ///
  /// Throws `null-user`, `user-disabled`, `user-token-expired`, ...
  Future<void> reload() =>
      _forUser((String idToken, int generation) => _reload(generation));

  /// Returns the ID token of the signed-in user, refreshing it when it expires within five minutes or when
  /// [forceRefresh] is set.
  ///
  /// Throws a [FirebaseNoSignedInUserException] when nobody is signed in (Firestore then sends the request without
  /// a token), and a [FirebaseAuthException] when the refresh fails. When the refresh fails because the
  /// session is no longer valid (the account was deleted or disabled, the refresh token revoked), the user is
  /// signed out. Throws whatever the `write` of the storage throws when a new refresh token cannot be stored; the
  /// new token is in use all the same, and the write is tried again at the next refresh.
  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    final _Session? session = _session;
    if (session == null) {
      throw FirebaseNoSignedInUserException('No user is signed in.');
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

  /// Stops the timers and closes the streams. The session stays in the storage, so a new instance can [restore]
  /// it. The HTTP client is closed unless it was passed to the constructor.
  ///
  /// Afterwards the sign-in and account operations throw a [StateError]. The instance stays the token provider of
  /// its app, and the Firestore instances that use it keep calling [getAccessToken]: terminate them (or delete the
  /// app) first.
  Future<void> dispose() async {
    _disposed = true;
    _cancelProactiveRefresh();
    await _tokenChanges.close();
    await _userChanges.close();
    await _authStateChanges.close();
    await _idTokenChanges.close();
    if (_ownsHttp) {
      _http.close();
    }
  }

  // ---- implementation ----

  static const FirebaseAuthException _userMismatch = FirebaseAuthException(
    code: 'user-mismatch',
    message:
        'The supplied credentials do not correspond to the signed-in user.',
  );

  _Session _requireSession() {
    final _Session? session = _session;
    if (session == null) {
      throw const FirebaseAuthException(
        code: 'null-user',
        message: 'No user is signed in.',
      );
    }
    return session;
  }

  /// Runs [operation] with the ID token of the signed-in user. Like `_logoutIfInvalidated` of the JS SDK, the user
  /// is signed out when the backend rejects the request with HTTP 400 because the account is disabled.
  ///
  /// When it rejects the ID token (`TOKEN_EXPIRED`, `INVALID_ID_TOKEN`), the session may still be valid, so the
  /// token is refreshed first, like `signOutIfSessionIsInvalid` of the iOS SDK: the refresh signs the user out when
  /// it fails because the session ended, and otherwise [operation] runs once more with the new token.
  Future<T> _forUser<T>(
    Future<T> Function(String idToken, int generation) operation,
  ) async {
    _checkNotDisposed();
    _requireSession();
    final int generation = _generation;
    final String idToken = await _idTokenOf(generation);
    try {
      return await operation(idToken, generation);
    } on _ChangeDone catch (done, stackTrace) {
      Error.throwWithStackTrace(done.error, stackTrace);
    } on FirebaseAuthException catch (e) {
      if (e.httpStatus != 400 ||
          generation != _generation ||
          _session == null) {
        rethrow;
      }
      if (e.code == 'user-disabled') {
        await _clearSession();
        rethrow;
      }
      if (e.code != 'user-token-expired' && e.code != 'invalid-user-token') {
        rethrow;
      }
      final String? refreshed = await _refreshAfterRejection(
        idToken,
        generation,
      );
      if (refreshed == null) {
        rethrow;
      }
      return operation(refreshed, generation);
    }
  }

  /// Refreshes the ID token after the backend rejected [rejected], to check whether the session of [generation]
  /// is still valid. Returns the new token, or null when the session changed, the token was replaced since
  /// [rejected] was sent, or the refresh failed (a refresh that fails because the session ended signs out).
  Future<String?> _refreshAfterRejection(
    String rejected,
    int generation,
  ) async {
    if (_session?.idToken != rejected) {
      return null;
    }
    try {
      final String? refreshed = await _refresh();
      return generation == _generation ? refreshed : null;
    } on FirebaseAuthException catch (e) {
      Log.w(
        'FirebaseUserAuth',
        'The ID token was rejected and the refresh that checks the session failed: ${e.code}',
      );
      return null;
    }
  }

  /// The ID token of the session of [generation]; throws `cancelled` when another session took its place, so that
  /// a request meant for the previous user is never sent with the token of the next one.
  Future<String> _idTokenOf(int generation) async {
    final String idToken = (await getAccessToken(forceRefresh: false)).token;
    if (generation != _generation) {
      throw _overtaken;
    }
    return idToken;
  }

  Future<void> _updateEmailOrPassword(Map<String, Object?> fields) =>
      _forUser((String idToken, int generation) async {
        final Map<String, Object?> response = await _send(
          _identityToolkit('accounts:update'),
          json: <String, Object?>{
            'idToken': idToken,
            ...fields,
            'returnSecureToken': true,
          },
        );
        await _updateSession(response, generation);
        await _reloadAfterChange(generation);
      });

  /// Takes the tokens of [response] (when it has them) and [user] (when given) into the session of [generation],
  /// like `_updateTokensIfNecessary` of the JS SDK, and tells the listeners.
  Future<void> _updateSession(
    Map<String, Object?> response,
    int generation, {
    AuthUser? user,
  }) async {
    final _Session? session = _session;
    if (session == null || generation != _generation) {
      return;
    }
    final Object? idToken = response['idToken'];
    final Object? refreshToken = response['refreshToken'];
    final AuthUser newUser = user ?? session.user;
    final _Session updated = idToken is String
        ? _Session(
            newUser,
            refreshToken is String ? refreshToken : session.refreshToken,
            idToken,
            _expiry(GetTokenResult(idToken), response['expiresIn']),
          )
        : _Session(
            newUser,
            session.refreshToken,
            session.idToken,
            session.expiry,
          );
    await _setSession(
      updated,
      persist:
          updated.refreshToken != session.refreshToken ||
          newUser != session.user,
    );
    if (generation != _generation) {
      return;
    }
    if (newUser != session.user && !_userChanges.isClosed) {
      _userChanges.add(newUser);
    }
    if (idToken is String) {
      _emitToken(idToken);
    }
  }

  /// Reads the account of the signed-in user (`accounts:lookup`) and takes it into the session of [generation].
  /// [_reload] after a request of [_forUser]'s operation changed the account (the backend may have revoked the
  /// ID token it was sent with, like `_updateTokensIfNecessary` and `reload` after `withdrawMfa` in the JS SDK's
  /// `MultiFactorUser.unenroll`). A rejected token is refreshed and the account read once more here; whatever
  /// fails then is thrown as a [_ChangeDone], so that [_forUser] rethrows it instead of sending the change again.
  Future<void> _reloadAfterChange(int generation) async {
    try {
      await _reload(generation);
    } on FirebaseAuthException catch (e) {
      final String? rejected = _session?.idToken;
      final bool tokenRejected =
          e.httpStatus == 400 &&
          (e.code == 'user-token-expired' || e.code == 'invalid-user-token');
      if (e.httpStatus == 400 &&
          e.code == 'user-disabled' &&
          generation == _generation) {
        await _clearSession();
      }
      if (!tokenRejected || rejected == null || generation != _generation) {
        throw _ChangeDone(e);
      }
      final String? refreshed = await _refreshAfterRejection(
        rejected,
        generation,
      );
      if (refreshed == null) {
        throw _ChangeDone(e);
      }
      try {
        await _reload(generation);
      } on FirebaseAuthException catch (again) {
        throw _ChangeDone(again);
      }
    }
  }

  Future<void> _reload(int generation) async {
    if (_session == null || generation != _generation) {
      return;
    }
    final String idToken = (await getAccessToken(forceRefresh: false)).token;
    if (generation != _generation) {
      return;
    }
    final Map<String, Object?> account = await _lookup(idToken);
    final AuthUser? user = _session?.user;
    if (user == null || generation != _generation) {
      return;
    }
    await _updateSession(
      const <String, Object?>{},
      generation,
      user: userFromAccount(account, user),
    );
  }

  /// The account of [idToken] (`accounts:lookup`).
  Future<Map<String, Object?>> _lookup(String idToken) async {
    final Map<String, Object?> response = await _send(
      _identityToolkit('accounts:lookup'),
      json: <String, Object?>{'idToken': idToken},
    );
    final Object? users = response['users'];
    final Object? account = users is List && users.isNotEmpty
        ? users.first
        : null;
    if (account is! Map<String, Object?>) {
      // What the JS SDK does when the backend has no such user.
      throw const FirebaseAuthException(
        code: 'internal-error',
        message: 'The authentication service returned no account.',
      );
    }
    return account;
  }

  bool _isFresh(_Session session) {
    final DateTime? expiry = session.expiry;
    return expiry != null && _clock().add(refreshBefore).isBefore(expiry);
  }

  Uri _identityToolkit(
    String method, {
    String version = 'v1',
    Map<String, String> query = const <String, String>{},
  }) {
    final String? emulator = _emulatorOrigin;
    final Map<String, String> parameters = <String, String>{
      ...query,
      'key': apiKey,
    };
    if (emulator == null) {
      return Uri.https(
        'identitytoolkit.googleapis.com',
        '/$version/$method',
        parameters,
      );
    }
    final String queryString = parameters.entries
        .map(
          (MapEntry<String, String> e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return Uri.parse(
      '$emulator/identitytoolkit.googleapis.com/$version/$method?$queryString',
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

  /// The headers the JS SDK sends with every request (`_getAdditionalHeaders`): the client version, the app id and
  /// the App Check token. A failed App Check request is logged and the request goes out anyway, with the
  /// placeholder token the provider returned (without the header when it threw), like in the JS SDK.
  Future<Map<String, String>> _additionalHeaders() async {
    final Map<String, String> headers = <String, String>{
      'X-Client-Version': clientVersion,
    };
    final String? id = appId;
    if (id != null && id.isNotEmpty) {
      headers['X-Firebase-gmpid'] = id;
    }
    final AppCheckTokenProvider? appCheck = _appCheck;
    if (appCheck != null) {
      try {
        final AppCheckTokenResult result = await appCheck.getToken(
          forceRefresh: false,
        );
        if (result.error != null) {
          Log.w(
            'FirebaseUserAuth',
            'Error while retrieving App Check token: ${result.error}',
          );
        }
        if (result.token.isNotEmpty) {
          headers['X-Firebase-AppCheck'] = result.token;
        }
      } on Object catch (e) {
        Log.w('FirebaseUserAuth', 'Error while retrieving App Check token: $e');
      }
    }
    return headers;
  }

  /// Sends a request and returns the decoded JSON object of the answer, or throws.
  ///
  /// With [tenant], the [tenantId] goes into the [json] body unless it names one (`_addTidIfNecessary` of the JS
  /// SDK). The [languageCode] goes into `X-Firebase-Locale` of every JSON request (the JS SDK sends it from
  /// `_performApiRequest`, which the token refresh does not use).
  Future<Map<String, Object?>> _send(
    Uri url, {
    Map<String, Object?>? json,
    Map<String, String>? form,
    bool tenant = false,
    bool get = false,
  }) async {
    final String? tenantId = this.tenantId;
    if (tenant &&
        json != null &&
        tenantId != null &&
        json['tenantId'] == null) {
      json = <String, Object?>{...json, 'tenantId': tenantId};
    }
    final Map<String, String> headers = await _additionalHeaders();
    final String? locale = languageCode;
    if ((json != null || get) && locale != null && locale.isNotEmpty) {
      headers['X-Firebase-Locale'] = locale;
    }
    final http.Response response;
    try {
      final Future<http.Response> request = get
          ? _http.get(
              url,
              headers: <String, String>{
                ...headers,
                'Content-Type': 'application/json',
              },
            )
          : json != null
          ? _http.post(
              url,
              headers: <String, String>{
                ...headers,
                'Content-Type': 'application/json',
              },
              body: jsonEncode(json),
            )
          : _http.post(
              url,
              headers: <String, String>{
                ...headers,
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: form,
            );
      response = await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw FirebaseAuthException(
        code: 'network-request-failed',
        message:
            'The request to the authentication service timed out after '
            '${_requestTimeout.inMilliseconds} ms.',
      );
    } on Object catch (_) {
      // The error of the HTTP client may quote the URL, which holds the API key.
      throw const FirebaseAuthException(
        code: 'network-request-failed',
        message:
            'The request to the authentication service failed (network error).',
      );
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    // Like _performFetchWithErrorHandling of the JS SDK: `needConfirmation` first, then an answer is a success
    // only when it is OK and has no `errorMessage` (signInWithIdp reports some errors with HTTP 200 and an
    // `errorMessage` next to the data of the account).
    final bool ok = response.statusCode == 200;
    if (body is Map<String, Object?>) {
      if (body.containsKey('needConfirmation')) {
        throw FirebaseAuthException.needConfirmation(
          body,
          httpStatus: response.statusCode,
        );
      }
      if (ok && !body.containsKey('errorMessage')) {
        return body;
      }
    }
    throw exceptionFromJsonError(response.statusCode, body);
  }

  Future<UserCredential> _signIn(
    String method,
    Map<String, Object?> request,
  ) async {
    _checkNotDisposed();
    final int attempt = ++_signInAttempt;
    final Map<String, Object?> response = await _send(
      _identityToolkit(method),
      json: request,
      tenant: true,
    );
    return _completeSignIn(response, attempt);
  }

  static const FirebaseAuthException _overtaken = FirebaseAuthException(
    code: 'cancelled',
    message: 'The operation was overtaken by another sign-in or a sign-out.',
  );

  /// Makes the user of a sign-in [response] the current user, like `UserCredentialImpl._fromIdTokenResponse` and
  /// `_updateCurrentUser` of the JS SDK: the account is read (`accounts:lookup`) first, so that the user is
  /// complete when it is announced.
  Future<UserCredential> _completeSignIn(
    Map<String, Object?> response,
    int attempt,
  ) async {
    // Finishing with a second factor is a sign-in of its own: it overtakes the sign-ins started before it, and
    // is overtaken by those started while its request is in flight.
    _throwIfSecondFactorRequired(
      response,
      finish: (Future<Map<String, Object?>> finalized) async {
        final int attempt = ++_signInAttempt;
        return _completeSignIn(await finalized, attempt);
      },
    );
    final Object? idToken = response['idToken'];
    final Object? refreshToken = response['refreshToken'];
    if (idToken is! String || refreshToken is! String) {
      throw const FirebaseAuthException(
        code: 'internal-error',
        message: 'The authentication service did not return tokens.',
      );
    }
    if (attempt != _signInAttempt || _disposed) {
      // Another sign-in or a sign-out started meanwhile and wins.
      throw _overtaken;
    }
    final GetTokenResult token = GetTokenResult(idToken);
    final Object? localId = response['localId'];
    final Object? uid = localId is String
        ? localId
        : token.claims['user_id'] ?? token.claims['sub'];
    if (uid is! String) {
      throw const FirebaseAuthException(
        code: 'internal-error',
        message:
            'The authentication service did not return the id of the user.',
      );
    }
    final Map<String, Object?> account = await _lookup(idToken);
    if (attempt != _signInAttempt || _disposed) {
      throw _overtaken;
    }
    AuthUser user = userFromAccount(
      account,
      AuthUser(uid: uid, isAnonymous: token.signInProvider == 'anonymous'),
    );
    if (user.tenantId == null) {
      final Object? firebase = token.claims['firebase'];
      final Object? tenant = firebase is Map ? firebase['tenant'] : null;
      if (tenant is String && tenant.isNotEmpty) {
        user = copyUser(user, tenantId: tenant);
      }
    }
    _checkTenant(user);
    await _runBeforeStateCallbacks(user);
    if (attempt != _signInAttempt || _disposed) {
      throw _overtaken;
    }
    final _Session session = _Session(
      user,
      refreshToken,
      idToken,
      _expiry(token, response['expiresIn']),
    );
    final int generation = await _installSession(session);
    if (generation != _generation) {
      // Signed out (or the session ended) while the session was stored.
      throw _overtaken;
    }
    if (!_userChanges.isClosed) {
      _userChanges.add(session.user);
    }
    _emitToken(idToken);
    _notifyAuthState();
    await _letListenersReact();
    return _result(response, session.user, OperationType.signIn);
  }

  /// Like `_performSignInRequest` of the JS SDK: a sign-in answer with an `mfaPendingCredential` (and no tokens)
  /// means that the account has a second factor. [finish] completes the operation with the answer of
  /// `mfaSignIn:finalize` merged into [response] (`MultiFactorResolverImpl._fromError` of the JS SDK), which it gets
  /// while the request is in flight; without it the exception has no resolver.
  void _throwIfSecondFactorRequired(
    Map<String, Object?> response, {
    Future<UserCredential> Function(Future<Map<String, Object?>> response)?
    finish,
  }) {
    final FirebaseAuthMultiFactorException? error =
        FirebaseAuthMultiFactorException.fromResponse(
          response,
          httpStatus: 200,
        );
    if (error == null) {
      return;
    }
    if (finish == null) {
      throw error;
    }
    throw FirebaseAuthMultiFactorException(
      pendingCredential: error.pendingCredential,
      hints: error.hints,
      message: error.message,
      httpStatus: error.httpStatus,
      resolver: _resolverFor(error, response, finish),
    );
  }

  /// The resolver of the second-factor challenge [error] of the sign-in answer [response]: each way
  /// to finish calls `mfaSignIn:finalize` and hands its answer, merged into [response]
  /// (`MultiFactorResolverImpl._fromError` of the JS SDK), to [finish].
  MultiFactorResolver _resolverFor(
    FirebaseAuthMultiFactorException error,
    Map<String, Object?> response,
    Future<UserCredential> Function(Future<Map<String, Object?>> response)
    finish,
  ) {
    // The pending credential belongs to the tenant of the first factor.
    final String? tenant = tenantId;
    final String pending = error.pendingCredential;
    Future<UserCredential> finishWith(Future<Map<String, Object?>> finalized) =>
        finish(
          finalized.then(
            (Map<String, Object?> answer) => <String, Object?>{
              for (final MapEntry<String, Object?> entry in response.entries)
                if (entry.key != 'mfaPendingCredential' &&
                    entry.key != 'mfaInfo')
                  entry.key: entry.value,
              'idToken': answer['idToken'],
              'refreshToken': answer['refreshToken'],
            },
          ),
        );
    return createMultiFactorResolver(
      error.hints,
      resolveTotp: (String enrollmentId, String code) {
        _checkNotDisposed();
        return finishWith(
          _multiFactor.finalizeTotpSignIn(
            pendingCredential: pending,
            enrollmentId: enrollmentId,
            code: code,
            tenantId: tenant,
          ),
        );
      },
      startPhone: (String enrollmentId, AppVerification appVerification) =>
          _startPhoneSignIn(pending, enrollmentId, appVerification, tenant),
      resolvePhone: (PhoneAuthCredential credential) {
        _checkNotDisposed();
        final (String verificationId, String code) = _checkPhoneCredential(
          credential,
        );
        return _withoutSecretsOf(
          credential,
          () => finishWith(
            _multiFactor.finalizePhoneSignIn(
              pendingCredential: pending,
              sessionInfo: verificationId,
              code: code,
              tenantId: tenant,
            ),
          ),
        );
      },
    );
  }

  /// `mfaSignIn:start` for the SMS factor [enrollmentId] of the pending sign-in [pending]: sends
  /// the SMS and returns the verification id.
  Future<String> _startPhoneSignIn(
    String pending,
    String enrollmentId,
    AppVerification appVerification,
    String? tenant,
  ) async {
    _checkNotDisposed();
    final List<String?> secrets = <String?>[];
    return _withoutPhoneSecrets(secrets, () async {
      final Map<String, Object?> proof = await _proofOf(
        appVerification,
        RecaptchaAction.mfaSmsSignIn,
        secrets,
      );
      final Map<String, Object?> response = await _multiFactor.startPhoneSignIn(
        pendingCredential: pending,
        enrollmentId: enrollmentId,
        appVerification: proof,
        tenantId: tenant,
      );
      final String verificationId = _sessionInfoOf(
        _fieldOf(response['phoneResponseInfo'], 'sessionInfo'),
      );
      secrets.add(verificationId);
      return verificationId;
    });
  }

  /// The value of [key] in [object] when it is a JSON object, else null.
  static Object? _fieldOf(Object? object, String key) =>
      object is Map<String, Object?> ? object[key] : null;

  /// The standard lifetime of an ID token. It replaces a lifetime from the backend that is out of range.
  static const Duration _standardTokenLifetime = Duration(hours: 1);

  /// The longest accepted token lifetime, and the longest delay of the proactive refresh (`AuthTokenLifetime` of
  /// the iOS SDK).
  static const Duration _maximumTokenLifetime = Duration(hours: 24);

  /// The expiry of an ID token: its `exp` claim, or now plus the `expiresIn` seconds of the response. Like
  /// `AuthTokenLifetime` of the iOS SDK, a lifetime outside of (0, 24 h], missing or not a number is one hour,
  /// and an `exp` more than 24 h ahead is not trusted.
  DateTime _expiry(GetTokenResult token, Object? expiresIn) {
    final DateTime now = _clock();
    if (token.claims['exp'] is num &&
        !token.expirationTimestamp.isAfter(now.add(_maximumTokenLifetime))) {
      return token.expirationTimestamp;
    }
    final double? seconds = double.tryParse('$expiresIn');
    if (seconds == null ||
        !seconds.isFinite ||
        seconds <= 0 ||
        seconds > _maximumTokenLifetime.inSeconds) {
      return now.add(_standardTokenLifetime);
    }
    return now.add(Duration(milliseconds: (seconds * 1000).round()));
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
    } on FirebaseAuthException catch (e) {
      if (e.invalidatesSession && generation == _generation) {
        await _clearSession();
      }
      rethrow;
    }
    final Object? idToken = response['id_token'];
    final Object? refreshToken = response['refresh_token'];
    if (idToken is! String) {
      throw const FirebaseAuthException(
        code: 'internal-error',
        message: 'The token service did not return an ID token.',
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
    if (generation != _generation) {
      return null;
    }
    _refreshFailures = 0;
    _emitToken(idToken);
    return idToken;
  }

  /// Installs the [session] of a new sign-in (or of [updateCurrentUser]) and stores it. The session count changes
  /// before the session is installed, so that no operation of the previous session writes into this one. Returns
  /// the count of this session.
  Future<int> _installSession(_Session session) async {
    final int generation = ++_generation;
    await _setSession(session, persist: true);
    return generation;
  }

  /// Makes [session] the current one and, when [persist] is set or an earlier write failed, stores it. The session
  /// changes in memory first, like `directlySetCurrentUser` of the JS SDK: the backend may already have replaced
  /// the refresh token, so the old session is not kept for a failed write. The error of the write is rethrown and
  /// the next session change (a token refresh, a reload, a sign-in) writes again.
  Future<void> _setSession(_Session session, {required bool persist}) async {
    _session = session;
    _sessionOfUser[session.user] = (apiKey, session);
    try {
      if (persist || _unsaved) {
        _unsaved = true;
        await _storage.write(
          _storageKey,
          encodeSession(session.user, session.refreshToken),
        );
        _unsaved = false;
      }
    } finally {
      if (_tokenChanges.hasListener) {
        _scheduleProactiveRefresh();
      }
    }
  }

  Future<void> _clearSession() async {
    _generation++;
    _session = null;
    _cancelProactiveRefresh();
    try {
      if (!_disposed) {
        // After dispose the stored session may belong to a new instance that restored it.
        _unsaved = true;
        await _storage.write(_storageKey, null);
      }
      _unsaved = false;
    } finally {
      // Signed out in memory even when the write failed, like `directlySetCurrentUser` of the JS SDK.
      if (!_userChanges.isClosed) {
        _userChanges.add(null);
      }
      _emitToken('');
      _notifyAuthState();
      await _letListenersReact();
    }
  }

  /// Tells the token listeners (Firestore) and [idTokenChanges] about a new ID token of the current session, or an
  /// empty one after a sign-out.
  void _emitToken(String idToken) {
    if (!_tokenChanges.isClosed) {
      _tokenChanges.add(AuthTokenChange(idToken));
    }
    if (!_idTokenChanges.isClosed) {
      _idTokenChanges.add(_session?.user);
    }
  }

  /// [authStateChanges] emits when the uid differs from the one it last emitted (`notifyAuthListeners` of the JS
  /// SDK).
  void _notifyAuthState() {
    final String? uid = _session?.user.uid;
    if (uid == _lastNotifiedUid) {
      return;
    }
    _lastNotifiedUid = uid;
    if (!_authStateChanges.isClosed) {
      _authStateChanges.add(_session?.user);
    }
  }

  /// [changes], preceded by the current user once [authStateReady] completes, unless a change came first.
  Stream<AuthUser?> _startingWithCurrentUser(Stream<AuthUser?> changes) =>
      Stream<AuthUser?>.multi((MultiStreamController<AuthUser?> controller) {
        bool emitted = false;
        final StreamSubscription<AuthUser?> subscription = changes.listen((
          AuthUser? user,
        ) {
          emitted = true;
          controller.add(user);
        }, onDone: controller.close);
        controller.onCancel = subscription.cancel;
        void emitCurrent() {
          if (!emitted && !controller.isClosed) {
            emitted = true;
            controller.add(_session?.user);
          }
        }

        authStateReady().then<void>(
          (_) => emitCurrent(),
          onError: (Object _) => emitCurrent(),
        );
      });

  /// Like `_updateCurrentUser` of the JS SDK: the user of a sign-in must belong to [tenantId].
  void _checkTenant(AuthUser user) {
    if (user.tenantId != tenantId) {
      throw const FirebaseAuthException(
        code: 'tenant-id-mismatch',
        message:
            "The provided tenant ID does not match the Auth instance's tenant ID.",
      );
    }
  }

  /// Runs the [beforeAuthStateChanged] callbacks for [next] (`AuthMiddlewareQueue.runMiddleware` of the JS SDK).
  Future<void> _runBeforeStateCallbacks(AuthUser? next) async {
    final List<void Function()> onAbort = <void Function()>[];
    for (final _BeforeStateCallback entry in List<_BeforeStateCallback>.of(
      _beforeStateCallbacks,
    )) {
      try {
        await entry.callback(next);
      } on Object catch (e) {
        for (final void Function() abort in onAbort.reversed) {
          try {
            abort();
          } on Object {
            // Like the JS SDK: an onAbort that throws does not stop the others.
          }
        }
        throw FirebaseAuthException(
          code: 'login-blocked',
          message:
              'Login blocked by user-provided method: ${e is FirebaseException ? e.message : e}',
        );
      }
      final void Function()? abort = entry.onAbort;
      if (abort != null) {
        onAbort.add(abort);
      }
    }
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
    // Like `boundedRefreshDelay` of the iOS SDK: a delay beyond the longest token lifetime comes from an expiry
    // that is out of range, and refreshes right away.
    if (delay.isNegative || delay > _maximumTokenLifetime) {
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
          // Any error but the end of the session (a network error, a failing storage, ...) is retried later.
          final bool sessionEnded =
              error is FirebaseAuthException && error.invalidatesSession;
          if (!sessionEnded &&
              _session != null &&
              !_disposed &&
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
      throw FirebaseUserAuthDisposedError();
    }
  }

  /// When the proactive refresh is due, for tests.
  @visibleForTesting
  bool get hasRefreshTimer => _refreshTimer != null;
}

/// The request of a credential: the Identity Toolkit method, the body, and whether the tenant goes in it.
class _CredentialRequest {
  _CredentialRequest(this.method, this.body, {this.tenant = true});

  final String method;
  final Map<String, Object?> body;
  final bool tenant;
}

class _BeforeStateCallback {
  _BeforeStateCallback(this.callback, this.onAbort);

  final FutureOr<void> Function(AuthUser? user) callback;
  final void Function()? onAbort;
}

class _Session {
  const _Session(this.user, this.refreshToken, this.idToken, this.expiry);

  final AuthUser user;
  final String refreshToken;

  /// Null after [FirebaseUserAuth.restore], until the first refresh.
  final String? idToken;
  final DateTime? expiry;
}

/// The error of the account read after a change of the account: [FirebaseUserAuth]'s `_forUser` rethrows it
/// without sending the change again.
class _ChangeDone implements Exception {
  _ChangeDone(this.error);

  final FirebaseAuthException error;
}
