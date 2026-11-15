// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

/// Whether the code runs on Android, iOS or Fuchsia. Read from `dart:io` `Platform`; `false` on
/// the web.
const bool isMobile = false;

/// Whether the code runs on a Dart VM that is not [isMobile] (desktop or server). `false` on the
/// web.
const bool isDesktop = false;

/// Whether the code runs on the web (compiled to JavaScript or WebAssembly).
const bool isWeb = true;
