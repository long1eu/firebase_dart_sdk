// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth;

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
      final Map<String, dynamic> data = serializers.serializeWith(FirebaseUser.serializer, user);
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

    final Map<String, dynamic> data = <String, dynamic>{...jsonDecode(json), 'auth': auth};
    return serializers.deserializeWith(FirebaseUser.serializer, data);
  }

  String get _userKey => _getKey('user');

  String _getKey(String field) => 'UserStorage___${_appName}__$field';
}
