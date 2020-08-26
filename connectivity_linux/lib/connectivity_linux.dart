
import 'dart:async';

import 'package:flutter/services.dart';

class ConnectivityLinux {
  static const MethodChannel _channel =
      const MethodChannel('connectivity_linux');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
