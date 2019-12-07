// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

library serializers;

import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:firebase_auth/firebase_auth.dart';

part 'serializers.g.dart';

@SerializersFor(<Type>[
  AdditionalUserInfoImpl,
  FacebookAuthCredentialImpl,
  GithubAuthCredentialImpl,
  GoogleAuthCredentialImpl,
  TwitterAuthCredentialImpl,
  UserInfoImpl,
  UserMetadataImpl,
])
Serializers serializers = (_$serializers.toBuilder() //
      ..add(FirebaseUser.serializer)
      ..addBuilderFactory(
        const FullType(BuiltList, <FullType>[FullType(UserInfoImpl)]),
        () => ListBuilder<UserInfoImpl>(),
      )
      ..addPlugin(StandardJsonPlugin()))
    .build();
