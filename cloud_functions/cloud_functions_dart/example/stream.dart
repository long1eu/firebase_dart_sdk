// A streaming call: each message of the function, then its result.
//
//     dart run example/stream.dart --emulator 127.0.0.1:9501
//
// The function `stream` of the emulator fixture sends three chunks and
// returns {final: true}. A real function sends chunks with
// `response.sendChunk(...)`; the timeout is the longest silence between two
// pieces of data, so keep it above the function's heartbeatSeconds.

import 'dart:async';

import 'package:cloud_functions_dart/cloud_functions_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseFunctions functions = exampleFunctions(arguments);
  try {
    final Stream<CallableStreamEvent> events = functions
        .httpsCallable('stream')
        .stream();
    await for (final CallableStreamEvent event in events) {
      switch (event) {
        case CallableMessage(:final Object? data):
          print('message: $data');
        case CallableResult(:final Object? data):
          print('result: $data');
      }
    }
  } on FirebaseFunctionsException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await functions.close();
  }
}
