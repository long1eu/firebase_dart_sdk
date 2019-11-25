// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of models;

abstract class EmailAuthProvider {
  /// Creates an [AuthCredential] for an email & password sign in.
  static AuthCredential getCredential({@required String email, @required String password}) {
    return EmailPasswordAuthCredential.withPassword(email: email, password: password);
  }

  /// Creates an [AuthCredential] for an email & link sign in.
  static AuthCredential getCredentialWithLink({@required String email, @required String link}) {
    return EmailPasswordAuthCredential.withLink(email: email, link: link);
  }
}

class FacebookAuthProvider {
  /// Creates an [AuthCredential] for a Facebook sign in.
  static AuthCredential getCredential(String accessToken) {
    return FacebookAuthCredential(accessToken);
  }
}

class GithubAuthProvider {
  /// Creates an [AuthCredential] for a GitHub sign in.
  static AuthCredential getCredential(String token) {
    return GithubAuthCredential(token);
  }
}

class GoogleAuthProvider {
  /// Creates an [AuthCredential] for a Google sign in.
  static AuthCredential getCredential({@required String idToken, @required String accessToken}) {
    return GoogleAuthCredential(idToken: idToken, accessToken: accessToken);
  }
}

class TwitterAuthProvider {
  /// Creates an [AuthCredential] for a Google sign in.
  static AuthCredential getCredential({@required String authToken, @required String authTokenSecret}) {
    return TwitterAuthCredential(authToken: authToken, authTokenSecret: authTokenSecret);
  }
}


class ProviderType {
  const ProviderType._(this._i, this._value);

  final String _value;
  final int _i;

  static const ProviderType password = ProviderType._(0, 'password');
  static const ProviderType facebook = ProviderType._(1, 'facebook.com');
  static const ProviderType github = ProviderType._(2, 'github.com');
  static const ProviderType google = ProviderType._(3, 'google.com');
  static const ProviderType twitter = ProviderType._(4, 'twitter.com');

  static const List<ProviderType> values = <ProviderType>[
    password,
    facebook,
    github,
    google,
    twitter,
  ];

  static const List<String> _names = <String>[
    'password',
    'facebook',
    'github',
    'google',
    'twitter',
  ];

  static Serializer<ProviderType> get serializer => _$ProviderTypeSerializer;

  @override
  String toString() => 'ProviderType.${_names[_i]}';
}

Serializer<ProviderType> _$ProviderTypeSerializer = _ProviderTypeSerializer();

class _ProviderTypeSerializer extends PrimitiveSerializer<ProviderType> {
  @override
  Iterable<Type> get types => BuiltList<Type>(<Type>[ProviderType]);

  @override
  String get wireName => 'ProviderType';

  @override
  ProviderType deserialize(Serializers serializers, Object serialized,
      {FullType specifiedType = FullType.unspecified}) {
    return ProviderType.values.firstWhere((ProviderType it) => it._value == serialized);
  }

  @override
  Object serialize(Serializers serializers, ProviderType object, {FullType specifiedType = FullType.unspecified}) {
    return object._value;
  }
}
