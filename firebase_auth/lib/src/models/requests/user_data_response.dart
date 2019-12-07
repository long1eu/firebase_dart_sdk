// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of requests;

abstract class UserDataResponse implements Built<UserDataResponse, UserDataResponseBuilder> {
  factory UserDataResponse([void Function(UserDataResponseBuilder b) updates]) = _$UserDataResponse;

  factory UserDataResponse.fromJson(Map<dynamic, dynamic> json) {
    return serializers.deserializeWith(serializer, json);
  }

  UserDataResponse._();

  ///	The uid of the current user.
  String get localId;

  ///	The email of the account.
  @nullable
  String get email;

  ///	Whether or not the account's email has been verified.
  @nullable
  bool get emailVerified;

  ///	The display name for the account.
  @nullable
  String get displayName;

  ///	List of all linked provider objects which contain "providerId" and "federatedId".
  BuiltList<ProviderUserInfo> get providerUserInfo;

  ///	The photo Url for the account.
  @nullable
  String get photoUrl;

  ///	The phone number for the account.
  @nullable
  String get phoneNumber;

  ///	Hash version of password.
  @nullable
  String get passwordHash;

  ///	The timestamp, in milliseconds, that the account password was last changed.
  @nullable
  double get passwordUpdatedAt;

  ///	The timestamp, in seconds, which marks a boundary, before which Firebase ID token are considered revoked.
  @nullable
  int get validSince;

  ///	Whether the account is disabled or not.
  @nullable
  bool get disabled;

  ///	The timestamp, in milliseconds, that the account last logged in at.
  int get lastLoginAt;

  ///	The timestamp, in milliseconds, that the account was created at.
  int get createdAt;

  ///	Whether the account is authenticated by the developer.
  @nullable
  bool get customAuth;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<UserDataResponse> get serializer => _$userDataResponseSerializer;
}
