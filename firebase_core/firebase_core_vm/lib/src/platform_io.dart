// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'dart:io';

final bool kIsMobile =
    Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;
final bool kIsDesktop = !kIsMobile;
const bool kIsWeb = false;
