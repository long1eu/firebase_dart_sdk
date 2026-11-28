import 'device.dart';

/// Neither dart:io nor a browser: nothing to read.
AnalyticsDevice detectDevice() => const AnalyticsDevice();
