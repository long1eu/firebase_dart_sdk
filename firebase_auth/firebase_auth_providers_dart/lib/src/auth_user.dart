import 'firebase_user_auth.dart';

/// The signed-in user of a [FirebaseUserAuth]: [FirebaseUserAuth.currentUser], the result of a sign-in, and the
/// events of [FirebaseUserAuth.userChanges()].
///
/// An immutable snapshot: a change (a [FirebaseUserAuth.updateProfile], a [FirebaseUserAuth.reload]) produces a new
/// object. Two users are equal when all their fields are. [toString] shows only [uid] and [isAnonymous].
///
/// The fields follow FlutterFire's `User` (and the JS SDK's): [providerData], [metadata], [phoneNumber] and
/// [tenantId] are read from the account (`accounts:lookup`) after every sign-in and [FirebaseUserAuth.reload].
///
/// ```dart
/// final AuthUser user = await auth.signInAnonymously();
/// print('${user.uid} anonymous: ${user.isAnonymous}'); // anonymous: true
/// auth.userChanges().listen((AuthUser? user) => print(user?.email ?? 'signed out'));
/// ```
class AuthUser {
  /// Creates a user. [FirebaseUserAuth] creates them; you need this only for tests.
  const AuthUser({
    required this.uid,
    this.email,
    this.isAnonymous = false,
    this.emailVerified = false,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
    this.tenantId,
    this.metadata = const UserMetadata(),
    this.providerData = const <UserInfo>[],
  });

  /// The id of the user.
  final String uid;

  /// The email address of the user, when the account has one.
  final String? email;

  /// Whether the user signed in anonymously (and has not added an email address and a password, or a provider,
  /// since).
  final bool isAnonymous;

  /// Whether the email address was verified. Up to date after a sign-in and after [FirebaseUserAuth.reload].
  final bool emailVerified;

  /// The display name of the user, when it has one.
  final String? displayName;

  /// The URL of the photo of the user, when it has one.
  final String? photoUrl;

  /// [photoUrl] under the name of FlutterFire and the JS SDK.
  String? get photoURL => photoUrl;

  /// The phone number of the account (E.164), when it has one.
  final String? phoneNumber;

  /// The tenant of the user (Identity Platform multi-tenancy), or null for a user of the project itself.
  final String? tenantId;

  /// When the account was created and when the user last signed in.
  final UserMetadata metadata;

  /// The sign-in methods linked to the account, one per provider (`password`, `google.com`, `phone`, ...).
  /// An anonymous user has none.
  final List<UserInfo> providerData;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          uid == other.uid &&
          email == other.email &&
          isAnonymous == other.isAnonymous &&
          emailVerified == other.emailVerified &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl &&
          phoneNumber == other.phoneNumber &&
          tenantId == other.tenantId &&
          metadata == other.metadata &&
          _listEquals(providerData, other.providerData);

  @override
  int get hashCode => Object.hash(
    uid,
    email,
    isAnonymous,
    emailVerified,
    displayName,
    photoUrl,
    phoneNumber,
    tenantId,
    metadata,
    Object.hashAll(providerData),
  );

  @override
  String toString() => 'AuthUser(uid: $uid, isAnonymous: $isAnonymous)';
}

bool _listEquals(List<UserInfo> a, List<UserInfo> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// One sign-in method linked to an account: an entry of [AuthUser.providerData] (`UserInfo` of FlutterFire and of
/// the JS SDK).
class UserInfo {
  /// Creates the information. [FirebaseUserAuth] creates them; you need this only for tests.
  const UserInfo({
    required this.providerId,
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
  });

  /// The provider: `password`, `phone`, `google.com`, `apple.com`, `oidc.<name>`, ...
  final String providerId;

  /// The id of the user at the provider (for `password` the email address), or an empty string when the backend
  /// did not say.
  final String uid;

  /// The email address at the provider.
  final String? email;

  /// The display name at the provider.
  final String? displayName;

  /// The URL of the photo at the provider.
  final String? photoUrl;

  /// [photoUrl] under the name of FlutterFire and the JS SDK.
  String? get photoURL => photoUrl;

  /// The phone number, for the `phone` provider.
  final String? phoneNumber;

  @override
  bool operator ==(Object other) =>
      other is UserInfo &&
      providerId == other.providerId &&
      uid == other.uid &&
      email == other.email &&
      displayName == other.displayName &&
      photoUrl == other.photoUrl &&
      phoneNumber == other.phoneNumber;

  @override
  int get hashCode =>
      Object.hash(providerId, uid, email, displayName, photoUrl, phoneNumber);

  @override
  String toString() => 'UserInfo($providerId)';
}

/// When an account was created and when its user last signed in ([AuthUser.metadata]; `UserMetadata` of
/// FlutterFire and of the JS SDK). Both are UTC, or null when the backend did not say (and for a session stored by
/// 0.2 until the first [FirebaseUserAuth.reload]).
class UserMetadata {
  /// Creates the metadata. [FirebaseUserAuth] creates them; you need this only for tests.
  const UserMetadata({this.creationTime, this.lastSignInTime});

  /// When the account was created.
  final DateTime? creationTime;

  /// When the user last signed in.
  final DateTime? lastSignInTime;

  @override
  bool operator ==(Object other) =>
      other is UserMetadata &&
      creationTime == other.creationTime &&
      lastSignInTime == other.lastSignInTime;

  @override
  int get hashCode => Object.hash(creationTime, lastSignInTime);

  @override
  String toString() =>
      'UserMetadata(creationTime: $creationTime, lastSignInTime: $lastSignInTime)';
}

/// What a sign-in tells beyond the user (`AdditionalUserInfo` of FlutterFire and `getAdditionalUserInfo` of the JS
/// SDK): [UserCredential.additionalUserInfo].
class AdditionalUserInfo {
  /// Creates the information. [FirebaseUserAuth] creates them; you need this only for tests.
  const AdditionalUserInfo({
    required this.isNewUser,
    this.providerId,
    this.profile,
    this.username,
  });

  /// Whether the sign-in created the account.
  final bool isNewUser;

  /// The provider of the sign-in (`password`, `google.com`, ...); null for anonymous and custom token sign-ins.
  final String? providerId;

  /// The profile the identity provider returned (`rawUserInfo` of the backend), for federated sign-ins; null
  /// otherwise. It is personal data: [toString] leaves it out.
  final Map<String, Object?>? profile;

  /// The user name at GitHub (`login`) or Twitter (screen name), for those providers.
  final String? username;

  @override
  String toString() =>
      'AdditionalUserInfo(isNewUser: $isNewUser, providerId: $providerId)';
}

/// The result of a sign-in, a link or a reauthentication (FlutterFire's `UserCredential`).
///
/// For compatibility with 0.2, whose sign-in methods returned an [AuthUser], it is also the signed-in user: the
/// fields of [AuthUser] are those of [user], and `final AuthUser user = await auth.signInAnonymously();` still
/// works. Equality is that of [AuthUser] (the extra fields do not count).
///
/// ```dart
/// final UserCredential result = await auth.signInAnonymously();
/// print(result.user?.uid);
/// print(result.additionalUserInfo?.isNewUser); // true
/// ```
class UserCredential extends AuthUser {
  /// Creates the result for [user]. [FirebaseUserAuth] creates them; you need this only for tests.
  UserCredential(AuthUser user, {this.additionalUserInfo})
    : _user = user,
      super(
        uid: user.uid,
        email: user.email,
        isAnonymous: user.isAnonymous,
        emailVerified: user.emailVerified,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        phoneNumber: user.phoneNumber,
        tenantId: user.tenantId,
        metadata: user.metadata,
        providerData: user.providerData,
      );

  final AuthUser _user;

  /// The signed-in user. Never null; typed as in FlutterFire (`userCredential.user!.uid` compiles).
  AuthUser? get user => _user;

  /// What the sign-in told beyond the user: whether the account is new, the provider and its profile.
  final AdditionalUserInfo? additionalUserInfo;

  @override
  String toString() => 'UserCredential(uid: $uid, isAnonymous: $isAnonymous)';
}
