import 'dart:js_interop';

import 'device.dart';

@JS('navigator.language')
external String? get _navigatorLanguage;

@JS('screen.width')
external int? get _screenWidth;

@JS('screen.height')
external int? get _screenHeight;

/// What the browser tells about the device: the language and the screen size.
AnalyticsDevice detectDevice() {
  String? language;
  String? resolution;
  try {
    final String? locale = _navigatorLanguage;
    language = locale == null ? null : languageOf(locale);
    final int? width = _screenWidth;
    final int? height = _screenHeight;
    if (width != null && height != null && width > 0 && height > 0) {
      resolution = '${width}x$height';
    }
  } on Object {
    // A worker has no screen; send what could be read.
  }
  return AnalyticsDevice(language: language, screenResolution: resolution);
}
