// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of requests;

abstract class BaseAuthRequest implements Built<BaseAuthRequest, BaseAuthRequestBuilder> {
  factory BaseAuthRequest({String email, String password, bool returnSecureToken = true}) {
    return _$BaseAuthRequest((BaseAuthRequestBuilder b) {
      b
        ..email = email
        ..password = password
        ..returnSecureToken = returnSecureToken;
    });
  }

  BaseAuthRequest._();

  /// The email for the user to create.
  ///
  /// Passing null for the email will create an anonymous user.
  @nullable
  String get email;

  /// The name for the user to create.
  @nullable
  String get displayName;

  /// The password for the user to create.
  ///
  /// If the email is null and an anonymous user is created, this filed is ignored.
  @nullable
  String get password;

  /// Whether or not to return an ID and refresh token. Should always be true.
  bool get returnSecureToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<BaseAuthRequest> get serializer => _$baseAuthRequestSerializer;
}

abstract class BaseAuthResponse implements Built<BaseAuthResponse, BaseAuthResponseBuilder> {
  factory BaseAuthResponse() = _$BaseAuthResponse;

  factory BaseAuthResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  BaseAuthResponse._();

  /// A Firebase Auth ID token for the newly created user.
  String get idToken;

  /// The email for the newly created user.
  @nullable
  String get email;

  /// A Firebase Auth refresh token for the newly created user.
  String get refreshToken;

  /// The number of seconds in which the ID token expires.
  int get expiresIn;

  /// The uid of the newly created user.
  String get localId;

  /// Whether the email is for an existing account.
  @nullable
  bool get registered;

  static Serializer<BaseAuthResponse> get serializer => _$baseAuthResponseSerializer;
}
