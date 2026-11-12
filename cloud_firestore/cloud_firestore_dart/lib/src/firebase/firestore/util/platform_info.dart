/// Describes the runtime for the `x-goog-api-client` header, without importing
/// `dart:io` where it does not exist.
library;

export 'platform_info_web.dart' if (dart.library.io) 'platform_info_io.dart';
