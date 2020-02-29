// GENERATED CODE - DO NOT MODIFY BY HAND

part of serializers;

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers = (new Serializers().toBuilder()
      ..add(AdditionalUserInfoImpl.serializer)
      ..add(EmailPasswordAuthCredentialImpl.serializer)
      ..add(FacebookAuthCredentialImpl.serializer)
      ..add(GameCenterAuthCredentialImpl.serializer)
      ..add(GithubAuthCredentialImpl.serializer)
      ..add(GoogleAuthCredentialImpl.serializer)
      ..add(OAuthCredentialImpl.serializer)
      ..add(PhoneAuthCredentialImpl.serializer)
      ..add(SamlAuthCredentialImpl.serializer)
      ..add(SecureTokenRequest.serializer)
      ..add(SecureTokenResponse.serializer)
      ..add(SignInWithGameCenterRequest.serializer)
      ..add(SignInWithGameCenterResponse.serializer)
      ..add(TwitterAuthCredentialImpl.serializer)
      ..add(UserInfoImpl.serializer)
      ..add(UserMetadataImpl.serializer)
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => new ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(
              BuiltMap, const [const FullType(String), const FullType(String)]),
          () => new MapBuilder<String, String>()))
    .build();

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
