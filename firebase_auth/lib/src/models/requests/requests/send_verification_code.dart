// File created by
// Lung Razvan <long1eu>
// on 06/12/2019

part of requests;

abstract class SendVerificationCodeRequest
    implements Built<SendVerificationCodeRequest, SendVerificationCodeRequestBuilder> {
  factory SendVerificationCodeRequest({String phoneNumber, AppCredential credential, String recaptchaToken}) {
    return _$SendVerificationCodeRequest((SendVerificationCodeRequestBuilder b) {
      b
        ..phoneNumber = phoneNumber
        ..receipt = credential.receipt
        ..secret = credential.secret
        ..recaptchaToken = recaptchaToken;
    });
  }

  SendVerificationCodeRequest._();

  /// The phone number to which the verification code should be sent.
  @nullable
  String get phoneNumber;

  /// The server acknowledgement of receiving client's claim of identity.
  @BuiltValueField(wireName: 'iosReceipt')
  @nullable
  String get receipt;

  /// The secret that the client received from server via a trusted channel, if ever.
  @BuiltValueField(wireName: 'iosSecret')
  @nullable
  String get secret;

  /// The reCAPTCHA token to prove the identity of the app in order to send the verification code.
  @nullable
  String get recaptchaToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<SendVerificationCodeRequest> get serializer => _$sendVerificationCodeRequestSerializer;
}

abstract class SendVerificationCodeResponse
    implements Built<SendVerificationCodeResponse, SendVerificationCodeResponseBuilder> {
  factory SendVerificationCodeResponse() = _$SendVerificationCodeResponse;

  factory SendVerificationCodeResponse.fromJson(Map<dynamic, dynamic> json) =>
      serializers.deserializeWith(serializer, json);

  SendVerificationCodeResponse._();

  /// Encrypted session information returned by the backend.
  String get sessionInfo;

  static Serializer<SendVerificationCodeResponse> get serializer => _$sendVerificationCodeResponseSerializer;
}
