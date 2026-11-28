import 'package:meta/meta.dart';

import 'device_stub.dart'
    if (dart.library.io) 'device_io.dart'
    if (dart.library.js_interop) 'device_web.dart';

/// The `device` block of every request: what Google Analytics reports in its Tech reports.
///
/// Without it, Google Analytics would derive device data from earlier gtag.js events of the same client,
/// which a program outside a browser never sends, so the client sends what it can read from the platform
/// ([AnalyticsDevice.detect]). Every field is optional; a null field is not sent. Pass your own to the
/// `FirebaseAnalytics` constructor to add what the platform does not tell a Dart program (the screen size of
/// a Flutter window, a device model), or `const AnalyticsDevice()` to send none.
@immutable
class AnalyticsDevice {
  /// A device block with the given fields.
  const AnalyticsDevice({
    this.category,
    this.language,
    this.screenResolution,
    this.operatingSystem,
    this.operatingSystemVersion,
    this.model,
    this.brand,
    this.browser,
    this.browserVersion,
  });

  /// What the platform tells a Dart program. On the VM: the operating system and its version, the language
  /// of the locale, and the category (`desktop` on Windows, macOS and Linux, `mobile` on Android and iOS). In
  /// a browser: the language and the screen resolution.
  factory AnalyticsDevice.detect() => detectDevice();

  /// `desktop`, `tablet`, `mobile` or `smart TV`.
  final String? category;

  /// The language, ISO 639-1 with an optional region: `en` or `en-US`.
  final String? language;

  /// The screen size as `WIDTHxHEIGHT`, for example `1920x1080`.
  final String? screenResolution;

  /// The operating system: `Windows`, `MacOS`, `Linux`, `Android`, `iOS`.
  final String? operatingSystem;

  /// The version of the operating system, for example `14.1`.
  final String? operatingSystemVersion;

  /// The model of the device.
  final String? model;

  /// The brand of the device.
  final String? brand;

  /// The browser, for example `Chrome`.
  final String? browser;

  /// The version of the browser.
  final String? browserVersion;

  /// A copy with the non-null fields of [other] replacing these.
  AnalyticsDevice merge(AnalyticsDevice other) => AnalyticsDevice(
    category: other.category ?? category,
    language: other.language ?? language,
    screenResolution: other.screenResolution ?? screenResolution,
    operatingSystem: other.operatingSystem ?? operatingSystem,
    operatingSystemVersion:
        other.operatingSystemVersion ?? operatingSystemVersion,
    model: other.model ?? model,
    brand: other.brand ?? brand,
    browser: other.browser ?? browser,
    browserVersion: other.browserVersion ?? browserVersion,
  );

  /// The `device` field of a request, or null when no field is set.
  @internal
  Map<String, String>? toRequest() {
    final Map<String, String> out = <String, String>{
      'category': ?_clean(category),
      'language': ?_clean(language),
      'screen_resolution': ?_clean(screenResolution),
      'operating_system': ?_clean(operatingSystem),
      'operating_system_version': ?_clean(operatingSystemVersion),
      'model': ?_clean(model),
      'brand': ?_clean(brand),
      'browser': ?_clean(browser),
      'browser_version': ?_clean(browserVersion),
    };
    return out.isEmpty ? null : out;
  }

  @override
  bool operator ==(Object other) =>
      other is AnalyticsDevice &&
      other.category == category &&
      other.language == language &&
      other.screenResolution == screenResolution &&
      other.operatingSystem == operatingSystem &&
      other.operatingSystemVersion == operatingSystemVersion &&
      other.model == model &&
      other.brand == brand &&
      other.browser == browser &&
      other.browserVersion == browserVersion;

  @override
  int get hashCode => Object.hash(
    category,
    language,
    screenResolution,
    operatingSystem,
    operatingSystemVersion,
    model,
    brand,
    browser,
    browserVersion,
  );

  @override
  String toString() => 'AnalyticsDevice(${toRequest() ?? <String, String>{}})';
}

/// The `user_location` block: where Google Analytics reports the user to be.
///
/// The client never guesses a location. Without this block Google Analytics reports what it derives, if
/// anything, and the property's granular location settings apply either way.
@immutable
class AnalyticsUserLocation {
  /// A location; Google recommends [countryId] and [regionId] at a minimum.
  const AnalyticsUserLocation({
    this.city,
    this.regionId,
    this.countryId,
    this.subcontinentId,
    this.continentId,
  });

  /// The city's name. For a city in the US, also set [countryId] and [regionId].
  final String? city;

  /// The country and subdivision, ISO 3166-2: `US-CA`, `GB-LND`.
  final String? regionId;

  /// The country, ISO 3166-1 alpha-2: `US`, `FR`.
  final String? countryId;

  /// The subcontinent, UN M49: `021`.
  final String? subcontinentId;

  /// The continent, UN M49: `019`.
  final String? continentId;

  /// The `user_location` field of a request, or null when no field is set.
  @internal
  Map<String, String>? toRequest() {
    final Map<String, String> out = <String, String>{
      'city': ?_clean(city),
      'region_id': ?_clean(regionId),
      'country_id': ?_clean(countryId),
      'subcontinent_id': ?_clean(subcontinentId),
      'continent_id': ?_clean(continentId),
    };
    return out.isEmpty ? null : out;
  }

  @override
  bool operator ==(Object other) =>
      other is AnalyticsUserLocation &&
      other.city == city &&
      other.regionId == regionId &&
      other.countryId == countryId &&
      other.subcontinentId == subcontinentId &&
      other.continentId == continentId;

  @override
  int get hashCode =>
      Object.hash(city, regionId, countryId, subcontinentId, continentId);

  @override
  String toString() =>
      'AnalyticsUserLocation(${toRequest() ?? <String, String>{}})';
}

/// A field as sent: trimmed, without control characters, at most 100 characters; null when empty.
String? _clean(String? value) {
  if (value == null) {
    return null;
  }
  final String clean = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  if (clean.isEmpty) {
    return null;
  }
  return clean.length <= 100 ? clean : clean.substring(0, 100);
}

/// The `language` of a locale name such as `en_US.UTF-8`, `de-DE` or `fr`: `en-US`, `de-DE`, `fr`; null when
/// the name has no ISO 639-1 language.
@internal
String? languageOf(String locale) {
  final RegExpMatch? match = RegExp(
    r'^([A-Za-z]{2})(?:[_-]([A-Za-z]{2}))?(?![A-Za-z])',
  ).firstMatch(locale);
  if (match == null) {
    return null;
  }
  final String language = match.group(1)!.toLowerCase();
  final String? region = match.group(2);
  return region == null ? language : '$language-${region.toUpperCase()}';
}
