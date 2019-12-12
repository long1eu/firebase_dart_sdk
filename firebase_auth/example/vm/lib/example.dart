library firebase_auth_example;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_internal/firebase_internal.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

import 'file:///Users/long1eu/.pub-cache/hosted/pub.dartlang.org/intl-0.16.0/lib/intl.dart';

import 'src/utils/email_validator.dart';

part 'src/auth/action_code.dart';
part 'src/auth/action_code_info.dart';
part 'src/auth/create_user.dart';
part 'src/auth/current_user.dart';
part 'src/auth/fetch_sign_in_methods.dart';
part 'src/auth/language_code.dart';
part 'src/auth/send_email_verification.dart';
part 'src/auth/sign_in_with_email_and_password.dart';
part 'src/codes.dart';
part 'src/console.dart';
part 'src/initialize.dart';
part 'src/no_user.dart';
part 'src/options.dart';
part 'src/options/multiple_string_option.dart';
part 'src/options/option.dart';
part 'src/options/simple_selection_list_option.dart';
part 'src/options/single_string_option.dart';
part 'src/progress.dart';
part 'src/user.dart';

final bool hasColor = stdout.supportsAnsiEscapes;

String getUserName(FirebaseUser user) {
  if (user.isAnonymous) {
    return 'Stranger';
  } else if (user.providerId == ProviderType.phone) {
    return user.phoneNumber;
  } else if (user.displayName == null) {
    return user.email;
  } else {
    return user.displayName;
  }
}

void printTitle() {
  stdout //
    ..writeln('Firebase Dart SDK'.bold.cyan.reset)
    ..writeln('Firebase Authentication'.bold.yellow.reset)
    ..writeln();
}

void close() {
  console.clearScreen();
  exit(0);
}
