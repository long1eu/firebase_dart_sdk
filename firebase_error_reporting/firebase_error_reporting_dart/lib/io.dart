/// The parts of `firebase_error_reporting_dart` that need `dart:io` or `dart:isolate`: a store in a file and
/// the errors of other isolates. Not available on the web.
library;

import 'dart:isolate';

import 'src/reporter.dart';

export 'src/io/file_store.dart' show FileErrorReportingStore;

/// Reports the uncaught errors of isolates.
extension IsolateErrorReporting on ErrorReporter {
  /// Records the uncaught errors of [isolate] (by default the current one) until the returned function is
  /// called.
  ///
  /// An isolate's error listener receives the error and its stack as text, so the header uses the error's
  /// text with the type `IsolateError`. An uncaught error ends the isolate unless it was spawned with
  /// `errorsAreFatal: false`; record it before it ends with `flush`.
  void Function() watchIsolate([Isolate? isolate]) {
    final Isolate target = isolate ?? Isolate.current;
    final RawReceivePort port = RawReceivePort((Object? message) {
      if (message is List && message.length == 2) {
        recordErrorText(
          '${message[0]}',
          '${message[1] ?? ''}',
          typeName: 'IsolateError',
        );
      }
    }, 'firebase_error_reporting isolate errors');
    target.addErrorListener(port.sendPort);
    return () {
      target.removeErrorListener(port.sendPort);
      port.close();
    };
  }
}
