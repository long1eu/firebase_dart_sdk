// The steps of the real-project harness, through the official firebase_auth
// API on top of this package. Each one leaves the account as it found it,
// through the CleanupLedger; none deletes an account.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage;

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
      credential = await resolveTotp(e.resolver);
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
      credential = await resolveTotp(e.resolver);
    }
    _expectPrimary(credential.user);
    return null;
  }

  Future<String?> _totp() async {
    final User user = await ensurePrimary();
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
    final CleanupToken unenrol = ledger.register(
      'unenrol the TOTP factor "$totpDisplayName"',
      _unenrolHarnessFactor,
    );
    final String factorUid =
        (await _harnessFactor(user))?.uid ??
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

  /// The factor the harness enrolled, newest first if there are several.
  Future<MultiFactorInfo?> _harnessFactor(User user) async {
    final List<MultiFactorInfo> factors = await user.multiFactor
        .getEnrolledFactors();
    return factors.reversed
        .where((MultiFactorInfo info) => info.displayName == totpDisplayName)
        .firstOrNull;
  }

  Future<void> _unenrolHarnessFactor() async {
    final User user = await ensurePrimary();
    final MultiFactorInfo? factor = await _harnessFactor(user);
    if (factor != null) {
      await user.multiFactor.unenroll(factorUid: factor.uid);
    }
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
