// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of models;

abstract class ExchangeRefreshTokenRequest
    implements Built<ExchangeRefreshTokenRequest, ExchangeRefreshTokenRequestBuilder> {
  factory ExchangeRefreshTokenRequest({
    String grantType = 'refresh_token',
    String refreshToken = '',
  }) {
    return _$ExchangeRefreshTokenRequest((ExchangeRefreshTokenRequestBuilder b) {
      b
        ..grantType = grantType
        ..refreshToken = refreshToken ?? '';
    });
  }

  ExchangeRefreshTokenRequest._();

  /// The refresh token's grant type, always "refresh_token".
  @BuiltValueField(wireName: 'grant_type')
  String get grantType;

  /// A Firebase Auth refresh token.
  @BuiltValueField(wireName: 'refresh_token')
  String get refreshToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<ExchangeRefreshTokenRequest> get serializer => _$exchangeRefreshTokenRequestSerializer;
}

abstract class ExchangeRefreshTokenResponse
    implements Built<ExchangeRefreshTokenResponse, ExchangeRefreshTokenResponseBuilder> {
  factory ExchangeRefreshTokenResponse() = _$ExchangeRefreshTokenResponse;

  factory ExchangeRefreshTokenResponse.fromJson(Map<dynamic, dynamic> json) =>
      serializers.deserializeWith(serializer, json);

  ExchangeRefreshTokenResponse._();

  /// The number of seconds in which the ID token expires.
  @BuiltValueField(wireName: 'expires_in')
  int get expiresIn;

  /// The type of the refresh token, always "Bearer".
  @BuiltValueField(wireName: 'token_type')
  String get tokenType;

  /// The Firebase Auth refresh token provided in the request or a new refresh token.
  @BuiltValueField(wireName: 'refresh_token')
  @nullable
  String get refreshToken;

  @BuiltValueField(wireName: 'access_token')
  @nullable
  String get accessToken;

  /// A Firebase Auth ID token.
  @BuiltValueField(wireName: 'id_token')
  String get idToken;

  /// The uid corresponding to the provided ID token.
  @BuiltValueField(wireName: 'user_id')
  String get userId;

  /// Your Firebase project ID.
  @BuiltValueField(wireName: 'project_id')
  String get projectId;

  static Serializer<ExchangeRefreshTokenResponse> get serializer => _$exchangeRefreshTokenResponseSerializer;
}

abstract class ExchangeCustomTokenRequest
    implements Built<ExchangeCustomTokenRequest, ExchangeCustomTokenRequestBuilder> {
  factory ExchangeCustomTokenRequest({@required String token, bool returnSecureToken = true}) {
    return _$ExchangeCustomTokenRequest((ExchangeCustomTokenRequestBuilder b) {
      b
        ..token = token
        ..returnSecureToken = returnSecureToken;
    });
  }

  ExchangeCustomTokenRequest._();

  /// A Firebase Auth custom token from which to create an ID and refresh token pair.
  String get token;

  /// Whether or not to return an ID and refresh token. Should always be true.
  bool get returnSecureToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<ExchangeCustomTokenRequest> get serializer => _$exchangeCustomTokenRequestSerializer;
}

abstract class ExchangeCustomTokenResponse
    implements Built<ExchangeCustomTokenResponse, ExchangeCustomTokenResponseBuilder> {
  factory ExchangeCustomTokenResponse() = _$ExchangeCustomTokenResponse;

  factory ExchangeCustomTokenResponse.fromJson(Map<dynamic, dynamic> json) =>
      serializers.deserializeWith(serializer, json);

  ExchangeCustomTokenResponse._();

  /// A Firebase Auth ID token generated from the provided custom token.
  String get idToken;

  /// A Firebase Auth refresh token generated from the provided custom token.
  String get refreshToken;

  /// The number of seconds in which the ID token expires.
  int get expiresIn;

  static Serializer<ExchangeCustomTokenResponse> get serializer => _$exchangeCustomTokenResponseSerializer;
}
