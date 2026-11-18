import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Environment variables do not exist in a browser.
String? environmentVariable(String name) => null;

/// The language of the browser, like `_getUserLanguage` of the JS SDK: the first of `navigator.languages`, else
/// `navigator.language`.
String? deviceLanguage() {
  final web.Navigator navigator = web.window.navigator;
  final List<JSString> languages = navigator.languages.toDart;
  if (languages.isNotEmpty && languages.first.toDart.isNotEmpty) {
    return languages.first.toDart;
  }
  final String language = navigator.language;
  return language.isEmpty ? null : language;
}
