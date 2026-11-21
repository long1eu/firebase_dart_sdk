// The checks and the script addresses that the reCAPTCHA page of the loopback server and the
// in-page presenter of the web share. Not exported.

/// What a reCAPTCHA site key looks like: letters, digits, `-` and `_`.
final RegExp siteKeyPattern = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

/// A plain language tag (`en`, `pt-BR`), the only `hl` the widgets get.
final RegExp languageTagPattern = RegExp(
  r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$',
);

/// What Google accepts as a reCAPTCHA Enterprise action: letters, digits, `/` and `_`.
final RegExp actionPattern = RegExp(r'^[A-Za-z0-9/_]{1,100}$');

/// Throws an [ArgumentError] that does not repeat [siteKey] when it is not a site key.
void checkSiteKey(String siteKey) {
  if (!siteKeyPattern.hasMatch(siteKey)) {
    throw ArgumentError.value(
      '<redacted>',
      'siteKey',
      'is not a reCAPTCHA site key (letters, digits, - and _)',
    );
  }
}

/// Throws an [ArgumentError] when [action] is not an Enterprise action.
void checkAction(String action) {
  if (!actionPattern.hasMatch(action)) {
    throw ArgumentError.value(
      action,
      'action',
      'is not a reCAPTCHA Enterprise action (letters, digits, / and _)',
    );
  }
}

/// [languageCode] when it is a plain language tag, else null (the widget follows the browser).
String? languageTagOrNull(String? languageCode) =>
    languageCode != null && languageTagPattern.hasMatch(languageCode)
    ? languageCode
    : null;

/// The address of Google's reCAPTCHA v2 script, rendering explicitly and calling the global
/// function [onload] once it is ready (the `api.js` of the JS SDK's loader).
Uri recaptchaV2ScriptUrl({required String onload, String? languageCode}) =>
    Uri.https('www.google.com', '/recaptcha/api.js', <String, String>{
      'onload': onload,
      'render': 'explicit',
      'hl': ?languageTagOrNull(languageCode),
    });

/// The address of Google's reCAPTCHA Enterprise script for [siteKey], calling the global function
/// [onload] once it is ready (`enterprise.js?render=<site key>` of the JS SDK's Enterprise
/// verifier).
Uri recaptchaEnterpriseScriptUrl({
  required String siteKey,
  required String onload,
  String? languageCode,
}) => Uri.https('www.google.com', '/recaptcha/enterprise.js', <String, String>{
  'render': siteKey,
  'onload': onload,
  'hl': ?languageTagOrNull(languageCode),
});
