// File created by
// Lung Razvan <long1eu>
// on 01/09/2020

part of firebase_auth_dart;

/// Dart delegate implementation of [UserPlatform].
class UserDart extends platform.UserPlatform {
  /// Creates a new [UserDart] instance.
  UserDart._(platform.FirebaseAuthPlatform auth, this._user)
      : super(auth, <String, dynamic>{
          'displayName': _user.displayName,
          'email': _user.email,
          'emailVerified': _user.isEmailVerified,
          'isAnonymous': _user.isAnonymous,
          'metadata': <String, int>{
            'creationTime': _user.metadata.creationDate.millisecondsSinceEpoch,
            'lastSignInTime': _user.metadata.lastSignInDate.millisecondsSinceEpoch,
          },
          'phoneNumber': _user.phoneNumber,
          'photoURL': _user.photoUrl,
          'providerData': _user.providerData
              .map((dart.UserInfo userInfo) => <String, dynamic>{
                    'displayName': userInfo.displayName,
                    'email': userInfo.email,
                    'phoneNumber': userInfo.phoneNumber,
                    'providerId': userInfo.providerId,
                    'photoURL': userInfo.photoUrl,
                    'uid': userInfo.uid,
                  })
              .toList(),
          'refreshToken': _user.refreshToken,
          'tenantId': null, // TODO(long1eu): not supported on firebase_auth_vm
          'uid': _user.uid,
        });

  final dart.FirebaseUser _user;

  @override
  Future<void> delete() {
    try {
      return _user.delete();
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<String> getIdToken(bool forceRefresh) async {
    try {
      final platform.IdTokenResult result = await getIdTokenResult(forceRefresh);
      return result.token;
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.IdTokenResult> getIdTokenResult(bool forceRefresh) async {
    final dart.GetTokenResult tokenResult = await _user.getIdToken(forceRefresh: forceRefresh);
    return convertDartIdTokenResult(tokenResult);
  }

  @override
  Future<platform.UserCredentialPlatform> linkWithCredential(platform.AuthCredential credential) async {
    try {
      final dart.AuthCredential dartCredential = convertPlatformCredential(credential);
      final dart.AuthResult authResult = await _user.linkWithCredential(dartCredential);

      return UserCredentialDart._(auth, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.UserCredentialPlatform> reauthenticateWithCredential(platform.AuthCredential credential) async {
    try {
      final dart.AuthCredential dartCredential = convertPlatformCredential(credential);
      final dart.AuthResult authResult = await _user.reauthenticateWithCredential(dartCredential);

      return UserCredentialDart._(auth, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> reload() async {
    try {
      await _user.reload();
      auth.sendAuthChangesEvent(auth.app.name, auth.currentUser);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> sendEmailVerification(platform.ActionCodeSettings actionCodeSettings) {
    try {
      final dart.ActionCodeSettings codeSettings = convertPlatformActionCodeSettings(actionCodeSettings);
      return _user.sendEmailVerification(codeSettings);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.UserPlatform> unlink(String providerId) async {
    try {
      await _user.unlinkFromProvider(providerId);
      return this;
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> updateEmail(String newEmail) async {
    try {
      await _user.updateEmail(newEmail);
      auth.sendAuthChangesEvent(auth.app.name, auth.currentUser);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _user.updatePassword(newPassword);
      auth.sendAuthChangesEvent(auth.app.name, auth.currentUser);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> updatePhoneNumber(platform.PhoneAuthCredential phoneCredential) async {
    try {
      final dart.PhoneAuthCredential authCredential = convertPlatformCredential(phoneCredential);
      await _user.updatePhoneNumberCredential(authCredential);
      await _user.reload();
      auth.sendAuthChangesEvent(auth.app.name, auth.currentUser);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> updateProfile(Map<String, String> profile) async {
    try {
      final dart.UserUpdateInfo info = dart.UserUpdateInfo();
      if (profile.containsKey('displayName')) {
        info.displayName = profile['displayName'];
      }
      if (profile.containsKey('photoURL')) {
        info.photoUrl = profile['photoURL'];
      }

      await _user.updateProfile(info);
      auth.sendAuthChangesEvent(auth.app.name, auth.currentUser);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> verifyBeforeUpdateEmail(String newEmail, [platform.ActionCodeSettings actionCodeSettings]) async {
    final dart.ActionCodeSettings codeSettings = convertPlatformActionCodeSettings(actionCodeSettings);

    try {
      await _user.sendEmailVerificationBeforeUpdating(newEmail, codeSettings);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }
}
