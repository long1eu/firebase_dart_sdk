// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of firebase_auth;

/// Represents user data returned from an identity provider.
abstract class UserInfo {
  const UserInfo._();

  /// The provider's user ID for the user.
  String get uid;

  /// The provider identifier.
  @nullable
  String get providerId;

  /// The name of the user.
  @nullable
  String get displayName;

  /// The URL of the user's profile photo.
  @nullable
  String get photoUrl;

  /// The user's email address.
  @nullable
  String get email;

  /// A phone number associated with the user.
  ///
  /// This property is only available for users authenticated via phone number auth.
  @nullable
  String get phoneNumber;

  /// Indicates the email address associated with this user has been verified.
  @nullable
  bool get isEmailVerified;
}

/// Represents additional user data returned from an identity provider.
abstract class AdditionalUserInfo {
  const AdditionalUserInfo._();

  /// Returns the provider ID for specifying which provider the information in [profile] is for.
  @nullable
  String get providerId;

  /// Returns a Map containing IDP-specific user data if the provider is one of Facebook, GitHub, Google, Twitter,
  /// Microsoft, or Yahoo.
  @nullable
  MapBuilder<String, JsonObject> get profile;

  /// Returns the username if the provider is GitHub or Twitter
  @nullable
  String get username;

  /// Indicates whether or not the current user was signed in for the first time.
  bool get isNewUser;
}

/// A data class representing the metadata corresponding to a Firebase user.
abstract class UserMetadata {
  const UserMetadata._();

  /// Stores the last sign in date for the corresponding Firebase user.
  DateTime get lastSignInDate;

  /// Stores the creation date for the corresponding Firebase user.
  DateTime get creationDate;
}
