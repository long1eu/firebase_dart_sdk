// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of requests;

abstract class OAuthRequest implements Built<OAuthRequest, OAuthRequestBuilder> {
  factory OAuthRequest([void Function(OAuthRequestBuilder b) updates]) = _$OAuthRequest;

  factory OAuthRequest.login({
    @required String requestUri,
    @required String postBody,
    @required bool returnIdpCredential,
    bool returnSecureToken = true,
  }) {
    return _$OAuthRequest((OAuthRequestBuilder b) {
      b
        ..requestUri = requestUri
        ..postBody = postBody
        ..returnIdpCredential = returnIdpCredential
        ..returnSecureToken = returnSecureToken;
    });
  }

  factory OAuthRequest.link({
    @required String idToken,
    @required String requestUri,
    @required String postBody,
    @required bool returnIdpCredential,
    bool returnSecureToken = true,
  }) {
    return _$OAuthRequest((OAuthRequestBuilder b) {
      b
        ..idToken = idToken
        ..requestUri = requestUri
        ..postBody = postBody
        ..returnIdpCredential = returnIdpCredential
        ..returnSecureToken = returnSecureToken;
    });
  }

  factory OAuthRequest.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  OAuthRequest._();

  /// The Firebase ID token of the account you are trying to link the credential to, if any
  @nullable
  String get idToken;

  ///	The URI to which the IDP redirects the user back.
  String get requestUri;

  ///	Contains the OAuth credential (an ID token or access token) and provider ID which issues the credential.
  String get postBody;

  ///	Whether to force the return of the OAuth credential on the following errors: [FederatedUserIdAlreadyLinked] and
  /// [EmailExists].
  bool get returnIdpCredential;

  ///	Whether or not to return an ID and refresh token. Should always be true.
  bool get returnSecureToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<OAuthRequest> get serializer => _$oAuthRequestSerializer;
}

abstract class OAuthResponse implements Built<OAuthResponse, OAuthResponseBuilder> {
  factory OAuthResponse([void Function(OAuthResponseBuilder b) updates]) = _$OAuthResponse;

  factory OAuthResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  OAuthResponse._();

  /// The unique ID identifies the IdP account.
  String get federatedId;

  /// The linked provider ID (e.g. "google.com" for the Google provider).
  String get providerId;

  /// The uid of the authenticated user.
  String get localId;

  /// Whether the sign-in email is verified.
  bool get emailVerified;

  /// The email of the account.
  String get email;

  /// The OIDC id token if available.
  @nullable
  String get oauthIdToken;

  /// The OAuth access token if available.
  @nullable
  String get oauthAccessToken;

  /// The OAuth 1.0 token secret if available.
  @nullable
  String get oauthTokenSecret;

  /// The stringified JSON response containing all the IdP data corresponding to the provided OAuth credential.
  String get rawUserInfo;

  /// The first name for the account.
  String get firstName;

  /// The last name for the account.
  String get lastName;

  /// The full name for the account.
  String get fullName;

  /// The display name for the account.
  String get displayName;

  /// The photo Url for the account.
  String get photoUrl;

  /// A Firebase Auth ID token for the authenticated user.
  String get idToken;

  /// A Firebase Auth refresh token for the authenticated user.
  String get refreshToken;

  /// The number of seconds in which the ID token expires.
  int get expiresIn;

  /// Whether another account with the same credential already exists. The user will need to sign in to the original
  /// account and then link the current credential to it.
  @nullable
  bool get needConfirmation;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<OAuthResponse> get serializer => _$oAuthResponseSerializer;
}
