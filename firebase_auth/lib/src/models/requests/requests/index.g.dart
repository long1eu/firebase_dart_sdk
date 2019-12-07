// GENERATED CODE - DO NOT MODIFY BY HAND

part of requests;

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers = (new Serializers().toBuilder()
      ..add(DeleteAccountRequest.serializer)
      ..add(EmailLinkSignInRequest.serializer)
      ..add(EmailLinkSignInResponse.serializer)
      ..add(GetAccountInfoRequest.serializer)
      ..add(GetAccountInfoResponse.serializer)
      ..add(GetOobConfirmationCodeRequest.serializer)
      ..add(GetOobConfirmationCodeResponse.serializer)
      ..add(GetProjectConfigResponse.serializer)
      ..add(ProviderUserInfo.serializer)
      ..add(ResetPasswordRequest.serializer)
      ..add(ResetPasswordResponse.serializer)
      ..add(ResponseUser.serializer)
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ProviderUserInfo)]),
          () => new ListBuilder<ProviderUserInfo>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ResponseUser)]),
          () => new ListBuilder<ResponseUser>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => new ListBuilder<String>()))
    .build();
Serializer<DeleteAccountRequest> _$deleteAccountRequestSerializer =
    new _$DeleteAccountRequestSerializer();
Serializer<EmailLinkSignInResponse> _$emailLinkSignInResponseSerializer =
    new _$EmailLinkSignInResponseSerializer();
Serializer<EmailLinkSignInRequest> _$emailLinkSignInRequestSerializer =
    new _$EmailLinkSignInRequestSerializer();
Serializer<GetAccountInfoRequest> _$getAccountInfoRequestSerializer =
    new _$GetAccountInfoRequestSerializer();
Serializer<GetAccountInfoResponse> _$getAccountInfoResponseSerializer =
    new _$GetAccountInfoResponseSerializer();
Serializer<ProviderUserInfo> _$providerUserInfoSerializer =
    new _$ProviderUserInfoSerializer();
Serializer<ResponseUser> _$responseUserSerializer =
    new _$ResponseUserSerializer();
Serializer<GetOobConfirmationCodeRequest>
    _$getOobConfirmationCodeRequestSerializer =
    new _$GetOobConfirmationCodeRequestSerializer();
Serializer<GetOobConfirmationCodeResponse>
    _$getOobConfirmationCodeResponseSerializer =
    new _$GetOobConfirmationCodeResponseSerializer();
Serializer<GetProjectConfigResponse> _$getProjectConfigResponseSerializer =
    new _$GetProjectConfigResponseSerializer();
Serializer<ResetPasswordRequest> _$resetPasswordRequestSerializer =
    new _$ResetPasswordRequestSerializer();
Serializer<ResetPasswordResponse> _$resetPasswordResponseSerializer =
    new _$ResetPasswordResponseSerializer();
Serializer<SecureTokenRequest> _$secureTokenRequestSerializer =
    new _$SecureTokenRequestSerializer();
Serializer<SecureTokenResponse> _$secureTokenResponseSerializer =
    new _$SecureTokenResponseSerializer();
Serializer<SendVerificationCodeRequest>
    _$sendVerificationCodeRequestSerializer =
    new _$SendVerificationCodeRequestSerializer();
Serializer<SendVerificationCodeResponse>
    _$sendVerificationCodeResponseSerializer =
    new _$SendVerificationCodeResponseSerializer();

class _$DeleteAccountRequestSerializer
    implements StructuredSerializer<DeleteAccountRequest> {
  @override
  final Iterable<Type> types = const [
    DeleteAccountRequest,
    _$DeleteAccountRequest
  ];
  @override
  final String wireName = 'DeleteAccountRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, DeleteAccountRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'idToken',
      serializers.serialize(object.accessToken,
          specifiedType: const FullType(String)),
      'localId',
      serializers.serialize(object.localId,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  DeleteAccountRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DeleteAccountRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'idToken':
          result.accessToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'localId':
          result.localId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$EmailLinkSignInResponseSerializer
    implements StructuredSerializer<EmailLinkSignInResponse> {
  @override
  final Iterable<Type> types = const [
    EmailLinkSignInResponse,
    _$EmailLinkSignInResponse
  ];
  @override
  final String wireName = 'EmailLinkSignInResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, EmailLinkSignInResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'email',
      serializers.serialize(object.email,
          specifiedType: const FullType(String)),
      'oobCode',
      serializers.serialize(object.oobCode,
          specifiedType: const FullType(String)),
    ];
    if (object.idToken != null) {
      result
        ..add('idToken')
        ..add(serializers.serialize(object.idToken,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  EmailLinkSignInResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new EmailLinkSignInResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'email':
          result.email = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'oobCode':
          result.oobCode = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'idToken':
          result.idToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$EmailLinkSignInRequestSerializer
    implements StructuredSerializer<EmailLinkSignInRequest> {
  @override
  final Iterable<Type> types = const [
    EmailLinkSignInRequest,
    _$EmailLinkSignInRequest
  ];
  @override
  final String wireName = 'EmailLinkSignInRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, EmailLinkSignInRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'idToken',
      serializers.serialize(object.idToken,
          specifiedType: const FullType(String)),
      'isNewUser',
      serializers.serialize(object.isNewUser,
          specifiedType: const FullType(bool)),
    ];
    if (object.email != null) {
      result
        ..add('email')
        ..add(serializers.serialize(object.email,
            specifiedType: const FullType(String)));
    }
    if (object.refreshToken != null) {
      result
        ..add('refreshToken')
        ..add(serializers.serialize(object.refreshToken,
            specifiedType: const FullType(String)));
    }
    if (object.expiresIn != null) {
      result
        ..add('expiresIn')
        ..add(serializers.serialize(object.expiresIn,
            specifiedType: const FullType(DateTime)));
    }
    return result;
  }

  @override
  EmailLinkSignInRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new EmailLinkSignInRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'idToken':
          result.idToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'email':
          result.email = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'isNewUser':
          result.isNewUser = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'refreshToken':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'expiresIn':
          result.expiresIn = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
      }
    }

    return result.build();
  }
}

class _$GetAccountInfoRequestSerializer
    implements StructuredSerializer<GetAccountInfoRequest> {
  @override
  final Iterable<Type> types = const [
    GetAccountInfoRequest,
    _$GetAccountInfoRequest
  ];
  @override
  final String wireName = 'GetAccountInfoRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, GetAccountInfoRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'idToken',
      serializers.serialize(object.accessToken,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  GetAccountInfoRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new GetAccountInfoRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'idToken':
          result.accessToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$GetAccountInfoResponseSerializer
    implements StructuredSerializer<GetAccountInfoResponse> {
  @override
  final Iterable<Type> types = const [
    GetAccountInfoResponse,
    _$GetAccountInfoResponse
  ];
  @override
  final String wireName = 'GetAccountInfoResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, GetAccountInfoResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'users',
      serializers.serialize(object.users,
          specifiedType:
              const FullType(BuiltList, const [const FullType(ResponseUser)])),
    ];

    return result;
  }

  @override
  GetAccountInfoResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new GetAccountInfoResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'users':
          result.users.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(ResponseUser)]))
              as BuiltList<dynamic>);
          break;
      }
    }

    return result.build();
  }
}

class _$ProviderUserInfoSerializer
    implements StructuredSerializer<ProviderUserInfo> {
  @override
  final Iterable<Type> types = const [ProviderUserInfo, _$ProviderUserInfo];
  @override
  final String wireName = 'ProviderUserInfo';

  @override
  Iterable<Object> serialize(Serializers serializers, ProviderUserInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[];
    if (object.providerId != null) {
      result
        ..add('providerId')
        ..add(serializers.serialize(object.providerId,
            specifiedType: const FullType(String)));
    }
    if (object.displayName != null) {
      result
        ..add('displayName')
        ..add(serializers.serialize(object.displayName,
            specifiedType: const FullType(String)));
    }
    if (object.photoUrl != null) {
      result
        ..add('photoUrl')
        ..add(serializers.serialize(object.photoUrl,
            specifiedType: const FullType(String)));
    }
    if (object.federatedId != null) {
      result
        ..add('federatedId')
        ..add(serializers.serialize(object.federatedId,
            specifiedType: const FullType(String)));
    }
    if (object.email != null) {
      result
        ..add('email')
        ..add(serializers.serialize(object.email,
            specifiedType: const FullType(String)));
    }
    if (object.phoneNumber != null) {
      result
        ..add('phoneNumber')
        ..add(serializers.serialize(object.phoneNumber,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  ProviderUserInfo deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ProviderUserInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'providerId':
          result.providerId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'displayName':
          result.displayName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'photoUrl':
          result.photoUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'federatedId':
          result.federatedId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'email':
          result.email = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'phoneNumber':
          result.phoneNumber = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ResponseUserSerializer implements StructuredSerializer<ResponseUser> {
  @override
  final Iterable<Type> types = const [ResponseUser, _$ResponseUser];
  @override
  final String wireName = 'ResponseUser';

  @override
  Iterable<Object> serialize(Serializers serializers, ResponseUser object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'lastLoginAt',
      serializers.serialize(object.lastLoginAt,
          specifiedType: const FullType(DateTime)),
      'createdAt',
      serializers.serialize(object.createdAt,
          specifiedType: const FullType(DateTime)),
      'lastRefreshAt',
      serializers.serialize(object.lastRefreshAt,
          specifiedType: const FullType(DateTime)),
      'passwordHash',
      serializers.serialize(object.passwordHash,
          specifiedType: const FullType(Uint8List)),
    ];
    if (object.localId != null) {
      result
        ..add('localId')
        ..add(serializers.serialize(object.localId,
            specifiedType: const FullType(String)));
    }
    if (object.email != null) {
      result
        ..add('email')
        ..add(serializers.serialize(object.email,
            specifiedType: const FullType(String)));
    }
    if (object.emailVerified != null) {
      result
        ..add('emailVerified')
        ..add(serializers.serialize(object.emailVerified,
            specifiedType: const FullType(bool)));
    }
    if (object.displayName != null) {
      result
        ..add('displayName')
        ..add(serializers.serialize(object.displayName,
            specifiedType: const FullType(String)));
    }
    if (object.photoUrl != null) {
      result
        ..add('photoUrl')
        ..add(serializers.serialize(object.photoUrl,
            specifiedType: const FullType(String)));
    }
    if (object.providerUserInfo != null) {
      result
        ..add('providerUserInfo')
        ..add(serializers.serialize(object.providerUserInfo,
            specifiedType: const FullType(
                BuiltList, const [const FullType(ProviderUserInfo)])));
    }
    if (object.salt != null) {
      result
        ..add('salt')
        ..add(serializers.serialize(object.salt,
            specifiedType: const FullType(Uint8List)));
    }
    if (object.version != null) {
      result
        ..add('version')
        ..add(serializers.serialize(object.version,
            specifiedType: const FullType(int)));
    }
    if (object.passwordUpdatedAt != null) {
      result
        ..add('passwordUpdatedAt')
        ..add(serializers.serialize(object.passwordUpdatedAt,
            specifiedType: const FullType(DateTime)));
    }
    if (object.validSince != null) {
      result
        ..add('validSince')
        ..add(serializers.serialize(object.validSince,
            specifiedType: const FullType(int)));
    }
    if (object.phoneNumber != null) {
      result
        ..add('phoneNumber')
        ..add(serializers.serialize(object.phoneNumber,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  ResponseUser deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ResponseUserBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'localId':
          result.localId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'email':
          result.email = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'emailVerified':
          result.emailVerified = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'displayName':
          result.displayName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'photoUrl':
          result.photoUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'lastLoginAt':
          result.lastLoginAt = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
        case 'createdAt':
          result.createdAt = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
        case 'lastRefreshAt':
          result.lastRefreshAt = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
        case 'providerUserInfo':
          result.providerUserInfo.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(ProviderUserInfo)]))
              as BuiltList<dynamic>);
          break;
        case 'passwordHash':
          result.passwordHash = serializers.deserialize(value,
              specifiedType: const FullType(Uint8List)) as Uint8List;
          break;
        case 'salt':
          result.salt = serializers.deserialize(value,
              specifiedType: const FullType(Uint8List)) as Uint8List;
          break;
        case 'version':
          result.version = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'passwordUpdatedAt':
          result.passwordUpdatedAt = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
        case 'validSince':
          result.validSince = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'phoneNumber':
          result.phoneNumber = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$GetOobConfirmationCodeRequestSerializer
    implements StructuredSerializer<GetOobConfirmationCodeRequest> {
  @override
  final Iterable<Type> types = const [
    GetOobConfirmationCodeRequest,
    _$GetOobConfirmationCodeRequest
  ];
  @override
  final String wireName = 'GetOobConfirmationCodeRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, GetOobConfirmationCodeRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'requestType',
      serializers.serialize(object.requestType,
          specifiedType: const FullType(OobCodeType)),
    ];
    if (object.email != null) {
      result
        ..add('email')
        ..add(serializers.serialize(object.email,
            specifiedType: const FullType(String)));
    }
    if (object.updateEmail != null) {
      result
        ..add('newEmail')
        ..add(serializers.serialize(object.updateEmail,
            specifiedType: const FullType(String)));
    }
    if (object.accessToken != null) {
      result
        ..add('idToken')
        ..add(serializers.serialize(object.accessToken,
            specifiedType: const FullType(String)));
    }
    if (object.continueUrl != null) {
      result
        ..add('continueUrl')
        ..add(serializers.serialize(object.continueUrl,
            specifiedType: const FullType(String)));
    }
    if (object.iOSBundleId != null) {
      result
        ..add('iOSBundleId')
        ..add(serializers.serialize(object.iOSBundleId,
            specifiedType: const FullType(String)));
    }
    if (object.androidPackageName != null) {
      result
        ..add('androidPackageName')
        ..add(serializers.serialize(object.androidPackageName,
            specifiedType: const FullType(String)));
    }
    if (object.androidInstallApp != null) {
      result
        ..add('androidInstallApp')
        ..add(serializers.serialize(object.androidInstallApp,
            specifiedType: const FullType(bool)));
    }
    if (object.androidMinimumVersion != null) {
      result
        ..add('androidMinimumVersion')
        ..add(serializers.serialize(object.androidMinimumVersion,
            specifiedType: const FullType(String)));
    }
    if (object.handleCodeInApp != null) {
      result
        ..add('canHandleCodeInApp')
        ..add(serializers.serialize(object.handleCodeInApp,
            specifiedType: const FullType(bool)));
    }
    if (object.dynamicLinkDomain != null) {
      result
        ..add('dynamicLinkDomain')
        ..add(serializers.serialize(object.dynamicLinkDomain,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  GetOobConfirmationCodeRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new GetOobConfirmationCodeRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'requestType':
          result.requestType = serializers.deserialize(value,
              specifiedType: const FullType(OobCodeType)) as OobCodeType;
          break;
        case 'email':
          result.email = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'newEmail':
          result.updateEmail = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'idToken':
          result.accessToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'continueUrl':
          result.continueUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'iOSBundleId':
          result.iOSBundleId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'androidPackageName':
          result.androidPackageName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'androidInstallApp':
          result.androidInstallApp = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'androidMinimumVersion':
          result.androidMinimumVersion = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'canHandleCodeInApp':
          result.handleCodeInApp = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'dynamicLinkDomain':
          result.dynamicLinkDomain = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$GetOobConfirmationCodeResponseSerializer
    implements StructuredSerializer<GetOobConfirmationCodeResponse> {
  @override
  final Iterable<Type> types = const [
    GetOobConfirmationCodeResponse,
    _$GetOobConfirmationCodeResponse
  ];
  @override
  final String wireName = 'GetOobConfirmationCodeResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, GetOobConfirmationCodeResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[];
    if (object.oobCode != null) {
      result
        ..add('oobCode')
        ..add(serializers.serialize(object.oobCode,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  GetOobConfirmationCodeResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new GetOobConfirmationCodeResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'oobCode':
          result.oobCode = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$GetProjectConfigResponseSerializer
    implements StructuredSerializer<GetProjectConfigResponse> {
  @override
  final Iterable<Type> types = const [
    GetProjectConfigResponse,
    _$GetProjectConfigResponse
  ];
  @override
  final String wireName = 'GetProjectConfigResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, GetProjectConfigResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[];
    if (object.projectId != null) {
      result
        ..add('projectId')
        ..add(serializers.serialize(object.projectId,
            specifiedType: const FullType(String)));
    }
    if (object.authorizedDomains != null) {
      result
        ..add('authorizedDomains')
        ..add(serializers.serialize(object.authorizedDomains,
            specifiedType:
                const FullType(BuiltList, const [const FullType(String)])));
    }
    return result;
  }

  @override
  GetProjectConfigResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new GetProjectConfigResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'projectId':
          result.projectId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'authorizedDomains':
          result.authorizedDomains.replace(serializers.deserialize(value,
                  specifiedType:
                      const FullType(BuiltList, const [const FullType(String)]))
              as BuiltList<dynamic>);
          break;
      }
    }

    return result.build();
  }
}

class _$ResetPasswordRequestSerializer
    implements StructuredSerializer<ResetPasswordRequest> {
  @override
  final Iterable<Type> types = const [
    ResetPasswordRequest,
    _$ResetPasswordRequest
  ];
  @override
  final String wireName = 'ResetPasswordRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, ResetPasswordRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'oobCode',
      serializers.serialize(object.oobCode,
          specifiedType: const FullType(String)),
      'updatedPassword',
      serializers.serialize(object.updatedPassword,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  ResetPasswordRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ResetPasswordRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'oobCode':
          result.oobCode = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'updatedPassword':
          result.updatedPassword = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ResetPasswordResponseSerializer
    implements StructuredSerializer<ResetPasswordResponse> {
  @override
  final Iterable<Type> types = const [
    ResetPasswordResponse,
    _$ResetPasswordResponse
  ];
  @override
  final String wireName = 'ResetPasswordResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, ResetPasswordResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'email',
      serializers.serialize(object.email,
          specifiedType: const FullType(String)),
      'verifiedEmail',
      serializers.serialize(object.verifiedEmail,
          specifiedType: const FullType(String)),
      'requestType',
      serializers.serialize(object.requestType,
          specifiedType: const FullType(OobCodeType)),
    ];

    return result;
  }

  @override
  ResetPasswordResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ResetPasswordResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'email':
          result.email = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'verifiedEmail':
          result.verifiedEmail = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'requestType':
          result.requestType = serializers.deserialize(value,
              specifiedType: const FullType(OobCodeType)) as OobCodeType;
          break;
      }
    }

    return result.build();
  }
}

class _$SecureTokenRequestSerializer
    implements StructuredSerializer<SecureTokenRequest> {
  @override
  final Iterable<Type> types = const [SecureTokenRequest, _$SecureTokenRequest];
  @override
  final String wireName = 'SecureTokenRequest';

  @override
  Iterable<Object> serialize(Serializers serializers, SecureTokenRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'grantType',
      serializers.serialize(object.grantType,
          specifiedType: const FullType(SecureTokenGrantType)),
    ];
    if (object.scope != null) {
      result
        ..add('scope')
        ..add(serializers.serialize(object.scope,
            specifiedType: const FullType(String)));
    }
    if (object.refreshToken != null) {
      result
        ..add('refreshToken')
        ..add(serializers.serialize(object.refreshToken,
            specifiedType: const FullType(String)));
    }
    if (object.code != null) {
      result
        ..add('code')
        ..add(serializers.serialize(object.code,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  SecureTokenRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new SecureTokenRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'grantType':
          result.grantType = serializers.deserialize(value,
                  specifiedType: const FullType(SecureTokenGrantType))
              as SecureTokenGrantType;
          break;
        case 'scope':
          result.scope = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'refreshToken':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'code':
          result.code = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$SecureTokenResponseSerializer
    implements StructuredSerializer<SecureTokenResponse> {
  @override
  final Iterable<Type> types = const [
    SecureTokenResponse,
    _$SecureTokenResponse
  ];
  @override
  final String wireName = 'SecureTokenResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, SecureTokenResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[];
    if (object.approximateExpirationDate != null) {
      result
        ..add('expires_in')
        ..add(serializers.serialize(object.approximateExpirationDate,
            specifiedType: const FullType(DateTime)));
    }
    if (object.refreshToken != null) {
      result
        ..add('refresh_token')
        ..add(serializers.serialize(object.refreshToken,
            specifiedType: const FullType(String)));
    }
    if (object.accessToken != null) {
      result
        ..add('access_token')
        ..add(serializers.serialize(object.accessToken,
            specifiedType: const FullType(String)));
    }
    if (object.idToken != null) {
      result
        ..add('id_token')
        ..add(serializers.serialize(object.idToken,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  SecureTokenResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new SecureTokenResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'expires_in':
          result.approximateExpirationDate = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
        case 'refresh_token':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'access_token':
          result.accessToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'id_token':
          result.idToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$SendVerificationCodeRequestSerializer
    implements StructuredSerializer<SendVerificationCodeRequest> {
  @override
  final Iterable<Type> types = const [
    SendVerificationCodeRequest,
    _$SendVerificationCodeRequest
  ];
  @override
  final String wireName = 'SendVerificationCodeRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, SendVerificationCodeRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[];
    if (object.phoneNumber != null) {
      result
        ..add('phoneNumber')
        ..add(serializers.serialize(object.phoneNumber,
            specifiedType: const FullType(String)));
    }
    if (object.receipt != null) {
      result
        ..add('iosReceipt')
        ..add(serializers.serialize(object.receipt,
            specifiedType: const FullType(String)));
    }
    if (object.secret != null) {
      result
        ..add('iosSecret')
        ..add(serializers.serialize(object.secret,
            specifiedType: const FullType(String)));
    }
    if (object.recaptchaToken != null) {
      result
        ..add('recaptchaToken')
        ..add(serializers.serialize(object.recaptchaToken,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  SendVerificationCodeRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new SendVerificationCodeRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'phoneNumber':
          result.phoneNumber = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'iosReceipt':
          result.receipt = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'iosSecret':
          result.secret = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'recaptchaToken':
          result.recaptchaToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$SendVerificationCodeResponseSerializer
    implements StructuredSerializer<SendVerificationCodeResponse> {
  @override
  final Iterable<Type> types = const [
    SendVerificationCodeResponse,
    _$SendVerificationCodeResponse
  ];
  @override
  final String wireName = 'SendVerificationCodeResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, SendVerificationCodeResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'sessionInfo',
      serializers.serialize(object.sessionInfo,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  SendVerificationCodeResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new SendVerificationCodeResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'sessionInfo':
          result.sessionInfo = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ActionCodeSettings extends ActionCodeSettings {
  @override
  final String continueUrl;
  @override
  final String iOSBundleId;
  @override
  final String androidPackageName;
  @override
  final bool androidInstallIfNotAvailable;
  @override
  final String androidMinimumVersion;
  @override
  final bool handleCodeInApp;
  @override
  final String dynamicLinkDomain;

  factory _$ActionCodeSettings(
          [void Function(ActionCodeSettingsBuilder) updates]) =>
      (new ActionCodeSettingsBuilder()..update(updates)).build();

  _$ActionCodeSettings._(
      {this.continueUrl,
      this.iOSBundleId,
      this.androidPackageName,
      this.androidInstallIfNotAvailable,
      this.androidMinimumVersion,
      this.handleCodeInApp,
      this.dynamicLinkDomain})
      : super._() {
    if (handleCodeInApp == null) {
      throw new BuiltValueNullFieldError(
          'ActionCodeSettings', 'handleCodeInApp');
    }
  }

  @override
  ActionCodeSettings rebuild(
          void Function(ActionCodeSettingsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ActionCodeSettingsBuilder toBuilder() =>
      new ActionCodeSettingsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ActionCodeSettings &&
        continueUrl == other.continueUrl &&
        iOSBundleId == other.iOSBundleId &&
        androidPackageName == other.androidPackageName &&
        androidInstallIfNotAvailable == other.androidInstallIfNotAvailable &&
        androidMinimumVersion == other.androidMinimumVersion &&
        handleCodeInApp == other.handleCodeInApp &&
        dynamicLinkDomain == other.dynamicLinkDomain;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, continueUrl.hashCode), iOSBundleId.hashCode),
                        androidPackageName.hashCode),
                    androidInstallIfNotAvailable.hashCode),
                androidMinimumVersion.hashCode),
            handleCodeInApp.hashCode),
        dynamicLinkDomain.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ActionCodeSettings')
          ..add('continueUrl', continueUrl)
          ..add('iOSBundleId', iOSBundleId)
          ..add('androidPackageName', androidPackageName)
          ..add('androidInstallIfNotAvailable', androidInstallIfNotAvailable)
          ..add('androidMinimumVersion', androidMinimumVersion)
          ..add('handleCodeInApp', handleCodeInApp)
          ..add('dynamicLinkDomain', dynamicLinkDomain))
        .toString();
  }
}

class ActionCodeSettingsBuilder
    implements Builder<ActionCodeSettings, ActionCodeSettingsBuilder> {
  _$ActionCodeSettings _$v;

  String _continueUrl;
  String get continueUrl => _$this._continueUrl;
  set continueUrl(String continueUrl) => _$this._continueUrl = continueUrl;

  String _iOSBundleId;
  String get iOSBundleId => _$this._iOSBundleId;
  set iOSBundleId(String iOSBundleId) => _$this._iOSBundleId = iOSBundleId;

  String _androidPackageName;
  String get androidPackageName => _$this._androidPackageName;
  set androidPackageName(String androidPackageName) =>
      _$this._androidPackageName = androidPackageName;

  bool _androidInstallIfNotAvailable;
  bool get androidInstallIfNotAvailable => _$this._androidInstallIfNotAvailable;
  set androidInstallIfNotAvailable(bool androidInstallIfNotAvailable) =>
      _$this._androidInstallIfNotAvailable = androidInstallIfNotAvailable;

  String _androidMinimumVersion;
  String get androidMinimumVersion => _$this._androidMinimumVersion;
  set androidMinimumVersion(String androidMinimumVersion) =>
      _$this._androidMinimumVersion = androidMinimumVersion;

  bool _handleCodeInApp;
  bool get handleCodeInApp => _$this._handleCodeInApp;
  set handleCodeInApp(bool handleCodeInApp) =>
      _$this._handleCodeInApp = handleCodeInApp;

  String _dynamicLinkDomain;
  String get dynamicLinkDomain => _$this._dynamicLinkDomain;
  set dynamicLinkDomain(String dynamicLinkDomain) =>
      _$this._dynamicLinkDomain = dynamicLinkDomain;

  ActionCodeSettingsBuilder();

  ActionCodeSettingsBuilder get _$this {
    if (_$v != null) {
      _continueUrl = _$v.continueUrl;
      _iOSBundleId = _$v.iOSBundleId;
      _androidPackageName = _$v.androidPackageName;
      _androidInstallIfNotAvailable = _$v.androidInstallIfNotAvailable;
      _androidMinimumVersion = _$v.androidMinimumVersion;
      _handleCodeInApp = _$v.handleCodeInApp;
      _dynamicLinkDomain = _$v.dynamicLinkDomain;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ActionCodeSettings other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ActionCodeSettings;
  }

  @override
  void update(void Function(ActionCodeSettingsBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ActionCodeSettings build() {
    final _$result = _$v ??
        new _$ActionCodeSettings._(
            continueUrl: continueUrl,
            iOSBundleId: iOSBundleId,
            androidPackageName: androidPackageName,
            androidInstallIfNotAvailable: androidInstallIfNotAvailable,
            androidMinimumVersion: androidMinimumVersion,
            handleCodeInApp: handleCodeInApp,
            dynamicLinkDomain: dynamicLinkDomain);
    replace(_$result);
    return _$result;
  }
}

class _$AppCredential extends AppCredential {
  @override
  final String receipt;
  @override
  final String secret;

  factory _$AppCredential([void Function(AppCredentialBuilder) updates]) =>
      (new AppCredentialBuilder()..update(updates)).build();

  _$AppCredential._({this.receipt, this.secret}) : super._() {
    if (receipt == null) {
      throw new BuiltValueNullFieldError('AppCredential', 'receipt');
    }
    if (secret == null) {
      throw new BuiltValueNullFieldError('AppCredential', 'secret');
    }
  }

  @override
  AppCredential rebuild(void Function(AppCredentialBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppCredentialBuilder toBuilder() => new AppCredentialBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppCredential &&
        receipt == other.receipt &&
        secret == other.secret;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, receipt.hashCode), secret.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('AppCredential')
          ..add('receipt', receipt)
          ..add('secret', secret))
        .toString();
  }
}

class AppCredentialBuilder
    implements Builder<AppCredential, AppCredentialBuilder> {
  _$AppCredential _$v;

  String _receipt;
  String get receipt => _$this._receipt;
  set receipt(String receipt) => _$this._receipt = receipt;

  String _secret;
  String get secret => _$this._secret;
  set secret(String secret) => _$this._secret = secret;

  AppCredentialBuilder();

  AppCredentialBuilder get _$this {
    if (_$v != null) {
      _receipt = _$v.receipt;
      _secret = _$v.secret;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppCredential other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$AppCredential;
  }

  @override
  void update(void Function(AppCredentialBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$AppCredential build() {
    final _$result =
        _$v ?? new _$AppCredential._(receipt: receipt, secret: secret);
    replace(_$result);
    return _$result;
  }
}

class _$DeleteAccountRequest extends DeleteAccountRequest {
  @override
  final String accessToken;
  @override
  final String localId;

  factory _$DeleteAccountRequest(
          [void Function(DeleteAccountRequestBuilder) updates]) =>
      (new DeleteAccountRequestBuilder()..update(updates)).build();

  _$DeleteAccountRequest._({this.accessToken, this.localId}) : super._() {
    if (accessToken == null) {
      throw new BuiltValueNullFieldError('DeleteAccountRequest', 'accessToken');
    }
    if (localId == null) {
      throw new BuiltValueNullFieldError('DeleteAccountRequest', 'localId');
    }
  }

  @override
  DeleteAccountRequest rebuild(
          void Function(DeleteAccountRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeleteAccountRequestBuilder toBuilder() =>
      new DeleteAccountRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeleteAccountRequest &&
        accessToken == other.accessToken &&
        localId == other.localId;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, accessToken.hashCode), localId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('DeleteAccountRequest')
          ..add('accessToken', accessToken)
          ..add('localId', localId))
        .toString();
  }
}

class DeleteAccountRequestBuilder
    implements Builder<DeleteAccountRequest, DeleteAccountRequestBuilder> {
  _$DeleteAccountRequest _$v;

  String _accessToken;
  String get accessToken => _$this._accessToken;
  set accessToken(String accessToken) => _$this._accessToken = accessToken;

  String _localId;
  String get localId => _$this._localId;
  set localId(String localId) => _$this._localId = localId;

  DeleteAccountRequestBuilder();

  DeleteAccountRequestBuilder get _$this {
    if (_$v != null) {
      _accessToken = _$v.accessToken;
      _localId = _$v.localId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeleteAccountRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$DeleteAccountRequest;
  }

  @override
  void update(void Function(DeleteAccountRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$DeleteAccountRequest build() {
    final _$result = _$v ??
        new _$DeleteAccountRequest._(
            accessToken: accessToken, localId: localId);
    replace(_$result);
    return _$result;
  }
}

class _$EmailLinkSignInResponse extends EmailLinkSignInResponse {
  @override
  final String email;
  @override
  final String oobCode;
  @override
  final String idToken;

  factory _$EmailLinkSignInResponse(
          [void Function(EmailLinkSignInResponseBuilder) updates]) =>
      (new EmailLinkSignInResponseBuilder()..update(updates)).build();

  _$EmailLinkSignInResponse._({this.email, this.oobCode, this.idToken})
      : super._() {
    if (email == null) {
      throw new BuiltValueNullFieldError('EmailLinkSignInResponse', 'email');
    }
    if (oobCode == null) {
      throw new BuiltValueNullFieldError('EmailLinkSignInResponse', 'oobCode');
    }
  }

  @override
  EmailLinkSignInResponse rebuild(
          void Function(EmailLinkSignInResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailLinkSignInResponseBuilder toBuilder() =>
      new EmailLinkSignInResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailLinkSignInResponse &&
        email == other.email &&
        oobCode == other.oobCode &&
        idToken == other.idToken;
  }

  @override
  int get hashCode {
    return $jf(
        $jc($jc($jc(0, email.hashCode), oobCode.hashCode), idToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('EmailLinkSignInResponse')
          ..add('email', email)
          ..add('oobCode', oobCode)
          ..add('idToken', idToken))
        .toString();
  }
}

class EmailLinkSignInResponseBuilder
    implements
        Builder<EmailLinkSignInResponse, EmailLinkSignInResponseBuilder> {
  _$EmailLinkSignInResponse _$v;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _oobCode;
  String get oobCode => _$this._oobCode;
  set oobCode(String oobCode) => _$this._oobCode = oobCode;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  EmailLinkSignInResponseBuilder();

  EmailLinkSignInResponseBuilder get _$this {
    if (_$v != null) {
      _email = _$v.email;
      _oobCode = _$v.oobCode;
      _idToken = _$v.idToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailLinkSignInResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$EmailLinkSignInResponse;
  }

  @override
  void update(void Function(EmailLinkSignInResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$EmailLinkSignInResponse build() {
    final _$result = _$v ??
        new _$EmailLinkSignInResponse._(
            email: email, oobCode: oobCode, idToken: idToken);
    replace(_$result);
    return _$result;
  }
}

class _$EmailLinkSignInRequest extends EmailLinkSignInRequest {
  @override
  final String idToken;
  @override
  final String email;
  @override
  final bool isNewUser;
  @override
  final String refreshToken;
  @override
  final DateTime expiresIn;

  factory _$EmailLinkSignInRequest(
          [void Function(EmailLinkSignInRequestBuilder) updates]) =>
      (new EmailLinkSignInRequestBuilder()..update(updates)).build();

  _$EmailLinkSignInRequest._(
      {this.idToken,
      this.email,
      this.isNewUser,
      this.refreshToken,
      this.expiresIn})
      : super._() {
    if (idToken == null) {
      throw new BuiltValueNullFieldError('EmailLinkSignInRequest', 'idToken');
    }
    if (isNewUser == null) {
      throw new BuiltValueNullFieldError('EmailLinkSignInRequest', 'isNewUser');
    }
  }

  @override
  EmailLinkSignInRequest rebuild(
          void Function(EmailLinkSignInRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailLinkSignInRequestBuilder toBuilder() =>
      new EmailLinkSignInRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailLinkSignInRequest &&
        idToken == other.idToken &&
        email == other.email &&
        isNewUser == other.isNewUser &&
        refreshToken == other.refreshToken &&
        expiresIn == other.expiresIn;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc($jc($jc(0, idToken.hashCode), email.hashCode),
                isNewUser.hashCode),
            refreshToken.hashCode),
        expiresIn.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('EmailLinkSignInRequest')
          ..add('idToken', idToken)
          ..add('email', email)
          ..add('isNewUser', isNewUser)
          ..add('refreshToken', refreshToken)
          ..add('expiresIn', expiresIn))
        .toString();
  }
}

class EmailLinkSignInRequestBuilder
    implements Builder<EmailLinkSignInRequest, EmailLinkSignInRequestBuilder> {
  _$EmailLinkSignInRequest _$v;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  bool _isNewUser;
  bool get isNewUser => _$this._isNewUser;
  set isNewUser(bool isNewUser) => _$this._isNewUser = isNewUser;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  DateTime _expiresIn;
  DateTime get expiresIn => _$this._expiresIn;
  set expiresIn(DateTime expiresIn) => _$this._expiresIn = expiresIn;

  EmailLinkSignInRequestBuilder();

  EmailLinkSignInRequestBuilder get _$this {
    if (_$v != null) {
      _idToken = _$v.idToken;
      _email = _$v.email;
      _isNewUser = _$v.isNewUser;
      _refreshToken = _$v.refreshToken;
      _expiresIn = _$v.expiresIn;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailLinkSignInRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$EmailLinkSignInRequest;
  }

  @override
  void update(void Function(EmailLinkSignInRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$EmailLinkSignInRequest build() {
    final _$result = _$v ??
        new _$EmailLinkSignInRequest._(
            idToken: idToken,
            email: email,
            isNewUser: isNewUser,
            refreshToken: refreshToken,
            expiresIn: expiresIn);
    replace(_$result);
    return _$result;
  }
}

class _$GetAccountInfoRequest extends GetAccountInfoRequest {
  @override
  final String accessToken;

  factory _$GetAccountInfoRequest(
          [void Function(GetAccountInfoRequestBuilder) updates]) =>
      (new GetAccountInfoRequestBuilder()..update(updates)).build();

  _$GetAccountInfoRequest._({this.accessToken}) : super._() {
    if (accessToken == null) {
      throw new BuiltValueNullFieldError(
          'GetAccountInfoRequest', 'accessToken');
    }
  }

  @override
  GetAccountInfoRequest rebuild(
          void Function(GetAccountInfoRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GetAccountInfoRequestBuilder toBuilder() =>
      new GetAccountInfoRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GetAccountInfoRequest && accessToken == other.accessToken;
  }

  @override
  int get hashCode {
    return $jf($jc(0, accessToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('GetAccountInfoRequest')
          ..add('accessToken', accessToken))
        .toString();
  }
}

class GetAccountInfoRequestBuilder
    implements Builder<GetAccountInfoRequest, GetAccountInfoRequestBuilder> {
  _$GetAccountInfoRequest _$v;

  String _accessToken;
  String get accessToken => _$this._accessToken;
  set accessToken(String accessToken) => _$this._accessToken = accessToken;

  GetAccountInfoRequestBuilder();

  GetAccountInfoRequestBuilder get _$this {
    if (_$v != null) {
      _accessToken = _$v.accessToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GetAccountInfoRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$GetAccountInfoRequest;
  }

  @override
  void update(void Function(GetAccountInfoRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$GetAccountInfoRequest build() {
    final _$result =
        _$v ?? new _$GetAccountInfoRequest._(accessToken: accessToken);
    replace(_$result);
    return _$result;
  }
}

class _$GetAccountInfoResponse extends GetAccountInfoResponse {
  @override
  final BuiltList<ResponseUser> users;

  factory _$GetAccountInfoResponse(
          [void Function(GetAccountInfoResponseBuilder) updates]) =>
      (new GetAccountInfoResponseBuilder()..update(updates)).build();

  _$GetAccountInfoResponse._({this.users}) : super._() {
    if (users == null) {
      throw new BuiltValueNullFieldError('GetAccountInfoResponse', 'users');
    }
  }

  @override
  GetAccountInfoResponse rebuild(
          void Function(GetAccountInfoResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GetAccountInfoResponseBuilder toBuilder() =>
      new GetAccountInfoResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GetAccountInfoResponse && users == other.users;
  }

  @override
  int get hashCode {
    return $jf($jc(0, users.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('GetAccountInfoResponse')
          ..add('users', users))
        .toString();
  }
}

class GetAccountInfoResponseBuilder
    implements Builder<GetAccountInfoResponse, GetAccountInfoResponseBuilder> {
  _$GetAccountInfoResponse _$v;

  ListBuilder<ResponseUser> _users;
  ListBuilder<ResponseUser> get users =>
      _$this._users ??= new ListBuilder<ResponseUser>();
  set users(ListBuilder<ResponseUser> users) => _$this._users = users;

  GetAccountInfoResponseBuilder();

  GetAccountInfoResponseBuilder get _$this {
    if (_$v != null) {
      _users = _$v.users?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GetAccountInfoResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$GetAccountInfoResponse;
  }

  @override
  void update(void Function(GetAccountInfoResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$GetAccountInfoResponse build() {
    _$GetAccountInfoResponse _$result;
    try {
      _$result = _$v ?? new _$GetAccountInfoResponse._(users: users.build());
    } catch (_) {
      String _$failedField;
      try {
        _$failedField = 'users';
        users.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'GetAccountInfoResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$ProviderUserInfo extends ProviderUserInfo {
  @override
  final String providerId;
  @override
  final String displayName;
  @override
  final String photoUrl;
  @override
  final String federatedId;
  @override
  final String email;
  @override
  final String phoneNumber;

  factory _$ProviderUserInfo(
          [void Function(ProviderUserInfoBuilder) updates]) =>
      (new ProviderUserInfoBuilder()..update(updates)).build();

  _$ProviderUserInfo._(
      {this.providerId,
      this.displayName,
      this.photoUrl,
      this.federatedId,
      this.email,
      this.phoneNumber})
      : super._();

  @override
  ProviderUserInfo rebuild(void Function(ProviderUserInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ProviderUserInfoBuilder toBuilder() =>
      new ProviderUserInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ProviderUserInfo &&
        providerId == other.providerId &&
        displayName == other.displayName &&
        photoUrl == other.photoUrl &&
        federatedId == other.federatedId &&
        email == other.email &&
        phoneNumber == other.phoneNumber;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc($jc($jc(0, providerId.hashCode), displayName.hashCode),
                    photoUrl.hashCode),
                federatedId.hashCode),
            email.hashCode),
        phoneNumber.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ProviderUserInfo')
          ..add('providerId', providerId)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('federatedId', federatedId)
          ..add('email', email)
          ..add('phoneNumber', phoneNumber))
        .toString();
  }
}

class ProviderUserInfoBuilder
    implements Builder<ProviderUserInfo, ProviderUserInfoBuilder> {
  _$ProviderUserInfo _$v;

  String _providerId;
  String get providerId => _$this._providerId;
  set providerId(String providerId) => _$this._providerId = providerId;

  String _displayName;
  String get displayName => _$this._displayName;
  set displayName(String displayName) => _$this._displayName = displayName;

  String _photoUrl;
  String get photoUrl => _$this._photoUrl;
  set photoUrl(String photoUrl) => _$this._photoUrl = photoUrl;

  String _federatedId;
  String get federatedId => _$this._federatedId;
  set federatedId(String federatedId) => _$this._federatedId = federatedId;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _phoneNumber;
  String get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String phoneNumber) => _$this._phoneNumber = phoneNumber;

  ProviderUserInfoBuilder();

  ProviderUserInfoBuilder get _$this {
    if (_$v != null) {
      _providerId = _$v.providerId;
      _displayName = _$v.displayName;
      _photoUrl = _$v.photoUrl;
      _federatedId = _$v.federatedId;
      _email = _$v.email;
      _phoneNumber = _$v.phoneNumber;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ProviderUserInfo other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ProviderUserInfo;
  }

  @override
  void update(void Function(ProviderUserInfoBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ProviderUserInfo build() {
    final _$result = _$v ??
        new _$ProviderUserInfo._(
            providerId: providerId,
            displayName: displayName,
            photoUrl: photoUrl,
            federatedId: federatedId,
            email: email,
            phoneNumber: phoneNumber);
    replace(_$result);
    return _$result;
  }
}

class _$ResponseUser extends ResponseUser {
  @override
  final String localId;
  @override
  final String email;
  @override
  final bool emailVerified;
  @override
  final String displayName;
  @override
  final String photoUrl;
  @override
  final DateTime lastLoginAt;
  @override
  final DateTime createdAt;
  @override
  final DateTime lastRefreshAt;
  @override
  final BuiltList<ProviderUserInfo> providerUserInfo;
  @override
  final Uint8List passwordHash;
  @override
  final Uint8List salt;
  @override
  final int version;
  @override
  final DateTime passwordUpdatedAt;
  @override
  final int validSince;
  @override
  final String phoneNumber;

  factory _$ResponseUser([void Function(ResponseUserBuilder) updates]) =>
      (new ResponseUserBuilder()..update(updates)).build();

  _$ResponseUser._(
      {this.localId,
      this.email,
      this.emailVerified,
      this.displayName,
      this.photoUrl,
      this.lastLoginAt,
      this.createdAt,
      this.lastRefreshAt,
      this.providerUserInfo,
      this.passwordHash,
      this.salt,
      this.version,
      this.passwordUpdatedAt,
      this.validSince,
      this.phoneNumber})
      : super._() {
    if (lastLoginAt == null) {
      throw new BuiltValueNullFieldError('ResponseUser', 'lastLoginAt');
    }
    if (createdAt == null) {
      throw new BuiltValueNullFieldError('ResponseUser', 'createdAt');
    }
    if (lastRefreshAt == null) {
      throw new BuiltValueNullFieldError('ResponseUser', 'lastRefreshAt');
    }
    if (passwordHash == null) {
      throw new BuiltValueNullFieldError('ResponseUser', 'passwordHash');
    }
  }

  @override
  ResponseUser rebuild(void Function(ResponseUserBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ResponseUserBuilder toBuilder() => new ResponseUserBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ResponseUser &&
        localId == other.localId &&
        email == other.email &&
        emailVerified == other.emailVerified &&
        displayName == other.displayName &&
        photoUrl == other.photoUrl &&
        lastLoginAt == other.lastLoginAt &&
        createdAt == other.createdAt &&
        lastRefreshAt == other.lastRefreshAt &&
        providerUserInfo == other.providerUserInfo &&
        passwordHash == other.passwordHash &&
        salt == other.salt &&
        version == other.version &&
        passwordUpdatedAt == other.passwordUpdatedAt &&
        validSince == other.validSince &&
        phoneNumber == other.phoneNumber;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc(
                        $jc(
                            $jc(
                                $jc(
                                    $jc(
                                        $jc(
                                            $jc(
                                                $jc(
                                                    $jc(
                                                        $jc(
                                                            $jc(
                                                                0,
                                                                localId
                                                                    .hashCode),
                                                            email.hashCode),
                                                        emailVerified.hashCode),
                                                    displayName.hashCode),
                                                photoUrl.hashCode),
                                            lastLoginAt.hashCode),
                                        createdAt.hashCode),
                                    lastRefreshAt.hashCode),
                                providerUserInfo.hashCode),
                            passwordHash.hashCode),
                        salt.hashCode),
                    version.hashCode),
                passwordUpdatedAt.hashCode),
            validSince.hashCode),
        phoneNumber.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ResponseUser')
          ..add('localId', localId)
          ..add('email', email)
          ..add('emailVerified', emailVerified)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('lastLoginAt', lastLoginAt)
          ..add('createdAt', createdAt)
          ..add('lastRefreshAt', lastRefreshAt)
          ..add('providerUserInfo', providerUserInfo)
          ..add('passwordHash', passwordHash)
          ..add('salt', salt)
          ..add('version', version)
          ..add('passwordUpdatedAt', passwordUpdatedAt)
          ..add('validSince', validSince)
          ..add('phoneNumber', phoneNumber))
        .toString();
  }
}

class ResponseUserBuilder
    implements Builder<ResponseUser, ResponseUserBuilder> {
  _$ResponseUser _$v;

  String _localId;
  String get localId => _$this._localId;
  set localId(String localId) => _$this._localId = localId;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  bool _emailVerified;
  bool get emailVerified => _$this._emailVerified;
  set emailVerified(bool emailVerified) =>
      _$this._emailVerified = emailVerified;

  String _displayName;
  String get displayName => _$this._displayName;
  set displayName(String displayName) => _$this._displayName = displayName;

  String _photoUrl;
  String get photoUrl => _$this._photoUrl;
  set photoUrl(String photoUrl) => _$this._photoUrl = photoUrl;

  DateTime _lastLoginAt;
  DateTime get lastLoginAt => _$this._lastLoginAt;
  set lastLoginAt(DateTime lastLoginAt) => _$this._lastLoginAt = lastLoginAt;

  DateTime _createdAt;
  DateTime get createdAt => _$this._createdAt;
  set createdAt(DateTime createdAt) => _$this._createdAt = createdAt;

  DateTime _lastRefreshAt;
  DateTime get lastRefreshAt => _$this._lastRefreshAt;
  set lastRefreshAt(DateTime lastRefreshAt) =>
      _$this._lastRefreshAt = lastRefreshAt;

  ListBuilder<ProviderUserInfo> _providerUserInfo;
  ListBuilder<ProviderUserInfo> get providerUserInfo =>
      _$this._providerUserInfo ??= new ListBuilder<ProviderUserInfo>();
  set providerUserInfo(ListBuilder<ProviderUserInfo> providerUserInfo) =>
      _$this._providerUserInfo = providerUserInfo;

  Uint8List _passwordHash;
  Uint8List get passwordHash => _$this._passwordHash;
  set passwordHash(Uint8List passwordHash) =>
      _$this._passwordHash = passwordHash;

  Uint8List _salt;
  Uint8List get salt => _$this._salt;
  set salt(Uint8List salt) => _$this._salt = salt;

  int _version;
  int get version => _$this._version;
  set version(int version) => _$this._version = version;

  DateTime _passwordUpdatedAt;
  DateTime get passwordUpdatedAt => _$this._passwordUpdatedAt;
  set passwordUpdatedAt(DateTime passwordUpdatedAt) =>
      _$this._passwordUpdatedAt = passwordUpdatedAt;

  int _validSince;
  int get validSince => _$this._validSince;
  set validSince(int validSince) => _$this._validSince = validSince;

  String _phoneNumber;
  String get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String phoneNumber) => _$this._phoneNumber = phoneNumber;

  ResponseUserBuilder();

  ResponseUserBuilder get _$this {
    if (_$v != null) {
      _localId = _$v.localId;
      _email = _$v.email;
      _emailVerified = _$v.emailVerified;
      _displayName = _$v.displayName;
      _photoUrl = _$v.photoUrl;
      _lastLoginAt = _$v.lastLoginAt;
      _createdAt = _$v.createdAt;
      _lastRefreshAt = _$v.lastRefreshAt;
      _providerUserInfo = _$v.providerUserInfo?.toBuilder();
      _passwordHash = _$v.passwordHash;
      _salt = _$v.salt;
      _version = _$v.version;
      _passwordUpdatedAt = _$v.passwordUpdatedAt;
      _validSince = _$v.validSince;
      _phoneNumber = _$v.phoneNumber;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ResponseUser other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ResponseUser;
  }

  @override
  void update(void Function(ResponseUserBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ResponseUser build() {
    _$ResponseUser _$result;
    try {
      _$result = _$v ??
          new _$ResponseUser._(
              localId: localId,
              email: email,
              emailVerified: emailVerified,
              displayName: displayName,
              photoUrl: photoUrl,
              lastLoginAt: lastLoginAt,
              createdAt: createdAt,
              lastRefreshAt: lastRefreshAt,
              providerUserInfo: _providerUserInfo?.build(),
              passwordHash: passwordHash,
              salt: salt,
              version: version,
              passwordUpdatedAt: passwordUpdatedAt,
              validSince: validSince,
              phoneNumber: phoneNumber);
    } catch (_) {
      String _$failedField;
      try {
        _$failedField = 'providerUserInfo';
        _providerUserInfo?.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'ResponseUser', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$GetOobConfirmationCodeRequest extends GetOobConfirmationCodeRequest {
  @override
  final OobCodeType requestType;
  @override
  final String email;
  @override
  final String updateEmail;
  @override
  final String accessToken;
  @override
  final String continueUrl;
  @override
  final String iOSBundleId;
  @override
  final String androidPackageName;
  @override
  final bool androidInstallApp;
  @override
  final String androidMinimumVersion;
  @override
  final bool handleCodeInApp;
  @override
  final String dynamicLinkDomain;

  factory _$GetOobConfirmationCodeRequest(
          [void Function(GetOobConfirmationCodeRequestBuilder) updates]) =>
      (new GetOobConfirmationCodeRequestBuilder()..update(updates)).build();

  _$GetOobConfirmationCodeRequest._(
      {this.requestType,
      this.email,
      this.updateEmail,
      this.accessToken,
      this.continueUrl,
      this.iOSBundleId,
      this.androidPackageName,
      this.androidInstallApp,
      this.androidMinimumVersion,
      this.handleCodeInApp,
      this.dynamicLinkDomain})
      : super._() {
    if (requestType == null) {
      throw new BuiltValueNullFieldError(
          'GetOobConfirmationCodeRequest', 'requestType');
    }
  }

  @override
  GetOobConfirmationCodeRequest rebuild(
          void Function(GetOobConfirmationCodeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GetOobConfirmationCodeRequestBuilder toBuilder() =>
      new GetOobConfirmationCodeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GetOobConfirmationCodeRequest &&
        requestType == other.requestType &&
        email == other.email &&
        updateEmail == other.updateEmail &&
        accessToken == other.accessToken &&
        continueUrl == other.continueUrl &&
        iOSBundleId == other.iOSBundleId &&
        androidPackageName == other.androidPackageName &&
        androidInstallApp == other.androidInstallApp &&
        androidMinimumVersion == other.androidMinimumVersion &&
        handleCodeInApp == other.handleCodeInApp &&
        dynamicLinkDomain == other.dynamicLinkDomain;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc(
                        $jc(
                            $jc(
                                $jc(
                                    $jc(
                                        $jc($jc(0, requestType.hashCode),
                                            email.hashCode),
                                        updateEmail.hashCode),
                                    accessToken.hashCode),
                                continueUrl.hashCode),
                            iOSBundleId.hashCode),
                        androidPackageName.hashCode),
                    androidInstallApp.hashCode),
                androidMinimumVersion.hashCode),
            handleCodeInApp.hashCode),
        dynamicLinkDomain.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('GetOobConfirmationCodeRequest')
          ..add('requestType', requestType)
          ..add('email', email)
          ..add('updateEmail', updateEmail)
          ..add('accessToken', accessToken)
          ..add('continueUrl', continueUrl)
          ..add('iOSBundleId', iOSBundleId)
          ..add('androidPackageName', androidPackageName)
          ..add('androidInstallApp', androidInstallApp)
          ..add('androidMinimumVersion', androidMinimumVersion)
          ..add('handleCodeInApp', handleCodeInApp)
          ..add('dynamicLinkDomain', dynamicLinkDomain))
        .toString();
  }
}

class GetOobConfirmationCodeRequestBuilder
    implements
        Builder<GetOobConfirmationCodeRequest,
            GetOobConfirmationCodeRequestBuilder> {
  _$GetOobConfirmationCodeRequest _$v;

  OobCodeType _requestType;
  OobCodeType get requestType => _$this._requestType;
  set requestType(OobCodeType requestType) => _$this._requestType = requestType;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _updateEmail;
  String get updateEmail => _$this._updateEmail;
  set updateEmail(String updateEmail) => _$this._updateEmail = updateEmail;

  String _accessToken;
  String get accessToken => _$this._accessToken;
  set accessToken(String accessToken) => _$this._accessToken = accessToken;

  String _continueUrl;
  String get continueUrl => _$this._continueUrl;
  set continueUrl(String continueUrl) => _$this._continueUrl = continueUrl;

  String _iOSBundleId;
  String get iOSBundleId => _$this._iOSBundleId;
  set iOSBundleId(String iOSBundleId) => _$this._iOSBundleId = iOSBundleId;

  String _androidPackageName;
  String get androidPackageName => _$this._androidPackageName;
  set androidPackageName(String androidPackageName) =>
      _$this._androidPackageName = androidPackageName;

  bool _androidInstallApp;
  bool get androidInstallApp => _$this._androidInstallApp;
  set androidInstallApp(bool androidInstallApp) =>
      _$this._androidInstallApp = androidInstallApp;

  String _androidMinimumVersion;
  String get androidMinimumVersion => _$this._androidMinimumVersion;
  set androidMinimumVersion(String androidMinimumVersion) =>
      _$this._androidMinimumVersion = androidMinimumVersion;

  bool _handleCodeInApp;
  bool get handleCodeInApp => _$this._handleCodeInApp;
  set handleCodeInApp(bool handleCodeInApp) =>
      _$this._handleCodeInApp = handleCodeInApp;

  String _dynamicLinkDomain;
  String get dynamicLinkDomain => _$this._dynamicLinkDomain;
  set dynamicLinkDomain(String dynamicLinkDomain) =>
      _$this._dynamicLinkDomain = dynamicLinkDomain;

  GetOobConfirmationCodeRequestBuilder();

  GetOobConfirmationCodeRequestBuilder get _$this {
    if (_$v != null) {
      _requestType = _$v.requestType;
      _email = _$v.email;
      _updateEmail = _$v.updateEmail;
      _accessToken = _$v.accessToken;
      _continueUrl = _$v.continueUrl;
      _iOSBundleId = _$v.iOSBundleId;
      _androidPackageName = _$v.androidPackageName;
      _androidInstallApp = _$v.androidInstallApp;
      _androidMinimumVersion = _$v.androidMinimumVersion;
      _handleCodeInApp = _$v.handleCodeInApp;
      _dynamicLinkDomain = _$v.dynamicLinkDomain;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GetOobConfirmationCodeRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$GetOobConfirmationCodeRequest;
  }

  @override
  void update(void Function(GetOobConfirmationCodeRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$GetOobConfirmationCodeRequest build() {
    final _$result = _$v ??
        new _$GetOobConfirmationCodeRequest._(
            requestType: requestType,
            email: email,
            updateEmail: updateEmail,
            accessToken: accessToken,
            continueUrl: continueUrl,
            iOSBundleId: iOSBundleId,
            androidPackageName: androidPackageName,
            androidInstallApp: androidInstallApp,
            androidMinimumVersion: androidMinimumVersion,
            handleCodeInApp: handleCodeInApp,
            dynamicLinkDomain: dynamicLinkDomain);
    replace(_$result);
    return _$result;
  }
}

class _$GetOobConfirmationCodeResponse extends GetOobConfirmationCodeResponse {
  @override
  final String oobCode;

  factory _$GetOobConfirmationCodeResponse(
          [void Function(GetOobConfirmationCodeResponseBuilder) updates]) =>
      (new GetOobConfirmationCodeResponseBuilder()..update(updates)).build();

  _$GetOobConfirmationCodeResponse._({this.oobCode}) : super._();

  @override
  GetOobConfirmationCodeResponse rebuild(
          void Function(GetOobConfirmationCodeResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GetOobConfirmationCodeResponseBuilder toBuilder() =>
      new GetOobConfirmationCodeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GetOobConfirmationCodeResponse && oobCode == other.oobCode;
  }

  @override
  int get hashCode {
    return $jf($jc(0, oobCode.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('GetOobConfirmationCodeResponse')
          ..add('oobCode', oobCode))
        .toString();
  }
}

class GetOobConfirmationCodeResponseBuilder
    implements
        Builder<GetOobConfirmationCodeResponse,
            GetOobConfirmationCodeResponseBuilder> {
  _$GetOobConfirmationCodeResponse _$v;

  String _oobCode;
  String get oobCode => _$this._oobCode;
  set oobCode(String oobCode) => _$this._oobCode = oobCode;

  GetOobConfirmationCodeResponseBuilder();

  GetOobConfirmationCodeResponseBuilder get _$this {
    if (_$v != null) {
      _oobCode = _$v.oobCode;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GetOobConfirmationCodeResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$GetOobConfirmationCodeResponse;
  }

  @override
  void update(void Function(GetOobConfirmationCodeResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$GetOobConfirmationCodeResponse build() {
    final _$result =
        _$v ?? new _$GetOobConfirmationCodeResponse._(oobCode: oobCode);
    replace(_$result);
    return _$result;
  }
}

class _$GetProjectConfigResponse extends GetProjectConfigResponse {
  @override
  final String projectId;
  @override
  final BuiltList<String> authorizedDomains;

  factory _$GetProjectConfigResponse(
          [void Function(GetProjectConfigResponseBuilder) updates]) =>
      (new GetProjectConfigResponseBuilder()..update(updates)).build();

  _$GetProjectConfigResponse._({this.projectId, this.authorizedDomains})
      : super._();

  @override
  GetProjectConfigResponse rebuild(
          void Function(GetProjectConfigResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GetProjectConfigResponseBuilder toBuilder() =>
      new GetProjectConfigResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GetProjectConfigResponse &&
        projectId == other.projectId &&
        authorizedDomains == other.authorizedDomains;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, projectId.hashCode), authorizedDomains.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('GetProjectConfigResponse')
          ..add('projectId', projectId)
          ..add('authorizedDomains', authorizedDomains))
        .toString();
  }
}

class GetProjectConfigResponseBuilder
    implements
        Builder<GetProjectConfigResponse, GetProjectConfigResponseBuilder> {
  _$GetProjectConfigResponse _$v;

  String _projectId;
  String get projectId => _$this._projectId;
  set projectId(String projectId) => _$this._projectId = projectId;

  ListBuilder<String> _authorizedDomains;
  ListBuilder<String> get authorizedDomains =>
      _$this._authorizedDomains ??= new ListBuilder<String>();
  set authorizedDomains(ListBuilder<String> authorizedDomains) =>
      _$this._authorizedDomains = authorizedDomains;

  GetProjectConfigResponseBuilder();

  GetProjectConfigResponseBuilder get _$this {
    if (_$v != null) {
      _projectId = _$v.projectId;
      _authorizedDomains = _$v.authorizedDomains?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GetProjectConfigResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$GetProjectConfigResponse;
  }

  @override
  void update(void Function(GetProjectConfigResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$GetProjectConfigResponse build() {
    _$GetProjectConfigResponse _$result;
    try {
      _$result = _$v ??
          new _$GetProjectConfigResponse._(
              projectId: projectId,
              authorizedDomains: _authorizedDomains?.build());
    } catch (_) {
      String _$failedField;
      try {
        _$failedField = 'authorizedDomains';
        _authorizedDomains?.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'GetProjectConfigResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$ResetPasswordRequest extends ResetPasswordRequest {
  @override
  final String oobCode;
  @override
  final String updatedPassword;

  factory _$ResetPasswordRequest(
          [void Function(ResetPasswordRequestBuilder) updates]) =>
      (new ResetPasswordRequestBuilder()..update(updates)).build();

  _$ResetPasswordRequest._({this.oobCode, this.updatedPassword}) : super._() {
    if (oobCode == null) {
      throw new BuiltValueNullFieldError('ResetPasswordRequest', 'oobCode');
    }
    if (updatedPassword == null) {
      throw new BuiltValueNullFieldError(
          'ResetPasswordRequest', 'updatedPassword');
    }
  }

  @override
  ResetPasswordRequest rebuild(
          void Function(ResetPasswordRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ResetPasswordRequestBuilder toBuilder() =>
      new ResetPasswordRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ResetPasswordRequest &&
        oobCode == other.oobCode &&
        updatedPassword == other.updatedPassword;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, oobCode.hashCode), updatedPassword.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ResetPasswordRequest')
          ..add('oobCode', oobCode)
          ..add('updatedPassword', updatedPassword))
        .toString();
  }
}

class ResetPasswordRequestBuilder
    implements Builder<ResetPasswordRequest, ResetPasswordRequestBuilder> {
  _$ResetPasswordRequest _$v;

  String _oobCode;
  String get oobCode => _$this._oobCode;
  set oobCode(String oobCode) => _$this._oobCode = oobCode;

  String _updatedPassword;
  String get updatedPassword => _$this._updatedPassword;
  set updatedPassword(String updatedPassword) =>
      _$this._updatedPassword = updatedPassword;

  ResetPasswordRequestBuilder();

  ResetPasswordRequestBuilder get _$this {
    if (_$v != null) {
      _oobCode = _$v.oobCode;
      _updatedPassword = _$v.updatedPassword;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ResetPasswordRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ResetPasswordRequest;
  }

  @override
  void update(void Function(ResetPasswordRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ResetPasswordRequest build() {
    final _$result = _$v ??
        new _$ResetPasswordRequest._(
            oobCode: oobCode, updatedPassword: updatedPassword);
    replace(_$result);
    return _$result;
  }
}

class _$ResetPasswordResponse extends ResetPasswordResponse {
  @override
  final String email;
  @override
  final String verifiedEmail;
  @override
  final OobCodeType requestType;

  factory _$ResetPasswordResponse(
          [void Function(ResetPasswordResponseBuilder) updates]) =>
      (new ResetPasswordResponseBuilder()..update(updates)).build();

  _$ResetPasswordResponse._({this.email, this.verifiedEmail, this.requestType})
      : super._() {
    if (email == null) {
      throw new BuiltValueNullFieldError('ResetPasswordResponse', 'email');
    }
    if (verifiedEmail == null) {
      throw new BuiltValueNullFieldError(
          'ResetPasswordResponse', 'verifiedEmail');
    }
    if (requestType == null) {
      throw new BuiltValueNullFieldError(
          'ResetPasswordResponse', 'requestType');
    }
  }

  @override
  ResetPasswordResponse rebuild(
          void Function(ResetPasswordResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ResetPasswordResponseBuilder toBuilder() =>
      new ResetPasswordResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ResetPasswordResponse &&
        email == other.email &&
        verifiedEmail == other.verifiedEmail &&
        requestType == other.requestType;
  }

  @override
  int get hashCode {
    return $jf($jc($jc($jc(0, email.hashCode), verifiedEmail.hashCode),
        requestType.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ResetPasswordResponse')
          ..add('email', email)
          ..add('verifiedEmail', verifiedEmail)
          ..add('requestType', requestType))
        .toString();
  }
}

class ResetPasswordResponseBuilder
    implements Builder<ResetPasswordResponse, ResetPasswordResponseBuilder> {
  _$ResetPasswordResponse _$v;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _verifiedEmail;
  String get verifiedEmail => _$this._verifiedEmail;
  set verifiedEmail(String verifiedEmail) =>
      _$this._verifiedEmail = verifiedEmail;

  OobCodeType _requestType;
  OobCodeType get requestType => _$this._requestType;
  set requestType(OobCodeType requestType) => _$this._requestType = requestType;

  ResetPasswordResponseBuilder();

  ResetPasswordResponseBuilder get _$this {
    if (_$v != null) {
      _email = _$v.email;
      _verifiedEmail = _$v.verifiedEmail;
      _requestType = _$v.requestType;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ResetPasswordResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ResetPasswordResponse;
  }

  @override
  void update(void Function(ResetPasswordResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ResetPasswordResponse build() {
    final _$result = _$v ??
        new _$ResetPasswordResponse._(
            email: email,
            verifiedEmail: verifiedEmail,
            requestType: requestType);
    replace(_$result);
    return _$result;
  }
}

class _$SecureTokenRequest extends SecureTokenRequest {
  @override
  final SecureTokenGrantType grantType;
  @override
  final String scope;
  @override
  final String refreshToken;
  @override
  final String code;

  factory _$SecureTokenRequest(
          [void Function(SecureTokenRequestBuilder) updates]) =>
      (new SecureTokenRequestBuilder()..update(updates)).build();

  _$SecureTokenRequest._(
      {this.grantType, this.scope, this.refreshToken, this.code})
      : super._() {
    if (grantType == null) {
      throw new BuiltValueNullFieldError('SecureTokenRequest', 'grantType');
    }
  }

  @override
  SecureTokenRequest rebuild(
          void Function(SecureTokenRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SecureTokenRequestBuilder toBuilder() =>
      new SecureTokenRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SecureTokenRequest &&
        grantType == other.grantType &&
        scope == other.scope &&
        refreshToken == other.refreshToken &&
        code == other.code;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, grantType.hashCode), scope.hashCode),
            refreshToken.hashCode),
        code.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('SecureTokenRequest')
          ..add('grantType', grantType)
          ..add('scope', scope)
          ..add('refreshToken', refreshToken)
          ..add('code', code))
        .toString();
  }
}

class SecureTokenRequestBuilder
    implements Builder<SecureTokenRequest, SecureTokenRequestBuilder> {
  _$SecureTokenRequest _$v;

  SecureTokenGrantType _grantType;
  SecureTokenGrantType get grantType => _$this._grantType;
  set grantType(SecureTokenGrantType grantType) =>
      _$this._grantType = grantType;

  String _scope;
  String get scope => _$this._scope;
  set scope(String scope) => _$this._scope = scope;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  String _code;
  String get code => _$this._code;
  set code(String code) => _$this._code = code;

  SecureTokenRequestBuilder();

  SecureTokenRequestBuilder get _$this {
    if (_$v != null) {
      _grantType = _$v.grantType;
      _scope = _$v.scope;
      _refreshToken = _$v.refreshToken;
      _code = _$v.code;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SecureTokenRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$SecureTokenRequest;
  }

  @override
  void update(void Function(SecureTokenRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$SecureTokenRequest build() {
    final _$result = _$v ??
        new _$SecureTokenRequest._(
            grantType: grantType,
            scope: scope,
            refreshToken: refreshToken,
            code: code);
    replace(_$result);
    return _$result;
  }
}

class _$SecureTokenResponse extends SecureTokenResponse {
  @override
  final DateTime approximateExpirationDate;
  @override
  final String refreshToken;
  @override
  final String accessToken;
  @override
  final String idToken;

  factory _$SecureTokenResponse(
          [void Function(SecureTokenResponseBuilder) updates]) =>
      (new SecureTokenResponseBuilder()..update(updates)).build();

  _$SecureTokenResponse._(
      {this.approximateExpirationDate,
      this.refreshToken,
      this.accessToken,
      this.idToken})
      : super._();

  @override
  SecureTokenResponse rebuild(
          void Function(SecureTokenResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SecureTokenResponseBuilder toBuilder() =>
      new SecureTokenResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SecureTokenResponse &&
        approximateExpirationDate == other.approximateExpirationDate &&
        refreshToken == other.refreshToken &&
        accessToken == other.accessToken &&
        idToken == other.idToken;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc($jc(0, approximateExpirationDate.hashCode),
                refreshToken.hashCode),
            accessToken.hashCode),
        idToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('SecureTokenResponse')
          ..add('approximateExpirationDate', approximateExpirationDate)
          ..add('refreshToken', refreshToken)
          ..add('accessToken', accessToken)
          ..add('idToken', idToken))
        .toString();
  }
}

class SecureTokenResponseBuilder
    implements Builder<SecureTokenResponse, SecureTokenResponseBuilder> {
  _$SecureTokenResponse _$v;

  DateTime _approximateExpirationDate;
  DateTime get approximateExpirationDate => _$this._approximateExpirationDate;
  set approximateExpirationDate(DateTime approximateExpirationDate) =>
      _$this._approximateExpirationDate = approximateExpirationDate;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  String _accessToken;
  String get accessToken => _$this._accessToken;
  set accessToken(String accessToken) => _$this._accessToken = accessToken;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  SecureTokenResponseBuilder();

  SecureTokenResponseBuilder get _$this {
    if (_$v != null) {
      _approximateExpirationDate = _$v.approximateExpirationDate;
      _refreshToken = _$v.refreshToken;
      _accessToken = _$v.accessToken;
      _idToken = _$v.idToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SecureTokenResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$SecureTokenResponse;
  }

  @override
  void update(void Function(SecureTokenResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$SecureTokenResponse build() {
    final _$result = _$v ??
        new _$SecureTokenResponse._(
            approximateExpirationDate: approximateExpirationDate,
            refreshToken: refreshToken,
            accessToken: accessToken,
            idToken: idToken);
    replace(_$result);
    return _$result;
  }
}

class _$SendVerificationCodeRequest extends SendVerificationCodeRequest {
  @override
  final String phoneNumber;
  @override
  final String receipt;
  @override
  final String secret;
  @override
  final String recaptchaToken;

  factory _$SendVerificationCodeRequest(
          [void Function(SendVerificationCodeRequestBuilder) updates]) =>
      (new SendVerificationCodeRequestBuilder()..update(updates)).build();

  _$SendVerificationCodeRequest._(
      {this.phoneNumber, this.receipt, this.secret, this.recaptchaToken})
      : super._();

  @override
  SendVerificationCodeRequest rebuild(
          void Function(SendVerificationCodeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SendVerificationCodeRequestBuilder toBuilder() =>
      new SendVerificationCodeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SendVerificationCodeRequest &&
        phoneNumber == other.phoneNumber &&
        receipt == other.receipt &&
        secret == other.secret &&
        recaptchaToken == other.recaptchaToken;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, phoneNumber.hashCode), receipt.hashCode),
            secret.hashCode),
        recaptchaToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('SendVerificationCodeRequest')
          ..add('phoneNumber', phoneNumber)
          ..add('receipt', receipt)
          ..add('secret', secret)
          ..add('recaptchaToken', recaptchaToken))
        .toString();
  }
}

class SendVerificationCodeRequestBuilder
    implements
        Builder<SendVerificationCodeRequest,
            SendVerificationCodeRequestBuilder> {
  _$SendVerificationCodeRequest _$v;

  String _phoneNumber;
  String get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String phoneNumber) => _$this._phoneNumber = phoneNumber;

  String _receipt;
  String get receipt => _$this._receipt;
  set receipt(String receipt) => _$this._receipt = receipt;

  String _secret;
  String get secret => _$this._secret;
  set secret(String secret) => _$this._secret = secret;

  String _recaptchaToken;
  String get recaptchaToken => _$this._recaptchaToken;
  set recaptchaToken(String recaptchaToken) =>
      _$this._recaptchaToken = recaptchaToken;

  SendVerificationCodeRequestBuilder();

  SendVerificationCodeRequestBuilder get _$this {
    if (_$v != null) {
      _phoneNumber = _$v.phoneNumber;
      _receipt = _$v.receipt;
      _secret = _$v.secret;
      _recaptchaToken = _$v.recaptchaToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SendVerificationCodeRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$SendVerificationCodeRequest;
  }

  @override
  void update(void Function(SendVerificationCodeRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$SendVerificationCodeRequest build() {
    final _$result = _$v ??
        new _$SendVerificationCodeRequest._(
            phoneNumber: phoneNumber,
            receipt: receipt,
            secret: secret,
            recaptchaToken: recaptchaToken);
    replace(_$result);
    return _$result;
  }
}

class _$SendVerificationCodeResponse extends SendVerificationCodeResponse {
  @override
  final String sessionInfo;

  factory _$SendVerificationCodeResponse(
          [void Function(SendVerificationCodeResponseBuilder) updates]) =>
      (new SendVerificationCodeResponseBuilder()..update(updates)).build();

  _$SendVerificationCodeResponse._({this.sessionInfo}) : super._() {
    if (sessionInfo == null) {
      throw new BuiltValueNullFieldError(
          'SendVerificationCodeResponse', 'sessionInfo');
    }
  }

  @override
  SendVerificationCodeResponse rebuild(
          void Function(SendVerificationCodeResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SendVerificationCodeResponseBuilder toBuilder() =>
      new SendVerificationCodeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SendVerificationCodeResponse &&
        sessionInfo == other.sessionInfo;
  }

  @override
  int get hashCode {
    return $jf($jc(0, sessionInfo.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('SendVerificationCodeResponse')
          ..add('sessionInfo', sessionInfo))
        .toString();
  }
}

class SendVerificationCodeResponseBuilder
    implements
        Builder<SendVerificationCodeResponse,
            SendVerificationCodeResponseBuilder> {
  _$SendVerificationCodeResponse _$v;

  String _sessionInfo;
  String get sessionInfo => _$this._sessionInfo;
  set sessionInfo(String sessionInfo) => _$this._sessionInfo = sessionInfo;

  SendVerificationCodeResponseBuilder();

  SendVerificationCodeResponseBuilder get _$this {
    if (_$v != null) {
      _sessionInfo = _$v.sessionInfo;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SendVerificationCodeResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$SendVerificationCodeResponse;
  }

  @override
  void update(void Function(SendVerificationCodeResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$SendVerificationCodeResponse build() {
    final _$result =
        _$v ?? new _$SendVerificationCodeResponse._(sessionInfo: sessionInfo);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
