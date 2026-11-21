import 'dart:convert';

import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/secrets.dart';

/// The style of every page: system font, light and dark from the system setting.
const String pageStyle =
    ':root{color-scheme:light dark}'
    'body{font:16px/1.5 system-ui,sans-serif;max-width:32em;margin:15vh auto;padding:0 16px}';

/// The content security policy of a message page whose style carries [nonce]: that style only.
String messageContentSecurityPolicy(String nonce) =>
    "default-src 'none'; style-src 'nonce-$nonce'; base-uri 'none'; "
    "form-action 'none'; frame-ancestors 'none'";

/// The document and the content security policy of [page]. A message page gets a new nonce for
/// its style on every call (every response).
({String html, String contentSecurityPolicy}) renderPage(SecurePage page) {
  final String? html = page.html;
  if (html != null) {
    return (html: html, contentSecurityPolicy: page.contentSecurityPolicy!);
  }
  const HtmlEscape escape = HtmlEscape();
  final String nonce = randomNonce();
  final String title = escape.convert(page.title ?? '');
  return (
    html:
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="color-scheme" content="light dark">'
        '<title>$title</title><style nonce="$nonce">$pageStyle</style>'
        '</head><body><h1>$title</h1><p>${escape.convert(page.text ?? '')}</p></body></html>',
    contentSecurityPolicy: messageContentSecurityPolicy(nonce),
  );
}
