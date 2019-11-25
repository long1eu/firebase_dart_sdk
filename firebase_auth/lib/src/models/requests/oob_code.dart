// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of models;

abstract class OobCodeRequest implements Built<OobCodeRequest, OobCodeRequestBuilder> {
  factory OobCodeRequest.resetPassword({@required String email}) {
    return _$OobCodeRequest((OobCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.passwordReset
        ..email = email;
    });
  }

  factory OobCodeRequest.verifyEmail({@required String idToken}) {
    return _$OobCodeRequest((OobCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.verifyEmail
        ..idToken = idToken;
    });
  }

  OobCodeRequest._();

  /// The kind of OOB code to return
  OobCodeType get requestType;

  /// User's email address.
  @nullable
  String get email;

  /// The Firebase ID token of the user to verify.
  @nullable
  String get idToken;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<OobCodeRequest> get serializer => _$oobCodeRequestSerializer;
}

abstract class OobCodeResponse implements Built<OobCodeResponse, OobCodeResponseBuilder> {
  factory OobCodeResponse() = _$OobCodeResponse;

  factory OobCodeResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  OobCodeResponse._();

  /// The kind of OOB code to return
  String get email;

  static Serializer<OobCodeResponse> get serializer => _$oobCodeResponseSerializer;
}

class OobCodeType {
  const OobCodeType._(this._i, this._value);

  final String _value;
  final int _i;

  static const OobCodeType passwordReset = OobCodeType._(0, 'PASSWORD_RESET');
  static const OobCodeType verifyEmail = OobCodeType._(1, 'VERIFY_EMAIL');

  static const List<OobCodeType> values = <OobCodeType>[passwordReset, verifyEmail];
  static const List<String> _names = <String>['passwordReset', 'verifyEmail'];

  static Serializer<OobCodeType> get serializer => _$oobCodeTypeSerializer;

  @override
  String toString() => 'OobCodeType.${_names[_i]}';
}

Serializer<OobCodeType> _$oobCodeTypeSerializer = _OobCodeTypeSerializer();

class _OobCodeTypeSerializer extends PrimitiveSerializer<OobCodeType> {
  @override
  Iterable<Type> get types => BuiltList<Type>(<Type>[OobCodeType]);

  @override
  String get wireName => 'OobCodeType';

  @override
  OobCodeType deserialize(Serializers serializers, Object serialized, {FullType specifiedType = FullType.unspecified}) {
    return OobCodeType.values.firstWhere((OobCodeType it) => it._value == serialized);
  }

  @override
  Object serialize(Serializers serializers, OobCodeType object, {FullType specifiedType = FullType.unspecified}) {
    return object._value;
  }
}
