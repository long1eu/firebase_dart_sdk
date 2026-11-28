/// Firebase callable Cloud Functions for pure Dart: calls and streaming calls on the VM and the
/// web.
///
/// Create a [FirebaseFunctions] for an app, get an [HttpsCallable] by name or by URL, then call it
/// with [HttpsCallable.call] or [HttpsCallable.stream]. The ID token of the signed-in user and the
/// App Check token come from the app's providers. Errors are [FirebaseFunctionsException]s.
///
/// ```dart
/// import 'package:cloud_functions_dart/cloud_functions_dart.dart';
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<the Web API key of the project>',
///       appId: '1:1234567890:web:0123456789abcdef',
///       projectId: 'my-project',
///     ),
///   );
///   final FirebaseFunctions functions = FirebaseFunctions(app);
///   final HttpsCallableResult result = await functions
///       .httpsCallable('echo')
///       .call(<String, Object?>{'hello': 'world'});
///   print(result.data);
///   await functions.close();
/// }
/// ```
library cloud_functions_dart;

// Imported for the references in the documentation above.
import 'package:cloud_functions_dart/src/exception.dart';
import 'package:cloud_functions_dart/src/firebase_functions.dart';
import 'package:cloud_functions_dart/src/https_callable.dart';

export 'package:cloud_functions_dart/src/exception.dart'
    show FirebaseFunctionsException, firebaseFunctionsExceptionCodes;
export 'package:cloud_functions_dart/src/firebase_functions.dart'
    show FirebaseFunctions;
export 'package:cloud_functions_dart/src/https_callable.dart'
    show
        CallableMessage,
        CallableResult,
        CallableStreamEvent,
        HttpsCallable,
        HttpsCallableOptions,
        HttpsCallableResult;
