// File created by
// Lung Razvan <long1eu>
// on 06/12/2019

part of requests;

/// Represents the parameters for the token endpoint.
abstract class SecureTokenRequest implements Built<SecureTokenRequest, SecureTokenRequestBuilder> {
  factory SecureTokenRequest({
    @required SecureTokenGrantType grantType,
    String scope,
    String refreshToken,
    String code,
  }) {
    return _$SecureTokenRequest((SecureTokenRequestBuilder b) {
      b
        ..grantType = grantType
        ..scope = scope
        ..refreshToken = refreshToken
        ..code = code;
    });
  }

  /// Creates an authorization code request with the given code (legacy Gitkit "ID Token").
  factory SecureTokenRequest.withCode(String code) {
    return _$SecureTokenRequest((SecureTokenRequestBuilder b) {
      b
        ..grantType = SecureTokenGrantType.authorizationCode
        ..code = code;
    });
  }

  /// Creates a refresh request with the given refresh token.
  factory SecureTokenRequest.withRefreshToken(String refreshToken) {
    return _$SecureTokenRequest((SecureTokenRequestBuilder b) {
      b
        ..grantType = SecureTokenGrantType.refreshToken
        ..refreshToken = refreshToken;
    });
  }

  SecureTokenRequest._();

  /// The type of grant requested.
  SecureTokenGrantType get grantType;

  /// The scopes requested (a comma-delimited list of scope strings.)
  @nullable
  String get scope;

  /// The client's refresh token.
  @nullable
  String get refreshToken;

  /// The client's authorization code (legacy Gitkit "ID Token").
  @nullable
  String get code;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<SecureTokenRequest> get serializer => _$secureTokenRequestSerializer;
}

/// Represents the response from the token endpoint.
abstract class SecureTokenResponse implements Built<SecureTokenResponse, SecureTokenResponseBuilder> {
  factory SecureTokenResponse() = _$SecureTokenResponse;

  factory SecureTokenResponse.fromJson(Map<dynamic, dynamic> json) {
    if (json.containsKey('expires_in')) {
      final int seconds = int.parse(json['expires_in']);
      final Duration duration = Duration(seconds: seconds);
      json['expires_in'] = DateTime.now().toUtc().add(duration).microsecondsSinceEpoch;
    }

    return serializers.deserializeWith(serializer, json);
  }

  SecureTokenResponse._();

  /// The approximate expiration date of the access token.
  @nullable
  @BuiltValueField(wireName: 'expires_in')
  DateTime get approximateExpirationDate;

  /// The refresh token. (Possibly an updated one for refresh requests.)
  @nullable
  @BuiltValueField(wireName: 'refresh_token')
  String get refreshToken;

  /// The new access token.
  @nullable
  @BuiltValueField(wireName: 'access_token')
  String get accessToken;

  /// The new ID Token.
  @nullable
  @BuiltValueField(wireName: 'id_token')
  String get idToken;

  static Serializer<SecureTokenResponse> get serializer => _$secureTokenResponseSerializer;
}

/// Represents the possible grant types for a token request.
class SecureTokenGrantType {
  const SecureTokenGrantType._(this._i, this._value);

  final String _value;
  final int _i;

  /// Indicates an authorization code request.
  ///
  /// Exchanges a Gitkit "ID Token" for an STS Access Token and Refresh Token.
  static const SecureTokenGrantType authorizationCode = SecureTokenGrantType._(0, 'authorization_code');

  /// Indicates an refresh token request.
  ///
  /// Uses an existing Refresh Token to create a new Access Token.
  static const SecureTokenGrantType refreshToken = SecureTokenGrantType._(1, 'refresh_token');

  static const List<SecureTokenGrantType> values = <SecureTokenGrantType>[authorizationCode, refreshToken];

  static const List<String> _names = <String>['authorizationCode', 'refreshToken'];

  static Serializer<SecureTokenGrantType> get serializer => _$secureTokenGrantTypeSerializer;

  @override
  String toString() => 'SecureTokenGrantType.${_names[_i]}';
}

Serializer<SecureTokenGrantType> _$secureTokenGrantTypeSerializer = _SecureTokenGrantTypeSerializer();

class _SecureTokenGrantTypeSerializer extends PrimitiveSerializer<SecureTokenGrantType> {
  @override
  Iterable<Type> get types => BuiltList<Type>(<Type>[SecureTokenGrantType]);

  @override
  String get wireName => 'SecureTokenGrantType';

  @override
  SecureTokenGrantType deserialize(Serializers serializers, Object serialized,
      {FullType specifiedType = FullType.unspecified}) {
    return SecureTokenGrantType.values.firstWhere((SecureTokenGrantType it) => it._value == serialized);
  }

  @override
  Object serialize(Serializers serializers, SecureTokenGrantType object,
      {FullType specifiedType = FullType.unspecified}) {
    return object._value;
  }
}
