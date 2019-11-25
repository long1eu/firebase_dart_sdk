// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of models;

abstract class UpdateRequest implements Built<UpdateRequest, UpdateRequestBuilder> {
  factory UpdateRequest.changeEmail({
    @required String idToken,
    @required String newEmail,
    @required bool returnSecureToken,
  }) {
    return _$UpdateRequest((UpdateRequestBuilder b) {
      b
        ..idToken = idToken
        ..email = newEmail
        ..returnSecureToken = returnSecureToken;
    });
  }

  factory UpdateRequest.changePassword({
    @required String idToken,
    @required String newPassword,
    @required bool returnSecureToken,
  }) {
    return _$UpdateRequest((UpdateRequestBuilder b) {
      b
        ..idToken = idToken
        ..password = newPassword
        ..returnSecureToken = returnSecureToken;
    });
  }

  factory UpdateRequest.updateProfile({
    @required String idToken,
    String newDisplayName,
    String newPhotoUrl,
    List<ProfileAttribute> deleteAttribute,
    @required bool returnSecureToken,
  }) {
    return _$UpdateRequest((UpdateRequestBuilder b) {
      b
        ..idToken = idToken
        ..displayName = newDisplayName
        ..photoUrl = newPhotoUrl
        ..deleteAttribute =
            deleteAttribute == null || deleteAttribute.isEmpty ? null : ListBuilder<ProfileAttribute>(deleteAttribute)
        ..returnSecureToken = returnSecureToken;
    });
  }

  factory UpdateRequest.linkEmailAndPassword({
    @required String idToken,
    @required String email,
    @required String password,
    @required bool returnSecureToken,
  }) {
    return _$UpdateRequest((UpdateRequestBuilder b) {
      b
        ..idToken = idToken
        ..email = email
        ..password = password
        ..returnSecureToken = returnSecureToken;
    });
  }

  factory UpdateRequest.unlinkProvider({
    @required String idToken,
    @required List<ProviderType> deleteProvider,
  }) {
    return _$UpdateRequest((UpdateRequestBuilder b) {
      b
        ..idToken = idToken
        ..deleteProvider = ListBuilder<ProviderType>(deleteProvider);
    });
  }

  factory UpdateRequest.confirmEmailVerification({@required String oobCode}) {
    return _$UpdateRequest((UpdateRequestBuilder b) {
      b.oobCode = oobCode;
    });
  }

  factory UpdateRequest.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  UpdateRequest._();

  /// A Firebase Auth ID token for the user.
  @nullable
  String get idToken;

  /// The user's email.
  @nullable
  String get email;

  /// User's password.
  @nullable
  String get password;

  /// User's display name.
  @nullable
  String get displayName;

  /// User's photo url.
  @nullable
  String get photoUrl;

  /// List of attributes to delete. This will nullify these values.
  @nullable
  BuiltList<ProfileAttribute> get deleteAttribute;

  /// Whether or not to return an ID and refresh token.
  @nullable
  bool get returnSecureToken;

  /// The list of provider IDs to unlink, eg: 'google.com', 'password', etc.
  @nullable
  BuiltList<ProviderType> get deleteProvider;

  /// The action code sent to user's email for email verification.
  @nullable
  String get oobCode;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<UpdateRequest> get serializer => _$updateRequestSerializer;
}

abstract class UpdateResponse implements Built<UpdateResponse, UpdateResponseBuilder> {
  factory UpdateResponse([void Function(UpdateResponseBuilder b) updates]) = _$UpdateResponse;

  factory UpdateResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  UpdateResponse._();

  /// The uid of the current user.
  @nullable
  String get localId;

  /// User's email address.
  String get email;

  /// User's display name.
  @nullable
  String get displayName;

  /// User's new photo url.
  @nullable
  String get photoUrl;

  /// Hash version of the password.
  String get passwordHash;

  /// List of all linked provider objects which contain "providerId" and "federatedId".
  BuiltList<ProviderUserInfo> get providerUserInfo;

  /// New Firebase Auth ID token for user.
  String get idToken;

  /// A Firebase Auth refresh token.
  String get refreshToken;

  /// The number of seconds in which the ID token expires.
  String get expiresIn;

  /// Whether or not the account's email has been verified.
  @nullable
  bool get emailVerified;

  static Serializer<UpdateResponse> get serializer => _$updateResponseSerializer;
}

abstract class ProviderUserInfo implements Built<ProviderUserInfo, ProviderUserInfoBuilder> {
  factory ProviderUserInfo() = _$ProviderUserInfo;

  ProviderUserInfo._();

  /// The ID of the identity provider.
  ProviderType get providerId;

  ///	The user's display name at the identity provider.
  @nullable
  String get displayName;

  ///	The user's photo URL at the identity provider.
  @nullable
  String get photoUrl;

  /// The user's identifier at the identity provider.
  String get federatedId;

  ///	The user's email at the identity provider.
  @nullable
  String get email;

  ///	A phone number associated with the user.
  @nullable
  String get phoneNumber;

  @memoized
  UserInfo get userInfo {
    return UserInfoImpl(
      providerId: providerId,
      uid: federatedId,
      displayName: displayName,
      photoUrl: photoUrl,
      email: email,
      phoneNumber: phoneNumber,
    );
  }

  static Serializer<ProviderUserInfo> get serializer => _$providerUserInfoSerializer;
}

class ProfileAttribute {
  const ProfileAttribute._(this._i, this._value);

  final String _value;
  final int _i;

  static const ProfileAttribute displayName = ProfileAttribute._(0, 'DISPLAY_NAME');
  static const ProfileAttribute photoUrl = ProfileAttribute._(1, 'PHOTO_URL');

  static const List<ProfileAttribute> values = <ProfileAttribute>[displayName, photoUrl];
  static const List<String> _names = <String>['displayName', 'photoUrl'];

  static Serializer<ProfileAttribute> get serializer => _$ProfileAttributeSerializer;

  @override
  String toString() => 'ProfileAttribute.${_names[_i]}';
}

Serializer<ProfileAttribute> _$ProfileAttributeSerializer = _ProfileAttributeSerializer();

class _ProfileAttributeSerializer extends PrimitiveSerializer<ProfileAttribute> {
  @override
  Iterable<Type> get types => BuiltList<Type>(<Type>[ProfileAttribute]);

  @override
  String get wireName => 'ProfileAttribute';

  @override
  ProfileAttribute deserialize(Serializers serializers, Object serialized,
      {FullType specifiedType = FullType.unspecified}) {
    return ProfileAttribute.values.firstWhere((ProfileAttribute it) => it._value == serialized);
  }

  @override
  Object serialize(Serializers serializers, ProfileAttribute object, {FullType specifiedType = FullType.unspecified}) {
    return object._value;
  }
}
