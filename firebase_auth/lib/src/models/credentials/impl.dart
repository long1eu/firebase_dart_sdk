// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of models;

abstract class EmailPasswordAuthCredentialImpl
    with AuthCredential
    implements
        Built<EmailPasswordAuthCredentialImpl, EmailPasswordAuthCredentialImplBuilder>,
        EmailPasswordAuthCredential {
  factory EmailPasswordAuthCredentialImpl() = _$EmailPasswordAuthCredentialImpl;

  EmailPasswordAuthCredentialImpl._();

  @override
  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<EmailPasswordAuthCredentialImpl> get serializer => _$emailPasswordAuthCredentialImplSerializer;
}

abstract class FacebookAuthCredentialImpl
    with AuthCredential
    implements Built<FacebookAuthCredentialImpl, FacebookAuthCredentialImplBuilder>, FacebookAuthCredential {
  factory FacebookAuthCredentialImpl() = _$FacebookAuthCredentialImpl;

  FacebookAuthCredentialImpl._();

  @override
  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<FacebookAuthCredentialImpl> get serializer => _$facebookAuthCredentialImplSerializer;
}

abstract class GithubAuthCredentialImpl
    with AuthCredential
    implements Built<GithubAuthCredentialImpl, GithubAuthCredentialImplBuilder>, GithubAuthCredential {
  factory GithubAuthCredentialImpl() = _$GithubAuthCredentialImpl;

  GithubAuthCredentialImpl._();

  @override
  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<GithubAuthCredentialImpl> get serializer => _$githubAuthCredentialImplSerializer;
}

abstract class GoogleAuthCredentialImpl
    with AuthCredential
    implements Built<GoogleAuthCredentialImpl, GoogleAuthCredentialImplBuilder>, GoogleAuthCredential {
  factory GoogleAuthCredentialImpl() = _$GoogleAuthCredentialImpl;

  GoogleAuthCredentialImpl._();

  @override
  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<GoogleAuthCredentialImpl> get serializer => _$googleAuthCredentialImplSerializer;
}

abstract class TwitterAuthCredentialImpl
    with AuthCredential
    implements Built<TwitterAuthCredentialImpl, TwitterAuthCredentialImplBuilder>, TwitterAuthCredential {
  factory TwitterAuthCredentialImpl() = _$TwitterAuthCredentialImpl;

  TwitterAuthCredentialImpl._();

  @override
  Map<String, dynamic> get json => serializers.serializeWith(serializer, this);

  static Serializer<TwitterAuthCredentialImpl> get serializer => _$twitterAuthCredentialImplSerializer;
}
