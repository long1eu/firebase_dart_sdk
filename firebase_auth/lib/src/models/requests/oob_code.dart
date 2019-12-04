// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of models;

abstract class OobCodeRequest implements Built<OobCodeRequest, OobCodeRequestBuilder> {
  /// For password reset requests, we only need an email address in addition to requestType.
  factory OobCodeRequest.resetPassword({@required String email, ActionCodeSettings settings}) {
    return _$OobCodeRequest((OobCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.passwordReset
        ..email = email
        ..continueUrl = settings?.continueUrl
        ..iOSBundleId = settings?.iOSBundleId
        ..androidPackageName = settings?.androidPackageName
        ..androidInstallApp = settings?.androidInstallApp
        ..androidMinimumVersion = settings?.androidMinimumVersion
        ..canHandleCodeInApp = settings?.canHandleCodeInApp
        ..dynamicLinkDomain = settings?.dynamicLinkDomain;
    });
  }

  /// For verify email requests, we only need an STS Access Token in addition to requestType.
  factory OobCodeRequest.verifyEmail({@required String idToken, ActionCodeSettings settings}) {
    return _$OobCodeRequest((OobCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.verifyEmail
        ..idToken = idToken
        ..continueUrl = settings?.continueUrl
        ..iOSBundleId = settings?.iOSBundleId
        ..androidPackageName = settings?.androidPackageName
        ..androidInstallApp = settings?.androidInstallApp
        ..androidMinimumVersion = settings?.androidMinimumVersion
        ..canHandleCodeInApp = settings?.canHandleCodeInApp
        ..dynamicLinkDomain = settings?.dynamicLinkDomain;
    });
  }

  /// For email sign-in link requests, we only need an email address in addition to requestType.
  factory OobCodeRequest.emailLink({@required String email, @required ActionCodeSettings settings}) {
    return _$OobCodeRequest((OobCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.emailLink
        ..email = email
        ..continueUrl = settings.continueUrl
        ..iOSBundleId = settings.iOSBundleId
        ..androidPackageName = settings.androidPackageName
        ..androidInstallApp = settings.androidInstallApp
        ..androidMinimumVersion = settings.androidMinimumVersion
        ..canHandleCodeInApp = settings.canHandleCodeInApp
        ..dynamicLinkDomain = settings.dynamicLinkDomain;
    });
  }

  /// For email update requests, we only need an STS Access Token, a new email address in addition to requestType.
  factory OobCodeRequest.verifyBeforeUpdateEmail({
    @required String idToken,
    @required String newEmail,
    ActionCodeSettings settings,
  }) {
    return _$OobCodeRequest((OobCodeRequestBuilder b) {
      b
        ..requestType = OobCodeType.verifyEmail
        ..idToken = idToken
        ..newEmail = newEmail
        ..continueUrl = settings?.continueUrl
        ..iOSBundleId = settings?.iOSBundleId
        ..androidPackageName = settings?.androidPackageName
        ..androidInstallApp = settings?.androidInstallApp
        ..androidMinimumVersion = settings?.androidMinimumVersion
        ..canHandleCodeInApp = settings?.canHandleCodeInApp
        ..dynamicLinkDomain = settings?.dynamicLinkDomain;
    });
  }

  OobCodeRequest._();

  /// The kind of OOB code to return
  OobCodeType get requestType;

  /// User's email address.
  @nullable
  String get email;

  /// The new email to be updated.
  @nullable
  String get newEmail;

  /// The Firebase ID token of the user to verify.
  @nullable
  String get idToken;

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

  /// Indicates whether the action code link will open the app directly after being redirected from a Firebase owned web
  /// widget.
  @nullable
  bool get canHandleCodeInApp;

  /// The Firebase Dynamic Link domain used for out of band code flow.
  @nullable
  String get dynamicLinkDomain;

  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<OobCodeRequest> get serializer => _$oobCodeRequestSerializer;
}

abstract class OobCodeResponse implements Built<OobCodeResponse, OobCodeResponseBuilder> {
  factory OobCodeResponse() = _$OobCodeResponse;

  factory OobCodeResponse.fromJson(Map<dynamic, dynamic> json) => serializers.deserializeWith(serializer, json);

  OobCodeResponse._();

  /// User's email address.
  String get email;

  static Serializer<OobCodeResponse> get serializer => _$oobCodeResponseSerializer;
}

class OobCodeType {
  const OobCodeType._(this._i, this._value);

  final String _value;
  final int _i;

  static const OobCodeType passwordReset = OobCodeType._(0, 'PASSWORD_RESET');
  static const OobCodeType verifyEmail = OobCodeType._(1, 'VERIFY_EMAIL');
  static const OobCodeType emailLink = OobCodeType._(1, 'EMAIL_SIGNIN');
  static const OobCodeType verifyBeforeUpdateEmail = OobCodeType._(1, 'VERIFY_AND_CHANGE_EMAIL');

  static const List<OobCodeType> values = <OobCodeType>[
    passwordReset,
    verifyEmail,
    emailLink,
    verifyBeforeUpdateEmail,
  ];

  static const List<String> _names = <String>[
    'passwordReset',
    'verifyEmail',
    'emailLink',
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
