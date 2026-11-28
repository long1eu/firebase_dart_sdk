import 'dart:io';

import 'device.dart';

/// What dart:io tells about the machine.
AnalyticsDevice detectDevice() {
  final String os = Platform.operatingSystem;
  return AnalyticsDevice(
    category: switch (os) {
      'windows' || 'macos' || 'linux' => 'desktop',
      'android' || 'ios' => 'mobile',
      _ => null,
    },
    operatingSystem: switch (os) {
      'windows' => 'Windows',
      'macos' => 'MacOS',
      'linux' => 'Linux',
      'android' => 'Android',
      'ios' => 'iOS',
      'fuchsia' => 'Fuchsia',
      _ => null,
    },
    operatingSystemVersion: _version(Platform.operatingSystemVersion),
    language: languageOf(Platform.localeName),
  );
}

/// The first version number in the platform's description: `Version 14.1 (Build 23B74)` gives `14.1`,
/// `"Windows 10 Pro" 10.0 (Build 19045)` gives `10`.
String? _version(String description) =>
    RegExp(r'\d+(?:\.\d+){0,3}').firstMatch(description)?.group(0);
