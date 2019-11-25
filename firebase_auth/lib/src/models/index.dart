// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

library models;

import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:meta/meta.dart';

part 'credentials/auth_credential.dart';

part 'credentials/auth_providers.dart';

part 'credentials/impl.dart';

part 'index.g.dart';

part 'requests/auth_request_configuration.dart';

part 'requests/base_auth.dart';

part 'requests/create_auth_uri.dart';

part 'requests/exchange_token.dart';

part 'requests/oauth.dart';

part 'requests/oob_code.dart';

part 'requests/reset_password.dart';

part 'requests/update.dart';

part 'requests/user_data_response.dart';

part 'user/impl.dart';

part 'user/user.dart';

@SerializersFor(<Type>[
  EmailPasswordAuthCredentialImpl,
  FacebookAuthCredentialImpl,
  GithubAuthCredentialImpl,
  GoogleAuthCredentialImpl,
  TwitterAuthCredentialImpl,
  BaseAuthRequest,
  BaseAuthResponse,
  CreateAuthUriRequest,
  CreateAuthUriResponse,
  ExchangeRefreshTokenRequest,
  ExchangeRefreshTokenResponse,
  ExchangeCustomTokenRequest,
  ExchangeCustomTokenResponse,
  OAuthRequest,
  OAuthResponse,
  OobCodeRequest,
  OobCodeResponse,
  ResetPasswordRequest,
  ResetPasswordResponse,
  UpdateRequest,
  UpdateResponse,
  ProviderUserInfo,
  UserDataResponse,
  AdditionalUserInfoImpl,
  UserInfoImpl,
  UserMetadataImpl,
])
Serializers serializers = (_$serializers.toBuilder() //
      ..add(IntSerializer())
      ..add(OobCodeType.serializer)
      ..add(ProfileAttribute.serializer)
      ..add(ProviderType.serializer)
      ..add(FirebaseUser.serializer)
      ..addBuilderFactory(
        const FullType(BuiltList, <FullType>[FullType(UserInfoImpl)]),
        () => ListBuilder<UserInfoImpl>(),
      )
      ..addPlugin(StandardJsonPlugin()))
    .build();

class IntSerializer implements PrimitiveSerializer<int> {
  final bool structured = false;
  @override
  final Iterable<Type> types = <Type>[int];
  @override
  final String wireName = 'int';

  @override
  Object serialize(Serializers serializers, int integer, {FullType specifiedType = FullType.unspecified}) {
    return integer;
  }

  @override
  int deserialize(Serializers serializers, Object serialized, {FullType specifiedType = FullType.unspecified}) {
    if (serialized is String) {
      return int.parse(serialized);
    } else {
      final int value = serialized;
      return value;
    }
  }
}
