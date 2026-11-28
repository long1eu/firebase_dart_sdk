// Unary calls: values, a typed read of the result, options, errors and
// cancellation.
//
//     dart run example/call.dart --emulator 127.0.0.1:9501
//
// The emulator fixture has the functions used here (echo, fail, slow).

import 'dart:async';

import 'package:cloud_functions_dart/cloud_functions_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseFunctions functions = exampleFunctions(arguments);
  try {
    await _values(functions);
    await _errors(functions);
    await _timeoutAndCancel(functions);
  } finally {
    await functions.close();
  }
}

Future<void> _values(FirebaseFunctions functions) async {
  final HttpsCallable echo = functions.httpsCallable('echo');
  final HttpsCallableResult result = await echo.call(<String, Object?>{
    'text': 'héllo',
    'count': 3,
    'ratio': 0.5,
    'flags': <bool>[true, false],
    'nested': <String, Object?>{'none': null},
  });
  // The result is Object?: decoded maps are Map<String, Object?>, numbers are
  // num. Read what you need and convert.
  final Map<String, Object?> map = result.data! as Map<String, Object?>;
  final int count = (map['count']! as num).toInt();
  print('echo: $map (count + 1 = ${count + 1})');
}

Future<void> _errors(FirebaseFunctions functions) async {
  final HttpsCallable fail = functions.httpsCallable('fail');
  try {
    await fail.call(<String, Object?>{
      'code': 'already-exists',
      'message': 'that name is taken',
      'details': <String, Object?>{'name': 'x'},
    });
  } on FirebaseFunctionsException catch (e) {
    // The code comes from the body of the answer; httpStatus is 409 for both
    // already-exists and aborted.
    print('${e.code}: ${e.message} (HTTP ${e.httpStatus}) ${e.details}');
  }
  try {
    unawaited(functions.httpsCallable('echo').call(DateTime.now()));
  } on ArgumentError catch (e) {
    // A value that is not JSON is a programmer error, thrown before sending.
    print('refused: ${e.message}');
  }
}

Future<void> _timeoutAndCancel(FirebaseFunctions functions) async {
  final HttpsCallable slow = functions.httpsCallable(
    'slow',
    options: const HttpsCallableOptions(timeout: Duration(seconds: 1)),
  );
  try {
    await slow.call();
  } on FirebaseFunctionsException catch (e) {
    // The request was aborted; the function on the server may still finish.
    print('timeout: ${e.code}: ${e.message}');
  }

  final Completer<void> cancel = Completer<void>();
  final Future<HttpsCallableResult> pending = functions
      .httpsCallable('slow')
      .call(null, cancel.future);
  Timer(const Duration(milliseconds: 200), cancel.complete);
  try {
    await pending;
  } on FirebaseFunctionsException catch (e) {
    print('cancel: ${e.code}: ${e.message}');
  }
}
