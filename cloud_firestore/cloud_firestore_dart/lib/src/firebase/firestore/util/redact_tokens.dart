// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// JWTs (ID tokens, App Check tokens): three base64url parts, the first one a JSON object (`eyJ`).
final RegExp _jwt = RegExp(
  r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*',
);

/// The value of an authorization header or a `token=` style field.
final RegExp _labelled = RegExp(
  r'((?:bearer|token|access_token|id_token|refresh_token)\s*[:=]?\s+|'
  r'(?:token|access_token|id_token|refresh_token)\s*[:=]\s*)'
  r'''["']?[A-Za-z0-9._~+/=-]{16,}''',
  caseSensitive: false,
);

/// Long runs of token characters (opaque OAuth tokens such as `ya29.`..., API keys): no word of a message is that
/// long.
final RegExp _opaque = RegExp(r'[A-Za-z0-9._~+/=-]{40,}');

/// Returns [text] with everything that looks like a credential replaced by `<redacted>`.
///
/// For the text of errors that come from auth and App Check providers, which the SDK logs and passes on: a provider
/// may put the token it failed to use into its exception message. The rest of the message stays readable.
String redactTokens(String text) {
  return text
      .replaceAll(_jwt, '<redacted>')
      .replaceAllMapped(_labelled, (Match m) => '${m[1]}<redacted>')
      .replaceAll(_opaque, '<redacted>');
}
