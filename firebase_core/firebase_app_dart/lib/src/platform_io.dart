// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'dart:io';

/// Whether the code runs on Android, iOS or Fuchsia.
final bool isMobile =
    Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;

/// Whether the code runs on a non-mobile Dart VM (desktop or server).
final bool isDesktop = !isMobile;

/// Whether the code runs on the web.
const bool isWeb = false;
