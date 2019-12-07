// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of models;

abstract class AdditionalUserInfoImpl
    implements Built<AdditionalUserInfoImpl, AdditionalUserInfoImplBuilder>, AdditionalUserInfo {
  factory AdditionalUserInfoImpl({
    String providerId,
    Map<String, dynamic> profile,
    String username,
    bool isNewUser,
  }) {
    MapBuilder<String, JsonObject> data;
    if (profile != null) {
      data = MapBuilder<String, JsonObject>();
      for (String key in profile.keys) {
        data[key] = JsonObject(profile[key]);
      }
    }

    return _$AdditionalUserInfoImpl((AdditionalUserInfoImplBuilder b) {
      b
        ..providerId = providerId
        ..profile = data
        ..username = username
        ..isNewUser = isNewUser;
    });
  }

  factory AdditionalUserInfoImpl.newAnonymous() {
    return _$AdditionalUserInfoImpl((AdditionalUserInfoImplBuilder b) => b.isNewUser = true);
  }

  factory AdditionalUserInfoImpl.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  AdditionalUserInfoImpl._();

  static Serializer<AdditionalUserInfoImpl> get serializer => _$additionalUserInfoImplSerializer;
}

abstract class UserInfoImpl implements Built<UserInfoImpl, UserInfoImplBuilder>, UserInfo {
  factory UserInfoImpl({
    String uid,
    String providerId,
    String displayName,
    String photoUrl,
    String email,
    String phoneNumber,
    bool isEmailVerified,
  }) {
    return _$UserInfoImpl((UserInfoImplBuilder b) {
      b
        ..uid = uid
        ..providerId = providerId
        ..displayName = displayName
        ..photoUrl = photoUrl
        ..email = email
        ..phoneNumber = phoneNumber
        ..isEmailVerified = isEmailVerified;
    });
  }

  factory UserInfoImpl.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  UserInfoImpl._();

  UserInfoImpl copyWith({
    String uid,
    String providerId,
    String displayName,
    String photoUrl,
    String email,
    String phoneNumber,
    bool isEmailVerified,
  }) {
    return _$UserInfoImpl((UserInfoImplBuilder b) {
      b
        ..uid = uid ?? this.uid
        ..providerId = providerId ?? this.providerId
        ..displayName = displayName ?? this.displayName
        ..photoUrl = photoUrl ?? this.photoUrl
        ..email = email ?? this.email
        ..phoneNumber = phoneNumber ?? this.phoneNumber
        ..isEmailVerified = isEmailVerified ?? this.isEmailVerified;
    });
  }

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<UserInfoImpl> get serializer => _$userInfoImplSerializer;
}

abstract class UserMetadataImpl implements Built<UserMetadataImpl, UserMetadataImplBuilder>, UserMetadata {
  factory UserMetadataImpl({
    @required DateTime lastSignInDate,
    @required DateTime creationDate,
  }) {
    return _$UserMetadataImpl((UserMetadataImplBuilder b) {
      b
        ..lastSignInDate = lastSignInDate
        ..creationDate = creationDate;
    });
  }

  factory UserMetadataImpl.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  UserMetadataImpl._();

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<UserMetadataImpl> get serializer => _$userMetadataImplSerializer;
}
