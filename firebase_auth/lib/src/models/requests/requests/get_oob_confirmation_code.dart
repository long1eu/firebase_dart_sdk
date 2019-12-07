// File created by
// Lung Razvan <long1eu>
// on 06/12/2019

part of requests;

/// Represents the parameters for the getOOBConfirmationCode endpoint.
abstract class GetOobConfirmationCodeRequest
    implements Built<GetOobConfirmationCodeRequest, GetOobConfirmationCodeRequestBuilder> {
  factory GetOobConfirmationCodeRequest() = _$GetOobConfirmationCodeRequest;

  /// For password reset requests, we only need an email address in addition to requestType.
  factory GetOobConfirmationCodeRequest.resetPassword({@required String email, ActionCodeSettings settings}) {
    return _$GetOobConfirmationCodeRequest((GetOobConfirmationCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.passwordReset
        ..email = email
        ..continueUrl = settings?.continueUrl
        ..iOSBundleId = settings?.iOSBundleId
        ..androidPackageName = settings?.androidPackageName
        ..androidInstallApp = settings?.androidInstallIfNotAvailable
        ..androidMinimumVersion = settings?.androidMinimumVersion
        ..handleCodeInApp = settings?.handleCodeInApp
        ..dynamicLinkDomain = settings?.dynamicLinkDomain;
    });
  }

  /// For verify email requests, we only need an STS Access Token in addition to requestType.
  factory GetOobConfirmationCodeRequest.verifyEmail({@required String accessToken, ActionCodeSettings settings}) {
    return _$GetOobConfirmationCodeRequest((GetOobConfirmationCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.verifyEmail
        ..accessToken = accessToken
        ..continueUrl = settings?.continueUrl
        ..iOSBundleId = settings?.iOSBundleId
        ..androidPackageName = settings?.androidPackageName
        ..androidInstallApp = settings?.androidInstallIfNotAvailable
        ..androidMinimumVersion = settings?.androidMinimumVersion
        ..handleCodeInApp = settings?.handleCodeInApp
        ..dynamicLinkDomain = settings?.dynamicLinkDomain;
    });
  }

  /// For email sign-in link requests, we only need an email address in addition to requestType.
  factory GetOobConfirmationCodeRequest.signInWithEmailLink({
    @required String email,
    @required ActionCodeSettings settings,
  }) {
    return _$GetOobConfirmationCodeRequest((GetOobConfirmationCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.emailLinkSignIn
        ..email = email
        ..continueUrl = settings.continueUrl
        ..iOSBundleId = settings.iOSBundleId
        ..androidPackageName = settings.androidPackageName
        ..androidInstallApp = settings.androidInstallIfNotAvailable
        ..androidMinimumVersion = settings.androidMinimumVersion
        ..handleCodeInApp = settings.handleCodeInApp
        ..dynamicLinkDomain = settings.dynamicLinkDomain;
    });
  }

  /// For email update requests, we only need an STS Access Token, a new email address in addition to requestType.
  factory GetOobConfirmationCodeRequest.verifyBeforeUpdateEmail({
    @required String accessToken,
    @required String updateEmail,
    ActionCodeSettings settings,
  }) {
    return _$GetOobConfirmationCodeRequest((GetOobConfirmationCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.verifyEmail
        ..accessToken = accessToken
        ..updateEmail = updateEmail
        ..continueUrl = settings?.continueUrl
        ..iOSBundleId = settings?.iOSBundleId
        ..androidPackageName = settings?.androidPackageName
        ..androidInstallApp = settings?.androidInstallIfNotAvailable
        ..androidMinimumVersion = settings?.androidMinimumVersion
        ..handleCodeInApp = settings?.handleCodeInApp
        ..dynamicLinkDomain = settings?.dynamicLinkDomain;
    });
  }

  GetOobConfirmationCodeRequest._();

  /// The type of OOB Confirmation Code to request.
  OobCodeType get requestType;

  /// The email of the user.
  ///
  /// For password reset.
  @nullable
  String get email;

  /// The new email to be updated.
  ///
  /// For verifyBeforeUpdateEmail.
  @nullable
  @BuiltValueField(wireName: 'newEmail')
  String get updateEmail;

  /// The STS Access Token of the authenticated user.
  ///
  /// For email change. This is actually the STS Access Token, despite it's confusing (backwards compatiable) wireName.
  @nullable
  @BuiltValueField(wireName: 'idToken')
  String get accessToken;

  /// This URL represents the state/Continue URL in the form of a universal link.
  @nullable
  String get continueUrl;

  /// The iOS bundle Identifier, if available.
  @nullable
  String get iOSBundleId;

  /// The Android package name, if available.
  @nullable
  String get androidPackageName;

  /// Indicates whether or not the Android app should be installed if not already available.
  @nullable
  bool get androidInstallApp;

  /// The minimum Android version supported, if available.
  @nullable
  String get androidMinimumVersion;

  /// Indicates whether the action code link will open the app directly or after being redirected from a Firebase owned
  /// web widget.
  @nullable
  @BuiltValueField(wireName: 'canHandleCodeInApp')
  bool get handleCodeInApp;

  /// The Firebase Dynamic Link domain used for out of band code flow.
  @nullable
  String get dynamicLinkDomain;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<GetOobConfirmationCodeRequest> get serializer => _$getOobConfirmationCodeRequestSerializer;
}

/// Represents the response from the getOobConfirmationCode endpoint.
abstract class GetOobConfirmationCodeResponse
    implements Built<GetOobConfirmationCodeResponse, GetOobConfirmationCodeResponseBuilder> {
  factory GetOobConfirmationCodeResponse() = _$GetOobConfirmationCodeResponse;

  factory GetOobConfirmationCodeResponse.fromJson(Map<dynamic, dynamic> json) =>
      serializers.deserializeWith(serializer, json);

  GetOobConfirmationCodeResponse._();

  /// The OOB code returned by the server in some cases.
  @nullable
  String get oobCode;

  static Serializer<GetOobConfirmationCodeResponse> get serializer => _$getOobConfirmationCodeResponseSerializer;
}

/// Types of OOB Confirmation Code requests.
class OobCodeType {
  const OobCodeType._(this._i, this._value);

  final String _value;
  final int _i;

  /// Requests a password reset code.
  static const OobCodeType passwordReset = OobCodeType._(0, 'PASSWORD_RESET');

  /// Requests an email verification code.
  static const OobCodeType verifyEmail = OobCodeType._(1, 'VERIFY_EMAIL');

  /// Requests an email sign-in link.
  static const OobCodeType emailLinkSignIn = OobCodeType._(1, 'EMAIL_SIGNIN');

  /// Requests an verify before update email.
  static const OobCodeType verifyBeforeUpdateEmail = OobCodeType._(1, 'VERIFY_AND_CHANGE_EMAIL');

  static const List<OobCodeType> values = <OobCodeType>[
    passwordReset,
    verifyEmail,
    emailLinkSignIn,
    verifyBeforeUpdateEmail,
  ];

  static const List<String> _names = <String>[
    'passwordReset',
    'verifyEmail',
    'emailLinkSignIn',
    'verifyBeforeUpdateEmail',
  ];

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
