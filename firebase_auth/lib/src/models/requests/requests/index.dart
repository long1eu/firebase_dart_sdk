// File created by
// Lung Razvan <long1eu>
// on 05/12/2019

library requests;

import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:meta/meta.dart';

part 'action_code_settings.dart';
part 'app_credential.dart';
part 'delete_account.dart';
part 'email_link_sign_in_response.dart';
part 'get_account_info.dart';
part 'get_oob_confirmation_code.dart';
part 'get_project_config.dart';
part 'index.g.dart';
part 'reset_password.dart';
part 'secure_token.dart';
part 'send_verification_code.dart';

@SerializersFor(<Type>[
  ActionCodeSettings,
  DeleteAccountRequest,
  EmailLinkSignInRequest,
  EmailLinkSignInResponse,
  GetAccountInfoRequest,
  GetAccountInfoResponse,
  GetOobConfirmationCodeRequest,
  GetOobConfirmationCodeResponse,
  GetProjectConfigResponse,
  ProviderUserInfo,
  ResetPasswordRequest,
  ResetPasswordResponse,
  ResponseUser,
])
Serializers serializers = (_$serializers.toBuilder() //
      ..add(OobCodeType.serializer))
    .build();
