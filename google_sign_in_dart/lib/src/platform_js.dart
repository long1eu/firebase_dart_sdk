// File created by
// Lung Razvan <long1eu>
// on 02/03/2020

import 'package:flutter/foundation.dart';

/// Whether we are running in a desktop environment
///
/// This should be conditionally imported with platform_io.dart
/// `import 'platform_js.dart' if (dart.library.io) 'platform_io.dart';`
const bool isDesktop = !kIsWeb;
