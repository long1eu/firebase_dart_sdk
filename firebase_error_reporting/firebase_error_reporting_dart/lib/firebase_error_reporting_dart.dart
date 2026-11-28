/// Reports Dart errors to Google Cloud Error Reporting, in the project of a Firebase app.
///
/// Create an `ErrorReporter` with an `ErrorReportingTransport`, then record errors with
/// `ErrorReporter.recordError` or run the program in `ErrorReporter.runGuarded`. The file store and the isolate
/// hook are in `package:firebase_error_reporting_dart/io.dart`.
library;

export 'src/format.dart' show MessageFormat;
export 'src/model.dart' show ErrorEvent, HttpRequestContext, SourceLocation;
export 'src/reporter.dart' show BeforeSend, ErrorReporter;
export 'src/store.dart' show ErrorReportingState, ErrorReportingStore;
export 'src/transport.dart' show ErrorReportingTransport;
