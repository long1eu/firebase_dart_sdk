import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;

import 'convert.dart';
import 'firebase_auth.dart';
import 'package:firebase_auth_dart_platform/src/phone.dart';

import 'multi_factor.dart';

/// A user of [DartFirebaseAuth]: a snapshot of the client's user. Its
/// operations act on the signed-in user, and throw `no-current-user` once
/// another user (or nobody) is signed in, like the native implementations.
class DartUser extends UserPlatform {
  DartUser(DartFirebaseAuth auth, this.source)
    : _auth = auth,
      super(auth, DartMultiFactor(auth, source.uid), userDetailsOf(source));

  final DartFirebaseAuth _auth;

  /// The user of `firebase_auth_providers_dart` this one shows.
  final dart_auth.AuthUser source;

  dart_auth.FirebaseUserAuth get _client => _auth.clientFor(uid);

  @override
  Future<void> delete() => guard(_auth, () => _client.deleteCurrentUser());

  @override
  Future<String?> getIdToken(bool forceRefresh) => guard(
    _auth,
    () async =>
        (await _client.getAccessToken(forceRefresh: forceRefresh)).token,
  );

  @override
  Future<IdTokenResult> getIdTokenResult(bool forceRefresh) => guard(
    _auth,
    () async => idTokenResultOf(
      await _client.getAccessToken(forceRefresh: forceRefresh),
    ),
  );

  @override
  Future<UserCredentialPlatform> linkWithCredential(
    AuthCredential credential,
  ) => guard(
    _auth,
    () async => _auth.resultOf(
      await _client.linkWithCredential(clientCredentialOf(credential)),
    ),
  );

  @override
  Future<UserCredentialPlatform> reauthenticateWithCredential(
    AuthCredential credential,
  ) => guard(
    _auth,
    () async => _auth.resultOf(
      await _client.reauthenticateWithCredential(
        clientCredentialOf(credential),
      ),
    ),
  );

  @override
  Future<void> reload() => guard(_auth, () => _client.reload());

  @override
  Future<void> sendEmailVerification(ActionCodeSettings? actionCodeSettings) =>
      guard(
        _auth,
        () => _client.sendEmailVerification(
          actionCodeSettings: actionCodeSettingsOf(actionCodeSettings),
        ),
      );

  @override
  Future<UserPlatform> unlink(String providerId) =>
      guard(_auth, () async => _auth.userOf(await _client.unlink(providerId))!);

  @override
  Future<void> updateEmail(String newEmail) =>
      guard(_auth, () => _client.updateEmail(newEmail));

  @override
  Future<void> updatePassword(String newPassword) =>
      guard(_auth, () => _client.updatePassword(newPassword));

  /// `firebase_auth` passes the fields to change; a null value removes the
  /// field. The client keeps a field for null and removes it for an empty
  /// string.
  @override
  Future<void> updateProfile(Map<String, String?> profile) => guard(_auth, () {
    String? valueOf(String key) =>
        profile.containsKey(key) ? profile[key] ?? '' : null;
    return _client.updateProfile(
      displayName: valueOf('displayName'),
      photoUrl: valueOf('photoURL'),
    );
  });

  @override
  Future<void> verifyBeforeUpdateEmail(
    String newEmail, [
    ActionCodeSettings? actionCodeSettings,
  ]) => guard(
    _auth,
    () => _client.verifyBeforeUpdateEmail(
      newEmail,
      actionCodeSettings: actionCodeSettingsOf(actionCodeSettings),
    ),
  );

  /// Links the provider through the system browser and a loopback redirect,
  /// with the `OAuthLoopbackProvider` passed to `FirebaseAuthDart.use` for the
  /// id of [provider] (see `DartFirebaseAuth.signInWithProvider`).
  @override
  Future<UserCredentialPlatform> linkWithProvider(AuthProvider provider) =>
      guard(_auth, () async {
        final dart_auth.FirebaseUserAuth userAuth = _client;
        final dart_auth.OAuthLoopbackProvider loopback = _auth
            .loopbackProviderFor('linkWithProvider', provider);
        return _auth.resultOf(
          await userAuth.linkWithOAuthLoopback(
            loopback,
            presenter: _auth.presenter,
          ),
        );
      });

  /// Signs this user in again through the system browser and a loopback
  /// redirect, with the `OAuthLoopbackProvider` passed to
  /// `FirebaseAuthDart.use` for the id of [provider] (see
  /// `DartFirebaseAuth.signInWithProvider`).
  @override
  Future<UserCredentialPlatform> reauthenticateWithProvider(
    AuthProvider provider,
  ) => guard(_auth, () async {
    final dart_auth.FirebaseUserAuth userAuth = _client;
    final dart_auth.OAuthLoopbackProvider loopback = _auth.loopbackProviderFor(
      'reauthenticateWithProvider',
      provider,
    );
    return _auth.resultOf(
      await userAuth.reauthenticateWithOAuthLoopback(
        loopback,
        presenter: _auth.presenter,
      ),
    );
  });

  /// Sends the SMS code to [phoneNumber] with the proof of
  /// `DartFirebaseAuth.appVerification`; the `confirm` of the result links the
  /// number to this user. [applicationVerifier] is not used. Like the JS SDK,
  /// it reads the account first and throws `provider-already-linked`, before
  /// any SMS, when the user has a phone number already.
  @override
  Future<ConfirmationResultPlatform> linkWithPhoneNumber(
    String phoneNumber,
    RecaptchaVerifierFactoryPlatform applicationVerifier,
  ) => guard(_auth, () async {
    final dart_auth.FirebaseUserAuth userAuth = _client;
    await userAuth.reload();
    if (userAuth.currentUser?.providerData.any(
          (dart_auth.UserInfo info) => info.providerId == 'phone',
        ) ??
        false) {
      throw FirebaseAuthException(
        code: 'provider-already-linked',
        message:
            'User can only be linked to one identity for the given provider.',
      );
    }
    final String verificationId = await userAuth.verifyPhoneNumber(
      phoneNumber,
      appVerification: _auth.appVerification,
    );
    return DartConfirmationResult(
      _auth,
      verificationId,
      (dart_auth.PhoneAuthCredential credential) =>
          _auth.clientFor(uid).linkWithCredential(credential),
    );
  });

  @override
  Future<void> updatePhoneNumber(PhoneAuthCredential phoneCredential) => guard(
    _auth,
    () => _client.updatePhoneNumber(clientPhoneCredentialOf(phoneCredential)),
  );

  // ---- not available: see the README ----

  @override
  Future<UserCredentialPlatform> linkWithPopup(AuthProvider provider) async =>
      throw unimplemented('linkWithPopup', noBrowserFlow);

  @override
  Future<void> linkWithRedirect(AuthProvider provider) async =>
      throw unimplemented('linkWithRedirect', noBrowserFlow);

  @override
  Future<UserCredentialPlatform> reauthenticateWithPopup(
    AuthProvider provider,
  ) async => throw unimplemented('reauthenticateWithPopup', noBrowserFlow);

  @override
  Future<void> reauthenticateWithRedirect(AuthProvider provider) async =>
      throw unimplemented('reauthenticateWithRedirect', noBrowserFlow);
}

/// The result of a sign-in, a link or a reauthentication.
class DartUserCredential extends UserCredentialPlatform {
  DartUserCredential({
    required super.auth,
    super.additionalUserInfo,
    super.credential,
    super.user,
  });
}
