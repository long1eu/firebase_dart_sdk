// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth_vm;

class UserStorage {
  const UserStorage({@required LocalStorage localStorage, @required String appName})
      : assert(localStorage != null),
        assert(appName != null),
        _localStorage = localStorage,
        _appName = appName;

  final LocalStorage _localStorage;
  final String _appName;

  void save(FirebaseUser user) {
    if (user != null) {
      final Map<String, dynamic> data = FirebaseUserExtension(user)._json;
      _localStorage.set(_userKey, jsonEncode(data));
    } else {
      _localStorage.set(_userKey, null);
    }
  }

  FirebaseUser get(FirebaseAuth auth) {
    final String json = _localStorage.get(_userKey);
    if (json == null) {
      return null;
    }

    return FirebaseUserExtension._fromJson(auth, jsonDecode(json));
  }

  String get _userKey => _getKey('user');

  String _getKey(String field) => 'UserStorage___${_appName}__$field';
}

extension FirebaseUserExtension on FirebaseUser {
  static FirebaseUser _fromJson(FirebaseAuth auth, Map<String, dynamic> json) {
    final String uid = json['uid'];
    final bool isAnonymous = json['isAnonymous'];
    final bool hasEmailPasswordCredential = json['hasEmailPasswordCredential'];
    final Map<String, UserInfo> providerUserInfo = json.containsKey('providerData')
        ? Map<String, dynamic>.from(json['providerData'])
            .map((String key, dynamic value) => MapEntry<String, UserInfo>(key, UserInfo._fromJson(value)))
        : null;
    final String email = json['email'];
    final String phoneNumber = json['phoneNumber'];
    final bool isEmailVerified = json['isEmailVerified'];
    final String photoUrl = json['photoUrl'];
    final String displayName = json['displayName'];
    final UserMetadata metadata = json.containsKey('metadata') ? UserMetadata._fromJson(json['metadata']) : null;
    final String accessToken = json['accessToken'];
    final DateTime accessTokenExpirationDate = DateTime.fromMicrosecondsSinceEpoch(json['accessTokenExpirationDate']);
    final String refreshToken = json['refreshToken'];

    final SecureTokenApi secureTokenApi = SecureTokenApi(
      client: auth._apiKeyClient,
      accessToken: accessToken,
      accessTokenExpirationDate: accessTokenExpirationDate,
      refreshToken: refreshToken,
    );

    return FirebaseUser._(secureTokenApi: secureTokenApi, auth: auth)
      .._isAnonymous = isAnonymous
      .._userInfo = UserInfo._(
        uid: uid,
        email: email,
        isEmailVerified: isEmailVerified,
        displayName: displayName,
        photoUrl: photoUrl,
        phoneNumber: phoneNumber,
      )
      .._hasEmailPasswordCredential = hasEmailPasswordCredential
      .._metadata = metadata
      .._providerData = providerUserInfo;
  }

  Map<String, dynamic> get _json {
    return <String, dynamic>{
      'uid': uid,
      'isAnonymous': isAnonymous,
      'hasEmailPasswordCredential': _hasEmailPasswordCredential,
      if (providerData != null)
        'providerData': providerData
            .asMap()
            .map<String, dynamic>((_, UserInfo value) => MapEntry<String, dynamic>(value.providerId, value._json)),
      'email': email,
      'phoneNumber': phoneNumber,
      'isEmailVerified': isEmailVerified,
      'photoUrl': photoUrl,
      'displayName': displayName,
      if (metadata != null) 'metadata': metadata._json,
      'accessToken': _secureTokenApi._accessToken,
      'accessTokenExpirationDate': _secureTokenApi._accessTokenExpirationDate.microsecondsSinceEpoch,
      'refreshToken': _secureTokenApi._refreshToken,
    };
  }
}
