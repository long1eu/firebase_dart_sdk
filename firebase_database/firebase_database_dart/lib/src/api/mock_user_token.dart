/// The mock user token of the Database emulator. JS: `util/src/emulator.ts` (`createMockUserToken`).
library;

import 'package:firebase_database_dart/src/realtime/emulator_token.dart';

/// Builds the `mockUserToken` that makes the Database emulator treat the client as the user [uid].
///
/// The result is an unsigned JWT, so it works only with an emulator. [projectId] is the project of the
/// app. [claims] are added to the token and are visible to the rules as `auth.token.<name>`; it must
/// not contain `uid`. Throws an [ArgumentError] for an empty [uid] or [projectId] and for a claim
/// that JSON cannot encode.
///
/// ```dart
/// final FirebaseDatabase db = FirebaseDatabase(
///   app,
///   emulatorHost: '127.0.0.1:9000',
///   mockUserToken: mockUserTokenFor('ada', projectId: 'demo-example'),
/// );
/// ```
String mockUserTokenFor(
  String uid, {
  required String projectId,
  Map<String, Object?> claims = const <String, Object?>{},
}) => createMockUserToken(<String, Object?>{
  ...claims,
  'sub': uid,
}, projectId: projectId);
