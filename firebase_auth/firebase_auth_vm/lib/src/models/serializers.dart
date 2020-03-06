// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

library serializers;

import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:firebase_auth_vm/firebase_auth_vm.dart';

part 'serializers.g.dart';

@SerializersFor(<Type>[
  PhoneAuthCredentialImpl,
  ActionCodeSettings,
  GoogleAuthCredentialImpl,
  SamlAuthCredentialImpl,
  GameCenterAuthCredentialImpl,
  EmailPasswordAuthCredentialImpl,
  SignInWithGameCenterResponse,
  OAuthCredentialImpl,
  AdditionalUserInfoImpl,
  SecureTokenRequest,
  UserInfoImpl,
  SecureTokenResponse,
  GithubAuthCredentialImpl,
  FacebookAuthCredentialImpl,
  UserMetadataImpl,
  SignInWithGameCenterRequest,
  TwitterAuthCredentialImpl,
])
Serializers serializers = (_$serializers.toBuilder() //
      ..add(FirebaseUser.serializer)
      ..add(SecureTokenGrantType.serializer)
      ..addBuilderFactory(
        const FullType(
            BuiltMap, <FullType>[FullType(String), FullType(UserInfoImpl)]),
        () => MapBuilder<String, UserInfoImpl>(),
      )
      ..addPlugin(StandardJsonPlugin()))
    .build();
