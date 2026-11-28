/// Server-side checks of Firebase App Check tokens: `FirebaseAppCheckAdmin(app)` or `app.appCheck()`.
///
/// ```dart
/// import 'package:firebase_admin_dart/app_check.dart';
///
/// Future<bool> fromMyApp(FirebaseAdminApp app, String token) async {
///   try {
///     await app.appCheck().verifyToken(token);
///     return true;
///   } on FirebaseAppCheckAdminException {
///     return false;
///   }
/// }
/// ```
library;

export 'firebase_admin_dart.dart';
export 'src/app_check/app_check_admin.dart';
export 'src/app_check/exception.dart';
