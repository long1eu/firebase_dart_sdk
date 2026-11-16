import 'package:firebase_app_dart/firebase_app_dart.dart';

/// The base of the exceptions of `firebase_admin_dart`: every admin library throws a subclass of it
/// (`FirebaseAuthAdminException` of `auth.dart`).
///
/// It extends [FirebaseException]: [plugin] names the admin service (`auth`), so an exception prints as
/// `[auth/user-not-found] ...`, the full code of the Firebase Admin SDKs, and `on FirebaseException catch (e)`
/// catches it too. [code] is the code of the Node.js Admin SDK without the service prefix. [message] never
/// contains a token, a password or a key.
///
/// ```dart
/// import 'package:firebase_admin_dart/firebase_admin_dart.dart';
///
/// void main() {
///   const FirebaseAdminException e = FirebaseAdminException(
///     plugin: 'auth',
///     code: 'user-not-found',
///     message: 'No user.',
///   );
///   print(e); // [auth/user-not-found] No user.
/// }
/// ```
class FirebaseAdminException extends FirebaseException {
  /// Creates an exception of the admin service [plugin] with the Admin SDK style [code] and a [message]. The
  /// package creates them; you need this only for tests.
  const FirebaseAdminException({
    required super.plugin,
    required String code,
    required String message,
    this.serverCode,
    this.httpStatus,
  }) : super(code: code, message: message);

  /// The error code in the style of the Firebase Admin SDKs, without the service prefix: `user-not-found`, not
  /// `auth/user-not-found`.
  @override
  String get code => super.code;

  /// A description of the error. It never contains a token, a password or a key.
  @override
  String get message => super.message!;

  /// The code the backend returned (for example `USER_NOT_FOUND`), when the error came from the backend.
  final String? serverCode;

  /// The HTTP status of the response, when there was one.
  final int? httpStatus;
}
