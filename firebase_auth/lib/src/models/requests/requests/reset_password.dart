// File created by
// Lung Razvan <long1eu>
// on 06/12/2019

part of requests;

/// Represents the parameters from the resetPassword endpoint.
abstract class ResetPasswordRequest implements Built<ResetPasswordRequest, ResetPasswordRequestBuilder> {
  factory ResetPasswordRequest({@required String oobCode, @required String updatedPassword}) {
    return _$ResetPasswordRequest((ResetPasswordRequestBuilder b) {
      b
        ..oobCode = oobCode
        ..updatedPassword = updatedPassword;
    });
  }

  ResetPasswordRequest._();

  /// The oobCode sent in the request.
  String get oobCode;

  /// The new password sent in the request.
  String get updatedPassword;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<ResetPasswordRequest> get serializer => _$resetPasswordRequestSerializer;
}

/// Represents the response from the resetPassword endpoint.
abstract class ResetPasswordResponse implements Built<ResetPasswordResponse, ResetPasswordResponseBuilder> {
  factory ResetPasswordResponse() = _$ResetPasswordResponse;

  factory ResetPasswordResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  ResetPasswordResponse._();

  /// The email address corresponding to the reset password request.
  String get email;

  /// The verified email returned from the backend.
  String get verifiedEmail;

  /// The type of request as returned by the backend.
  OobCodeType get requestType;

  static Serializer<ResetPasswordResponse> get serializer => _$resetPasswordResponseSerializer;
}
