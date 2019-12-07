part of firebase_auth;

_$FirebaseUserSerializer _$firebaseUserSerializer = _$FirebaseUserSerializer();

class _$FirebaseUserSerializer implements StructuredSerializer<FirebaseUser> {
  @override
  final Iterable<Type> types = const <Type>[FirebaseUser];
  @override
  final String wireName = 'FirebaseUser';

  @override
  Iterable<Object> serialize(Serializers serializers, FirebaseUser object,
      {FullType specifiedType = FullType.unspecified}) {
    return <Object>[
      'uid',
      serializers.serialize(object.uid, specifiedType: const FullType(String)),
      'isAnonymous',
      serializers.serialize(object.isAnonymous, specifiedType: const FullType(bool)),
      'hasEmailPasswordCredential',
      serializers.serialize(object._hasEmailPasswordCredential, specifiedType: const FullType(bool)),
      'providerData',
      serializers.serialize(BuiltList<UserInfoImpl>(object.providerData),
          specifiedType: const FullType(
            BuiltList,
            <FullType>[FullType(UserInfoImpl)],
          )),
      'email',
      serializers.serialize(object.email, specifiedType: const FullType(String)),
      'phoneNumber',
      serializers.serialize(object.phoneNumber, specifiedType: const FullType(String)),
      'isEmailVerified',
      serializers.serialize(object.isEmailVerified, specifiedType: const FullType(bool)),
      'photoUrl',
      serializers.serialize(object.photoUrl, specifiedType: const FullType(String)),
      'displayName',
      serializers.serialize(object.displayName, specifiedType: const FullType(String)),
      'metadata',
      serializers.serialize(object.metadata, specifiedType: const FullType(UserMetadataImpl)),
      'configuration',
      serializers.serialize(object.metadata, specifiedType: const FullType(AuthRequestConfiguration)),
      'accessToken',
      serializers.serialize(object._secureTokenApi._accessToken, specifiedType: const FullType(String)),
      'accessTokenExpirationDate',
      serializers.serialize(object._secureTokenApi._accessTokenExpirationDate, specifiedType: const FullType(DateTime)),
      'refreshToken',
      serializers.serialize(object._secureTokenApi._refreshToken, specifiedType: const FullType(String)),
    ];
  }

  @override
  FirebaseUser deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    String uid;
    bool isAnonymous;
    bool hasEmailPasswordCredential;
    List<UserInfo> providerUserInfo;
    String email;
    String phoneNumber;
    bool isEmailVerified;
    String photoUrl;
    String displayName;
    UserMetadataImpl metadata;
    AuthRequestConfiguration configuration;
    String accessToken;
    DateTime accessTokenExpirationDate;
    String refreshToken;
    FirebaseAuth auth;

    final Iterator<Object> iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final String key = iterator.current;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'uid':
          uid = serializers.deserialize(value, specifiedType: const FullType(String));
          break;
        case 'isAnonymous':
          isAnonymous = serializers.deserialize(value, specifiedType: const FullType(bool));
          break;
        case 'hasEmailPasswordCredential':
          hasEmailPasswordCredential = serializers.deserialize(value, specifiedType: const FullType(bool));
          break;
        case 'providerData':
          final BuiltList<UserInfoImpl> _info = serializers.deserialize(value,
              specifiedType: const FullType(
                BuiltList,
                <FullType>[FullType(UserInfoImpl)],
              ));
          providerUserInfo = _info.toList();
          break;
        case 'email':
          email = serializers.deserialize(value, specifiedType: const FullType(String));
          break;
        case 'phoneNumber':
          phoneNumber = serializers.deserialize(value, specifiedType: const FullType(String));
          break;
        case 'isEmailVerified':
          isEmailVerified = serializers.deserialize(value, specifiedType: const FullType(bool));
          break;
        case 'photoUrl':
          photoUrl = serializers.deserialize(value, specifiedType: const FullType(String));
          break;
        case 'displayName':
          displayName = serializers.deserialize(value, specifiedType: const FullType(String));
          break;
        case 'metadata':
          metadata = serializers.deserialize(value, specifiedType: const FullType(UserMetadataImpl));
          break;
        case 'configuration':
          configuration = serializers.deserialize(value, specifiedType: const FullType(AuthRequestConfiguration));
          break;
        case 'accessToken':
          accessToken = serializers.deserialize(value, specifiedType: const FullType(String));
          break;
        case 'accessTokenExpirationDate':
          accessTokenExpirationDate = serializers.deserialize(value, specifiedType: const FullType(DateTime));
          break;
        case 'refreshToken':
          refreshToken = serializers.deserialize(value, specifiedType: const FullType(String));
          break;
        case 'auth':
          auth = value;
          break;
      }
    }

    final HttpService secureTokenService =
        HttpService(configuration: configuration, host: 'https://securetoken.googleapis.com');
    final SecureTokenApi secureTokenApi = SecureTokenApi(
      secureTokenService: SecureTokenService(service: secureTokenService),
      accessToken: accessToken,
      accessTokenExpirationDate: accessTokenExpirationDate,
      refreshToken: refreshToken,
    );

    final FirebaseUser user = FirebaseUser(secureTokenApi: secureTokenApi, auth: auth);

    return user
      .._isAnonymous = isAnonymous
      .._userInfo = UserInfoImpl(
        uid: uid,
        email: email,
        isEmailVerified: isEmailVerified,
        displayName: displayName,
        photoUrl: photoUrl,
        phoneNumber: phoneNumber,
      )
      ..__hasEmailPasswordCredential = hasEmailPasswordCredential
      .._metadata = metadata
      .._providerData = providerUserInfo;
  }
}

mixin UserInfoMixin implements UserInfo {
  UserInfo _userInfo;

  @override
  String get uid => _userInfo.uid;

  @override
  String get providerId => _userInfo.providerId;

  @override
  String get displayName => _userInfo.displayName;

  @override
  String get photoUrl => _userInfo.photoUrl;

  @override
  String get email => _userInfo.email;

  @override
  String get phoneNumber => _userInfo.phoneNumber;

  @override
  bool get isEmailVerified => _userInfo.isEmailVerified;
}
