import 'dart:math';

import 'package:meta/meta.dart';

/// Everything the client knows about how an installation is identified to Google Analytics, in one place.
///
/// The client targets a GA4 **web stream**: the request names the stream with `measurement_id` in the query
/// and the installation with `client_id` in the body, a value the client generates on first use in the
/// documented form "two positive numbers, joined by a period" (docs/analytics_protocol.md, sections 3 and 5).
///
/// Whether Google Analytics reports events from a `client_id` that gtag.js never used is checked by
/// `tool/analytics_probe.dart`. If it does not, this is the class to change; nothing else in the package
/// builds or parses an identifier.
@internal
abstract final class ClientIdentity {
  static final RegExp _pattern = RegExp(r'^[1-9][0-9]{0,9}\.[1-9][0-9]{0,11}$');

  /// A new client id: a random positive 31-bit number and the Unix time of first use in seconds, as gtag.js
  /// forms its own.
  static String generate(Random random, DateTime now) =>
      '${1 + random.nextInt(0x7fffffff)}.${now.millisecondsSinceEpoch ~/ 1000}';

  /// Whether [id], read back from a store, has the form [generate] produces.
  static bool isValid(String id) => _pattern.hasMatch(id);

  /// The query parameters that name the stream.
  static Map<String, String> streamQuery(String measurementId) =>
      <String, String>{'measurement_id': measurementId};

  /// The body fields that name the installation.
  static Map<String, Object> bodyFields(String clientId) => <String, Object>{
    'client_id': clientId,
  };
}
