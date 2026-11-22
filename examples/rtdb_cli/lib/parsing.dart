// Pure functions of rtdb_cli: arguments, paths, JSON and the choice of the
// backend. Nothing here touches the network or the file system.

import 'dart:convert';

/// Thrown for arguments that cannot be used; the message is for people.
class UsageError implements Exception {
  UsageError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the flags and the environment do not name a backend.
class ConfigurationError implements Exception {
  ConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Splits `host:port` or `[ipv6]:port`; throws [UsageError] otherwise.
({String host, int port}) parseHostPort(String value) {
  final RegExpMatch? match = RegExp(
    r'^(\[[0-9a-fA-F:.]+\]|[^:\[\]/\s]+):(\d{1,5})$',
  ).firstMatch(value);
  final int? port = match == null ? null : int.parse(match.group(2)!);
  if (match == null || port == null || port < 1 || port > 65535) {
    throw UsageError('Expected host:port, got "$value".');
  }
  return (host: match.group(1)!, port: port);
}

/// A path of the database without leading or trailing slashes; `/` and the
/// empty string are the root, the empty path.
String normalizePath(String path) {
  final String trimmed = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  if (trimmed.contains('//')) {
    throw UsageError('Empty segment in the path "$path".');
  }
  if (RegExp(r'[.#$\[\]]').hasMatch(trimmed)) {
    throw UsageError('The path "$path" contains one of . # \$ [ ].');
  }
  return trimmed;
}

/// Decodes [text] as JSON; throws [UsageError] with the position on failure.
Object? parseJson(String text, {String what = 'value'}) {
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    throw UsageError('The $what is not valid JSON: ${e.message}');
  }
}

/// The value of `set` and `push`: any JSON.
Object? parseJsonValue(String text) => parseJson(text);

/// The value of `update`: a JSON object.
Map<String, Object?> parseJsonObject(String text) {
  final Object? value = parseJson(text);
  if (value is! Map<String, dynamic>) {
    throw UsageError('update needs a JSON object, for example {"a": 1}.');
  }
  return Map<String, Object?>.from(value);
}

/// The text of [value] as JSON, indented unless [compact].
String encodeJson(Object? value, {bool compact = false}) => compact
    ? jsonEncode(value)
    : const JsonEncoder.withIndent('  ').convert(value);

/// A query bound given on the command line: JSON when it parses (`5`, `true`,
/// `"a"`, `null`), the text itself otherwise (`alice`).
Object? parseBound(String text) {
  try {
    final Object? value = jsonDecode(text);
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
  } on FormatException {
    // Not JSON: a plain string.
  }
  return text;
}

/// How a query is ordered.
enum OrderBy { key, value, child }

/// The query flags of `get` and `watch`, validated.
class QuerySpec {
  const QuerySpec({
    this.orderBy,
    this.orderByChild,
    this.limitToFirst,
    this.limitToLast,
    this.hasStartAt = false,
    this.startAt,
    this.hasEndAt = false,
    this.endAt,
    this.hasEqualTo = false,
    this.equalTo,
  });

  final OrderBy? orderBy;

  /// The child path when [orderBy] is [OrderBy.child].
  final String? orderByChild;
  final int? limitToFirst;
  final int? limitToLast;
  final bool hasStartAt;
  final Object? startAt;
  final bool hasEndAt;
  final Object? endAt;
  final bool hasEqualTo;
  final Object? equalTo;

  bool get isPlain =>
      orderBy == null &&
      limitToFirst == null &&
      limitToLast == null &&
      !hasStartAt &&
      !hasEndAt &&
      !hasEqualTo;
}

/// Builds a [QuerySpec] from the raw option values (null when not given);
/// throws [UsageError] for combinations the database refuses.
QuerySpec parseQuerySpec({
  String? orderByChild,
  bool orderByKey = false,
  bool orderByValue = false,
  String? limitToFirst,
  String? limitToLast,
  String? startAt,
  String? endAt,
  String? equalTo,
}) {
  final int orders =
      (orderByChild != null ? 1 : 0) +
      (orderByKey ? 1 : 0) +
      (orderByValue ? 1 : 0);
  if (orders > 1) {
    throw UsageError(
      'Use only one of --order-by-child, --order-by-key and --order-by-value.',
    );
  }
  if (limitToFirst != null && limitToLast != null) {
    throw UsageError('Use only one of --limit-to-first and --limit-to-last.');
  }
  if (equalTo != null && (startAt != null || endAt != null)) {
    throw UsageError('--equal-to cannot be combined with --start-at/--end-at.');
  }
  int? limit(String? text, String flag) {
    if (text == null) {
      return null;
    }
    final int? n = int.tryParse(text);
    if (n == null || n < 1) {
      throw UsageError('$flag needs a positive integer, got "$text".');
    }
    return n;
  }

  String? child;
  if (orderByChild != null) {
    child = normalizePath(orderByChild);
    if (child.isEmpty) {
      throw UsageError('--order-by-child needs a child path.');
    }
  }
  final Object? start = startAt == null ? null : parseBound(startAt);
  final Object? end = endAt == null ? null : parseBound(endAt);
  final Object? equal = equalTo == null ? null : parseBound(equalTo);
  if (orderByKey) {
    for (final (String flag, Object? bound) in <(String, Object?)>[
      ('--start-at', start),
      ('--end-at', end),
      ('--equal-to', equal),
    ]) {
      if (bound != null && bound is! String) {
        throw UsageError('$flag needs a string with --order-by-key.');
      }
    }
  }
  return QuerySpec(
    orderBy: orderByKey
        ? OrderBy.key
        : orderByValue
        ? OrderBy.value
        : child != null
        ? OrderBy.child
        : null,
    orderByChild: child,
    limitToFirst: limit(limitToFirst, '--limit-to-first'),
    limitToLast: limit(limitToLast, '--limit-to-last'),
    hasStartAt: startAt != null,
    startAt: start,
    hasEndAt: endAt != null,
    endAt: end,
    hasEqualTo: equalTo != null,
    equalTo: equal,
  );
}

/// Which database the tool talks to.
class DatabaseTarget {
  const DatabaseTarget({
    required this.projectId,
    this.emulatorHost,
    this.databaseUrl,
  });

  final String projectId;

  /// `host:port` of the emulator; null for a real database.
  final String? emulatorHost;

  /// The explicit database URL, for a real database.
  final String? databaseUrl;
}

/// Chooses the backend. An emulator (flag, then environment) wins; without
/// one, an explicit [databaseUrl] is required, so the tool never reaches a real
/// project by accident. The project id defaults to `demo-example` with an
/// emulator and to the first label of the URL's host otherwise.
DatabaseTarget resolveTarget({
  String? emulator,
  String? databaseUrl,
  String? project,
  Map<String, String> environment = const <String, String>{},
}) {
  String? nonEmpty(String? v) => v == null || v.isEmpty ? null : v;
  final String? host =
      nonEmpty(emulator) ??
      nonEmpty(environment['FIREBASE_DATABASE_EMULATOR_HOST']);
  final String? url = nonEmpty(databaseUrl);
  String? projectId = nonEmpty(project);
  if (host != null) {
    parseHostPort(host);
    return DatabaseTarget(
      projectId: projectId ?? 'demo-example',
      emulatorHost: host,
    );
  }
  if (url == null) {
    throw ConfigurationError(
      'Refusing to run without a backend: pass --emulator-host host:port (or set '
      'FIREBASE_DATABASE_EMULATOR_HOST), or an explicit --database-url to use '
      'a real database.',
    );
  }
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
    throw UsageError('--database-url is not a URL: "$url".');
  }
  projectId ??= uri.host
      .split('.')
      .first
      .replaceFirst(RegExp(r'-default-rtdb$'), '');
  return DatabaseTarget(projectId: projectId, databaseUrl: url);
}
