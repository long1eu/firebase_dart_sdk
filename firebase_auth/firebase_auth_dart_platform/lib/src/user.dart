import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;

import 'convert.dart';
import 'firebase_auth.dart';
import 'multi_factor.dart';

/// A user of [DartFirebaseAuth]: a snapshot of the client's user. Its
/// operations act on the signed-in user, and throw `no-current-user` once
/// another user (or nobody) is signed in, like the native implementations.
class DartUser extends UserPlatform {
  DartUser(DartFirebaseAuth auth, this.source)
    : _auth = auth,
      super(auth, DartMultiFactor(auth), userDetailsOf(source));

  final DartFirebaseAuth _auth;

  /// The user of `firebase_auth_providers_dart` this one shows.
  final dart_auth.AuthUser source;

  dart_auth.FirebaseUserAuth get _client {
    final dart_auth.FirebaseUserAuth userAuth = _auth.client;
    if (userAuth.uid != uid) {
      throw noCurrentUser();
    }
    return userAuth;
  }

  @override
  Future<void> delete() => guard(() => _client.deleteCurrentUser());

  @override
  Future<String?> getIdToken(bool forceRefresh) => guard(
    () async =>
        (await _client.getAccessToken(forceRefresh: forceRefresh)).token,
  );

  @override
  Future<IdTokenResult> getIdTokenResult(bool forceRefresh) => guard(
    () async => idTokenResultOf(
      await _client.getAccessToken(forceRefresh: forceRefresh),
    ),
  );

  @override
  Future<UserCredentialPlatform> linkWithCredential(
    AuthCredential credential,
  ) => guard(
    () async => _auth.resultOf(
      await _client.linkWithCredential(clientCredentialOf(credential)),
    ),
  );

  @override
  Future<UserCredentialPlatform> reauthenticateWithCredential(
    AuthCredential credential,
  ) => guard(
    () async => _auth.resultOf(
      await _client.reauthenticateWithCredential(
        clientCredentialOf(credential),
      ),
    ),
  );

  @override
  Future<void> reload() => guard(() => _client.reload());

  @override
  Future<void> sendEmailVerification(ActionCodeSettings? actionCodeSettings) =>
      guard(
        () => _client.sendEmailVerification(
          actionCodeSettings: actionCodeSettingsOf(actionCodeSettings),
        ),
      );

  @override
  Future<UserPlatform> unlink(String providerId) =>
      guard(() async => _auth.userOf(await _client.unlink(providerId))!);

  @override
  Future<void> updateEmail(String newEmail) =>
      guard(() => _client.updateEmail(newEmail));

  @override
  Future<void> updatePassword(String newPassword) =>
      guard(() => _client.updatePassword(newPassword));

  /// `firebase_auth` passes the fields to change; a null value removes the
  /// field. The client keeps a field for null and removes it for an empty
  /// string.
  @override
  Future<void> updateProfile(Map<String, String?> profile) => guard(() {
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
    () => _client.verifyBeforeUpdateEmail(
      newEmail,
      actionCodeSettings: actionCodeSettingsOf(actionCodeSettings),
    ),
  );

  // ---- not available: see the README ----

  @override
  Future<UserCredentialPlatform> linkWithProvider(
    AuthProvider provider,
  ) async => throw unimplemented('linkWithProvider', noProviderFlow);

  @override
  Future<UserCredentialPlatform> reauthenticateWithProvider(
    AuthProvider provider,
  ) async => throw unimplemented('reauthenticateWithProvider', noProviderFlow);

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

  @override
  Future<ConfirmationResultPlatform> linkWithPhoneNumber(
    String phoneNumber,
    RecaptchaVerifierFactoryPlatform applicationVerifier,
  ) async => throw unimplemented('linkWithPhoneNumber', noPhone);

  @override
  Future<void> updatePhoneNumber(PhoneAuthCredential phoneCredential) async =>
      throw unimplemented('updatePhoneNumber', noPhone);
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
