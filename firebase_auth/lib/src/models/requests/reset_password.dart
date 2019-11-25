// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of models;

abstract class ResetPasswordRequest implements Built<ResetPasswordRequest, ResetPasswordRequestBuilder> {
  /// Used to verify a password reset code
  factory ResetPasswordRequest.verify({@required String oobCode}) {
    return _$ResetPasswordRequest((ResetPasswordRequestBuilder b) => b.oobCode = oobCode);
  }

  /// Used to apply a password reset change
  factory ResetPasswordRequest.confirm({@required String oobCode, @required String newPassword}) {
    return _$ResetPasswordRequest((ResetPasswordRequestBuilder b) {
      b
        ..oobCode = oobCode
        ..newPassword = newPassword;
    });
  }

  ResetPasswordRequest._();

  /// The email action code sent to the user's email for resetting the password.
  String get oobCode;

  /// The user's new password.
  @nullable
  String get newPassword;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<ResetPasswordRequest> get serializer => _$resetPasswordRequestSerializer;
}

abstract class ResetPasswordResponse implements Built<ResetPasswordResponse, ResetPasswordResponseBuilder> {
  factory ResetPasswordResponse() = _$ResetPasswordResponse;

  factory ResetPasswordResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  ResetPasswordResponse._();

  /// User's email address.
  String get email;

  /// Type of the email action code. Should be [OobCodeType.passwordReset].
  OobCodeType get requestType;

  static Serializer<ResetPasswordResponse> get serializer => _$resetPasswordResponseSerializer;
}
