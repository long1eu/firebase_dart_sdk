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
    final Map<String, dynamic> data = serializers.serializeWith(FirebaseUser.serializer, user);
    _userBox.put(_getKey('user'), jsonEncode(data));
  }

  FirebaseUser get() {
    final String json = _userBox.get(_getKey('user'));
    return serializers.deserializeWith(FirebaseUser.serializer, jsonDecode(json));
  }

  String _getKey(String field) => 'UserStorage___${_appName}__$field';
}
