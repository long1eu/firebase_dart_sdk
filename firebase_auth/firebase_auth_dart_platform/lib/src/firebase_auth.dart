import 'dart:async';

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import 'package:firebase_auth_dart_platform/src/multi_factor.dart';
import 'package:firebase_auth_dart_platform/src/phone.dart';

import 'convert.dart';
import 'oauth_provider.dart';
import 'storage.dart';
import 'user.dart';

/// Returns the storage of the session of the FlutterFire [app] (see
/// `FirebaseAuthDart.use`).
typedef AuthStorageFactory = dart_auth.AuthStorage Function(FirebaseApp app);

/// Returns the loopback providers of the FlutterFire [app] (see
/// `FirebaseAuthDart.use`).
typedef OAuthProvidersFactory =
    Iterable<dart_auth.OAuthLoopbackProvider> Function(FirebaseApp app);

/// [providers] by their Firebase provider id; throws an [ArgumentError] naming
/// [argument] when two have the same id.
Map<String, dart_auth.OAuthLoopbackProvider> providersById(
  Iterable<dart_auth.OAuthLoopbackProvider> providers,
  String argument,
) {
  final Map<String, dart_auth.OAuthLoopbackProvider> byId =
      <String, dart_auth.OAuthLoopbackProvider>{};
  for (final dart_auth.OAuthLoopbackProvider provider in providers) {
    if (byId.containsKey(provider.providerId)) {
      throw ArgumentError.value(
        provider.providerId,
        argument,
        'has two providers with this id',
      );
    }
    byId[provider.providerId] = provider;
  }
  return Map<String, dart_auth.OAuthLoopbackProvider>.unmodifiable(byId);
}

/// What `FirebaseAuthDart.use` configures; read when the instance of an app is
/// created.
class DartAuthConfig {
  const DartAuthConfig({
    this.storageFor,
    this.httpClient,
    this.oauthProviders = const <String, dart_auth.OAuthLoopbackProvider>{},
    this.oauthProvidersFor,
    this.presenter,
    this.appVerification,
  });

  final AuthStorageFactory? storageFor;
  final http.Client? httpClient;

  /// The providers of `signInWithProvider` and its link and reauthenticate
  /// variants, by Firebase provider id (`google.com`, `github.com`, ...).
  final Map<String, dart_auth.OAuthLoopbackProvider> oauthProviders;

  /// The providers of one app, added to [oauthProviders] for that app; a
  /// provider here replaces the one of [oauthProviders] with the same id.
  final OAuthProvidersFactory? oauthProvidersFor;

  /// Runs the browser flow of a provider sign-in; the client's default
  /// (the presenter of the environment that the flow ranks best: the system
  /// browser on a desktop) when null.
  final dart_auth.SecurePresenter? presenter;

  /// The proof of the phone requests; see `DartFirebaseAuth.appVerification`.
  final dart_auth.AppVerification? appVerification;
}

/// The implementation of [FirebaseAuthPlatform] on top of
/// `FirebaseUserAuth` of `firebase_auth_providers_dart`: one client per
/// FlutterFire app.
///
/// The instance registered as [FirebaseAuthPlatform.instance] has no app; the
/// official `firebase_auth` asks it for the instance of each app
/// ([delegateFor]).
class DartFirebaseAuth extends FirebaseAuthPlatform {
  /// The instance without an app, for [FirebaseAuthPlatform.instance].
  DartFirebaseAuth()
    : _client = null,
      _persistent = null,
      _config = const DartAuthConfig(),
      _oauthProviders = const <String, dart_auth.OAuthLoopbackProvider>{},
      super();

  DartFirebaseAuth._(
    FirebaseApp app,
    this._client,
    this._persistent,
    this._config,
    this._oauthProviders,
  ) : super(appInstance: app);

  /// The configuration of the instances created from now on.
  static DartAuthConfig config = const DartAuthConfig();

  static final Map<String, DartFirebaseAuth> _instances =
      <String, DartFirebaseAuth>{};

  /// Whether the instance of an app exists, after which [config] no longer
  /// changes anything for that app.
  static bool get anyStarted => _instances.isNotEmpty;

  /// The instance of [app], created on first use (`firebase_auth` asks for it
  /// at the first call on `FirebaseAuth.instanceFor(app: app)`). Its client
  /// starts to restore the stored session at once, in the background:
  /// [currentUser] is null until that has finished, and `authStateChanges()`
  /// waits for it, so code that needs the restored user at start awaits
  /// `authStateChanges().first`.
  static DartFirebaseAuth forApp(FirebaseApp app) =>
      _instances.putIfAbsent(app.name, () {
        // Read first: a duplicate id throws before anything is created.
        final Map<String, dart_auth.OAuthLoopbackProvider> providers =
            <String, dart_auth.OAuthLoopbackProvider>{
              ...config.oauthProviders,
              ...providersById(
                config.oauthProvidersFor?.call(app) ??
                    const <dart_auth.OAuthLoopbackProvider>[],
                'oauthProvidersFor',
              ),
            };
        final dart_auth.AuthStorage storage =
            config.storageFor?.call(app) ?? defaultStorage();
        final FallbackStorage persistent = FallbackStorage(storage);
        final dart_auth.FirebaseUserAuth userAuth = dart_auth.FirebaseUserAuth(
          apiKey: app.options.apiKey,
          appId: app.options.appId,
          storage: persistent,
          storageKey: storageKeyOf(app),
          httpClient: config.httpClient,
        );
        // The error of a failed restore (an unreadable storage) reaches
        // authStateReady(); the app starts signed out.
        unawaited(userAuth.restore().catchError((Object _) {}));
        return DartFirebaseAuth._(
          app,
          userAuth,
          persistent,
          config,
          Map<String, dart_auth.OAuthLoopbackProvider>.unmodifiable(providers),
        );
      });

  /// The key of the session of [app] in its storage, the one `forApp` of
  /// `FirebaseUserAuth` uses: two apps keep two sessions in one file.
  static String storageKeyOf(FirebaseApp app) =>
      'firebase_auth_providers_dart:${app.options.apiKey}:${app.name}';

  final dart_auth.FirebaseUserAuth? _client;

  /// The storage of the app (memory after a failed write); the session is
  /// there unless `setPersistence` moved it to [_memory].
  final FallbackStorage? _persistent;

  /// Where `setPersistence(Persistence.NONE)` keeps the session.
  final dart_auth.InMemoryAuthStorage _memory = dart_auth.InMemoryAuthStorage();
  final DartAuthConfig _config;

  /// The loopback providers of this instance's app: those of `use`'s
  /// `oauthProviders` and `oauthProvidersFor`, by provider id.
  final Map<String, dart_auth.OAuthLoopbackProvider> _oauthProviders;
  final Expando<DartUser> _users = Expando<DartUser>();

  /// The client of this instance's app.
  dart_auth.FirebaseUserAuth get client =>
      _client ??
      (throw StateError(
        'This is the registered instance of firebase_auth_dart_platform, '
        'which has no app: use FirebaseAuth.instanceFor(app: ...).',
      ));

  /// The [client] while [uid] is its signed-in user. Throws `no-current-user`
  /// once another user (or nobody) is signed in, like the native
  /// implementations.
  dart_auth.FirebaseUserAuth clientFor(String uid) {
    final dart_auth.FirebaseUserAuth userAuth = client;
    if (userAuth.uid != uid) {
      throw noCurrentUser();
    }
    return userAuth;
  }

  /// The user of the interface for [user], the same object for the same
  /// snapshot of the client.
  DartUser? userOf(dart_auth.AuthUser? user) {
    if (user == null) {
      return null;
    }
    // A UserCredential of the client is a copy of its user; use the user.
    final dart_auth.AuthUser source = user is dart_auth.UserCredential
        ? user.user!
        : user;
    return _users[source] ??= DartUser(this, source);
  }

  /// The result of a sign-in, link or reauthentication of the client.
  DartUserCredential resultOf(dart_auth.UserCredential result) =>
      DartUserCredential(
        auth: this,
        additionalUserInfo: additionalUserInfoOf(result.additionalUserInfo),
        credential: credentialOf(result.credential),
        user: userOf(result.user),
      );

  /// The loopback provider registered for [provider]'s id, with the scopes
  /// and custom parameters of [provider] added to its own (the parameters of
  /// [provider] win over those of the registered provider).
  ///
  /// Throws `unimplemented` when no provider is registered for that id and on
  /// the web, where the loopback flow does not exist, and
  /// `operation-not-supported-in-this-environment` (the code the client gives
  /// a flow without a presenter) on a platform without a default browser
  /// launcher (Android, iOS) when `use` got no `presenter`.
  dart_auth.OAuthLoopbackProvider loopbackProviderFor(
    String member,
    AuthProvider provider,
  ) {
    if (kIsWeb) {
      throw unimplemented(member, noLoopbackOnWeb);
    }
    if (_config.presenter == null &&
        !_systemBrowserPlatforms.contains(defaultTargetPlatform)) {
      throw FirebaseAuthException(
        code: 'operation-not-supported-in-this-environment',
        message: '$member: $noPresenter',
      );
    }
    final dart_auth.OAuthLoopbackProvider? registered =
        _oauthProviders[provider.providerId];
    if (registered == null) {
      throw unimplemented(member, noProviderFlowFor(provider.providerId));
    }
    final (List<String> scopes, Map<String, String> parameters) =
        oauthRequestOf(provider);
    if (scopes.isEmpty && parameters.isEmpty) {
      return registered;
    }
    return registered.copyWith(
      scopes: <String>{...registered.scopes, ...scopes}.toList(),
      customParameters: <String, String>{
        ...registered.customParameters,
        ...parameters,
      },
    );
  }

  /// Where the client opens the system browser without a `presenter`.
  static const Set<TargetPlatform> _systemBrowserPlatforms = <TargetPlatform>{
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  };

  /// The presenter of the provider flows passed to `FirebaseAuthDart.use`.
  dart_auth.SecurePresenter? get presenter => _config.presenter;

  /// Set by `setSettings(appVerificationDisabledForTesting: true)`.
  bool _appVerificationDisabled = false;

  /// The proof the phone requests of this app carry: none after
  /// `setSettings(appVerificationDisabledForTesting: true)`, or with the Auth
  /// emulator when `FirebaseAuthDart.use` got no `appVerification` (the
  /// emulator does not check it); else the `appVerification` of `use`, by
  /// default the reCAPTCHA v2 page of the client in the system browser.
  dart_auth.AppVerification get appVerification {
    final dart_auth.AppVerification? configured = _config.appVerification;
    if (_appVerificationDisabled ||
        (configured == null && client.emulatorConfig != null)) {
      return const dart_auth.AppVerification.none();
    }
    return configured ?? dart_auth.AppVerification.recaptchaV2Loopback();
  }

  // ---- plumbing ----

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => forApp(app);

  /// The initial values come from a native plugin; the client has its own.
  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;

  /// Called by `firebase_auth` when its app is deleted: closes the client. The
  /// session stays in the storage.
  @override
  Future<void> dispose() async {
    final dart_auth.FirebaseUserAuth? userAuth = _client;
    if (userAuth == null) {
      return;
    }
    if (identical(_instances[app.name], this)) {
      _instances.remove(app.name);
    }
    await userAuth.dispose();
  }

  /// The signed-in user. Null until the stored session has been restored,
  /// which starts when this instance is created: await
  /// `authStateChanges().first` for the user at start.
  @override
  UserPlatform? get currentUser => userOf(client.currentUser);

  /// Ignored: the signed-in user is the client's. Only the method channel
  /// implementation sets it.
  @override
  set currentUser(UserPlatform? userPlatform) {}

  /// Ignored: the streams follow the client.
  @override
  void sendAuthChangesEvent(String appName, UserPlatform? userPlatform) {}

  @override
  String? get tenantId => _client?.tenantId;

  @override
  set tenantId(String? tenantId) => client.tenantId = tenantId;

  @override
  String? get languageCode => client.languageCode;

  @override
  Future<void> setLanguageCode(String? languageCode) =>
      client.setLanguageCode(languageCode);

  @override
  Future<void> useAuthEmulator(String host, int port) async {
    final String authority = host.contains(':') && !host.startsWith('[')
        ? '[$host]:$port'
        : '$host:$port';
    client.useEmulator(authority);
  }

  /// [Persistence.NONE] and [Persistence.SESSION] keep the session in memory
  /// only (until the process ends); [Persistence.LOCAL] and
  /// [Persistence.INDEXED_DB] in the storage of the app (by default a file).
  /// The current session moves to the new place (`setStorage` of the
  /// client): it is written there first, then deleted from the old place.
  @override
  Future<void> setPersistence(Persistence persistence) {
    final dart_auth.FirebaseUserAuth userAuth = client;
    final bool inMemory =
        persistence == Persistence.NONE || persistence == Persistence.SESSION;
    return guard(
      this,
      () => userAuth.setStorage(inMemory ? _memory : _persistent!),
    );
  }

  /// [appVerificationDisabledForTesting] sends the phone requests without a
  /// proof ([appVerification]), for the test phone numbers of a project and
  /// the emulator. The other settings are for the Android test number
  /// auto-retrieval, the reCAPTCHA flow of Android and the iOS keychain, and
  /// are ignored.
  @override
  Future<void> setSettings({
    bool appVerificationDisabledForTesting = false,
    String? userAccessGroup,
    bool migrateCurrentUser = false,
    String? phoneNumber,
    String? smsCode,
    bool? forceRecaptchaFlow,
  }) async {
    _appVerificationDisabled = appVerificationDisabledForTesting;
  }

  // ---- streams ----

  @override
  Stream<UserPlatform?> authStateChanges() =>
      client.authStateChanges().map(userOf);

  @override
  Stream<UserPlatform?> idTokenChanges() => client.idTokenChanges().map(userOf);

  /// Like `firebase_auth` on the other platforms: the current user when it
  /// is listened to, then one event per sign-in or sign-out, per new ID token
  /// (a refresh) and per change of the user's data.
  ///
  /// It merges the client's [idTokenChanges] and `userChanges()`. One change
  /// of the client (a sign-in, a sign-out, an update that returns a new ID
  /// token) emits the same user object, or null, on both, before the next
  /// timer event: the second of the two is dropped. A refresh emits on
  /// [idTokenChanges] only and a change of the user's data without a new token
  /// on `userChanges()` only, so each of them is one event too.
  @override
  Stream<UserPlatform?> userChanges() {
    final dart_auth.FirebaseUserAuth userAuth = client;
    // Not paused with the listener: this controller buffers instead, so that
    // the two events of one change still arrive together.
    late final StreamController<UserPlatform?> controller;
    final List<StreamSubscription<dart_auth.AuthUser?>> subscriptions =
        <StreamSubscription<dart_auth.AuthUser?>>[];
    // The events each stream delivered in the current turn, not yet matched
    // by the other stream.
    final List<dart_auth.AuthUser?> fromTokens = <dart_auth.AuthUser?>[];
    final List<dart_auth.AuthUser?> fromUsers = <dart_auth.AuthUser?>[];
    Timer? endOfTurn;

    void on(
      dart_auth.AuthUser? user,
      List<dart_auth.AuthUser?> mine,
      List<dart_auth.AuthUser?> other,
    ) {
      final int match = other.indexWhere(
        (dart_auth.AuthUser? u) => identical(u, user),
      );
      if (match >= 0) {
        other.removeAt(match);
        return;
      }
      mine.add(user);
      endOfTurn ??= Timer(Duration.zero, () {
        endOfTurn = null;
        fromTokens.clear();
        fromUsers.clear();
      });
      controller.add(userOf(user));
    }

    controller = StreamController<UserPlatform?>(
      sync: true,
      onListen: () {
        subscriptions
          ..add(
            userAuth.idTokenChanges().listen(
              (dart_auth.AuthUser? user) => on(user, fromTokens, fromUsers),
              onError: controller.addError,
            ),
          )
          ..add(
            userAuth.userChanges().listen(
              (dart_auth.AuthUser? user) => on(user, fromUsers, fromTokens),
              onError: controller.addError,
            ),
          );
      },
      onCancel: () async {
        endOfTurn?.cancel();
        await Future.wait(<Future<void>>[
          for (final StreamSubscription<dart_auth.AuthUser?> s in subscriptions)
            s.cancel(),
        ]);
      },
    );
    return controller.stream;
  }

  // ---- sign-in ----

  @override
  Future<UserCredentialPlatform> signInAnonymously() =>
      guard(this, () async => resultOf(await client.signInAnonymously()));

  @override
  Future<UserCredentialPlatform> createUserWithEmailAndPassword(
    String email,
    String password,
  ) => guard(
    this,
    () async => resultOf(
      await client.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
    ),
  );

  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) => guard(
    this,
    () async => resultOf(
      await client.signInWithEmailAndPassword(email: email, password: password),
    ),
  );

  @override
  Future<UserCredentialPlatform> signInWithCustomToken(String token) => guard(
    this,
    () async => resultOf(await client.signInWithCustomToken(token)),
  );

  @override
  Future<UserCredentialPlatform> signInWithCredential(
    AuthCredential credential,
  ) => guard(
    this,
    () async => resultOf(
      await client.signInWithCredential(clientCredentialOf(credential)),
    ),
  );

  @override
  Future<UserCredentialPlatform> signInWithEmailLink(
    String email,
    String emailLink,
  ) => guard(
    this,
    () async => resultOf(
      await client.signInWithEmailLink(email: email, emailLink: emailLink),
    ),
  );

  @override
  bool isSignInWithEmailLink(String emailLink) =>
      client.isSignInWithEmailLink(emailLink);

  @override
  Future<void> signOut() => guard(this, () => client.signOut());

  // ---- email actions ----

  @override
  Future<void> sendPasswordResetEmail(
    String email, [
    ActionCodeSettings? actionCodeSettings,
  ]) => guard(
    this,
    () => client.sendPasswordResetEmail(
      email: email,
      actionCodeSettings: actionCodeSettingsOf(actionCodeSettings),
    ),
  );

  @override
  Future<void> sendSignInLinkToEmail(
    String email,
    ActionCodeSettings actionCodeSettings,
  ) => guard(
    this,
    () => client.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: actionCodeSettingsOf(actionCodeSettings)!,
    ),
  );

  @override
  Future<void> applyActionCode(String code) =>
      guard(this, () => client.applyActionCode(code));

  @override
  Future<ActionCodeInfo> checkActionCode(String code) => guard(
    this,
    () async => actionCodeInfoOf(await client.checkActionCode(code)),
  );

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) => guard(
    this,
    () => client.confirmPasswordReset(code: code, newPassword: newPassword),
  );

  @override
  Future<String> verifyPasswordResetCode(String code) =>
      guard(this, () => client.verifyPasswordResetCode(code));

  @override
  Future<List<String>> fetchSignInMethodsForEmail(String email) =>
      guard(this, () => client.fetchSignInMethodsForEmail(email));

  /// Signs in through the system browser and a loopback redirect, with the
  /// `OAuthLoopbackProvider` passed to `FirebaseAuthDart.use` for the id of
  /// [provider]; the scopes and custom parameters of [provider] are added to
  /// its request. Throws `unimplemented` for a provider id that was not
  /// passed.
  @override
  Future<UserCredentialPlatform> signInWithProvider(AuthProvider provider) =>
      guard(this, () async {
        final dart_auth.OAuthLoopbackProvider loopback = loopbackProviderFor(
          'signInWithProvider',
          provider,
        );
        return resultOf(
          await client.signInWithOAuthLoopback(loopback, presenter: presenter),
        );
      });

  // ---- not available: see the README ----

  @override
  Future<UserCredentialPlatform> signInWithPopup(AuthProvider provider) async =>
      throw unimplemented('signInWithPopup', noBrowserFlow);

  @override
  Future<void> signInWithRedirect(AuthProvider provider) async =>
      throw unimplemented('signInWithRedirect', noBrowserFlow);

  @override
  Future<UserCredentialPlatform> getRedirectResult() async =>
      throw unimplemented('getRedirectResult', noBrowserFlow);

  @override
  Future<void> initializeRecaptchaConfig() async =>
      throw unimplemented('initializeRecaptchaConfig', noRecaptchaConfig);

  // ---- phone ----

  /// Sends the SMS code to [phoneNumber] with the proof of [appVerification]
  /// and returns a [ConfirmationResultPlatform] whose `confirm` signs in with
  /// the code. [applicationVerifier] is not used (see
  /// `DartRecaptchaVerifierFactory`).
  @override
  Future<ConfirmationResultPlatform> signInWithPhoneNumber(
    String phoneNumber,
    RecaptchaVerifierFactoryPlatform applicationVerifier,
  ) => guard(this, () async {
    final dart_auth.FirebaseUserAuth userAuth = client;
    final String verificationId = await userAuth.verifyPhoneNumber(
      phoneNumber,
      appVerification: appVerification,
    );
    return DartConfirmationResult(
      this,
      verificationId,
      userAuth.signInWithCredential,
    );
  });

  /// Sends an SMS code with the proof of [appVerification]: to [phoneNumber]
  /// for a sign-in; to [phoneNumber] for an enrolment when
  /// [multiFactorSession] comes from `User.multiFactor.getSession()`; to the
  /// factor [multiFactorInfo] when it is the session of a
  /// `MultiFactorResolver` (a single SMS factor is picked without
  /// [multiFactorInfo]).
  ///
  /// [codeSent] gets the verification id (and no resending token: send again
  /// to resend), [verificationFailed] every error, and
  /// [codeAutoRetrievalTimeout] the verification id after [timeout].
  /// [verificationCompleted] is never called: there is no instant verification
  /// and no automatic reading of the SMS outside Android, so the user types the
  /// code in. [forceResendingToken] and [autoRetrievedSmsCodeForTesting] are
  /// ignored.
  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
    String? autoRetrievedSmsCodeForTesting,
  }) async {
    final String verificationId;
    try {
      verificationId = await guard(
        this,
        () => _sendCode(phoneNumber, multiFactorInfo, multiFactorSession),
      );
    } on FirebaseAuthException catch (e) {
      verificationFailed(e);
      return;
    }
    codeSent(verificationId, null);
    Timer(timeout, () => codeAutoRetrievalTimeout(verificationId));
  }

  Future<String> _sendCode(
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    MultiFactorSession? session,
  ) => switch (session) {
    null => client.verifyPhoneNumber(
      phoneNumber ?? '',
      appVerification: appVerification,
    ),
    DartMultiFactorSession(:final DartMultiFactor multiFactor) =>
      multiFactor.startPhoneEnrollment(phoneNumber ?? '', appVerification),
    DartMultiFactorSignInSession() => session.startPhoneSignIn(
      multiFactorInfo?.uid,
      appVerification,
    ),
    _ => throw FirebaseAuthException(
      code: 'argument-error',
      message:
          'verifyPhoneNumber takes the session of User.multiFactor.getSession() '
          'or of a MultiFactorResolver of this package.',
    ),
  };

  /// Revokes an Apple access token (`revokeAccessToken` of the client).
  @override
  Future<void> revokeAccessToken(String accessToken) =>
      guard(this, () => client.revokeAccessToken(accessToken));

  /// Revokes the tokens of a Sign in with Apple authorization code
  /// (`revokeToken` of the client).
  @override
  Future<void> revokeTokenWithAuthorizationCode(String authorizationCode) =>
      guard(this, () => client.revokeToken(authorizationCode));
}
