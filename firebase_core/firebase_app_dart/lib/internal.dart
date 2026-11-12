/// Internal utilities shared by `firebase_app_dart` and `cloud_firestore_dart`
/// (token types, logging, preconditions).
///
/// **Not public API.** This library exists so that other packages of this
/// repository can share code. It can change in any release, including patch
/// releases, without notice. Do not import it from application code.
library firebase_app_dart.internal;

export 'src/internal/app_check.dart';
export 'src/internal/auth.dart';
export 'src/internal/internal.dart';
export 'src/internal/util/log.dart';
export 'src/internal/util/preconditions.dart';
export 'src/internal/util/to_string_helper.dart';
