// File created by
// Lung Razvan <long1eu>
// on 07/12/2019

part of firebase_auth_vm;

abstract class SignInWithGameCenterRequest
    implements
        Built<SignInWithGameCenterRequest, SignInWithGameCenterRequestBuilder> {
  factory SignInWithGameCenterRequest({
    @required String playerId,
    @required String publicKeyUrl,
    @required Uint8List signature,
    @required Uint8List salt,
    @required DateTime timestamp,
    String accessToken,
    @required String displayName,
  }) {
    final String encodedSignature = signature != null
        ? base64Encode(signature)
            .replaceAll('/', '_')
            .replaceAll('+', '-')
            .replaceAll('=', '')
        : null;

    final String encodedSalt = signature != null //
        ? base64Encode(salt)
            .replaceAll('/', '_')
            .replaceAll('+', '-')
            .replaceAll('=', '')
        : null;

    return _$SignInWithGameCenterRequest(
        (SignInWithGameCenterRequestBuilder b) {
      b
        ..playerId = playerId
        ..publicKeyUrl = publicKeyUrl
        ..signature = encodedSignature
        ..salt = encodedSalt
        ..timestamp = timestamp?.toUtc()?.millisecondsSinceEpoch
        ..accessToken = accessToken
        ..displayName = displayName;
    });
  }

  SignInWithGameCenterRequest._();

  /// The playerID to verify.
  @nullable
  String get playerId;

  /// The URL for the public encryption key.
  @nullable
  String get publicKeyUrl;

  /// The verification signature data generated by Game Center.
  @nullable
  String get signature;

  /// A random strong used to compute the hash and keep it randomized.
  @nullable
  String get salt;

  /// The date and time that the signature was created.
  @nullable
  int get timestamp;

  /// The STS Access Token for the authenticated user, only needed for linking the user.
  @nullable
  @BuiltValueField(wireName: 'idToken')
  String get accessToken;

  /// The display name of the local Game Center player.
  @nullable
  String get displayName;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<SignInWithGameCenterRequest> get serializer =>
      _$signInWithGameCenterRequestSerializer;
}

abstract class SignInWithGameCenterResponse
    implements
        Built<SignInWithGameCenterResponse,
            SignInWithGameCenterResponseBuilder> {
  factory SignInWithGameCenterResponse() = _$SignInWithGameCenterResponse;

  factory SignInWithGameCenterResponse.fromJson(Map<dynamic, dynamic> json) =>
      serializers.deserializeWith(serializer, json);

  SignInWithGameCenterResponse._();

  /// Either an authorization code suitable for performing an STS token exchange, or the access token from Secure Token
  /// Service, depending on whether [returnSecureToken] is set on the request.
  String get idToken;

  /// The refresh token from Secure Token Service.
  String get refreshToken;

  /// The Firebase Auth user ID.
  String get localId;

  /// The verified player ID.
  String get playerId;

  /// The approximate expiration date of the access token.
  String get expiresIn;

  /// Flag indicating that the user signing in is a new user and not a returning user.
  bool get isNewUser;

  /// The user's Game Center display name.
  String get displayName;

  static Serializer<SignInWithGameCenterResponse> get serializer =>
      _$signInWithGameCenterResponseSerializer;
}
