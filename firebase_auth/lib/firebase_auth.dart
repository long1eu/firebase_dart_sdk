library firebase_auth;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:_discoveryapis_commons/_discoveryapis_commons.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:firebase_auth/src/models/serializers.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_internal/firebase_internal.dart';
import 'package:googleapis/identitytoolkit/v3.dart' as gitkit;
import 'package:googleapis/identitytoolkit/v3.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/subjects.dart';

part 'firebase_auth.g.dart';
part 'src/auth_result.dart';
part 'src/data/firebase_auth_api.dart';
part 'src/data/secure_token_api.dart';
part 'src/data/secure_token_service.dart';
part 'src/data/user_storage.dart';
part 'src/firebase_auth.dart';
part 'src/firebase_user.dart';
part 'src/models/action_code_settings.dart';
part 'src/models/credentials/auth_credential.dart';
part 'src/models/credentials/auth_providers.dart';
part 'src/models/credentials/provider_type.dart';
part 'src/models/impl.dart';
part 'src/models/oob_code_type.dart';
part 'src/models/secure_token.dart';
part 'src/models/user.dart';
part 'src/util/api_key_client.dart';
part 'src/util/errors.dart';
