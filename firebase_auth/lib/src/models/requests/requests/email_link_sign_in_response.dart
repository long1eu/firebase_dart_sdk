// File created by
// Lung Razvan <long1eu>
// on 05/12/2019

part of requests;

/// Represents the parameters for the emailLinkSignin endpoint.
abstract class EmailLinkSignInResponse implements Built<EmailLinkSignInResponse, EmailLinkSignInResponseBuilder> {
  factory EmailLinkSignInResponse({@required String email, @required String oobCode, @required String idToken}) {
    return _$EmailLinkSignInResponse((EmailLinkSignInResponseBuilder b) {
      b
        ..email = email
        ..oobCode = oobCode
        ..idToken = idToken;
    });
  }

  EmailLinkSignInResponse._();

  /// The email identifier used to complete the email link sign-in.
  String get email;

  /// The OOB code used to complete the email link sign-in flow.
  String get oobCode;

  /// The ID Token code potentially used to complete the email link sign-in flow.
  @nullable
  String get idToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<EmailLinkSignInResponse> get serializer => _$emailLinkSignInResponseSerializer;
}

/// Represents the response from the emailLinkSignin endpoint.
abstract class EmailLinkSignInRequest implements Built<EmailLinkSignInRequest, EmailLinkSignInRequestBuilder> {
  factory EmailLinkSignInRequest() = _$EmailLinkSignInRequest;

  factory EmailLinkSignInRequest.fromJson(Map<dynamic, dynamic> json) {
    if (json.containsKey('expiresIn')) {
      json['expiresIn'] = int.parse(json['expiresIn']) * 1000;
    }
    return serializers.deserializeWith(serializer, json);
  }

  EmailLinkSignInRequest._();

  /// The ID token in the email link sign-in response.
  String get idToken;

  /// The email returned by the IdP.
  @nullable
  String get email;

  /// Flag indicating that the user signing in is a new user and not a returning user.
  bool get isNewUser;

  /// The refreshToken returned by the server.
  @nullable
  String get refreshToken;

  /// The approximate expiration date of the access token.
  @nullable
  DateTime get expiresIn;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<EmailLinkSignInRequest> get serializer => _$emailLinkSignInRequestSerializer;
}
