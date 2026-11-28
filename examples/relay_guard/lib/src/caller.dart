import 'package:firebase_admin_dart/app_check.dart';
import 'package:firebase_admin_dart/auth.dart';

/// Who sent a request, as far as its tokens prove.
final class Caller {
  /// A caller with the app id of its App Check token and the uid of its ID token.
  const Caller({this.appId, this.uid});

  /// The Firebase app id from the App Check token, or null when the request had none.
  final String? appId;

  /// The uid from the Firebase ID token, or null when nobody was signed in.
  final String? uid;

  @override
  String toString() => 'Caller(appId: $appId, uid: $uid)';
}

/// Thrown by a [CallerVerifier] when a token is not valid. [reason] is for the log of the relay: never send it
/// back to the caller.
final class CallerRejected implements Exception {
  /// A refusal for [reason].
  const CallerRejected(this.reason);

  /// Why the token was refused.
  final String reason;

  @override
  String toString() => 'CallerRejected: $reason';
}

/// Checks the tokens of a request.
abstract interface class CallerVerifier {
  /// The Firebase app id of a valid App Check [token]. Throws [CallerRejected] when it is not valid.
  Future<String> appIdOf(String token);

  /// The uid of a valid Firebase ID [token]. Throws [CallerRejected] when it is not valid.
  Future<String> uidOf(String token);
}

/// A [CallerVerifier] on `firebase_admin_dart`: `verifyToken` of `FirebaseAppCheckAdmin` and `verifyIdToken` of
/// `FirebaseAuthAdmin`.
///
/// Checking tokens needs no credential: the keys are public. A `FirebaseAdminApp` made with any credential (or
/// [FirebaseAdminApp.emulator] for the Auth emulator) works; only `projectId` matters. [projectNumber] makes the
/// App Check check exact (see `FirebaseAppCheckAdmin.verifyToken`). With [checkRevoked] the ID token check also
/// looks the user up, which needs a credential with access to Firebase Auth.
final class AdminCallerVerifier implements CallerVerifier {
  /// A verifier for the project of [app].
  AdminCallerVerifier(
    this.app, {
    this.projectNumber,
    this.checkRevoked = false,
  });

  /// The app whose project the tokens must belong to.
  final FirebaseAdminApp app;

  /// The project number, when known.
  final String? projectNumber;

  /// Whether ID tokens of revoked sessions and disabled users are refused (one more request per check).
  final bool checkRevoked;

  @override
  Future<String> appIdOf(String token) async {
    try {
      return (await app.appCheck().verifyToken(
        token,
        projectNumber: projectNumber,
      )).appId;
    } on FirebaseAppCheckAdminException catch (e) {
      if (e.code == 'internal-error') {
        rethrow;
      }
      throw CallerRejected('App Check: ${e.code}');
    }
  }

  @override
  Future<String> uidOf(String token) async {
    try {
      return (await app.auth().verifyIdToken(
        token,
        checkRevoked: checkRevoked,
      )).uid;
    } on FirebaseAuthAdminException catch (e) {
      if (e.code == 'internal-error' || e.code == 'network-error') {
        rethrow;
      }
      throw CallerRejected('ID token: ${e.code}');
    }
  }
}
