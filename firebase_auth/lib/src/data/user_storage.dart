// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth;

class UserStorage {
  const UserStorage({@required Box<dynamic> userBox, @required String appName})
      : assert(userBox != null),
        assert(appName != null),
        _userBox = userBox,
        _appName = appName;

  final Box<dynamic> _userBox;
  final String _appName;

  void save(FirebaseUser user) {
    if (user != null) {
      final Map<String, dynamic> data = serializers.serializeWith(FirebaseUser.serializer, user);
      _userBox.put(_userKey, jsonEncode(data));
    } else {
      _userBox.delete(_userKey);
    }
  }

  FirebaseUser get(FirebaseAuth auth) {
    final String json = _userBox.get(_userKey);
    if (json == null) {
      return null;
    }

    final Map<String, dynamic> data = <String, dynamic>{...jsonDecode(json), 'auth': auth};
    return serializers.deserializeWith(FirebaseUser.serializer, data);
  }

  String get _userKey => _getKey('user');

  String _getKey(String field) => 'UserStorage___${_appName}__$field';
}
