library firebase_auth_example;

import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_internal/firebase_internal.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

import 'src/utils/email_validator.dart';

part 'src/auth/create_user.dart';
part 'src/auth/fetch_sign_in_methods.dart';
part 'src/auth/language_code.dart';
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

final bool hasColor = stdout.supportsAnsiEscapes;

int lineCount = 1;

String getUserName(FirebaseUser user) {
  if (user.isAnonymous) {
    return 'Stranger';
  } else if (user.providerId == ProviderType.phone) {
    return user.phoneNumber;
  } else {
    return user.displayName;
  }
}

void clearScreen() {
  stdout //
    ..write(_clearScreen)
    ..write(_moveUp)
    ..writeln()
    ..writeln('Firebase Dart SDK'.bold.cyan.reset)
    ..writeln('Firebase Authentication'.bold.yellow.reset)
    ..writeln();
}

void close() {
  stdout.writeln();
  exit(0);
}

void print(Object object) {}
