// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of requests;

/// Represents the parameters for the createAuthUri endpoint.
///
/// see https://developers.google.com/identity/toolkit/web/reference/relyingparty/createAuthUri
abstract class CreateAuthUriRequest implements Built<CreateAuthUriRequest, CreateAuthUriRequestBuilder> {
  factory CreateAuthUriRequest({
    @required String identifier,
    @required String continueUri,
    String openidRealm,
    String providerId,
    String clientId,
    String context,
    String otaApp,
    String appId,
  }) {
    return _$CreateAuthUriRequest((CreateAuthUriRequestBuilder b) {
      b
        ..identifier = identifier
        ..continueUri = continueUri
        ..openidRealm = openidRealm
        ..providerId = providerId
        ..clientId = clientId
        ..context = context
        ..otaApp = otaApp
        ..appId = appId;
    });
  }

  CreateAuthUriRequest._();

  /// The email or federated ID of the user.
  String get identifier;

  /// The URI to which the IDP redirects the user after the federated login flow.
  String get continueUri;

  ///	Optional realm for OpenID protocol.
  ///
  /// The sub string "scheme://domain:port" of the param "continueUri" is used if this is not set.
  @nullable
  String get openidRealm;

  ///	The IdP ID. For white listed IdPs it's a short domain name e.g. google.com, aol.com, live.net and yahoo.com. For
  /// other OpenID IdPs it's the OP identifier.
  @nullable
  String get providerId;

  ///	The relying party OAuth client ID.
  @nullable
  String get clientId;

  ///	The opaque value used by the client to maintain context info between the authentication request and the IDP
  /// callback.
  @nullable
  String get context;

  /// The native app package for OTA installation.
  @nullable
  String get otaApp;

  /// The client application's application identifier.
  ///
  /// The app ID of the app, base64(CERT_SHA1):PACKAGE_NAME for Android, BUNDLE_ID for iOS.
  @nullable
  String get appId;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<CreateAuthUriRequest> get serializer => _$createAuthUriRequestSerializer;
}

/// Represents the response for the createAuthUri endpoint.
///
/// https://developers.google.com/identity/toolkit/web/reference/relyingparty/createAuthUri
abstract class CreateAuthUriResponse implements Built<CreateAuthUriResponse, CreateAuthUriResponseBuilder> {
  factory CreateAuthUriResponse() = _$CreateAuthUriResponse;

  factory CreateAuthUriResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  CreateAuthUriResponse._();

  /// The URI used by the IDP to authenticate the user.
  @nullable
  String get authUri;

  /// Whether the user is registered if the identifier is an email.
  bool get registered;

  /// The provider ID of the auth URI.
  @nullable
  String get providerId;

  /// True if the authUri is for user's existing provider.
  @nullable
  bool get forExistingProvider;

  /// A list of provider IDs the passed identifier could use to sign in with.
  @nullable
  BuiltList<String> get allProviders;

  /// A list of sign-in methods available for the passed @c identifier.
  @nullable
  @BuiltValueField(wireName: 'signinMethods')
  BuiltList<String> get signInMethods;

  static Serializer<CreateAuthUriResponse> get serializer => _$createAuthUriResponseSerializer;
}
