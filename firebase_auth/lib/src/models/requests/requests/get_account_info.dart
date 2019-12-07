// File created by
// Lung Razvan <long1eu>
// on 05/12/2019

part of requests;

/// Represents the parameters for the getAccountInfo endpoint.
///
/// see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
abstract class GetAccountInfoRequest implements Built<GetAccountInfoRequest, GetAccountInfoRequestBuilder> {
  factory GetAccountInfoRequest(String accessToken) {
    return _$GetAccountInfoRequest((GetAccountInfoRequestBuilder b) => b.accessToken = accessToken);
  }

  GetAccountInfoRequest._();

  /// The STS Access Token of the authenticated user.
  ///
  /// This is actually the STS Access Token, despite it's confusing (backwards compatible) wireName.
  @BuiltValueField(wireName: 'idToken')
  String get accessToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<GetAccountInfoRequest> get serializer => _$getAccountInfoRequestSerializer;
}

///  Represents the response from the setAccountInfo endpoint.
///  see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
abstract class GetAccountInfoResponse implements Built<GetAccountInfoResponse, GetAccountInfoResponseBuilder> {
  factory GetAccountInfoResponse() = _$GetAccountInfoResponse;

  factory GetAccountInfoResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  GetAccountInfoResponse._();

  BuiltList<ResponseUser> get users;

  // The client side never sends a getAccountInfo request with multiple localIs, so only one user
  // data is expected in the response.
  ResponseUser get user => users.isNotEmpty ? users.first : null;

  static Serializer<GetAccountInfoResponse> get serializer => _$getAccountInfoResponseSerializer;
}

/// Represents the provider user info part of the response from the getAccountInfo endpoint.
///
/// see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
abstract class ProviderUserInfo implements Built<ProviderUserInfo, ProviderUserInfoBuilder> {
  factory ProviderUserInfo() = _$ProviderUserInfo;

  factory ProviderUserInfo.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  ProviderUserInfo._();

  /// The ID of the identity provider.
  ///
  /// For white listed IdPs it's a short domain name, e.g., google.com, aol.com, live.net and yahoo.com. For other
  /// OpenID IdPs it's the OP identifier.
  @nullable
  String get providerId;

  /// The user's display name at the identity provider.
  @nullable
  String get displayName;

  /// The user's photo URL at the identity provider.
  @nullable
  String get photoUrl;

  /// The user's identifier at the identity provider.
  @nullable
  String get federatedId;

  ///  The user's email at the identity provider.
  @nullable
  String get email;

  /// A phone number associated with the user.
  @nullable
  String get phoneNumber;

  static Serializer<ProviderUserInfo> get serializer => _$providerUserInfoSerializer;
}

/// Represents the firebase user info part of the response from the getAccountInfo endpoint.
///
///  see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
abstract class ResponseUser implements Built<ResponseUser, ResponseUserBuilder> {
  factory ResponseUser() = _$ResponseUser;

  factory ResponseUser.fromJson(Map<dynamic, dynamic> json) {
    if (json.containsKey('lastLoginAt')) {
      // make it microseconds
      json['lastLoginAt'] = int.parse(json['lastLoginAt']) * 1000;
    }

    if (json.containsKey('createdAt')) {
      // make it microseconds
      json['createdAt'] = int.parse(json['createdAt']) * 1000;
    }

    if (json.containsKey('lastRefreshAt')) {
      json['lastRefreshAt'] = DateTime.parse(json['lastRefreshAt']).microsecondsSinceEpoch;
    }

    // TODO(long1eu): Handle the same for passwordUpdatedAt and timestamp

    return serializers.deserializeWith(serializer, json);
  }

  ResponseUser._();

  /// The local ID of the user.
  @nullable
  String get localId;

  /// The email of the user.
  @nullable
  String get email;

  /// Whether the email has been verified.
  @nullable
  bool get emailVerified;

  /// The name of the user.
  @nullable
  String get displayName;

  /// The URL of the user profile photo.
  @nullable
  String get photoUrl;

  /// The user's last login date.
  DateTime get lastLoginAt;

  /// The user's creation date.
  DateTime get createdAt;

  DateTime get lastRefreshAt;

  /// The user's profiles at the associated identity providers.
  @nullable
  BuiltList<ProviderUserInfo> get providerUserInfo;

  /// Information about user's password.
  ///
  /// This is not necessarily the hash of user's actual password.
  Uint8List get passwordHash;

  /// The user's password salt.
  @nullable
  Uint8List get salt;

  /// Version of the user's password.
  @nullable
  int get version;

  ///	The timestamp when the password was last updated.
  @nullable
  DateTime get passwordUpdatedAt;

  /// The timestamp, in seconds, which marks a boundary, before which Firebase ID token are considered revoked.
  @nullable
  int get validSince;

  /// A phone number associated with the user.
  @nullable
  String get phoneNumber;

  static Serializer<ResponseUser> get serializer => _$responseUserSerializer;
}
