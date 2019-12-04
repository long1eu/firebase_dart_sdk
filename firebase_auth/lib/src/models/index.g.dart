// GENERATED CODE - DO NOT MODIFY BY HAND

part of models;

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers = (new Serializers().toBuilder()
      ..add(AdditionalUserInfoImpl.serializer)
      ..add(AuthRequestConfiguration.serializer)
      ..add(BaseAuthRequest.serializer)
      ..add(BaseAuthResponse.serializer)
      ..add(CreateAuthUriRequest.serializer)
      ..add(CreateAuthUriResponse.serializer)
      ..add(EmailPasswordAuthCredentialImpl.serializer)
      ..add(ExchangeCustomTokenRequest.serializer)
      ..add(ExchangeCustomTokenResponse.serializer)
      ..add(ExchangeRefreshTokenRequest.serializer)
      ..add(ExchangeRefreshTokenResponse.serializer)
      ..add(FacebookAuthCredentialImpl.serializer)
      ..add(GithubAuthCredentialImpl.serializer)
      ..add(GoogleAuthCredentialImpl.serializer)
      ..add(OAuthRequest.serializer)
      ..add(OAuthResponse.serializer)
      ..add(OobCodeRequest.serializer)
      ..add(OobCodeResponse.serializer)
      ..add(ProviderUserInfo.serializer)
      ..add(ResetPasswordRequest.serializer)
      ..add(ResetPasswordResponse.serializer)
      ..add(TwitterAuthCredentialImpl.serializer)
      ..add(UpdateRequest.serializer)
      ..add(UpdateResponse.serializer)
      ..add(UserDataResponse.serializer)
      ..add(UserInfoImpl.serializer)
      ..add(UserMetadataImpl.serializer)
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ProfileAttribute)]),
          () => new ListBuilder<ProfileAttribute>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ProviderType)]),
          () => new ListBuilder<ProviderType>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ProviderUserInfo)]),
          () => new ListBuilder<ProviderUserInfo>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ProviderUserInfo)]),
          () => new ListBuilder<ProviderUserInfo>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => new ListBuilder<String>()))
    .build();
Serializer<EmailPasswordAuthCredentialImpl>
    _$emailPasswordAuthCredentialImplSerializer =
    new _$EmailPasswordAuthCredentialImplSerializer();
Serializer<FacebookAuthCredentialImpl> _$facebookAuthCredentialImplSerializer =
    new _$FacebookAuthCredentialImplSerializer();
Serializer<GithubAuthCredentialImpl> _$githubAuthCredentialImplSerializer =
    new _$GithubAuthCredentialImplSerializer();
Serializer<GoogleAuthCredentialImpl> _$googleAuthCredentialImplSerializer =
    new _$GoogleAuthCredentialImplSerializer();
Serializer<TwitterAuthCredentialImpl> _$twitterAuthCredentialImplSerializer =
    new _$TwitterAuthCredentialImplSerializer();
Serializer<AuthRequestConfiguration> _$authRequestConfigurationSerializer =
    new _$AuthRequestConfigurationSerializer();
Serializer<BaseAuthRequest> _$baseAuthRequestSerializer =
    new _$BaseAuthRequestSerializer();
Serializer<BaseAuthResponse> _$baseAuthResponseSerializer =
    new _$BaseAuthResponseSerializer();
Serializer<CreateAuthUriRequest> _$createAuthUriRequestSerializer =
    new _$CreateAuthUriRequestSerializer();
Serializer<CreateAuthUriResponse> _$createAuthUriResponseSerializer =
    new _$CreateAuthUriResponseSerializer();
Serializer<ExchangeRefreshTokenRequest>
    _$exchangeRefreshTokenRequestSerializer =
    new _$ExchangeRefreshTokenRequestSerializer();
Serializer<ExchangeRefreshTokenResponse>
    _$exchangeRefreshTokenResponseSerializer =
    new _$ExchangeRefreshTokenResponseSerializer();
Serializer<ExchangeCustomTokenRequest> _$exchangeCustomTokenRequestSerializer =
    new _$ExchangeCustomTokenRequestSerializer();
Serializer<ExchangeCustomTokenResponse>
    _$exchangeCustomTokenResponseSerializer =
    new _$ExchangeCustomTokenResponseSerializer();
Serializer<OAuthRequest> _$oAuthRequestSerializer =
    new _$OAuthRequestSerializer();
Serializer<OAuthResponse> _$oAuthResponseSerializer =
    new _$OAuthResponseSerializer();
Serializer<OobCodeRequest> _$oobCodeRequestSerializer =
    new _$OobCodeRequestSerializer();
Serializer<OobCodeResponse> _$oobCodeResponseSerializer =
    new _$OobCodeResponseSerializer();
Serializer<ResetPasswordRequest> _$resetPasswordRequestSerializer =
    new _$ResetPasswordRequestSerializer();
Serializer<ResetPasswordResponse> _$resetPasswordResponseSerializer =
    new _$ResetPasswordResponseSerializer();
Serializer<UpdateRequest> _$updateRequestSerializer =
    new _$UpdateRequestSerializer();
Serializer<UpdateResponse> _$updateResponseSerializer =
    new _$UpdateResponseSerializer();
Serializer<ProviderUserInfo> _$providerUserInfoSerializer =
    new _$ProviderUserInfoSerializer();
Serializer<UserDataResponse> _$userDataResponseSerializer =
    new _$UserDataResponseSerializer();
Serializer<AdditionalUserInfoImpl> _$additionalUserInfoImplSerializer =
    new _$AdditionalUserInfoImplSerializer();
Serializer<UserInfoImpl> _$userInfoImplSerializer =
    new _$UserInfoImplSerializer();
Serializer<UserMetadataImpl> _$userMetadataImplSerializer =
    new _$UserMetadataImplSerializer();

class _$EmailPasswordAuthCredentialImplSerializer
    implements StructuredSerializer<EmailPasswordAuthCredentialImpl> {
  @override
  final Iterable<Type> types = const [
    EmailPasswordAuthCredentialImpl,
    _$EmailPasswordAuthCredentialImpl
  ];
  @override
  final String wireName = 'EmailPasswordAuthCredentialImpl';

  @override
  Iterable<Object> serialize(
      Serializers serializers, EmailPasswordAuthCredentialImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'email',
      serializers.serialize(object.email,
          specifiedType: const FullType(String)),
      'provider',
      serializers.serialize(object.provider,
          specifiedType: const FullType(ProviderType)),
    ];
    if (object.password != null) {
      result
        ..add('password')
        ..add(serializers.serialize(object.password,
            specifiedType: const FullType(String)));
    }
    if (object.link != null) {
      result
        ..add('link')
        ..add(serializers.serialize(object.link,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  EmailPasswordAuthCredentialImpl deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new EmailPasswordAuthCredentialImplBuilder();

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
        case 'password':
          result.password = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'link':
          result.link = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'provider':
          result.provider = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
      }
    }

    return result.build();
  }
}

class _$FacebookAuthCredentialImplSerializer
    implements StructuredSerializer<FacebookAuthCredentialImpl> {
  @override
  final Iterable<Type> types = const [
    FacebookAuthCredentialImpl,
    _$FacebookAuthCredentialImpl
  ];
  @override
  final String wireName = 'FacebookAuthCredentialImpl';

  @override
  Iterable<Object> serialize(
      Serializers serializers, FacebookAuthCredentialImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'accessToken',
      serializers.serialize(object.accessToken,
          specifiedType: const FullType(String)),
      'provider',
      serializers.serialize(object.provider,
          specifiedType: const FullType(ProviderType)),
    ];

    return result;
  }

  @override
  FacebookAuthCredentialImpl deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new FacebookAuthCredentialImplBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'accessToken':
          result.accessToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'provider':
          result.provider = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
      }
    }

    return result.build();
  }
}

class _$GithubAuthCredentialImplSerializer
    implements StructuredSerializer<GithubAuthCredentialImpl> {
  @override
  final Iterable<Type> types = const [
    GithubAuthCredentialImpl,
    _$GithubAuthCredentialImpl
  ];
  @override
  final String wireName = 'GithubAuthCredentialImpl';

  @override
  Iterable<Object> serialize(
      Serializers serializers, GithubAuthCredentialImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'token',
      serializers.serialize(object.token,
          specifiedType: const FullType(String)),
      'provider',
      serializers.serialize(object.provider,
          specifiedType: const FullType(ProviderType)),
    ];

    return result;
  }

  @override
  GithubAuthCredentialImpl deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new GithubAuthCredentialImplBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'token':
          result.token = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'provider':
          result.provider = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
      }
    }

    return result.build();
  }
}

class _$GoogleAuthCredentialImplSerializer
    implements StructuredSerializer<GoogleAuthCredentialImpl> {
  @override
  final Iterable<Type> types = const [
    GoogleAuthCredentialImpl,
    _$GoogleAuthCredentialImpl
  ];
  @override
  final String wireName = 'GoogleAuthCredentialImpl';

  @override
  Iterable<Object> serialize(
      Serializers serializers, GoogleAuthCredentialImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'idToken',
      serializers.serialize(object.idToken,
          specifiedType: const FullType(String)),
      'accessToken',
      serializers.serialize(object.accessToken,
          specifiedType: const FullType(String)),
      'provider',
      serializers.serialize(object.provider,
          specifiedType: const FullType(ProviderType)),
    ];

    return result;
  }

  @override
  GoogleAuthCredentialImpl deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new GoogleAuthCredentialImplBuilder();

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
        case 'accessToken':
          result.accessToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'provider':
          result.provider = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
      }
    }

    return result.build();
  }
}

class _$TwitterAuthCredentialImplSerializer
    implements StructuredSerializer<TwitterAuthCredentialImpl> {
  @override
  final Iterable<Type> types = const [
    TwitterAuthCredentialImpl,
    _$TwitterAuthCredentialImpl
  ];
  @override
  final String wireName = 'TwitterAuthCredentialImpl';

  @override
  Iterable<Object> serialize(
      Serializers serializers, TwitterAuthCredentialImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'authToken',
      serializers.serialize(object.authToken,
          specifiedType: const FullType(String)),
      'authTokenSecret',
      serializers.serialize(object.authTokenSecret,
          specifiedType: const FullType(String)),
      'provider',
      serializers.serialize(object.provider,
          specifiedType: const FullType(ProviderType)),
    ];

    return result;
  }

  @override
  TwitterAuthCredentialImpl deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new TwitterAuthCredentialImplBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'authToken':
          result.authToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'authTokenSecret':
          result.authTokenSecret = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'provider':
          result.provider = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
      }
    }

    return result.build();
  }
}

class _$AuthRequestConfigurationSerializer
    implements StructuredSerializer<AuthRequestConfiguration> {
  @override
  final Iterable<Type> types = const [
    AuthRequestConfiguration,
    _$AuthRequestConfiguration
  ];
  @override
  final String wireName = 'AuthRequestConfiguration';

  @override
  Iterable<Object> serialize(
      Serializers serializers, AuthRequestConfiguration object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'apiKey',
      serializers.serialize(object.apiKey,
          specifiedType: const FullType(String)),
      'languageCode',
      serializers.serialize(object.languageCode,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  AuthRequestConfiguration deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new AuthRequestConfigurationBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'apiKey':
          result.apiKey = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'languageCode':
          result.languageCode = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$BaseAuthRequestSerializer
    implements StructuredSerializer<BaseAuthRequest> {
  @override
  final Iterable<Type> types = const [BaseAuthRequest, _$BaseAuthRequest];
  @override
  final String wireName = 'BaseAuthRequest';

  @override
  Iterable<Object> serialize(Serializers serializers, BaseAuthRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'returnSecureToken',
      serializers.serialize(object.returnSecureToken,
          specifiedType: const FullType(bool)),
    ];
    if (object.email != null) {
      result
        ..add('email')
        ..add(serializers.serialize(object.email,
            specifiedType: const FullType(String)));
    }
    if (object.password != null) {
      result
        ..add('password')
        ..add(serializers.serialize(object.password,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  BaseAuthRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new BaseAuthRequestBuilder();

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
        case 'password':
          result.password = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'returnSecureToken':
          result.returnSecureToken = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$BaseAuthResponseSerializer
    implements StructuredSerializer<BaseAuthResponse> {
  @override
  final Iterable<Type> types = const [BaseAuthResponse, _$BaseAuthResponse];
  @override
  final String wireName = 'BaseAuthResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, BaseAuthResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'idToken',
      serializers.serialize(object.idToken,
          specifiedType: const FullType(String)),
      'refreshToken',
      serializers.serialize(object.refreshToken,
          specifiedType: const FullType(String)),
      'expiresIn',
      serializers.serialize(object.expiresIn,
          specifiedType: const FullType(int)),
      'localId',
      serializers.serialize(object.localId,
          specifiedType: const FullType(String)),
    ];
    if (object.email != null) {
      result
        ..add('email')
        ..add(serializers.serialize(object.email,
            specifiedType: const FullType(String)));
    }
    if (object.registered != null) {
      result
        ..add('registered')
        ..add(serializers.serialize(object.registered,
            specifiedType: const FullType(bool)));
    }
    return result;
  }

  @override
  BaseAuthResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new BaseAuthResponseBuilder();

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
        case 'refreshToken':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'expiresIn':
          result.expiresIn = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'localId':
          result.localId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'registered':
          result.registered = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$CreateAuthUriRequestSerializer
    implements StructuredSerializer<CreateAuthUriRequest> {
  @override
  final Iterable<Type> types = const [
    CreateAuthUriRequest,
    _$CreateAuthUriRequest
  ];
  @override
  final String wireName = 'CreateAuthUriRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, CreateAuthUriRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'identifier',
      serializers.serialize(object.identifier,
          specifiedType: const FullType(String)),
      'continueUri',
      serializers.serialize(object.continueUri,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  CreateAuthUriRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new CreateAuthUriRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'identifier':
          result.identifier = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'continueUri':
          result.continueUri = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$CreateAuthUriResponseSerializer
    implements StructuredSerializer<CreateAuthUriResponse> {
  @override
  final Iterable<Type> types = const [
    CreateAuthUriResponse,
    _$CreateAuthUriResponse
  ];
  @override
  final String wireName = 'CreateAuthUriResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, CreateAuthUriResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'registered',
      serializers.serialize(object.registered,
          specifiedType: const FullType(bool)),
    ];
    if (object.allProviders != null) {
      result
        ..add('allProviders')
        ..add(serializers.serialize(object.allProviders,
            specifiedType:
                const FullType(BuiltList, const [const FullType(String)])));
    }
    return result;
  }

  @override
  CreateAuthUriResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new CreateAuthUriResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'allProviders':
          result.allProviders.replace(serializers.deserialize(value,
                  specifiedType:
                      const FullType(BuiltList, const [const FullType(String)]))
              as BuiltList<dynamic>);
          break;
        case 'registered':
          result.registered = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$ExchangeRefreshTokenRequestSerializer
    implements StructuredSerializer<ExchangeRefreshTokenRequest> {
  @override
  final Iterable<Type> types = const [
    ExchangeRefreshTokenRequest,
    _$ExchangeRefreshTokenRequest
  ];
  @override
  final String wireName = 'ExchangeRefreshTokenRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, ExchangeRefreshTokenRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'grant_type',
      serializers.serialize(object.grantType,
          specifiedType: const FullType(String)),
      'refresh_token',
      serializers.serialize(object.refreshToken,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  ExchangeRefreshTokenRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ExchangeRefreshTokenRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'grant_type':
          result.grantType = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'refresh_token':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ExchangeRefreshTokenResponseSerializer
    implements StructuredSerializer<ExchangeRefreshTokenResponse> {
  @override
  final Iterable<Type> types = const [
    ExchangeRefreshTokenResponse,
    _$ExchangeRefreshTokenResponse
  ];
  @override
  final String wireName = 'ExchangeRefreshTokenResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, ExchangeRefreshTokenResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'expires_in',
      serializers.serialize(object.expiresIn,
          specifiedType: const FullType(int)),
      'token_type',
      serializers.serialize(object.tokenType,
          specifiedType: const FullType(String)),
      'id_token',
      serializers.serialize(object.idToken,
          specifiedType: const FullType(String)),
      'user_id',
      serializers.serialize(object.userId,
          specifiedType: const FullType(String)),
      'project_id',
      serializers.serialize(object.projectId,
          specifiedType: const FullType(String)),
    ];
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
    return result;
  }

  @override
  ExchangeRefreshTokenResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ExchangeRefreshTokenResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'expires_in':
          result.expiresIn = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'token_type':
          result.tokenType = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
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
        case 'user_id':
          result.userId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'project_id':
          result.projectId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ExchangeCustomTokenRequestSerializer
    implements StructuredSerializer<ExchangeCustomTokenRequest> {
  @override
  final Iterable<Type> types = const [
    ExchangeCustomTokenRequest,
    _$ExchangeCustomTokenRequest
  ];
  @override
  final String wireName = 'ExchangeCustomTokenRequest';

  @override
  Iterable<Object> serialize(
      Serializers serializers, ExchangeCustomTokenRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'token',
      serializers.serialize(object.token,
          specifiedType: const FullType(String)),
      'returnSecureToken',
      serializers.serialize(object.returnSecureToken,
          specifiedType: const FullType(bool)),
    ];

    return result;
  }

  @override
  ExchangeCustomTokenRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ExchangeCustomTokenRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'token':
          result.token = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'returnSecureToken':
          result.returnSecureToken = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$ExchangeCustomTokenResponseSerializer
    implements StructuredSerializer<ExchangeCustomTokenResponse> {
  @override
  final Iterable<Type> types = const [
    ExchangeCustomTokenResponse,
    _$ExchangeCustomTokenResponse
  ];
  @override
  final String wireName = 'ExchangeCustomTokenResponse';

  @override
  Iterable<Object> serialize(
      Serializers serializers, ExchangeCustomTokenResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'idToken',
      serializers.serialize(object.idToken,
          specifiedType: const FullType(String)),
      'refreshToken',
      serializers.serialize(object.refreshToken,
          specifiedType: const FullType(String)),
      'expiresIn',
      serializers.serialize(object.expiresIn,
          specifiedType: const FullType(int)),
    ];

    return result;
  }

  @override
  ExchangeCustomTokenResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ExchangeCustomTokenResponseBuilder();

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
        case 'refreshToken':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'expiresIn':
          result.expiresIn = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
      }
    }

    return result.build();
  }
}

class _$OAuthRequestSerializer implements StructuredSerializer<OAuthRequest> {
  @override
  final Iterable<Type> types = const [OAuthRequest, _$OAuthRequest];
  @override
  final String wireName = 'OAuthRequest';

  @override
  Iterable<Object> serialize(Serializers serializers, OAuthRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'requestUri',
      serializers.serialize(object.requestUri,
          specifiedType: const FullType(String)),
      'postBody',
      serializers.serialize(object.postBody,
          specifiedType: const FullType(String)),
      'returnIdpCredential',
      serializers.serialize(object.returnIdpCredential,
          specifiedType: const FullType(bool)),
      'returnSecureToken',
      serializers.serialize(object.returnSecureToken,
          specifiedType: const FullType(bool)),
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
  OAuthRequest deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new OAuthRequestBuilder();

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
        case 'requestUri':
          result.requestUri = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'postBody':
          result.postBody = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'returnIdpCredential':
          result.returnIdpCredential = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'returnSecureToken':
          result.returnSecureToken = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$OAuthResponseSerializer implements StructuredSerializer<OAuthResponse> {
  @override
  final Iterable<Type> types = const [OAuthResponse, _$OAuthResponse];
  @override
  final String wireName = 'OAuthResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, OAuthResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'federatedId',
      serializers.serialize(object.federatedId,
          specifiedType: const FullType(String)),
      'providerId',
      serializers.serialize(object.providerId,
          specifiedType: const FullType(ProviderType)),
      'localId',
      serializers.serialize(object.localId,
          specifiedType: const FullType(String)),
      'emailVerified',
      serializers.serialize(object.emailVerified,
          specifiedType: const FullType(bool)),
      'email',
      serializers.serialize(object.email,
          specifiedType: const FullType(String)),
      'rawUserInfo',
      serializers.serialize(object.rawUserInfo,
          specifiedType: const FullType(String)),
      'firstName',
      serializers.serialize(object.firstName,
          specifiedType: const FullType(String)),
      'lastName',
      serializers.serialize(object.lastName,
          specifiedType: const FullType(String)),
      'fullName',
      serializers.serialize(object.fullName,
          specifiedType: const FullType(String)),
      'displayName',
      serializers.serialize(object.displayName,
          specifiedType: const FullType(String)),
      'photoUrl',
      serializers.serialize(object.photoUrl,
          specifiedType: const FullType(String)),
      'idToken',
      serializers.serialize(object.idToken,
          specifiedType: const FullType(String)),
      'refreshToken',
      serializers.serialize(object.refreshToken,
          specifiedType: const FullType(String)),
      'expiresIn',
      serializers.serialize(object.expiresIn,
          specifiedType: const FullType(int)),
    ];
    if (object.oauthIdToken != null) {
      result
        ..add('oauthIdToken')
        ..add(serializers.serialize(object.oauthIdToken,
            specifiedType: const FullType(String)));
    }
    if (object.oauthAccessToken != null) {
      result
        ..add('oauthAccessToken')
        ..add(serializers.serialize(object.oauthAccessToken,
            specifiedType: const FullType(String)));
    }
    if (object.oauthTokenSecret != null) {
      result
        ..add('oauthTokenSecret')
        ..add(serializers.serialize(object.oauthTokenSecret,
            specifiedType: const FullType(String)));
    }
    if (object.needConfirmation != null) {
      result
        ..add('needConfirmation')
        ..add(serializers.serialize(object.needConfirmation,
            specifiedType: const FullType(bool)));
    }
    return result;
  }

  @override
  OAuthResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new OAuthResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'federatedId':
          result.federatedId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'providerId':
          result.providerId = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
        case 'localId':
          result.localId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'emailVerified':
          result.emailVerified = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'email':
          result.email = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'oauthIdToken':
          result.oauthIdToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'oauthAccessToken':
          result.oauthAccessToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'oauthTokenSecret':
          result.oauthTokenSecret = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'rawUserInfo':
          result.rawUserInfo = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'firstName':
          result.firstName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'lastName':
          result.lastName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'fullName':
          result.fullName = serializers.deserialize(value,
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
        case 'idToken':
          result.idToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'refreshToken':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'expiresIn':
          result.expiresIn = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'needConfirmation':
          result.needConfirmation = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$OobCodeRequestSerializer
    implements StructuredSerializer<OobCodeRequest> {
  @override
  final Iterable<Type> types = const [OobCodeRequest, _$OobCodeRequest];
  @override
  final String wireName = 'OobCodeRequest';

  @override
  Iterable<Object> serialize(Serializers serializers, OobCodeRequest object,
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
    if (object.newEmail != null) {
      result
        ..add('newEmail')
        ..add(serializers.serialize(object.newEmail,
            specifiedType: const FullType(String)));
    }
    if (object.idToken != null) {
      result
        ..add('idToken')
        ..add(serializers.serialize(object.idToken,
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
    if (object.canHandleCodeInApp != null) {
      result
        ..add('canHandleCodeInApp')
        ..add(serializers.serialize(object.canHandleCodeInApp,
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
  OobCodeRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new OobCodeRequestBuilder();

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
          result.newEmail = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'idToken':
          result.idToken = serializers.deserialize(value,
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
          result.canHandleCodeInApp = serializers.deserialize(value,
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

class _$OobCodeResponseSerializer
    implements StructuredSerializer<OobCodeResponse> {
  @override
  final Iterable<Type> types = const [OobCodeResponse, _$OobCodeResponse];
  @override
  final String wireName = 'OobCodeResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, OobCodeResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'email',
      serializers.serialize(object.email,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  OobCodeResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new OobCodeResponseBuilder();

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
    ];
    if (object.newPassword != null) {
      result
        ..add('newPassword')
        ..add(serializers.serialize(object.newPassword,
            specifiedType: const FullType(String)));
    }
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
        case 'newPassword':
          result.newPassword = serializers.deserialize(value,
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
        case 'requestType':
          result.requestType = serializers.deserialize(value,
              specifiedType: const FullType(OobCodeType)) as OobCodeType;
          break;
      }
    }

    return result.build();
  }
}

class _$UpdateRequestSerializer implements StructuredSerializer<UpdateRequest> {
  @override
  final Iterable<Type> types = const [UpdateRequest, _$UpdateRequest];
  @override
  final String wireName = 'UpdateRequest';

  @override
  Iterable<Object> serialize(Serializers serializers, UpdateRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[];
    if (object.idToken != null) {
      result
        ..add('idToken')
        ..add(serializers.serialize(object.idToken,
            specifiedType: const FullType(String)));
    }
    if (object.email != null) {
      result
        ..add('email')
        ..add(serializers.serialize(object.email,
            specifiedType: const FullType(String)));
    }
    if (object.password != null) {
      result
        ..add('password')
        ..add(serializers.serialize(object.password,
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
    if (object.deleteAttribute != null) {
      result
        ..add('deleteAttribute')
        ..add(serializers.serialize(object.deleteAttribute,
            specifiedType: const FullType(
                BuiltList, const [const FullType(ProfileAttribute)])));
    }
    if (object.returnSecureToken != null) {
      result
        ..add('returnSecureToken')
        ..add(serializers.serialize(object.returnSecureToken,
            specifiedType: const FullType(bool)));
    }
    if (object.deleteProvider != null) {
      result
        ..add('deleteProvider')
        ..add(serializers.serialize(object.deleteProvider,
            specifiedType: const FullType(
                BuiltList, const [const FullType(ProviderType)])));
    }
    if (object.oobCode != null) {
      result
        ..add('oobCode')
        ..add(serializers.serialize(object.oobCode,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  UpdateRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new UpdateRequestBuilder();

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
        case 'password':
          result.password = serializers.deserialize(value,
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
        case 'deleteAttribute':
          result.deleteAttribute.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(ProfileAttribute)]))
              as BuiltList<dynamic>);
          break;
        case 'returnSecureToken':
          result.returnSecureToken = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'deleteProvider':
          result.deleteProvider.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(ProviderType)]))
              as BuiltList<dynamic>);
          break;
        case 'oobCode':
          result.oobCode = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$UpdateResponseSerializer
    implements StructuredSerializer<UpdateResponse> {
  @override
  final Iterable<Type> types = const [UpdateResponse, _$UpdateResponse];
  @override
  final String wireName = 'UpdateResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, UpdateResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'email',
      serializers.serialize(object.email,
          specifiedType: const FullType(String)),
      'passwordHash',
      serializers.serialize(object.passwordHash,
          specifiedType: const FullType(String)),
      'providerUserInfo',
      serializers.serialize(object.providerUserInfo,
          specifiedType: const FullType(
              BuiltList, const [const FullType(ProviderUserInfo)])),
      'idToken',
      serializers.serialize(object.idToken,
          specifiedType: const FullType(String)),
      'refreshToken',
      serializers.serialize(object.refreshToken,
          specifiedType: const FullType(String)),
      'expiresIn',
      serializers.serialize(object.expiresIn,
          specifiedType: const FullType(String)),
    ];
    if (object.localId != null) {
      result
        ..add('localId')
        ..add(serializers.serialize(object.localId,
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
    if (object.emailVerified != null) {
      result
        ..add('emailVerified')
        ..add(serializers.serialize(object.emailVerified,
            specifiedType: const FullType(bool)));
    }
    return result;
  }

  @override
  UpdateResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new UpdateResponseBuilder();

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
        case 'displayName':
          result.displayName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'photoUrl':
          result.photoUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'passwordHash':
          result.passwordHash = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'providerUserInfo':
          result.providerUserInfo.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(ProviderUserInfo)]))
              as BuiltList<dynamic>);
          break;
        case 'idToken':
          result.idToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'refreshToken':
          result.refreshToken = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'expiresIn':
          result.expiresIn = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'emailVerified':
          result.emailVerified = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
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
    final result = <Object>[
      'providerId',
      serializers.serialize(object.providerId,
          specifiedType: const FullType(ProviderType)),
      'federatedId',
      serializers.serialize(object.federatedId,
          specifiedType: const FullType(String)),
    ];
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
              specifiedType: const FullType(ProviderType)) as ProviderType;
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

class _$UserDataResponseSerializer
    implements StructuredSerializer<UserDataResponse> {
  @override
  final Iterable<Type> types = const [UserDataResponse, _$UserDataResponse];
  @override
  final String wireName = 'UserDataResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, UserDataResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'localId',
      serializers.serialize(object.localId,
          specifiedType: const FullType(String)),
      'providerUserInfo',
      serializers.serialize(object.providerUserInfo,
          specifiedType: const FullType(
              BuiltList, const [const FullType(ProviderUserInfo)])),
      'lastLoginAt',
      serializers.serialize(object.lastLoginAt,
          specifiedType: const FullType(int)),
      'createdAt',
      serializers.serialize(object.createdAt,
          specifiedType: const FullType(int)),
    ];
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
    if (object.phoneNumber != null) {
      result
        ..add('phoneNumber')
        ..add(serializers.serialize(object.phoneNumber,
            specifiedType: const FullType(String)));
    }
    if (object.passwordHash != null) {
      result
        ..add('passwordHash')
        ..add(serializers.serialize(object.passwordHash,
            specifiedType: const FullType(String)));
    }
    if (object.passwordUpdatedAt != null) {
      result
        ..add('passwordUpdatedAt')
        ..add(serializers.serialize(object.passwordUpdatedAt,
            specifiedType: const FullType(double)));
    }
    if (object.validSince != null) {
      result
        ..add('validSince')
        ..add(serializers.serialize(object.validSince,
            specifiedType: const FullType(int)));
    }
    if (object.disabled != null) {
      result
        ..add('disabled')
        ..add(serializers.serialize(object.disabled,
            specifiedType: const FullType(bool)));
    }
    if (object.customAuth != null) {
      result
        ..add('customAuth')
        ..add(serializers.serialize(object.customAuth,
            specifiedType: const FullType(bool)));
    }
    return result;
  }

  @override
  UserDataResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new UserDataResponseBuilder();

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
        case 'providerUserInfo':
          result.providerUserInfo.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(ProviderUserInfo)]))
              as BuiltList<dynamic>);
          break;
        case 'photoUrl':
          result.photoUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'phoneNumber':
          result.phoneNumber = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'passwordHash':
          result.passwordHash = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'passwordUpdatedAt':
          result.passwordUpdatedAt = serializers.deserialize(value,
              specifiedType: const FullType(double)) as double;
          break;
        case 'validSince':
          result.validSince = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'disabled':
          result.disabled = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'lastLoginAt':
          result.lastLoginAt = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'createdAt':
          result.createdAt = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'customAuth':
          result.customAuth = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$AdditionalUserInfoImplSerializer
    implements StructuredSerializer<AdditionalUserInfoImpl> {
  @override
  final Iterable<Type> types = const [
    AdditionalUserInfoImpl,
    _$AdditionalUserInfoImpl
  ];
  @override
  final String wireName = 'AdditionalUserInfoImpl';

  @override
  Iterable<Object> serialize(
      Serializers serializers, AdditionalUserInfoImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'isNewUser',
      serializers.serialize(object.isNewUser,
          specifiedType: const FullType(bool)),
    ];
    if (object.providerId != null) {
      result
        ..add('providerId')
        ..add(serializers.serialize(object.providerId,
            specifiedType: const FullType(ProviderType)));
    }
    if (object.profile != null) {
      result
        ..add('profile')
        ..add(serializers.serialize(object.profile,
            specifiedType: const FullType(MapBuilder,
                const [const FullType(String), const FullType(JsonObject)])));
    }
    if (object.username != null) {
      result
        ..add('username')
        ..add(serializers.serialize(object.username,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  AdditionalUserInfoImpl deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new AdditionalUserInfoImplBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'providerId':
          result.providerId = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
        case 'profile':
          result.profile = serializers.deserialize(value,
              specifiedType: const FullType(MapBuilder, const [
                const FullType(String),
                const FullType(JsonObject)
              ])) as MapBuilder<String, JsonObject>;
          break;
        case 'username':
          result.username = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'isNewUser':
          result.isNewUser = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$UserInfoImplSerializer implements StructuredSerializer<UserInfoImpl> {
  @override
  final Iterable<Type> types = const [UserInfoImpl, _$UserInfoImpl];
  @override
  final String wireName = 'UserInfoImpl';

  @override
  Iterable<Object> serialize(Serializers serializers, UserInfoImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'uid',
      serializers.serialize(object.uid, specifiedType: const FullType(String)),
    ];
    if (object.providerId != null) {
      result
        ..add('providerId')
        ..add(serializers.serialize(object.providerId,
            specifiedType: const FullType(ProviderType)));
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
    if (object.isEmailVerified != null) {
      result
        ..add('isEmailVerified')
        ..add(serializers.serialize(object.isEmailVerified,
            specifiedType: const FullType(bool)));
    }
    return result;
  }

  @override
  UserInfoImpl deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new UserInfoImplBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'uid':
          result.uid = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'providerId':
          result.providerId = serializers.deserialize(value,
              specifiedType: const FullType(ProviderType)) as ProviderType;
          break;
        case 'displayName':
          result.displayName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'photoUrl':
          result.photoUrl = serializers.deserialize(value,
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
        case 'isEmailVerified':
          result.isEmailVerified = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$UserMetadataImplSerializer
    implements StructuredSerializer<UserMetadataImpl> {
  @override
  final Iterable<Type> types = const [UserMetadataImpl, _$UserMetadataImpl];
  @override
  final String wireName = 'UserMetadataImpl';

  @override
  Iterable<Object> serialize(Serializers serializers, UserMetadataImpl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'lastSignInDate',
      serializers.serialize(object.lastSignInDate,
          specifiedType: const FullType(DateTime)),
      'creationDate',
      serializers.serialize(object.creationDate,
          specifiedType: const FullType(DateTime)),
    ];

    return result;
  }

  @override
  UserMetadataImpl deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new UserMetadataImplBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'lastSignInDate':
          result.lastSignInDate = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
        case 'creationDate':
          result.creationDate = serializers.deserialize(value,
              specifiedType: const FullType(DateTime)) as DateTime;
          break;
      }
    }

    return result.build();
  }
}

class _$EmailPasswordAuthCredentialImpl
    extends EmailPasswordAuthCredentialImpl {
  @override
  final String email;
  @override
  final String password;
  @override
  final String link;
  @override
  final ProviderType provider;

  factory _$EmailPasswordAuthCredentialImpl(
          [void Function(EmailPasswordAuthCredentialImplBuilder) updates]) =>
      (new EmailPasswordAuthCredentialImplBuilder()..update(updates)).build();

  _$EmailPasswordAuthCredentialImpl._(
      {this.email, this.password, this.link, this.provider})
      : super._() {
    if (email == null) {
      throw new BuiltValueNullFieldError(
          'EmailPasswordAuthCredentialImpl', 'email');
    }
    if (provider == null) {
      throw new BuiltValueNullFieldError(
          'EmailPasswordAuthCredentialImpl', 'provider');
    }
  }

  @override
  EmailPasswordAuthCredentialImpl rebuild(
          void Function(EmailPasswordAuthCredentialImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailPasswordAuthCredentialImplBuilder toBuilder() =>
      new EmailPasswordAuthCredentialImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailPasswordAuthCredentialImpl &&
        email == other.email &&
        password == other.password &&
        link == other.link &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, email.hashCode), password.hashCode), link.hashCode),
        provider.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('EmailPasswordAuthCredentialImpl')
          ..add('email', email)
          ..add('password', password)
          ..add('link', link)
          ..add('provider', provider))
        .toString();
  }
}

class EmailPasswordAuthCredentialImplBuilder
    implements
        Builder<EmailPasswordAuthCredentialImpl,
            EmailPasswordAuthCredentialImplBuilder> {
  _$EmailPasswordAuthCredentialImpl _$v;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _password;
  String get password => _$this._password;
  set password(String password) => _$this._password = password;

  String _link;
  String get link => _$this._link;
  set link(String link) => _$this._link = link;

  ProviderType _provider;
  ProviderType get provider => _$this._provider;
  set provider(ProviderType provider) => _$this._provider = provider;

  EmailPasswordAuthCredentialImplBuilder();

  EmailPasswordAuthCredentialImplBuilder get _$this {
    if (_$v != null) {
      _email = _$v.email;
      _password = _$v.password;
      _link = _$v.link;
      _provider = _$v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailPasswordAuthCredentialImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$EmailPasswordAuthCredentialImpl;
  }

  @override
  void update(void Function(EmailPasswordAuthCredentialImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$EmailPasswordAuthCredentialImpl build() {
    final _$result = _$v ??
        new _$EmailPasswordAuthCredentialImpl._(
            email: email, password: password, link: link, provider: provider);
    replace(_$result);
    return _$result;
  }
}

class _$FacebookAuthCredentialImpl extends FacebookAuthCredentialImpl {
  @override
  final String accessToken;
  @override
  final ProviderType provider;

  factory _$FacebookAuthCredentialImpl(
          [void Function(FacebookAuthCredentialImplBuilder) updates]) =>
      (new FacebookAuthCredentialImplBuilder()..update(updates)).build();

  _$FacebookAuthCredentialImpl._({this.accessToken, this.provider})
      : super._() {
    if (accessToken == null) {
      throw new BuiltValueNullFieldError(
          'FacebookAuthCredentialImpl', 'accessToken');
    }
    if (provider == null) {
      throw new BuiltValueNullFieldError(
          'FacebookAuthCredentialImpl', 'provider');
    }
  }

  @override
  FacebookAuthCredentialImpl rebuild(
          void Function(FacebookAuthCredentialImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FacebookAuthCredentialImplBuilder toBuilder() =>
      new FacebookAuthCredentialImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FacebookAuthCredentialImpl &&
        accessToken == other.accessToken &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, accessToken.hashCode), provider.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('FacebookAuthCredentialImpl')
          ..add('accessToken', accessToken)
          ..add('provider', provider))
        .toString();
  }
}

class FacebookAuthCredentialImplBuilder
    implements
        Builder<FacebookAuthCredentialImpl, FacebookAuthCredentialImplBuilder> {
  _$FacebookAuthCredentialImpl _$v;

  String _accessToken;
  String get accessToken => _$this._accessToken;
  set accessToken(String accessToken) => _$this._accessToken = accessToken;

  ProviderType _provider;
  ProviderType get provider => _$this._provider;
  set provider(ProviderType provider) => _$this._provider = provider;

  FacebookAuthCredentialImplBuilder();

  FacebookAuthCredentialImplBuilder get _$this {
    if (_$v != null) {
      _accessToken = _$v.accessToken;
      _provider = _$v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FacebookAuthCredentialImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$FacebookAuthCredentialImpl;
  }

  @override
  void update(void Function(FacebookAuthCredentialImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$FacebookAuthCredentialImpl build() {
    final _$result = _$v ??
        new _$FacebookAuthCredentialImpl._(
            accessToken: accessToken, provider: provider);
    replace(_$result);
    return _$result;
  }
}

class _$GithubAuthCredentialImpl extends GithubAuthCredentialImpl {
  @override
  final String token;
  @override
  final ProviderType provider;

  factory _$GithubAuthCredentialImpl(
          [void Function(GithubAuthCredentialImplBuilder) updates]) =>
      (new GithubAuthCredentialImplBuilder()..update(updates)).build();

  _$GithubAuthCredentialImpl._({this.token, this.provider}) : super._() {
    if (token == null) {
      throw new BuiltValueNullFieldError('GithubAuthCredentialImpl', 'token');
    }
    if (provider == null) {
      throw new BuiltValueNullFieldError(
          'GithubAuthCredentialImpl', 'provider');
    }
  }

  @override
  GithubAuthCredentialImpl rebuild(
          void Function(GithubAuthCredentialImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GithubAuthCredentialImplBuilder toBuilder() =>
      new GithubAuthCredentialImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GithubAuthCredentialImpl &&
        token == other.token &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, token.hashCode), provider.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('GithubAuthCredentialImpl')
          ..add('token', token)
          ..add('provider', provider))
        .toString();
  }
}

class GithubAuthCredentialImplBuilder
    implements
        Builder<GithubAuthCredentialImpl, GithubAuthCredentialImplBuilder> {
  _$GithubAuthCredentialImpl _$v;

  String _token;
  String get token => _$this._token;
  set token(String token) => _$this._token = token;

  ProviderType _provider;
  ProviderType get provider => _$this._provider;
  set provider(ProviderType provider) => _$this._provider = provider;

  GithubAuthCredentialImplBuilder();

  GithubAuthCredentialImplBuilder get _$this {
    if (_$v != null) {
      _token = _$v.token;
      _provider = _$v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GithubAuthCredentialImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$GithubAuthCredentialImpl;
  }

  @override
  void update(void Function(GithubAuthCredentialImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$GithubAuthCredentialImpl build() {
    final _$result = _$v ??
        new _$GithubAuthCredentialImpl._(token: token, provider: provider);
    replace(_$result);
    return _$result;
  }
}

class _$GoogleAuthCredentialImpl extends GoogleAuthCredentialImpl {
  @override
  final String idToken;
  @override
  final String accessToken;
  @override
  final ProviderType provider;

  factory _$GoogleAuthCredentialImpl(
          [void Function(GoogleAuthCredentialImplBuilder) updates]) =>
      (new GoogleAuthCredentialImplBuilder()..update(updates)).build();

  _$GoogleAuthCredentialImpl._({this.idToken, this.accessToken, this.provider})
      : super._() {
    if (idToken == null) {
      throw new BuiltValueNullFieldError('GoogleAuthCredentialImpl', 'idToken');
    }
    if (accessToken == null) {
      throw new BuiltValueNullFieldError(
          'GoogleAuthCredentialImpl', 'accessToken');
    }
    if (provider == null) {
      throw new BuiltValueNullFieldError(
          'GoogleAuthCredentialImpl', 'provider');
    }
  }

  @override
  GoogleAuthCredentialImpl rebuild(
          void Function(GoogleAuthCredentialImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GoogleAuthCredentialImplBuilder toBuilder() =>
      new GoogleAuthCredentialImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GoogleAuthCredentialImpl &&
        idToken == other.idToken &&
        accessToken == other.accessToken &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    return $jf($jc($jc($jc(0, idToken.hashCode), accessToken.hashCode),
        provider.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('GoogleAuthCredentialImpl')
          ..add('idToken', idToken)
          ..add('accessToken', accessToken)
          ..add('provider', provider))
        .toString();
  }
}

class GoogleAuthCredentialImplBuilder
    implements
        Builder<GoogleAuthCredentialImpl, GoogleAuthCredentialImplBuilder> {
  _$GoogleAuthCredentialImpl _$v;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _accessToken;
  String get accessToken => _$this._accessToken;
  set accessToken(String accessToken) => _$this._accessToken = accessToken;

  ProviderType _provider;
  ProviderType get provider => _$this._provider;
  set provider(ProviderType provider) => _$this._provider = provider;

  GoogleAuthCredentialImplBuilder();

  GoogleAuthCredentialImplBuilder get _$this {
    if (_$v != null) {
      _idToken = _$v.idToken;
      _accessToken = _$v.accessToken;
      _provider = _$v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GoogleAuthCredentialImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$GoogleAuthCredentialImpl;
  }

  @override
  void update(void Function(GoogleAuthCredentialImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$GoogleAuthCredentialImpl build() {
    final _$result = _$v ??
        new _$GoogleAuthCredentialImpl._(
            idToken: idToken, accessToken: accessToken, provider: provider);
    replace(_$result);
    return _$result;
  }
}

class _$TwitterAuthCredentialImpl extends TwitterAuthCredentialImpl {
  @override
  final String authToken;
  @override
  final String authTokenSecret;
  @override
  final ProviderType provider;

  factory _$TwitterAuthCredentialImpl(
          [void Function(TwitterAuthCredentialImplBuilder) updates]) =>
      (new TwitterAuthCredentialImplBuilder()..update(updates)).build();

  _$TwitterAuthCredentialImpl._(
      {this.authToken, this.authTokenSecret, this.provider})
      : super._() {
    if (authToken == null) {
      throw new BuiltValueNullFieldError(
          'TwitterAuthCredentialImpl', 'authToken');
    }
    if (authTokenSecret == null) {
      throw new BuiltValueNullFieldError(
          'TwitterAuthCredentialImpl', 'authTokenSecret');
    }
    if (provider == null) {
      throw new BuiltValueNullFieldError(
          'TwitterAuthCredentialImpl', 'provider');
    }
  }

  @override
  TwitterAuthCredentialImpl rebuild(
          void Function(TwitterAuthCredentialImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TwitterAuthCredentialImplBuilder toBuilder() =>
      new TwitterAuthCredentialImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TwitterAuthCredentialImpl &&
        authToken == other.authToken &&
        authTokenSecret == other.authTokenSecret &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    return $jf($jc($jc($jc(0, authToken.hashCode), authTokenSecret.hashCode),
        provider.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('TwitterAuthCredentialImpl')
          ..add('authToken', authToken)
          ..add('authTokenSecret', authTokenSecret)
          ..add('provider', provider))
        .toString();
  }
}

class TwitterAuthCredentialImplBuilder
    implements
        Builder<TwitterAuthCredentialImpl, TwitterAuthCredentialImplBuilder> {
  _$TwitterAuthCredentialImpl _$v;

  String _authToken;
  String get authToken => _$this._authToken;
  set authToken(String authToken) => _$this._authToken = authToken;

  String _authTokenSecret;
  String get authTokenSecret => _$this._authTokenSecret;
  set authTokenSecret(String authTokenSecret) =>
      _$this._authTokenSecret = authTokenSecret;

  ProviderType _provider;
  ProviderType get provider => _$this._provider;
  set provider(ProviderType provider) => _$this._provider = provider;

  TwitterAuthCredentialImplBuilder();

  TwitterAuthCredentialImplBuilder get _$this {
    if (_$v != null) {
      _authToken = _$v.authToken;
      _authTokenSecret = _$v.authTokenSecret;
      _provider = _$v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TwitterAuthCredentialImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$TwitterAuthCredentialImpl;
  }

  @override
  void update(void Function(TwitterAuthCredentialImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$TwitterAuthCredentialImpl build() {
    final _$result = _$v ??
        new _$TwitterAuthCredentialImpl._(
            authToken: authToken,
            authTokenSecret: authTokenSecret,
            provider: provider);
    replace(_$result);
    return _$result;
  }
}

class _$AuthRequestConfiguration extends AuthRequestConfiguration {
  @override
  final String apiKey;
  @override
  final String languageCode;

  factory _$AuthRequestConfiguration(
          [void Function(AuthRequestConfigurationBuilder) updates]) =>
      (new AuthRequestConfigurationBuilder()..update(updates)).build();

  _$AuthRequestConfiguration._({this.apiKey, this.languageCode}) : super._() {
    if (apiKey == null) {
      throw new BuiltValueNullFieldError('AuthRequestConfiguration', 'apiKey');
    }
    if (languageCode == null) {
      throw new BuiltValueNullFieldError(
          'AuthRequestConfiguration', 'languageCode');
    }
  }

  @override
  AuthRequestConfiguration rebuild(
          void Function(AuthRequestConfigurationBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AuthRequestConfigurationBuilder toBuilder() =>
      new AuthRequestConfigurationBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AuthRequestConfiguration &&
        apiKey == other.apiKey &&
        languageCode == other.languageCode;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, apiKey.hashCode), languageCode.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('AuthRequestConfiguration')
          ..add('apiKey', apiKey)
          ..add('languageCode', languageCode))
        .toString();
  }
}

class AuthRequestConfigurationBuilder
    implements
        Builder<AuthRequestConfiguration, AuthRequestConfigurationBuilder> {
  _$AuthRequestConfiguration _$v;

  String _apiKey;
  String get apiKey => _$this._apiKey;
  set apiKey(String apiKey) => _$this._apiKey = apiKey;

  String _languageCode;
  String get languageCode => _$this._languageCode;
  set languageCode(String languageCode) => _$this._languageCode = languageCode;

  AuthRequestConfigurationBuilder();

  AuthRequestConfigurationBuilder get _$this {
    if (_$v != null) {
      _apiKey = _$v.apiKey;
      _languageCode = _$v.languageCode;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AuthRequestConfiguration other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$AuthRequestConfiguration;
  }

  @override
  void update(void Function(AuthRequestConfigurationBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$AuthRequestConfiguration build() {
    final _$result = _$v ??
        new _$AuthRequestConfiguration._(
            apiKey: apiKey, languageCode: languageCode);
    replace(_$result);
    return _$result;
  }
}

class _$BaseAuthRequest extends BaseAuthRequest {
  @override
  final String email;
  @override
  final String password;
  @override
  final bool returnSecureToken;

  factory _$BaseAuthRequest([void Function(BaseAuthRequestBuilder) updates]) =>
      (new BaseAuthRequestBuilder()..update(updates)).build();

  _$BaseAuthRequest._({this.email, this.password, this.returnSecureToken})
      : super._() {
    if (returnSecureToken == null) {
      throw new BuiltValueNullFieldError(
          'BaseAuthRequest', 'returnSecureToken');
    }
  }

  @override
  BaseAuthRequest rebuild(void Function(BaseAuthRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BaseAuthRequestBuilder toBuilder() =>
      new BaseAuthRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BaseAuthRequest &&
        email == other.email &&
        password == other.password &&
        returnSecureToken == other.returnSecureToken;
  }

  @override
  int get hashCode {
    return $jf($jc($jc($jc(0, email.hashCode), password.hashCode),
        returnSecureToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('BaseAuthRequest')
          ..add('email', email)
          ..add('password', password)
          ..add('returnSecureToken', returnSecureToken))
        .toString();
  }
}

class BaseAuthRequestBuilder
    implements Builder<BaseAuthRequest, BaseAuthRequestBuilder> {
  _$BaseAuthRequest _$v;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _password;
  String get password => _$this._password;
  set password(String password) => _$this._password = password;

  bool _returnSecureToken;
  bool get returnSecureToken => _$this._returnSecureToken;
  set returnSecureToken(bool returnSecureToken) =>
      _$this._returnSecureToken = returnSecureToken;

  BaseAuthRequestBuilder();

  BaseAuthRequestBuilder get _$this {
    if (_$v != null) {
      _email = _$v.email;
      _password = _$v.password;
      _returnSecureToken = _$v.returnSecureToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BaseAuthRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$BaseAuthRequest;
  }

  @override
  void update(void Function(BaseAuthRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$BaseAuthRequest build() {
    final _$result = _$v ??
        new _$BaseAuthRequest._(
            email: email,
            password: password,
            returnSecureToken: returnSecureToken);
    replace(_$result);
    return _$result;
  }
}

class _$BaseAuthResponse extends BaseAuthResponse {
  @override
  final String idToken;
  @override
  final String email;
  @override
  final String refreshToken;
  @override
  final int expiresIn;
  @override
  final String localId;
  @override
  final bool registered;

  factory _$BaseAuthResponse(
          [void Function(BaseAuthResponseBuilder) updates]) =>
      (new BaseAuthResponseBuilder()..update(updates)).build();

  _$BaseAuthResponse._(
      {this.idToken,
      this.email,
      this.refreshToken,
      this.expiresIn,
      this.localId,
      this.registered})
      : super._() {
    if (idToken == null) {
      throw new BuiltValueNullFieldError('BaseAuthResponse', 'idToken');
    }
    if (refreshToken == null) {
      throw new BuiltValueNullFieldError('BaseAuthResponse', 'refreshToken');
    }
    if (expiresIn == null) {
      throw new BuiltValueNullFieldError('BaseAuthResponse', 'expiresIn');
    }
    if (localId == null) {
      throw new BuiltValueNullFieldError('BaseAuthResponse', 'localId');
    }
  }

  @override
  BaseAuthResponse rebuild(void Function(BaseAuthResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BaseAuthResponseBuilder toBuilder() =>
      new BaseAuthResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BaseAuthResponse &&
        idToken == other.idToken &&
        email == other.email &&
        refreshToken == other.refreshToken &&
        expiresIn == other.expiresIn &&
        localId == other.localId &&
        registered == other.registered;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc($jc($jc(0, idToken.hashCode), email.hashCode),
                    refreshToken.hashCode),
                expiresIn.hashCode),
            localId.hashCode),
        registered.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('BaseAuthResponse')
          ..add('idToken', idToken)
          ..add('email', email)
          ..add('refreshToken', refreshToken)
          ..add('expiresIn', expiresIn)
          ..add('localId', localId)
          ..add('registered', registered))
        .toString();
  }
}

class BaseAuthResponseBuilder
    implements Builder<BaseAuthResponse, BaseAuthResponseBuilder> {
  _$BaseAuthResponse _$v;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  int _expiresIn;
  int get expiresIn => _$this._expiresIn;
  set expiresIn(int expiresIn) => _$this._expiresIn = expiresIn;

  String _localId;
  String get localId => _$this._localId;
  set localId(String localId) => _$this._localId = localId;

  bool _registered;
  bool get registered => _$this._registered;
  set registered(bool registered) => _$this._registered = registered;

  BaseAuthResponseBuilder();

  BaseAuthResponseBuilder get _$this {
    if (_$v != null) {
      _idToken = _$v.idToken;
      _email = _$v.email;
      _refreshToken = _$v.refreshToken;
      _expiresIn = _$v.expiresIn;
      _localId = _$v.localId;
      _registered = _$v.registered;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BaseAuthResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$BaseAuthResponse;
  }

  @override
  void update(void Function(BaseAuthResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$BaseAuthResponse build() {
    final _$result = _$v ??
        new _$BaseAuthResponse._(
            idToken: idToken,
            email: email,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            localId: localId,
            registered: registered);
    replace(_$result);
    return _$result;
  }
}

class _$CreateAuthUriRequest extends CreateAuthUriRequest {
  @override
  final String identifier;
  @override
  final String continueUri;

  factory _$CreateAuthUriRequest(
          [void Function(CreateAuthUriRequestBuilder) updates]) =>
      (new CreateAuthUriRequestBuilder()..update(updates)).build();

  _$CreateAuthUriRequest._({this.identifier, this.continueUri}) : super._() {
    if (identifier == null) {
      throw new BuiltValueNullFieldError('CreateAuthUriRequest', 'identifier');
    }
    if (continueUri == null) {
      throw new BuiltValueNullFieldError('CreateAuthUriRequest', 'continueUri');
    }
  }

  @override
  CreateAuthUriRequest rebuild(
          void Function(CreateAuthUriRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateAuthUriRequestBuilder toBuilder() =>
      new CreateAuthUriRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateAuthUriRequest &&
        identifier == other.identifier &&
        continueUri == other.continueUri;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, identifier.hashCode), continueUri.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('CreateAuthUriRequest')
          ..add('identifier', identifier)
          ..add('continueUri', continueUri))
        .toString();
  }
}

class CreateAuthUriRequestBuilder
    implements Builder<CreateAuthUriRequest, CreateAuthUriRequestBuilder> {
  _$CreateAuthUriRequest _$v;

  String _identifier;
  String get identifier => _$this._identifier;
  set identifier(String identifier) => _$this._identifier = identifier;

  String _continueUri;
  String get continueUri => _$this._continueUri;
  set continueUri(String continueUri) => _$this._continueUri = continueUri;

  CreateAuthUriRequestBuilder();

  CreateAuthUriRequestBuilder get _$this {
    if (_$v != null) {
      _identifier = _$v.identifier;
      _continueUri = _$v.continueUri;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateAuthUriRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$CreateAuthUriRequest;
  }

  @override
  void update(void Function(CreateAuthUriRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$CreateAuthUriRequest build() {
    final _$result = _$v ??
        new _$CreateAuthUriRequest._(
            identifier: identifier, continueUri: continueUri);
    replace(_$result);
    return _$result;
  }
}

class _$CreateAuthUriResponse extends CreateAuthUriResponse {
  @override
  final BuiltList<String> allProviders;
  @override
  final bool registered;

  factory _$CreateAuthUriResponse(
          [void Function(CreateAuthUriResponseBuilder) updates]) =>
      (new CreateAuthUriResponseBuilder()..update(updates)).build();

  _$CreateAuthUriResponse._({this.allProviders, this.registered}) : super._() {
    if (registered == null) {
      throw new BuiltValueNullFieldError('CreateAuthUriResponse', 'registered');
    }
  }

  @override
  CreateAuthUriResponse rebuild(
          void Function(CreateAuthUriResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateAuthUriResponseBuilder toBuilder() =>
      new CreateAuthUriResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateAuthUriResponse &&
        allProviders == other.allProviders &&
        registered == other.registered;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, allProviders.hashCode), registered.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('CreateAuthUriResponse')
          ..add('allProviders', allProviders)
          ..add('registered', registered))
        .toString();
  }
}

class CreateAuthUriResponseBuilder
    implements Builder<CreateAuthUriResponse, CreateAuthUriResponseBuilder> {
  _$CreateAuthUriResponse _$v;

  ListBuilder<String> _allProviders;
  ListBuilder<String> get allProviders =>
      _$this._allProviders ??= new ListBuilder<String>();
  set allProviders(ListBuilder<String> allProviders) =>
      _$this._allProviders = allProviders;

  bool _registered;
  bool get registered => _$this._registered;
  set registered(bool registered) => _$this._registered = registered;

  CreateAuthUriResponseBuilder();

  CreateAuthUriResponseBuilder get _$this {
    if (_$v != null) {
      _allProviders = _$v.allProviders?.toBuilder();
      _registered = _$v.registered;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateAuthUriResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$CreateAuthUriResponse;
  }

  @override
  void update(void Function(CreateAuthUriResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$CreateAuthUriResponse build() {
    _$CreateAuthUriResponse _$result;
    try {
      _$result = _$v ??
          new _$CreateAuthUriResponse._(
              allProviders: _allProviders?.build(), registered: registered);
    } catch (_) {
      String _$failedField;
      try {
        _$failedField = 'allProviders';
        _allProviders?.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'CreateAuthUriResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$ExchangeRefreshTokenRequest extends ExchangeRefreshTokenRequest {
  @override
  final String grantType;
  @override
  final String refreshToken;

  factory _$ExchangeRefreshTokenRequest(
          [void Function(ExchangeRefreshTokenRequestBuilder) updates]) =>
      (new ExchangeRefreshTokenRequestBuilder()..update(updates)).build();

  _$ExchangeRefreshTokenRequest._({this.grantType, this.refreshToken})
      : super._() {
    if (grantType == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeRefreshTokenRequest', 'grantType');
    }
    if (refreshToken == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeRefreshTokenRequest', 'refreshToken');
    }
  }

  @override
  ExchangeRefreshTokenRequest rebuild(
          void Function(ExchangeRefreshTokenRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExchangeRefreshTokenRequestBuilder toBuilder() =>
      new ExchangeRefreshTokenRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExchangeRefreshTokenRequest &&
        grantType == other.grantType &&
        refreshToken == other.refreshToken;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, grantType.hashCode), refreshToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ExchangeRefreshTokenRequest')
          ..add('grantType', grantType)
          ..add('refreshToken', refreshToken))
        .toString();
  }
}

class ExchangeRefreshTokenRequestBuilder
    implements
        Builder<ExchangeRefreshTokenRequest,
            ExchangeRefreshTokenRequestBuilder> {
  _$ExchangeRefreshTokenRequest _$v;

  String _grantType;
  String get grantType => _$this._grantType;
  set grantType(String grantType) => _$this._grantType = grantType;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  ExchangeRefreshTokenRequestBuilder();

  ExchangeRefreshTokenRequestBuilder get _$this {
    if (_$v != null) {
      _grantType = _$v.grantType;
      _refreshToken = _$v.refreshToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExchangeRefreshTokenRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ExchangeRefreshTokenRequest;
  }

  @override
  void update(void Function(ExchangeRefreshTokenRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ExchangeRefreshTokenRequest build() {
    final _$result = _$v ??
        new _$ExchangeRefreshTokenRequest._(
            grantType: grantType, refreshToken: refreshToken);
    replace(_$result);
    return _$result;
  }
}

class _$ExchangeRefreshTokenResponse extends ExchangeRefreshTokenResponse {
  @override
  final int expiresIn;
  @override
  final String tokenType;
  @override
  final String refreshToken;
  @override
  final String accessToken;
  @override
  final String idToken;
  @override
  final String userId;
  @override
  final String projectId;

  factory _$ExchangeRefreshTokenResponse(
          [void Function(ExchangeRefreshTokenResponseBuilder) updates]) =>
      (new ExchangeRefreshTokenResponseBuilder()..update(updates)).build();

  _$ExchangeRefreshTokenResponse._(
      {this.expiresIn,
      this.tokenType,
      this.refreshToken,
      this.accessToken,
      this.idToken,
      this.userId,
      this.projectId})
      : super._() {
    if (expiresIn == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeRefreshTokenResponse', 'expiresIn');
    }
    if (tokenType == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeRefreshTokenResponse', 'tokenType');
    }
    if (idToken == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeRefreshTokenResponse', 'idToken');
    }
    if (userId == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeRefreshTokenResponse', 'userId');
    }
    if (projectId == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeRefreshTokenResponse', 'projectId');
    }
  }

  @override
  ExchangeRefreshTokenResponse rebuild(
          void Function(ExchangeRefreshTokenResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExchangeRefreshTokenResponseBuilder toBuilder() =>
      new ExchangeRefreshTokenResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExchangeRefreshTokenResponse &&
        expiresIn == other.expiresIn &&
        tokenType == other.tokenType &&
        refreshToken == other.refreshToken &&
        accessToken == other.accessToken &&
        idToken == other.idToken &&
        userId == other.userId &&
        projectId == other.projectId;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, expiresIn.hashCode), tokenType.hashCode),
                        refreshToken.hashCode),
                    accessToken.hashCode),
                idToken.hashCode),
            userId.hashCode),
        projectId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ExchangeRefreshTokenResponse')
          ..add('expiresIn', expiresIn)
          ..add('tokenType', tokenType)
          ..add('refreshToken', refreshToken)
          ..add('accessToken', accessToken)
          ..add('idToken', idToken)
          ..add('userId', userId)
          ..add('projectId', projectId))
        .toString();
  }
}

class ExchangeRefreshTokenResponseBuilder
    implements
        Builder<ExchangeRefreshTokenResponse,
            ExchangeRefreshTokenResponseBuilder> {
  _$ExchangeRefreshTokenResponse _$v;

  int _expiresIn;
  int get expiresIn => _$this._expiresIn;
  set expiresIn(int expiresIn) => _$this._expiresIn = expiresIn;

  String _tokenType;
  String get tokenType => _$this._tokenType;
  set tokenType(String tokenType) => _$this._tokenType = tokenType;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  String _accessToken;
  String get accessToken => _$this._accessToken;
  set accessToken(String accessToken) => _$this._accessToken = accessToken;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _userId;
  String get userId => _$this._userId;
  set userId(String userId) => _$this._userId = userId;

  String _projectId;
  String get projectId => _$this._projectId;
  set projectId(String projectId) => _$this._projectId = projectId;

  ExchangeRefreshTokenResponseBuilder();

  ExchangeRefreshTokenResponseBuilder get _$this {
    if (_$v != null) {
      _expiresIn = _$v.expiresIn;
      _tokenType = _$v.tokenType;
      _refreshToken = _$v.refreshToken;
      _accessToken = _$v.accessToken;
      _idToken = _$v.idToken;
      _userId = _$v.userId;
      _projectId = _$v.projectId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExchangeRefreshTokenResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ExchangeRefreshTokenResponse;
  }

  @override
  void update(void Function(ExchangeRefreshTokenResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ExchangeRefreshTokenResponse build() {
    final _$result = _$v ??
        new _$ExchangeRefreshTokenResponse._(
            expiresIn: expiresIn,
            tokenType: tokenType,
            refreshToken: refreshToken,
            accessToken: accessToken,
            idToken: idToken,
            userId: userId,
            projectId: projectId);
    replace(_$result);
    return _$result;
  }
}

class _$ExchangeCustomTokenRequest extends ExchangeCustomTokenRequest {
  @override
  final String token;
  @override
  final bool returnSecureToken;

  factory _$ExchangeCustomTokenRequest(
          [void Function(ExchangeCustomTokenRequestBuilder) updates]) =>
      (new ExchangeCustomTokenRequestBuilder()..update(updates)).build();

  _$ExchangeCustomTokenRequest._({this.token, this.returnSecureToken})
      : super._() {
    if (token == null) {
      throw new BuiltValueNullFieldError('ExchangeCustomTokenRequest', 'token');
    }
    if (returnSecureToken == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeCustomTokenRequest', 'returnSecureToken');
    }
  }

  @override
  ExchangeCustomTokenRequest rebuild(
          void Function(ExchangeCustomTokenRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExchangeCustomTokenRequestBuilder toBuilder() =>
      new ExchangeCustomTokenRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExchangeCustomTokenRequest &&
        token == other.token &&
        returnSecureToken == other.returnSecureToken;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, token.hashCode), returnSecureToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ExchangeCustomTokenRequest')
          ..add('token', token)
          ..add('returnSecureToken', returnSecureToken))
        .toString();
  }
}

class ExchangeCustomTokenRequestBuilder
    implements
        Builder<ExchangeCustomTokenRequest, ExchangeCustomTokenRequestBuilder> {
  _$ExchangeCustomTokenRequest _$v;

  String _token;
  String get token => _$this._token;
  set token(String token) => _$this._token = token;

  bool _returnSecureToken;
  bool get returnSecureToken => _$this._returnSecureToken;
  set returnSecureToken(bool returnSecureToken) =>
      _$this._returnSecureToken = returnSecureToken;

  ExchangeCustomTokenRequestBuilder();

  ExchangeCustomTokenRequestBuilder get _$this {
    if (_$v != null) {
      _token = _$v.token;
      _returnSecureToken = _$v.returnSecureToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExchangeCustomTokenRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ExchangeCustomTokenRequest;
  }

  @override
  void update(void Function(ExchangeCustomTokenRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ExchangeCustomTokenRequest build() {
    final _$result = _$v ??
        new _$ExchangeCustomTokenRequest._(
            token: token, returnSecureToken: returnSecureToken);
    replace(_$result);
    return _$result;
  }
}

class _$ExchangeCustomTokenResponse extends ExchangeCustomTokenResponse {
  @override
  final String idToken;
  @override
  final String refreshToken;
  @override
  final int expiresIn;

  factory _$ExchangeCustomTokenResponse(
          [void Function(ExchangeCustomTokenResponseBuilder) updates]) =>
      (new ExchangeCustomTokenResponseBuilder()..update(updates)).build();

  _$ExchangeCustomTokenResponse._(
      {this.idToken, this.refreshToken, this.expiresIn})
      : super._() {
    if (idToken == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeCustomTokenResponse', 'idToken');
    }
    if (refreshToken == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeCustomTokenResponse', 'refreshToken');
    }
    if (expiresIn == null) {
      throw new BuiltValueNullFieldError(
          'ExchangeCustomTokenResponse', 'expiresIn');
    }
  }

  @override
  ExchangeCustomTokenResponse rebuild(
          void Function(ExchangeCustomTokenResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExchangeCustomTokenResponseBuilder toBuilder() =>
      new ExchangeCustomTokenResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExchangeCustomTokenResponse &&
        idToken == other.idToken &&
        refreshToken == other.refreshToken &&
        expiresIn == other.expiresIn;
  }

  @override
  int get hashCode {
    return $jf($jc($jc($jc(0, idToken.hashCode), refreshToken.hashCode),
        expiresIn.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ExchangeCustomTokenResponse')
          ..add('idToken', idToken)
          ..add('refreshToken', refreshToken)
          ..add('expiresIn', expiresIn))
        .toString();
  }
}

class ExchangeCustomTokenResponseBuilder
    implements
        Builder<ExchangeCustomTokenResponse,
            ExchangeCustomTokenResponseBuilder> {
  _$ExchangeCustomTokenResponse _$v;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  int _expiresIn;
  int get expiresIn => _$this._expiresIn;
  set expiresIn(int expiresIn) => _$this._expiresIn = expiresIn;

  ExchangeCustomTokenResponseBuilder();

  ExchangeCustomTokenResponseBuilder get _$this {
    if (_$v != null) {
      _idToken = _$v.idToken;
      _refreshToken = _$v.refreshToken;
      _expiresIn = _$v.expiresIn;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExchangeCustomTokenResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ExchangeCustomTokenResponse;
  }

  @override
  void update(void Function(ExchangeCustomTokenResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ExchangeCustomTokenResponse build() {
    final _$result = _$v ??
        new _$ExchangeCustomTokenResponse._(
            idToken: idToken, refreshToken: refreshToken, expiresIn: expiresIn);
    replace(_$result);
    return _$result;
  }
}

class _$OAuthRequest extends OAuthRequest {
  @override
  final String idToken;
  @override
  final String requestUri;
  @override
  final String postBody;
  @override
  final bool returnIdpCredential;
  @override
  final bool returnSecureToken;

  factory _$OAuthRequest([void Function(OAuthRequestBuilder) updates]) =>
      (new OAuthRequestBuilder()..update(updates)).build();

  _$OAuthRequest._(
      {this.idToken,
      this.requestUri,
      this.postBody,
      this.returnIdpCredential,
      this.returnSecureToken})
      : super._() {
    if (requestUri == null) {
      throw new BuiltValueNullFieldError('OAuthRequest', 'requestUri');
    }
    if (postBody == null) {
      throw new BuiltValueNullFieldError('OAuthRequest', 'postBody');
    }
    if (returnIdpCredential == null) {
      throw new BuiltValueNullFieldError('OAuthRequest', 'returnIdpCredential');
    }
    if (returnSecureToken == null) {
      throw new BuiltValueNullFieldError('OAuthRequest', 'returnSecureToken');
    }
  }

  @override
  OAuthRequest rebuild(void Function(OAuthRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OAuthRequestBuilder toBuilder() => new OAuthRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OAuthRequest &&
        idToken == other.idToken &&
        requestUri == other.requestUri &&
        postBody == other.postBody &&
        returnIdpCredential == other.returnIdpCredential &&
        returnSecureToken == other.returnSecureToken;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc($jc($jc(0, idToken.hashCode), requestUri.hashCode),
                postBody.hashCode),
            returnIdpCredential.hashCode),
        returnSecureToken.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('OAuthRequest')
          ..add('idToken', idToken)
          ..add('requestUri', requestUri)
          ..add('postBody', postBody)
          ..add('returnIdpCredential', returnIdpCredential)
          ..add('returnSecureToken', returnSecureToken))
        .toString();
  }
}

class OAuthRequestBuilder
    implements Builder<OAuthRequest, OAuthRequestBuilder> {
  _$OAuthRequest _$v;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _requestUri;
  String get requestUri => _$this._requestUri;
  set requestUri(String requestUri) => _$this._requestUri = requestUri;

  String _postBody;
  String get postBody => _$this._postBody;
  set postBody(String postBody) => _$this._postBody = postBody;

  bool _returnIdpCredential;
  bool get returnIdpCredential => _$this._returnIdpCredential;
  set returnIdpCredential(bool returnIdpCredential) =>
      _$this._returnIdpCredential = returnIdpCredential;

  bool _returnSecureToken;
  bool get returnSecureToken => _$this._returnSecureToken;
  set returnSecureToken(bool returnSecureToken) =>
      _$this._returnSecureToken = returnSecureToken;

  OAuthRequestBuilder();

  OAuthRequestBuilder get _$this {
    if (_$v != null) {
      _idToken = _$v.idToken;
      _requestUri = _$v.requestUri;
      _postBody = _$v.postBody;
      _returnIdpCredential = _$v.returnIdpCredential;
      _returnSecureToken = _$v.returnSecureToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OAuthRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$OAuthRequest;
  }

  @override
  void update(void Function(OAuthRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$OAuthRequest build() {
    final _$result = _$v ??
        new _$OAuthRequest._(
            idToken: idToken,
            requestUri: requestUri,
            postBody: postBody,
            returnIdpCredential: returnIdpCredential,
            returnSecureToken: returnSecureToken);
    replace(_$result);
    return _$result;
  }
}

class _$OAuthResponse extends OAuthResponse {
  @override
  final String federatedId;
  @override
  final ProviderType providerId;
  @override
  final String localId;
  @override
  final bool emailVerified;
  @override
  final String email;
  @override
  final String oauthIdToken;
  @override
  final String oauthAccessToken;
  @override
  final String oauthTokenSecret;
  @override
  final String rawUserInfo;
  @override
  final String firstName;
  @override
  final String lastName;
  @override
  final String fullName;
  @override
  final String displayName;
  @override
  final String photoUrl;
  @override
  final String idToken;
  @override
  final String refreshToken;
  @override
  final int expiresIn;
  @override
  final bool needConfirmation;

  factory _$OAuthResponse([void Function(OAuthResponseBuilder) updates]) =>
      (new OAuthResponseBuilder()..update(updates)).build();

  _$OAuthResponse._(
      {this.federatedId,
      this.providerId,
      this.localId,
      this.emailVerified,
      this.email,
      this.oauthIdToken,
      this.oauthAccessToken,
      this.oauthTokenSecret,
      this.rawUserInfo,
      this.firstName,
      this.lastName,
      this.fullName,
      this.displayName,
      this.photoUrl,
      this.idToken,
      this.refreshToken,
      this.expiresIn,
      this.needConfirmation})
      : super._() {
    if (federatedId == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'federatedId');
    }
    if (providerId == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'providerId');
    }
    if (localId == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'localId');
    }
    if (emailVerified == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'emailVerified');
    }
    if (email == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'email');
    }
    if (rawUserInfo == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'rawUserInfo');
    }
    if (firstName == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'firstName');
    }
    if (lastName == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'lastName');
    }
    if (fullName == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'fullName');
    }
    if (displayName == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'displayName');
    }
    if (photoUrl == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'photoUrl');
    }
    if (idToken == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'idToken');
    }
    if (refreshToken == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'refreshToken');
    }
    if (expiresIn == null) {
      throw new BuiltValueNullFieldError('OAuthResponse', 'expiresIn');
    }
  }

  @override
  OAuthResponse rebuild(void Function(OAuthResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OAuthResponseBuilder toBuilder() => new OAuthResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OAuthResponse &&
        federatedId == other.federatedId &&
        providerId == other.providerId &&
        localId == other.localId &&
        emailVerified == other.emailVerified &&
        email == other.email &&
        oauthIdToken == other.oauthIdToken &&
        oauthAccessToken == other.oauthAccessToken &&
        oauthTokenSecret == other.oauthTokenSecret &&
        rawUserInfo == other.rawUserInfo &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        fullName == other.fullName &&
        displayName == other.displayName &&
        photoUrl == other.photoUrl &&
        idToken == other.idToken &&
        refreshToken == other.refreshToken &&
        expiresIn == other.expiresIn &&
        needConfirmation == other.needConfirmation;
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
                                                                $jc(
                                                                    $jc(
                                                                        $jc(
                                                                            0,
                                                                            federatedId
                                                                                .hashCode),
                                                                        providerId
                                                                            .hashCode),
                                                                    localId
                                                                        .hashCode),
                                                                emailVerified
                                                                    .hashCode),
                                                            email.hashCode),
                                                        oauthIdToken.hashCode),
                                                    oauthAccessToken.hashCode),
                                                oauthTokenSecret.hashCode),
                                            rawUserInfo.hashCode),
                                        firstName.hashCode),
                                    lastName.hashCode),
                                fullName.hashCode),
                            displayName.hashCode),
                        photoUrl.hashCode),
                    idToken.hashCode),
                refreshToken.hashCode),
            expiresIn.hashCode),
        needConfirmation.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('OAuthResponse')
          ..add('federatedId', federatedId)
          ..add('providerId', providerId)
          ..add('localId', localId)
          ..add('emailVerified', emailVerified)
          ..add('email', email)
          ..add('oauthIdToken', oauthIdToken)
          ..add('oauthAccessToken', oauthAccessToken)
          ..add('oauthTokenSecret', oauthTokenSecret)
          ..add('rawUserInfo', rawUserInfo)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('fullName', fullName)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('idToken', idToken)
          ..add('refreshToken', refreshToken)
          ..add('expiresIn', expiresIn)
          ..add('needConfirmation', needConfirmation))
        .toString();
  }
}

class OAuthResponseBuilder
    implements Builder<OAuthResponse, OAuthResponseBuilder> {
  _$OAuthResponse _$v;

  String _federatedId;
  String get federatedId => _$this._federatedId;
  set federatedId(String federatedId) => _$this._federatedId = federatedId;

  ProviderType _providerId;
  ProviderType get providerId => _$this._providerId;
  set providerId(ProviderType providerId) => _$this._providerId = providerId;

  String _localId;
  String get localId => _$this._localId;
  set localId(String localId) => _$this._localId = localId;

  bool _emailVerified;
  bool get emailVerified => _$this._emailVerified;
  set emailVerified(bool emailVerified) =>
      _$this._emailVerified = emailVerified;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _oauthIdToken;
  String get oauthIdToken => _$this._oauthIdToken;
  set oauthIdToken(String oauthIdToken) => _$this._oauthIdToken = oauthIdToken;

  String _oauthAccessToken;
  String get oauthAccessToken => _$this._oauthAccessToken;
  set oauthAccessToken(String oauthAccessToken) =>
      _$this._oauthAccessToken = oauthAccessToken;

  String _oauthTokenSecret;
  String get oauthTokenSecret => _$this._oauthTokenSecret;
  set oauthTokenSecret(String oauthTokenSecret) =>
      _$this._oauthTokenSecret = oauthTokenSecret;

  String _rawUserInfo;
  String get rawUserInfo => _$this._rawUserInfo;
  set rawUserInfo(String rawUserInfo) => _$this._rawUserInfo = rawUserInfo;

  String _firstName;
  String get firstName => _$this._firstName;
  set firstName(String firstName) => _$this._firstName = firstName;

  String _lastName;
  String get lastName => _$this._lastName;
  set lastName(String lastName) => _$this._lastName = lastName;

  String _fullName;
  String get fullName => _$this._fullName;
  set fullName(String fullName) => _$this._fullName = fullName;

  String _displayName;
  String get displayName => _$this._displayName;
  set displayName(String displayName) => _$this._displayName = displayName;

  String _photoUrl;
  String get photoUrl => _$this._photoUrl;
  set photoUrl(String photoUrl) => _$this._photoUrl = photoUrl;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  int _expiresIn;
  int get expiresIn => _$this._expiresIn;
  set expiresIn(int expiresIn) => _$this._expiresIn = expiresIn;

  bool _needConfirmation;
  bool get needConfirmation => _$this._needConfirmation;
  set needConfirmation(bool needConfirmation) =>
      _$this._needConfirmation = needConfirmation;

  OAuthResponseBuilder();

  OAuthResponseBuilder get _$this {
    if (_$v != null) {
      _federatedId = _$v.federatedId;
      _providerId = _$v.providerId;
      _localId = _$v.localId;
      _emailVerified = _$v.emailVerified;
      _email = _$v.email;
      _oauthIdToken = _$v.oauthIdToken;
      _oauthAccessToken = _$v.oauthAccessToken;
      _oauthTokenSecret = _$v.oauthTokenSecret;
      _rawUserInfo = _$v.rawUserInfo;
      _firstName = _$v.firstName;
      _lastName = _$v.lastName;
      _fullName = _$v.fullName;
      _displayName = _$v.displayName;
      _photoUrl = _$v.photoUrl;
      _idToken = _$v.idToken;
      _refreshToken = _$v.refreshToken;
      _expiresIn = _$v.expiresIn;
      _needConfirmation = _$v.needConfirmation;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OAuthResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$OAuthResponse;
  }

  @override
  void update(void Function(OAuthResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$OAuthResponse build() {
    final _$result = _$v ??
        new _$OAuthResponse._(
            federatedId: federatedId,
            providerId: providerId,
            localId: localId,
            emailVerified: emailVerified,
            email: email,
            oauthIdToken: oauthIdToken,
            oauthAccessToken: oauthAccessToken,
            oauthTokenSecret: oauthTokenSecret,
            rawUserInfo: rawUserInfo,
            firstName: firstName,
            lastName: lastName,
            fullName: fullName,
            displayName: displayName,
            photoUrl: photoUrl,
            idToken: idToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            needConfirmation: needConfirmation);
    replace(_$result);
    return _$result;
  }
}

class _$OobCodeRequest extends OobCodeRequest {
  @override
  final OobCodeType requestType;
  @override
  final String email;
  @override
  final String newEmail;
  @override
  final String idToken;
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
  final bool canHandleCodeInApp;
  @override
  final String dynamicLinkDomain;

  factory _$OobCodeRequest([void Function(OobCodeRequestBuilder) updates]) =>
      (new OobCodeRequestBuilder()..update(updates)).build();

  _$OobCodeRequest._(
      {this.requestType,
      this.email,
      this.newEmail,
      this.idToken,
      this.continueUrl,
      this.iOSBundleId,
      this.androidPackageName,
      this.androidInstallApp,
      this.androidMinimumVersion,
      this.canHandleCodeInApp,
      this.dynamicLinkDomain})
      : super._() {
    if (requestType == null) {
      throw new BuiltValueNullFieldError('OobCodeRequest', 'requestType');
    }
  }

  @override
  OobCodeRequest rebuild(void Function(OobCodeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OobCodeRequestBuilder toBuilder() =>
      new OobCodeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OobCodeRequest &&
        requestType == other.requestType &&
        email == other.email &&
        newEmail == other.newEmail &&
        idToken == other.idToken &&
        continueUrl == other.continueUrl &&
        iOSBundleId == other.iOSBundleId &&
        androidPackageName == other.androidPackageName &&
        androidInstallApp == other.androidInstallApp &&
        androidMinimumVersion == other.androidMinimumVersion &&
        canHandleCodeInApp == other.canHandleCodeInApp &&
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
                                        newEmail.hashCode),
                                    idToken.hashCode),
                                continueUrl.hashCode),
                            iOSBundleId.hashCode),
                        androidPackageName.hashCode),
                    androidInstallApp.hashCode),
                androidMinimumVersion.hashCode),
            canHandleCodeInApp.hashCode),
        dynamicLinkDomain.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('OobCodeRequest')
          ..add('requestType', requestType)
          ..add('email', email)
          ..add('newEmail', newEmail)
          ..add('idToken', idToken)
          ..add('continueUrl', continueUrl)
          ..add('iOSBundleId', iOSBundleId)
          ..add('androidPackageName', androidPackageName)
          ..add('androidInstallApp', androidInstallApp)
          ..add('androidMinimumVersion', androidMinimumVersion)
          ..add('canHandleCodeInApp', canHandleCodeInApp)
          ..add('dynamicLinkDomain', dynamicLinkDomain))
        .toString();
  }
}

class OobCodeRequestBuilder
    implements Builder<OobCodeRequest, OobCodeRequestBuilder> {
  _$OobCodeRequest _$v;

  OobCodeType _requestType;
  OobCodeType get requestType => _$this._requestType;
  set requestType(OobCodeType requestType) => _$this._requestType = requestType;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _newEmail;
  String get newEmail => _$this._newEmail;
  set newEmail(String newEmail) => _$this._newEmail = newEmail;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

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

  bool _canHandleCodeInApp;
  bool get canHandleCodeInApp => _$this._canHandleCodeInApp;
  set canHandleCodeInApp(bool canHandleCodeInApp) =>
      _$this._canHandleCodeInApp = canHandleCodeInApp;

  String _dynamicLinkDomain;
  String get dynamicLinkDomain => _$this._dynamicLinkDomain;
  set dynamicLinkDomain(String dynamicLinkDomain) =>
      _$this._dynamicLinkDomain = dynamicLinkDomain;

  OobCodeRequestBuilder();

  OobCodeRequestBuilder get _$this {
    if (_$v != null) {
      _requestType = _$v.requestType;
      _email = _$v.email;
      _newEmail = _$v.newEmail;
      _idToken = _$v.idToken;
      _continueUrl = _$v.continueUrl;
      _iOSBundleId = _$v.iOSBundleId;
      _androidPackageName = _$v.androidPackageName;
      _androidInstallApp = _$v.androidInstallApp;
      _androidMinimumVersion = _$v.androidMinimumVersion;
      _canHandleCodeInApp = _$v.canHandleCodeInApp;
      _dynamicLinkDomain = _$v.dynamicLinkDomain;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OobCodeRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$OobCodeRequest;
  }

  @override
  void update(void Function(OobCodeRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$OobCodeRequest build() {
    final _$result = _$v ??
        new _$OobCodeRequest._(
            requestType: requestType,
            email: email,
            newEmail: newEmail,
            idToken: idToken,
            continueUrl: continueUrl,
            iOSBundleId: iOSBundleId,
            androidPackageName: androidPackageName,
            androidInstallApp: androidInstallApp,
            androidMinimumVersion: androidMinimumVersion,
            canHandleCodeInApp: canHandleCodeInApp,
            dynamicLinkDomain: dynamicLinkDomain);
    replace(_$result);
    return _$result;
  }
}

class _$OobCodeResponse extends OobCodeResponse {
  @override
  final String email;

  factory _$OobCodeResponse([void Function(OobCodeResponseBuilder) updates]) =>
      (new OobCodeResponseBuilder()..update(updates)).build();

  _$OobCodeResponse._({this.email}) : super._() {
    if (email == null) {
      throw new BuiltValueNullFieldError('OobCodeResponse', 'email');
    }
  }

  @override
  OobCodeResponse rebuild(void Function(OobCodeResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OobCodeResponseBuilder toBuilder() =>
      new OobCodeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OobCodeResponse && email == other.email;
  }

  @override
  int get hashCode {
    return $jf($jc(0, email.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('OobCodeResponse')..add('email', email))
        .toString();
  }
}

class OobCodeResponseBuilder
    implements Builder<OobCodeResponse, OobCodeResponseBuilder> {
  _$OobCodeResponse _$v;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  OobCodeResponseBuilder();

  OobCodeResponseBuilder get _$this {
    if (_$v != null) {
      _email = _$v.email;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OobCodeResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$OobCodeResponse;
  }

  @override
  void update(void Function(OobCodeResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$OobCodeResponse build() {
    final _$result = _$v ?? new _$OobCodeResponse._(email: email);
    replace(_$result);
    return _$result;
  }
}

class _$ResetPasswordRequest extends ResetPasswordRequest {
  @override
  final String oobCode;
  @override
  final String newPassword;

  factory _$ResetPasswordRequest(
          [void Function(ResetPasswordRequestBuilder) updates]) =>
      (new ResetPasswordRequestBuilder()..update(updates)).build();

  _$ResetPasswordRequest._({this.oobCode, this.newPassword}) : super._() {
    if (oobCode == null) {
      throw new BuiltValueNullFieldError('ResetPasswordRequest', 'oobCode');
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
        newPassword == other.newPassword;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, oobCode.hashCode), newPassword.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ResetPasswordRequest')
          ..add('oobCode', oobCode)
          ..add('newPassword', newPassword))
        .toString();
  }
}

class ResetPasswordRequestBuilder
    implements Builder<ResetPasswordRequest, ResetPasswordRequestBuilder> {
  _$ResetPasswordRequest _$v;

  String _oobCode;
  String get oobCode => _$this._oobCode;
  set oobCode(String oobCode) => _$this._oobCode = oobCode;

  String _newPassword;
  String get newPassword => _$this._newPassword;
  set newPassword(String newPassword) => _$this._newPassword = newPassword;

  ResetPasswordRequestBuilder();

  ResetPasswordRequestBuilder get _$this {
    if (_$v != null) {
      _oobCode = _$v.oobCode;
      _newPassword = _$v.newPassword;
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
            oobCode: oobCode, newPassword: newPassword);
    replace(_$result);
    return _$result;
  }
}

class _$ResetPasswordResponse extends ResetPasswordResponse {
  @override
  final String email;
  @override
  final OobCodeType requestType;

  factory _$ResetPasswordResponse(
          [void Function(ResetPasswordResponseBuilder) updates]) =>
      (new ResetPasswordResponseBuilder()..update(updates)).build();

  _$ResetPasswordResponse._({this.email, this.requestType}) : super._() {
    if (email == null) {
      throw new BuiltValueNullFieldError('ResetPasswordResponse', 'email');
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
        requestType == other.requestType;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, email.hashCode), requestType.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ResetPasswordResponse')
          ..add('email', email)
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

  OobCodeType _requestType;
  OobCodeType get requestType => _$this._requestType;
  set requestType(OobCodeType requestType) => _$this._requestType = requestType;

  ResetPasswordResponseBuilder();

  ResetPasswordResponseBuilder get _$this {
    if (_$v != null) {
      _email = _$v.email;
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
        new _$ResetPasswordResponse._(email: email, requestType: requestType);
    replace(_$result);
    return _$result;
  }
}

class _$UpdateRequest extends UpdateRequest {
  @override
  final String idToken;
  @override
  final String email;
  @override
  final String password;
  @override
  final String displayName;
  @override
  final String photoUrl;
  @override
  final BuiltList<ProfileAttribute> deleteAttribute;
  @override
  final bool returnSecureToken;
  @override
  final BuiltList<ProviderType> deleteProvider;
  @override
  final String oobCode;

  factory _$UpdateRequest([void Function(UpdateRequestBuilder) updates]) =>
      (new UpdateRequestBuilder()..update(updates)).build();

  _$UpdateRequest._(
      {this.idToken,
      this.email,
      this.password,
      this.displayName,
      this.photoUrl,
      this.deleteAttribute,
      this.returnSecureToken,
      this.deleteProvider,
      this.oobCode})
      : super._();

  @override
  UpdateRequest rebuild(void Function(UpdateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateRequestBuilder toBuilder() => new UpdateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateRequest &&
        idToken == other.idToken &&
        email == other.email &&
        password == other.password &&
        displayName == other.displayName &&
        photoUrl == other.photoUrl &&
        deleteAttribute == other.deleteAttribute &&
        returnSecureToken == other.returnSecureToken &&
        deleteProvider == other.deleteProvider &&
        oobCode == other.oobCode;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc(
                        $jc(
                            $jc($jc($jc(0, idToken.hashCode), email.hashCode),
                                password.hashCode),
                            displayName.hashCode),
                        photoUrl.hashCode),
                    deleteAttribute.hashCode),
                returnSecureToken.hashCode),
            deleteProvider.hashCode),
        oobCode.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('UpdateRequest')
          ..add('idToken', idToken)
          ..add('email', email)
          ..add('password', password)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('deleteAttribute', deleteAttribute)
          ..add('returnSecureToken', returnSecureToken)
          ..add('deleteProvider', deleteProvider)
          ..add('oobCode', oobCode))
        .toString();
  }
}

class UpdateRequestBuilder
    implements Builder<UpdateRequest, UpdateRequestBuilder> {
  _$UpdateRequest _$v;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _password;
  String get password => _$this._password;
  set password(String password) => _$this._password = password;

  String _displayName;
  String get displayName => _$this._displayName;
  set displayName(String displayName) => _$this._displayName = displayName;

  String _photoUrl;
  String get photoUrl => _$this._photoUrl;
  set photoUrl(String photoUrl) => _$this._photoUrl = photoUrl;

  ListBuilder<ProfileAttribute> _deleteAttribute;
  ListBuilder<ProfileAttribute> get deleteAttribute =>
      _$this._deleteAttribute ??= new ListBuilder<ProfileAttribute>();
  set deleteAttribute(ListBuilder<ProfileAttribute> deleteAttribute) =>
      _$this._deleteAttribute = deleteAttribute;

  bool _returnSecureToken;
  bool get returnSecureToken => _$this._returnSecureToken;
  set returnSecureToken(bool returnSecureToken) =>
      _$this._returnSecureToken = returnSecureToken;

  ListBuilder<ProviderType> _deleteProvider;
  ListBuilder<ProviderType> get deleteProvider =>
      _$this._deleteProvider ??= new ListBuilder<ProviderType>();
  set deleteProvider(ListBuilder<ProviderType> deleteProvider) =>
      _$this._deleteProvider = deleteProvider;

  String _oobCode;
  String get oobCode => _$this._oobCode;
  set oobCode(String oobCode) => _$this._oobCode = oobCode;

  UpdateRequestBuilder();

  UpdateRequestBuilder get _$this {
    if (_$v != null) {
      _idToken = _$v.idToken;
      _email = _$v.email;
      _password = _$v.password;
      _displayName = _$v.displayName;
      _photoUrl = _$v.photoUrl;
      _deleteAttribute = _$v.deleteAttribute?.toBuilder();
      _returnSecureToken = _$v.returnSecureToken;
      _deleteProvider = _$v.deleteProvider?.toBuilder();
      _oobCode = _$v.oobCode;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$UpdateRequest;
  }

  @override
  void update(void Function(UpdateRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$UpdateRequest build() {
    _$UpdateRequest _$result;
    try {
      _$result = _$v ??
          new _$UpdateRequest._(
              idToken: idToken,
              email: email,
              password: password,
              displayName: displayName,
              photoUrl: photoUrl,
              deleteAttribute: _deleteAttribute?.build(),
              returnSecureToken: returnSecureToken,
              deleteProvider: _deleteProvider?.build(),
              oobCode: oobCode);
    } catch (_) {
      String _$failedField;
      try {
        _$failedField = 'deleteAttribute';
        _deleteAttribute?.build();

        _$failedField = 'deleteProvider';
        _deleteProvider?.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'UpdateRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$UpdateResponse extends UpdateResponse {
  @override
  final String localId;
  @override
  final String email;
  @override
  final String displayName;
  @override
  final String photoUrl;
  @override
  final String passwordHash;
  @override
  final BuiltList<ProviderUserInfo> providerUserInfo;
  @override
  final String idToken;
  @override
  final String refreshToken;
  @override
  final String expiresIn;
  @override
  final bool emailVerified;

  factory _$UpdateResponse([void Function(UpdateResponseBuilder) updates]) =>
      (new UpdateResponseBuilder()..update(updates)).build();

  _$UpdateResponse._(
      {this.localId,
      this.email,
      this.displayName,
      this.photoUrl,
      this.passwordHash,
      this.providerUserInfo,
      this.idToken,
      this.refreshToken,
      this.expiresIn,
      this.emailVerified})
      : super._() {
    if (email == null) {
      throw new BuiltValueNullFieldError('UpdateResponse', 'email');
    }
    if (passwordHash == null) {
      throw new BuiltValueNullFieldError('UpdateResponse', 'passwordHash');
    }
    if (providerUserInfo == null) {
      throw new BuiltValueNullFieldError('UpdateResponse', 'providerUserInfo');
    }
    if (idToken == null) {
      throw new BuiltValueNullFieldError('UpdateResponse', 'idToken');
    }
    if (refreshToken == null) {
      throw new BuiltValueNullFieldError('UpdateResponse', 'refreshToken');
    }
    if (expiresIn == null) {
      throw new BuiltValueNullFieldError('UpdateResponse', 'expiresIn');
    }
  }

  @override
  UpdateResponse rebuild(void Function(UpdateResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateResponseBuilder toBuilder() =>
      new UpdateResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateResponse &&
        localId == other.localId &&
        email == other.email &&
        displayName == other.displayName &&
        photoUrl == other.photoUrl &&
        passwordHash == other.passwordHash &&
        providerUserInfo == other.providerUserInfo &&
        idToken == other.idToken &&
        refreshToken == other.refreshToken &&
        expiresIn == other.expiresIn &&
        emailVerified == other.emailVerified;
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
                                    $jc($jc(0, localId.hashCode),
                                        email.hashCode),
                                    displayName.hashCode),
                                photoUrl.hashCode),
                            passwordHash.hashCode),
                        providerUserInfo.hashCode),
                    idToken.hashCode),
                refreshToken.hashCode),
            expiresIn.hashCode),
        emailVerified.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('UpdateResponse')
          ..add('localId', localId)
          ..add('email', email)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('passwordHash', passwordHash)
          ..add('providerUserInfo', providerUserInfo)
          ..add('idToken', idToken)
          ..add('refreshToken', refreshToken)
          ..add('expiresIn', expiresIn)
          ..add('emailVerified', emailVerified))
        .toString();
  }
}

class UpdateResponseBuilder
    implements Builder<UpdateResponse, UpdateResponseBuilder> {
  _$UpdateResponse _$v;

  String _localId;
  String get localId => _$this._localId;
  set localId(String localId) => _$this._localId = localId;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _displayName;
  String get displayName => _$this._displayName;
  set displayName(String displayName) => _$this._displayName = displayName;

  String _photoUrl;
  String get photoUrl => _$this._photoUrl;
  set photoUrl(String photoUrl) => _$this._photoUrl = photoUrl;

  String _passwordHash;
  String get passwordHash => _$this._passwordHash;
  set passwordHash(String passwordHash) => _$this._passwordHash = passwordHash;

  ListBuilder<ProviderUserInfo> _providerUserInfo;
  ListBuilder<ProviderUserInfo> get providerUserInfo =>
      _$this._providerUserInfo ??= new ListBuilder<ProviderUserInfo>();
  set providerUserInfo(ListBuilder<ProviderUserInfo> providerUserInfo) =>
      _$this._providerUserInfo = providerUserInfo;

  String _idToken;
  String get idToken => _$this._idToken;
  set idToken(String idToken) => _$this._idToken = idToken;

  String _refreshToken;
  String get refreshToken => _$this._refreshToken;
  set refreshToken(String refreshToken) => _$this._refreshToken = refreshToken;

  String _expiresIn;
  String get expiresIn => _$this._expiresIn;
  set expiresIn(String expiresIn) => _$this._expiresIn = expiresIn;

  bool _emailVerified;
  bool get emailVerified => _$this._emailVerified;
  set emailVerified(bool emailVerified) =>
      _$this._emailVerified = emailVerified;

  UpdateResponseBuilder();

  UpdateResponseBuilder get _$this {
    if (_$v != null) {
      _localId = _$v.localId;
      _email = _$v.email;
      _displayName = _$v.displayName;
      _photoUrl = _$v.photoUrl;
      _passwordHash = _$v.passwordHash;
      _providerUserInfo = _$v.providerUserInfo?.toBuilder();
      _idToken = _$v.idToken;
      _refreshToken = _$v.refreshToken;
      _expiresIn = _$v.expiresIn;
      _emailVerified = _$v.emailVerified;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$UpdateResponse;
  }

  @override
  void update(void Function(UpdateResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$UpdateResponse build() {
    _$UpdateResponse _$result;
    try {
      _$result = _$v ??
          new _$UpdateResponse._(
              localId: localId,
              email: email,
              displayName: displayName,
              photoUrl: photoUrl,
              passwordHash: passwordHash,
              providerUserInfo: providerUserInfo.build(),
              idToken: idToken,
              refreshToken: refreshToken,
              expiresIn: expiresIn,
              emailVerified: emailVerified);
    } catch (_) {
      String _$failedField;
      try {
        _$failedField = 'providerUserInfo';
        providerUserInfo.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'UpdateResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$ProviderUserInfo extends ProviderUserInfo {
  @override
  final ProviderType providerId;
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
  UserInfo __userInfo;

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
      : super._() {
    if (providerId == null) {
      throw new BuiltValueNullFieldError('ProviderUserInfo', 'providerId');
    }
    if (federatedId == null) {
      throw new BuiltValueNullFieldError('ProviderUserInfo', 'federatedId');
    }
  }

  @override
  UserInfo get userInfo => __userInfo ??= super.userInfo;

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

  ProviderType _providerId;
  ProviderType get providerId => _$this._providerId;
  set providerId(ProviderType providerId) => _$this._providerId = providerId;

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

class _$UserDataResponse extends UserDataResponse {
  @override
  final String localId;
  @override
  final String email;
  @override
  final bool emailVerified;
  @override
  final String displayName;
  @override
  final BuiltList<ProviderUserInfo> providerUserInfo;
  @override
  final String photoUrl;
  @override
  final String phoneNumber;
  @override
  final String passwordHash;
  @override
  final double passwordUpdatedAt;
  @override
  final int validSince;
  @override
  final bool disabled;
  @override
  final int lastLoginAt;
  @override
  final int createdAt;
  @override
  final bool customAuth;

  factory _$UserDataResponse(
          [void Function(UserDataResponseBuilder) updates]) =>
      (new UserDataResponseBuilder()..update(updates)).build();

  _$UserDataResponse._(
      {this.localId,
      this.email,
      this.emailVerified,
      this.displayName,
      this.providerUserInfo,
      this.photoUrl,
      this.phoneNumber,
      this.passwordHash,
      this.passwordUpdatedAt,
      this.validSince,
      this.disabled,
      this.lastLoginAt,
      this.createdAt,
      this.customAuth})
      : super._() {
    if (localId == null) {
      throw new BuiltValueNullFieldError('UserDataResponse', 'localId');
    }
    if (providerUserInfo == null) {
      throw new BuiltValueNullFieldError(
          'UserDataResponse', 'providerUserInfo');
    }
    if (lastLoginAt == null) {
      throw new BuiltValueNullFieldError('UserDataResponse', 'lastLoginAt');
    }
    if (createdAt == null) {
      throw new BuiltValueNullFieldError('UserDataResponse', 'createdAt');
    }
  }

  @override
  UserDataResponse rebuild(void Function(UserDataResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserDataResponseBuilder toBuilder() =>
      new UserDataResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserDataResponse &&
        localId == other.localId &&
        email == other.email &&
        emailVerified == other.emailVerified &&
        displayName == other.displayName &&
        providerUserInfo == other.providerUserInfo &&
        photoUrl == other.photoUrl &&
        phoneNumber == other.phoneNumber &&
        passwordHash == other.passwordHash &&
        passwordUpdatedAt == other.passwordUpdatedAt &&
        validSince == other.validSince &&
        disabled == other.disabled &&
        lastLoginAt == other.lastLoginAt &&
        createdAt == other.createdAt &&
        customAuth == other.customAuth;
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
                                                        $jc(0,
                                                            localId.hashCode),
                                                        email.hashCode),
                                                    emailVerified.hashCode),
                                                displayName.hashCode),
                                            providerUserInfo.hashCode),
                                        photoUrl.hashCode),
                                    phoneNumber.hashCode),
                                passwordHash.hashCode),
                            passwordUpdatedAt.hashCode),
                        validSince.hashCode),
                    disabled.hashCode),
                lastLoginAt.hashCode),
            createdAt.hashCode),
        customAuth.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('UserDataResponse')
          ..add('localId', localId)
          ..add('email', email)
          ..add('emailVerified', emailVerified)
          ..add('displayName', displayName)
          ..add('providerUserInfo', providerUserInfo)
          ..add('photoUrl', photoUrl)
          ..add('phoneNumber', phoneNumber)
          ..add('passwordHash', passwordHash)
          ..add('passwordUpdatedAt', passwordUpdatedAt)
          ..add('validSince', validSince)
          ..add('disabled', disabled)
          ..add('lastLoginAt', lastLoginAt)
          ..add('createdAt', createdAt)
          ..add('customAuth', customAuth))
        .toString();
  }
}

class UserDataResponseBuilder
    implements Builder<UserDataResponse, UserDataResponseBuilder> {
  _$UserDataResponse _$v;

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

  ListBuilder<ProviderUserInfo> _providerUserInfo;
  ListBuilder<ProviderUserInfo> get providerUserInfo =>
      _$this._providerUserInfo ??= new ListBuilder<ProviderUserInfo>();
  set providerUserInfo(ListBuilder<ProviderUserInfo> providerUserInfo) =>
      _$this._providerUserInfo = providerUserInfo;

  String _photoUrl;
  String get photoUrl => _$this._photoUrl;
  set photoUrl(String photoUrl) => _$this._photoUrl = photoUrl;

  String _phoneNumber;
  String get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String phoneNumber) => _$this._phoneNumber = phoneNumber;

  String _passwordHash;
  String get passwordHash => _$this._passwordHash;
  set passwordHash(String passwordHash) => _$this._passwordHash = passwordHash;

  double _passwordUpdatedAt;
  double get passwordUpdatedAt => _$this._passwordUpdatedAt;
  set passwordUpdatedAt(double passwordUpdatedAt) =>
      _$this._passwordUpdatedAt = passwordUpdatedAt;

  int _validSince;
  int get validSince => _$this._validSince;
  set validSince(int validSince) => _$this._validSince = validSince;

  bool _disabled;
  bool get disabled => _$this._disabled;
  set disabled(bool disabled) => _$this._disabled = disabled;

  int _lastLoginAt;
  int get lastLoginAt => _$this._lastLoginAt;
  set lastLoginAt(int lastLoginAt) => _$this._lastLoginAt = lastLoginAt;

  int _createdAt;
  int get createdAt => _$this._createdAt;
  set createdAt(int createdAt) => _$this._createdAt = createdAt;

  bool _customAuth;
  bool get customAuth => _$this._customAuth;
  set customAuth(bool customAuth) => _$this._customAuth = customAuth;

  UserDataResponseBuilder();

  UserDataResponseBuilder get _$this {
    if (_$v != null) {
      _localId = _$v.localId;
      _email = _$v.email;
      _emailVerified = _$v.emailVerified;
      _displayName = _$v.displayName;
      _providerUserInfo = _$v.providerUserInfo?.toBuilder();
      _photoUrl = _$v.photoUrl;
      _phoneNumber = _$v.phoneNumber;
      _passwordHash = _$v.passwordHash;
      _passwordUpdatedAt = _$v.passwordUpdatedAt;
      _validSince = _$v.validSince;
      _disabled = _$v.disabled;
      _lastLoginAt = _$v.lastLoginAt;
      _createdAt = _$v.createdAt;
      _customAuth = _$v.customAuth;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserDataResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$UserDataResponse;
  }

  @override
  void update(void Function(UserDataResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$UserDataResponse build() {
    _$UserDataResponse _$result;
    try {
      _$result = _$v ??
          new _$UserDataResponse._(
              localId: localId,
              email: email,
              emailVerified: emailVerified,
              displayName: displayName,
              providerUserInfo: providerUserInfo.build(),
              photoUrl: photoUrl,
              phoneNumber: phoneNumber,
              passwordHash: passwordHash,
              passwordUpdatedAt: passwordUpdatedAt,
              validSince: validSince,
              disabled: disabled,
              lastLoginAt: lastLoginAt,
              createdAt: createdAt,
              customAuth: customAuth);
    } catch (_) {
      String _$failedField;
      try {
        _$failedField = 'providerUserInfo';
        providerUserInfo.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'UserDataResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

class _$AdditionalUserInfoImpl extends AdditionalUserInfoImpl {
  @override
  final ProviderType providerId;
  @override
  final MapBuilder<String, JsonObject> profile;
  @override
  final String username;
  @override
  final bool isNewUser;

  factory _$AdditionalUserInfoImpl(
          [void Function(AdditionalUserInfoImplBuilder) updates]) =>
      (new AdditionalUserInfoImplBuilder()..update(updates)).build();

  _$AdditionalUserInfoImpl._(
      {this.providerId, this.profile, this.username, this.isNewUser})
      : super._() {
    if (isNewUser == null) {
      throw new BuiltValueNullFieldError('AdditionalUserInfoImpl', 'isNewUser');
    }
  }

  @override
  AdditionalUserInfoImpl rebuild(
          void Function(AdditionalUserInfoImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AdditionalUserInfoImplBuilder toBuilder() =>
      new AdditionalUserInfoImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdditionalUserInfoImpl &&
        providerId == other.providerId &&
        profile == other.profile &&
        username == other.username &&
        isNewUser == other.isNewUser;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, providerId.hashCode), profile.hashCode),
            username.hashCode),
        isNewUser.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('AdditionalUserInfoImpl')
          ..add('providerId', providerId)
          ..add('profile', profile)
          ..add('username', username)
          ..add('isNewUser', isNewUser))
        .toString();
  }
}

class AdditionalUserInfoImplBuilder
    implements Builder<AdditionalUserInfoImpl, AdditionalUserInfoImplBuilder> {
  _$AdditionalUserInfoImpl _$v;

  ProviderType _providerId;
  ProviderType get providerId => _$this._providerId;
  set providerId(ProviderType providerId) => _$this._providerId = providerId;

  MapBuilder<String, JsonObject> _profile;
  MapBuilder<String, JsonObject> get profile => _$this._profile;
  set profile(MapBuilder<String, JsonObject> profile) =>
      _$this._profile = profile;

  String _username;
  String get username => _$this._username;
  set username(String username) => _$this._username = username;

  bool _isNewUser;
  bool get isNewUser => _$this._isNewUser;
  set isNewUser(bool isNewUser) => _$this._isNewUser = isNewUser;

  AdditionalUserInfoImplBuilder();

  AdditionalUserInfoImplBuilder get _$this {
    if (_$v != null) {
      _providerId = _$v.providerId;
      _profile = _$v.profile;
      _username = _$v.username;
      _isNewUser = _$v.isNewUser;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdditionalUserInfoImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$AdditionalUserInfoImpl;
  }

  @override
  void update(void Function(AdditionalUserInfoImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$AdditionalUserInfoImpl build() {
    final _$result = _$v ??
        new _$AdditionalUserInfoImpl._(
            providerId: providerId,
            profile: profile,
            username: username,
            isNewUser: isNewUser);
    replace(_$result);
    return _$result;
  }
}

class _$UserInfoImpl extends UserInfoImpl {
  @override
  final String uid;
  @override
  final ProviderType providerId;
  @override
  final String displayName;
  @override
  final String photoUrl;
  @override
  final String email;
  @override
  final String phoneNumber;
  @override
  final bool isEmailVerified;

  factory _$UserInfoImpl([void Function(UserInfoImplBuilder) updates]) =>
      (new UserInfoImplBuilder()..update(updates)).build();

  _$UserInfoImpl._(
      {this.uid,
      this.providerId,
      this.displayName,
      this.photoUrl,
      this.email,
      this.phoneNumber,
      this.isEmailVerified})
      : super._() {
    if (uid == null) {
      throw new BuiltValueNullFieldError('UserInfoImpl', 'uid');
    }
  }

  @override
  UserInfoImpl rebuild(void Function(UserInfoImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserInfoImplBuilder toBuilder() => new UserInfoImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserInfoImpl &&
        uid == other.uid &&
        providerId == other.providerId &&
        displayName == other.displayName &&
        photoUrl == other.photoUrl &&
        email == other.email &&
        phoneNumber == other.phoneNumber &&
        isEmailVerified == other.isEmailVerified;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, uid.hashCode), providerId.hashCode),
                        displayName.hashCode),
                    photoUrl.hashCode),
                email.hashCode),
            phoneNumber.hashCode),
        isEmailVerified.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('UserInfoImpl')
          ..add('uid', uid)
          ..add('providerId', providerId)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('email', email)
          ..add('phoneNumber', phoneNumber)
          ..add('isEmailVerified', isEmailVerified))
        .toString();
  }
}

class UserInfoImplBuilder
    implements Builder<UserInfoImpl, UserInfoImplBuilder> {
  _$UserInfoImpl _$v;

  String _uid;
  String get uid => _$this._uid;
  set uid(String uid) => _$this._uid = uid;

  ProviderType _providerId;
  ProviderType get providerId => _$this._providerId;
  set providerId(ProviderType providerId) => _$this._providerId = providerId;

  String _displayName;
  String get displayName => _$this._displayName;
  set displayName(String displayName) => _$this._displayName = displayName;

  String _photoUrl;
  String get photoUrl => _$this._photoUrl;
  set photoUrl(String photoUrl) => _$this._photoUrl = photoUrl;

  String _email;
  String get email => _$this._email;
  set email(String email) => _$this._email = email;

  String _phoneNumber;
  String get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String phoneNumber) => _$this._phoneNumber = phoneNumber;

  bool _isEmailVerified;
  bool get isEmailVerified => _$this._isEmailVerified;
  set isEmailVerified(bool isEmailVerified) =>
      _$this._isEmailVerified = isEmailVerified;

  UserInfoImplBuilder();

  UserInfoImplBuilder get _$this {
    if (_$v != null) {
      _uid = _$v.uid;
      _providerId = _$v.providerId;
      _displayName = _$v.displayName;
      _photoUrl = _$v.photoUrl;
      _email = _$v.email;
      _phoneNumber = _$v.phoneNumber;
      _isEmailVerified = _$v.isEmailVerified;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserInfoImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$UserInfoImpl;
  }

  @override
  void update(void Function(UserInfoImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$UserInfoImpl build() {
    final _$result = _$v ??
        new _$UserInfoImpl._(
            uid: uid,
            providerId: providerId,
            displayName: displayName,
            photoUrl: photoUrl,
            email: email,
            phoneNumber: phoneNumber,
            isEmailVerified: isEmailVerified);
    replace(_$result);
    return _$result;
  }
}

class _$UserMetadataImpl extends UserMetadataImpl {
  @override
  final DateTime lastSignInDate;
  @override
  final DateTime creationDate;

  factory _$UserMetadataImpl(
          [void Function(UserMetadataImplBuilder) updates]) =>
      (new UserMetadataImplBuilder()..update(updates)).build();

  _$UserMetadataImpl._({this.lastSignInDate, this.creationDate}) : super._() {
    if (lastSignInDate == null) {
      throw new BuiltValueNullFieldError('UserMetadataImpl', 'lastSignInDate');
    }
    if (creationDate == null) {
      throw new BuiltValueNullFieldError('UserMetadataImpl', 'creationDate');
    }
  }

  @override
  UserMetadataImpl rebuild(void Function(UserMetadataImplBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserMetadataImplBuilder toBuilder() =>
      new UserMetadataImplBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserMetadataImpl &&
        lastSignInDate == other.lastSignInDate &&
        creationDate == other.creationDate;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, lastSignInDate.hashCode), creationDate.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('UserMetadataImpl')
          ..add('lastSignInDate', lastSignInDate)
          ..add('creationDate', creationDate))
        .toString();
  }
}

class UserMetadataImplBuilder
    implements Builder<UserMetadataImpl, UserMetadataImplBuilder> {
  _$UserMetadataImpl _$v;

  DateTime _lastSignInDate;
  DateTime get lastSignInDate => _$this._lastSignInDate;
  set lastSignInDate(DateTime lastSignInDate) =>
      _$this._lastSignInDate = lastSignInDate;

  DateTime _creationDate;
  DateTime get creationDate => _$this._creationDate;
  set creationDate(DateTime creationDate) =>
      _$this._creationDate = creationDate;

  UserMetadataImplBuilder();

  UserMetadataImplBuilder get _$this {
    if (_$v != null) {
      _lastSignInDate = _$v.lastSignInDate;
      _creationDate = _$v.creationDate;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserMetadataImpl other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$UserMetadataImpl;
  }

  @override
  void update(void Function(UserMetadataImplBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$UserMetadataImpl build() {
    final _$result = _$v ??
        new _$UserMetadataImpl._(
            lastSignInDate: lastSignInDate, creationDate: creationDate);
    replace(_$result);
    return _$result;
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
  final bool androidInstallApp;
  @override
  final String androidMinimumVersion;
  @override
  final bool canHandleCodeInApp;
  @override
  final String dynamicLinkDomain;

  factory _$ActionCodeSettings(
          [void Function(ActionCodeSettingsBuilder) updates]) =>
      (new ActionCodeSettingsBuilder()..update(updates)).build();

  _$ActionCodeSettings._(
      {this.continueUrl,
      this.iOSBundleId,
      this.androidPackageName,
      this.androidInstallApp,
      this.androidMinimumVersion,
      this.canHandleCodeInApp,
      this.dynamicLinkDomain})
      : super._();

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
        androidInstallApp == other.androidInstallApp &&
        androidMinimumVersion == other.androidMinimumVersion &&
        canHandleCodeInApp == other.canHandleCodeInApp &&
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
                    androidInstallApp.hashCode),
                androidMinimumVersion.hashCode),
            canHandleCodeInApp.hashCode),
        dynamicLinkDomain.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ActionCodeSettings')
          ..add('continueUrl', continueUrl)
          ..add('iOSBundleId', iOSBundleId)
          ..add('androidPackageName', androidPackageName)
          ..add('androidInstallApp', androidInstallApp)
          ..add('androidMinimumVersion', androidMinimumVersion)
          ..add('canHandleCodeInApp', canHandleCodeInApp)
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

  bool _androidInstallApp;
  bool get androidInstallApp => _$this._androidInstallApp;
  set androidInstallApp(bool androidInstallApp) =>
      _$this._androidInstallApp = androidInstallApp;

  String _androidMinimumVersion;
  String get androidMinimumVersion => _$this._androidMinimumVersion;
  set androidMinimumVersion(String androidMinimumVersion) =>
      _$this._androidMinimumVersion = androidMinimumVersion;

  bool _canHandleCodeInApp;
  bool get canHandleCodeInApp => _$this._canHandleCodeInApp;
  set canHandleCodeInApp(bool canHandleCodeInApp) =>
      _$this._canHandleCodeInApp = canHandleCodeInApp;

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
      _androidInstallApp = _$v.androidInstallApp;
      _androidMinimumVersion = _$v.androidMinimumVersion;
      _canHandleCodeInApp = _$v.canHandleCodeInApp;
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
            androidInstallApp: androidInstallApp,
            androidMinimumVersion: androidMinimumVersion,
            canHandleCodeInApp: canHandleCodeInApp,
            dynamicLinkDomain: dynamicLinkDomain);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
