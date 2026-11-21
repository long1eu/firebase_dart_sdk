// The steps of the real-project harness, through the official firebase_auth
// API on top of this package. Each one leaves the account as it found it,
// through the CleanupLedger; none deletes an account.

import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show
        AppVerification,
        AuthStorage,
        RecaptchaV2Request,
        RecaptchaV2TokenSource,
        RecaptchaV2Verification;

import 'cleanup.dart';
import 'code_prompt.dart';
import 'harness_config.dart';

/// The outcome of a step.
enum StepStatus {
  /// The step did what it checks.
  pass,

  /// The step failed; the detail is the error code.
  fail,

  /// The step cannot say anything meaningful here; the detail says why.
  skip,
}

/// The outcome of one step, printed as one line by [line].
class StepResult {
  /// The [status] of [step], with an optional [detail].
  const StepResult(this.step, this.status, [this.detail]);

  /// The step.
  final HarnessStep step;

  /// Its outcome.
  final StepStatus status;

  /// The error code of a failure, the reason of a skip, or a note.
  final String? detail;

  /// `PASS google`, `FAIL github: credential-already-in-use`, ...
  String line() {
    final String text = '${status.name.toUpperCase()} ${step.name}';
    final String? note = detail;
    return note == null ? text : '$text: $note';
  }
}

/// A check of the harness that failed, with an error [code] of its own.
class StepFailure implements Exception {
  /// A failure with [code].
  StepFailure(this.code);

  /// What went wrong, in the style of an auth error code.
  final String code;

  @override
  String toString() => 'StepFailure: $code';
}

/// Thrown by a step that cannot say anything meaningful; [reason] says why.
class StepSkipped implements Exception {
  /// A skip because of [reason].
  StepSkipped(this.reason);

  /// Why the step was skipped.
  final String reason;
}

/// The text of [error] for a FAIL line: the auth error code (with the server's
/// code when it differs), the code of a [StepFailure], or the type and the
/// redacted message of anything else. Never a token or a full email address.
String describeError(Object error) {
  if (error is DartFirebaseAuthException) {
    final String? server = error.serverCode?.split(RegExp(r'[\s:]')).first;
    return server == null || server.isEmpty
        ? error.code
        : '${error.code} (server: ${redact(server)})';
  }
  if (error is FirebaseAuthException) {
    return error.code;
  }
  if (error is StepFailure) {
    return error.code;
  }
  if (error is TimeoutException) {
    return 'timeout';
  }
  return '${error.runtimeType}: ${redact(error.toString())}';
}

/// An [AuthStorage] in front of another one that knows which keys it holds a
/// value for, so that the harness can tell whether the session is there.
class RecordingStorage extends AuthStorage {
  /// Records the keys written to [inner].
  RecordingStorage(this.inner);

  /// The storage the values are kept in.
  final AuthStorage inner;

  final Set<String> _keys = <String>{};

  @override
  FutureOr<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String? value) async {
    _keys.add(key);
    await inner.write(key, value);
  }

  /// Whether [inner] holds a value under any key written through this
  /// storage: the session, when the client wrote one.
  Future<bool> holdsSession() async {
    for (final String key in _keys) {
      if (await inner.read(key) != null) {
        return true;
      }
    }
    return false;
  }
}

/// The display name of the TOTP factor the harness enrols.
const String totpDisplayName = 'auth-harness';

/// The display name of the SMS factor the harness enrols.
const String smsDisplayName = 'auth-harness-sms';

/// The proofs the phone requests of the harness try, in this order, until the
/// project accepts one (a test phone number may need less than a real one).
enum ProofMode {
  /// No proof: `setSettings(appVerificationDisabledForTesting: true)`.
  none('no proof'),

  /// A random 50-character `recaptchaToken`, as the JS SDK sends for test
  /// numbers with `appVerificationDisabledForTesting`.
  fakeToken('a placeholder reCAPTCHA token'),

  /// A real reCAPTCHA v2 token from the client's page in the browser.
  recaptchaPage('the reCAPTCHA page');

  const ProofMode(this.label);

  /// How the report names it.
  final String label;
}

/// The `AppVerification` of the harness, passed to `FirebaseAuthDart.use`: a
/// reCAPTCHA v2 token that is a placeholder or comes from the page, by [mode].
class HarnessProof {
  /// The source of [verification]; [ProofMode.none] is not set here but with
  /// `setSettings`.
  ProofMode mode = ProofMode.fakeToken;

  final RecaptchaV2TokenSource _page =
      (AppVerification.recaptchaV2Loopback() as RecaptchaV2Verification).token;

  /// What `FirebaseAuthDart.use` gets.
  AppVerification get verification =>
      AppVerification.recaptchaV2((RecaptchaV2Request request) {
        if (mode == ProofMode.recaptchaPage) {
          return _page(request);
        }
        const String letters =
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        final Random random = Random.secure();
        return String.fromCharCodes(<int>[
          for (int i = 0; i < 50; i++)
            letters.codeUnitAt(random.nextInt(letters.length)),
        ]);
      });
}

/// The placeholder `revokeAccessToken` is called with.
const String placeholderAppleToken = 'auth-harness-placeholder-token';

/// Runs the steps against [auth], keeping one primary account: the one of the
/// first Google sign-in. Every step that needs a user signs in to it.
class HarnessRun {
  /// A run on [auth], asking for codes through [codes], undoing changes
  /// through [ledger], checking the session in [storage], printing through
  /// [log].
  HarnessRun({
    required this.auth,
    required this.codes,
    required this.ledger,
    required this.storage,
    required this.log,
    required this.githubAccountExists,
    this.phoneNumber,
    this.phoneCode,
    this.proof,
  });

  /// The `FirebaseAuth` of the app.
  final FirebaseAuth auth;

  /// Asks for one-time codes.
  final CodeSource codes;

  /// The undo actions of the changes made.
  final CleanupLedger ledger;

  /// The storage of the app's session.
  final RecordingStorage storage;

  /// Prints a line.
  final void Function(String line) log;

  /// See [HarnessConfig.githubAccountExists].
  final bool githubAccountExists;

  /// See [HarnessConfig.phoneNumber]; the phone and sms steps are skipped
  /// without it.
  final String? phoneNumber;

  /// See [HarnessConfig.phoneCode].
  final String? phoneCode;

  /// The `AppVerification` passed to `FirebaseAuthDart.use`; without it the
  /// phone requests try [ProofMode.none] only.
  final HarnessProof? proof;

  /// The proof the phone requests use now: the first the project accepted.
  ProofMode proofMode = ProofMode.none;

  /// The uid of the primary account, once signed in.
  String? primaryUid;

  /// Runs [step]; never throws.
  Future<StepResult> runStep(HarnessStep step) async {
    try {
      final String? note = await switch (step) {
        HarnessStep.google => _google(),
        HarnessStep.github => _github(),
        HarnessStep.reauthenticate => _reauthenticate(),
        HarnessStep.totp => _totp(),
        HarnessStep.phone => _phone(),
        HarnessStep.sms => _sms(),
        HarnessStep.revoke => _revoke(),
        HarnessStep.persistence => _persistence(),
      };
      return StepResult(step, StepStatus.pass, note);
    } on StepSkipped catch (e) {
      return StepResult(step, StepStatus.skip, e.reason);
    } on Object catch (e) {
      return StepResult(step, StepStatus.fail, describeError(e));
    }
  }

  /// Signs in with [provider], finishing a TOTP challenge with a code if one
  /// comes. A new account is recorded for deletion by hand and fails.
  Future<UserCredential> signInWith(AuthProvider provider) async {
    UserCredential credential;
    try {
      credential = await auth.signInWithProvider(provider);
    } on FirebaseAuthMultiFactorException catch (e) {
      credential = await resolveChallenge(e.resolver);
    }
    final User user = credential.user!;
    if (credential.additionalUserInfo?.isNewUser ?? false) {
      ledger.recordManual(
        'The ${provider.providerId} sign-in created the new account '
        '${user.uid}; delete it in the Firebase console.',
      );
      await auth.signOut();
      throw StepFailure('new-account-created');
    }
    return credential;
  }

  /// Finishes the second-factor challenge of [resolver]: with a TOTP code when
  /// the account has a TOTP factor, else with the SMS code of the test phone
  /// number when it has an SMS factor and the phone variables are set.
  Future<UserCredential> resolveChallenge(MultiFactorResolver resolver) {
    final bool totp = resolver.hints.any(
      (MultiFactorInfo info) => info is TotpMultiFactorInfo,
    );
    final bool sms = resolver.hints.any(
      (MultiFactorInfo info) => info is PhoneMultiFactorInfo,
    );
    return !totp && sms && phoneNumber != null
        ? resolveSms(resolver)
        : resolveTotp(resolver);
  }

  /// Finishes the second-factor challenge of [resolver] with the SMS code of
  /// the test phone number: for the factor [factorUid], or the first SMS
  /// factor.
  Future<UserCredential> resolveSms(
    MultiFactorResolver resolver, {
    String? factorUid,
  }) async {
    _testPhone();
    final PhoneMultiFactorInfo hint =
        resolver.hints
            .whereType<PhoneMultiFactorInfo>()
            .where(
              (MultiFactorInfo info) =>
                  factorUid == null || info.uid == factorUid,
            )
            .firstOrNull ??
        (throw StepFailure('no-sms-factor'));
    final String verificationId = await _withProof(
      () => _sendCode(session: resolver.session, hint: hint),
    );
    return resolver.resolveSignIn(
      PhoneMultiFactorGenerator.getAssertion(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: await _smsCode('the second-factor sign-in'),
        ),
      ),
    );
  }

  /// Finishes the second-factor challenge of [resolver] with a TOTP code: for
  /// the factor [factorUid], or the first TOTP factor.
  Future<UserCredential> resolveTotp(
    MultiFactorResolver resolver, {
    String? factorUid,
    String prompt = 'The code of your authenticator app',
  }) async {
    final MultiFactorInfo? hint = resolver.hints
        .whereType<TotpMultiFactorInfo>()
        .where(
          (MultiFactorInfo info) => factorUid == null || info.uid == factorUid,
        )
        .firstOrNull;
    if (hint == null) {
      throw StepFailure('no-totp-factor');
    }
    final String code = await codes.ask('$prompt ("${hint.displayName}")');
    return resolver.resolveSignIn(
      await TotpMultiFactorGenerator.getAssertionForSignIn(hint.uid, code),
    );
  }

  /// Signs in to the primary account with Google; the first call decides
  /// which account that is.
  Future<User> signInPrimary() async {
    if (auth.currentUser != null) {
      await auth.signOut();
    }
    final User user = (await signInWith(GoogleAuthProvider())).user!;
    final String? expected = primaryUid;
    if (expected != null && user.uid != expected) {
      await auth.signOut();
      throw StepFailure('signed-in-to-another-account');
    }
    primaryUid = user.uid;
    log('  Signed in as ${maskEmail(user.email)} (uid ${user.uid}).');
    return user;
  }

  /// The primary user, signing in to it when someone else or nobody is.
  Future<User> ensurePrimary() async {
    final User? user = auth.currentUser;
    if (user != null && primaryUid != null && user.uid == primaryUid) {
      return user;
    }
    return signInPrimary();
  }

  void _expectPrimary(User? user) {
    if (user == null || user.uid != primaryUid) {
      throw StepFailure('wrong-account');
    }
  }

  Future<String?> _google() async {
    await signInPrimary();
    return null;
  }

  Future<String?> _github() async {
    final User user = await ensurePrimary();
    if (user.providerData.any(
      (UserInfo info) => info.providerId == 'github.com',
    )) {
      await auth.signOut();
      _expectPrimary((await signInWith(GithubAuthProvider())).user);
      return 'GitHub was already linked: signed in with it; link and unlink '
          'skipped, the link is kept';
    }
    if (githubAccountExists) {
      await _accountExistsRecovery();
    }
    await (await ensurePrimary()).linkWithProvider(GithubAuthProvider());
    final CleanupToken unlink = ledger.register(
      'unlink github.com',
      () => _unlink('github.com'),
    );
    await auth.signOut();
    _expectPrimary((await signInWith(GithubAuthProvider())).user);
    await ledger.run(unlink);
    return githubAccountExists
        ? 'account-exists recovery, link, sign-in and unlink'
        : 'link, sign-in and unlink (account-exists part off)';
  }

  /// A GitHub sign-in that must fail with
  /// `account-exists-with-different-credential`, then the documented
  /// recovery: sign in with Google and link the credential of the error.
  Future<void> _accountExistsRecovery() async {
    await auth.signOut();
    final AuthCredential? credential;
    try {
      await signInWith(GithubAuthProvider());
      await auth.signOut();
      throw StepFailure('no-account-exists-error');
    } on FirebaseAuthException catch (e) {
      if (e.code != 'account-exists-with-different-credential') {
        rethrow;
      }
      credential = e.credential;
      log(
        '  account-exists-with-different-credential for ${maskEmail(e.email)}.',
      );
    }
    if (credential == null) {
      throw StepFailure('no-credential-in-error');
    }
    final User user = await signInPrimary();
    await user.linkWithCredential(credential);
    await ledger.run(
      ledger.register('unlink github.com', () => _unlink('github.com')),
    );
  }

  Future<void> _unlink(String providerId) async {
    final User user = await ensurePrimary();
    if (user.providerData.any(
      (UserInfo info) => info.providerId == providerId,
    )) {
      await user.unlink(providerId);
    }
  }

  Future<String?> _reauthenticate() async {
    final User user = await ensurePrimary();
    UserCredential credential;
    try {
      credential = await user.reauthenticateWithProvider(GoogleAuthProvider());
    } on FirebaseAuthMultiFactorException catch (e) {
      credential = await resolveChallenge(e.resolver);
    }
    _expectPrimary(credential.user);
    return null;
  }

  /// Runs [action]; when the backend asks for a recent sign-in
  /// (`requires-recent-login`), reauthenticates with Google and runs it once
  /// more.
  Future<T> _withRecentLogin<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') {
        rethrow;
      }
      log(
        '  requires-recent-login: signing in again with Google, then retrying',
      );
      await _reauthenticate();
      return action();
    }
  }

  Future<String?> _totp() async {
    final User user = await ensurePrimary();
    await _withRecentLogin(() => _enrolHarnessFactor(user));
    final CleanupToken unenrol = ledger.register(
      'unenrol the TOTP factor "$totpDisplayName"',
      () => _unenrolFactorNamed(totpDisplayName),
    );
    final String factorUid =
        (await _factorNamed(user, totpDisplayName))?.uid ??
        (throw StepFailure('enrolled-factor-not-listed'));
    await auth.signOut();
    try {
      await auth.signInWithProvider(GoogleAuthProvider());
      throw StepFailure('no-second-factor-challenge');
    } on FirebaseAuthMultiFactorException catch (e) {
      _expectPrimary(
        (await resolveTotp(
          e.resolver,
          factorUid: factorUid,
          prompt:
              'The NEXT code of the "$totpDisplayName" entry (the first '
              'one is spent)',
        )).user,
      );
    }
    await ledger.run(unenrol);
    return null;
  }

  /// Enrols the throwaway TOTP factor of the harness: a new secret, its code
  /// from the code page, and `enroll`.
  Future<void> _enrolHarnessFactor(User user) async {
    final TotpSecret secret = await TotpMultiFactorGenerator.generateSecret(
      await user.multiFactor.getSession(),
    );
    final String uri = await secret.generateQrCodeUrl(
      accountName: maskEmail(user.email),
      issuer: totpDisplayName,
    );
    log('  otpauth URI of a throwaway factor (unenrolled at the end): $uri');
    final String enrolCode = await codes.ask(
      'The code of the new "$totpDisplayName" entry of your authenticator app',
      otpauthUri: uri,
    );
    await user.multiFactor.enroll(
      await TotpMultiFactorGenerator.getAssertionForEnrollment(
        secret,
        enrolCode,
      ),
      displayName: totpDisplayName,
    );
  }

  /// The factor named [name] that the harness enrolled, newest first if there
  /// are several.
  Future<MultiFactorInfo?> _factorNamed(User user, String name) async {
    final List<MultiFactorInfo> factors = await user.multiFactor
        .getEnrolledFactors();
    return factors.reversed
        .where((MultiFactorInfo info) => info.displayName == name)
        .firstOrNull;
  }

  Future<void> _unenrolFactorNamed(String name) async {
    final User user = await ensurePrimary();
    final MultiFactorInfo? factor = await _factorNamed(user, name);
    if (factor != null) {
      await _withRecentLogin(
        () => user.multiFactor.unenroll(factorUid: factor.uid),
      );
    }
  }

  /// The test phone number and its code, or a skip when they are not set.
  (String, String) _testPhone() {
    final String? number = phoneNumber;
    final String? code = phoneCode;
    if (number == null || code == null) {
      throw StepSkipped(
        'set $phoneNumberVariable and $phoneCodeVariable (a test phone number '
        'of the project and its code)',
      );
    }
    return (number, code);
  }

  /// The code of the SMS just sent for [purpose]: the one of the test phone
  /// number, or, with [askForPhoneCode], the one the person types.
  Future<String> _smsCode(String purpose) async {
    final String code = _testPhone().$2;
    return code == askForPhoneCode
        ? codes.ask('The code of the SMS just sent for $purpose')
        : code;
  }

  /// The verification id of an SMS sent by `verifyPhoneNumber`, or the error
  /// of `verificationFailed`.
  Future<String> _sendCode({
    String? phoneNumber,
    MultiFactorSession? session,
    PhoneMultiFactorInfo? hint,
  }) {
    final Completer<String> sent = Completer<String>();
    unawaited(
      auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        multiFactorSession: session,
        multiFactorInfo: hint,
        verificationCompleted: (_) {},
        verificationFailed: sent.completeError,
        codeSent: (String verificationId, int? _) =>
            sent.complete(verificationId),
        codeAutoRetrievalTimeout: (_) {},
      ),
    );
    return sent.future;
  }

  /// Runs the phone request [send] with [proofMode]; when the project refuses
  /// the proof, moves to the next [ProofMode] and sends again.
  Future<T> _withProof<T>(Future<T> Function() send) async {
    while (true) {
      await auth.setSettings(
        appVerificationDisabledForTesting: proofMode == ProofMode.none,
      );
      proof?.mode = proofMode;
      try {
        return await send();
      } on FirebaseAuthException catch (e) {
        final bool refused = const <String>{
          'missing-app-credential',
          'invalid-app-credential',
          'captcha-check-failed',
        }.contains(e.code);
        final int next = proofMode.index + 1;
        if (!refused || proof == null || next >= ProofMode.values.length) {
          rethrow;
        }
        log(
          '  The project refused the phone request with ${proofMode.label} '
          '(${e.code}); trying ${ProofMode.values[next].label}.',
        );
        proofMode = ProofMode.values[next];
      }
    }
  }

  Future<String?> _phone() async {
    final (String number, _) = _testPhone();
    final User user = await ensurePrimary();
    if (user.providerData.any((UserInfo info) => info.providerId == 'phone')) {
      throw StepSkipped(
        'the account already has a phone number; unlink it to run this step',
      );
    }
    final ConfirmationResult link = await _withProof(
      () => user.linkWithPhoneNumber(number),
    );
    _expectPrimary((await link.confirm(await _smsCode('the link'))).user);
    final CleanupToken unlink = ledger.register(
      'unlink phone',
      () => _unlink('phone'),
    );
    log('  Linked ${maskPhone(number)}.');
    await auth.signOut();
    final ConfirmationResult signIn = await _withProof(
      () => auth.signInWithPhoneNumber(number),
    );
    _expectPrimary((await signIn.confirm(await _smsCode('the sign-in'))).user);
    final String verificationId = await _withProof(
      () => _sendCode(phoneNumber: number),
    );
    _expectPrimary(
      (await auth.currentUser!.reauthenticateWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: await _smsCode('the reauthentication'),
        ),
      )).user,
    );
    await ledger.run(unlink);
    return 'link, sign-in, reauthentication and unlink; proof: '
        '${proofMode.label}';
  }

  Future<String?> _sms() async {
    final (String number, _) = _testPhone();
    final User user = await ensurePrimary();
    await _withRecentLogin(() async {
      final String verificationId = await _withProof(
        () async => _sendCode(
          phoneNumber: number,
          session: await user.multiFactor.getSession(),
        ),
      );
      await user.multiFactor.enroll(
        PhoneMultiFactorGenerator.getAssertion(
          PhoneAuthProvider.credential(
            verificationId: verificationId,
            smsCode: await _smsCode('the second-factor enrolment'),
          ),
        ),
        displayName: smsDisplayName,
      );
    });
    final CleanupToken unenrol = ledger.register(
      'unenrol the SMS factor "$smsDisplayName"',
      () => _unenrolFactorNamed(smsDisplayName),
    );
    final String factorUid =
        (await _factorNamed(user, smsDisplayName))?.uid ??
        (throw StepFailure('enrolled-factor-not-listed'));
    await auth.signOut();
    try {
      await auth.signInWithProvider(GoogleAuthProvider());
      throw StepFailure('no-second-factor-challenge');
    } on FirebaseAuthMultiFactorException catch (e) {
      _expectPrimary((await resolveSms(e.resolver, factorUid: factorUid)).user);
    }
    await ledger.run(unenrol);
    return 'enrol, sign-in through the resolver and unenrol; proof: '
        '${proofMode.label}';
  }

  Future<String?> _revoke() async {
    await ensurePrimary();
    try {
      await auth.revokeAccessToken(placeholderAppleToken);
    } on DartFirebaseAuthException catch (e) {
      if (e.httpStatus == null) {
        rethrow;
      }
      throw StepSkipped(
        'Apple-only (needs a Sign in with Apple access token); the request '
        'reached the backend, which refused the placeholder token: '
        '${describeError(e)}',
      );
    }
    throw StepSkipped(
      'Apple-only (needs a Sign in with Apple access token); the backend '
      'accepted the placeholder token, so nothing was checked',
    );
  }

  Future<String?> _persistence() async {
    await ensurePrimary();
    if (!await storage.holdsSession()) {
      throw StepFailure('no-session-in-storage-before');
    }
    await auth.setPersistence(Persistence.NONE);
    final CleanupToken restore = ledger.register(
      'setPersistence(LOCAL)',
      () => auth.setPersistence(Persistence.LOCAL),
    );
    if (await storage.holdsSession()) {
      throw StepFailure('session-still-in-storage-after-none');
    }
    _expectPrimary(auth.currentUser);
    await auth.currentUser!.getIdToken(true);
    await ledger.run(restore);
    if (!await storage.holdsSession()) {
      throw StepFailure('no-session-in-storage-after-local');
    }
    _expectPrimary(auth.currentUser);
    return null;
  }
}
