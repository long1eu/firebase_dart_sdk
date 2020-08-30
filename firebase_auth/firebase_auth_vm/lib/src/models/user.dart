// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of firebase_auth_vm;

/// Represents user data returned from an identity provider.
class UserInfo {
  const UserInfo._({
    this.uid,
    this.providerId,
    this.displayName,
    this.photoUrl,
    this.email,
    this.phoneNumber,
    this.isEmailVerified,
  });

  factory UserInfo._fromJson(Map<String, dynamic> json) {
    return UserInfo._(
      uid: json['uid'],
      providerId: json['providerId'],
      displayName: json['displayName'],
      photoUrl: json['photoUrl'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      isEmailVerified: json['isEmailVerified'],
    );
  }

  /// The provider's user ID for the user.
  /*@nullable*/
  final String uid;

  /// The provider identifier.
  /*@nullable*/
  final String providerId;

  /// The name of the user.
  /*@nullable*/
  final String displayName;

  /// The URL of the user's profile photo.
  /*@nullable*/
  final String photoUrl;

  /// The user's email address.
  /*@nullable*/
  final String email;

  /// A phone number associated with the user.
  ///
  /// This property is only available for users authenticated via phone number auth.
  /*@nullable*/
  final String phoneNumber;

  /// Indicates the email address associated with this user has been verified.
  /*@nullable*/
  final bool isEmailVerified;

  @override
  String toString() {
    return (ToStringHelper(UserInfo)
          ..add('uid', uid)
          ..add('providerId', providerId)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('email', email)
          ..add('phoneNumber', phoneNumber)
          ..add('isEmailVerified', isEmailVerified))
        .toString();
  }
}

extension UserInfoExtension on UserInfo {
  Map<String, dynamic> get _json {
    return <String, dynamic>{
      if (uid != null) 'uid': uid,
      if (providerId != null) 'providerId': providerId,
      if (displayName != null) 'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (email != null) 'email': email,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (isEmailVerified != null) 'isEmailVerified': isEmailVerified,
    };
  }

  UserInfo _copyWith({
    String uid,
    String providerId,
    String displayName,
    String photoUrl,
    String email,
    String phoneNumber,
    bool isEmailVerified,
    bool removePhoneNumber = false,
  }) {
    return UserInfo._(
      uid: uid ?? this.uid,
      providerId: providerId ?? this.providerId,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      email: email ?? this.email,
      phoneNumber: removePhoneNumber ? null : phoneNumber ?? this.phoneNumber,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    );
  }
}

mixin UserInfoMixin implements UserInfo {
  UserInfo _userInfo;

  @override
  String get uid => _userInfo.uid;

  @override
  String get providerId => _userInfo.providerId;

  @override
  String get displayName => _userInfo.displayName;

  @override
  String get photoUrl => _userInfo.photoUrl;

  @override
  String get email => _userInfo.email;

  @override
  String get phoneNumber => _userInfo.phoneNumber;

  @override
  bool get isEmailVerified => _userInfo.isEmailVerified;
}

/// Represents additional user data returned from an identity provider.
class AdditionalUserInfo {
  AdditionalUserInfo._({
    this.providerId,
    this.profile,
    this.username,
    @required this.isNewUser,
  });

  factory AdditionalUserInfo.newAnonymous() {
    return AdditionalUserInfo._(isNewUser: true);
  }

  factory AdditionalUserInfo.fromVerifyAssertionResponse(VerifyAssertionResponse response) {
    return AdditionalUserInfo._(
      providerId: response.providerId,
      profile: response.rawUserInfo != null ? Map<String, dynamic>.from(jsonDecode(response.rawUserInfo)) : null,
      username: response.screenName,
      isNewUser: response.isNewUser ?? false,
    );
  }

  /// Returns the provider ID for specifying which provider the information in [profile] is for.
  /*@nullable*/
  final String providerId;

  /// Returns a Map containing IDP-specific user data if the provider is one of Facebook, GitHub, Google, Twitter,
  /// Microsoft, or Yahoo.
  /*@nullable*/
  final Map<String, Object> profile;

  /// Returns the username if the provider is GitHub or Twitter
  /*@nullable*/
  final String username;

  /// Indicates whether or not the current user was signed in for the first time.
  final bool isNewUser;

  @override
  String toString() {
    return (ToStringHelper(AdditionalUserInfo)
          ..add('providerId', providerId)
          ..add('profile', profile)
          ..add('username', username)
          ..add('isNewUser', isNewUser))
        .toString();
  }
}

/// A data class representing the metadata corresponding to a Firebase user.
class UserMetadata {
  const UserMetadata._({
    @required this.lastSignInDate,
    @required this.creationDate,
  });

  factory UserMetadata._fromJson(Map<String, dynamic> json) {
    return UserMetadata._(
      lastSignInDate: DateTime.fromMicrosecondsSinceEpoch(json['lastSignInDate']),
      creationDate: DateTime.fromMicrosecondsSinceEpoch(json['creationDate']),
    );
  }

  /// Stores the last sign in date for the corresponding Firebase user.
  final DateTime lastSignInDate;

  /// Stores the creation date for the corresponding Firebase user.
  final DateTime creationDate;

  Map<String, dynamic> get _json {
    return <String, dynamic>{
      'lastSignInDate': lastSignInDate.microsecondsSinceEpoch,
      'creationDate': creationDate.microsecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(UserMetadata) //
          ..add('lastSignInDate', lastSignInDate)
          ..add('creationDate', creationDate))
        .toString();
  }
}
