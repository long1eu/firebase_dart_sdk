// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

import 'dart:io';

final bool isMobile =
    Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;
final bool isDesktop = !isMobile;
const bool isWeb = false;
