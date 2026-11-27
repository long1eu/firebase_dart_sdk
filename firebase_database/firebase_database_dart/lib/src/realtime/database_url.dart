/// Parsing and validating a database URL into the core's [RepoInfo] (owner U):
/// `rtdb_protocol.md` 2.1 and 2.4 with the stricter rules of threat model T3 and T6.
///
/// A bad URL is a programmer error: these functions throw [FormatException] (text that is not a
/// database URL) or [ArgumentError] (a value out of range), never a database error. No message
/// quotes the URL or a query value: a URL can carry user info or a credential by mistake (T8).
library;

import 'package:firebase_database_dart/src/core/repo_info.dart';

/// Firebase database names: lowercase letters, digits and `-` (threat model T6). The emulator
/// refuses `_` and an empty name (`rtdb_emulator_probe.md`, "Namespaces") and lowercases the rest
/// (probe addendum 2, question 13), so names are lowercased before this check.
final RegExp _namespacePattern = RegExp(r'^[a-z0-9-]{1,63}$');

/// One DNS label (RFC 1123): letters, digits and inner hyphens, at most 63 characters.
final RegExp _dnsLabel = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');

/// A dotted-quad IPv4 literal in canonical form (no leading zeros, which some URL parsers read as
/// octal).
final RegExp _ipv4 = RegExp(
  r'^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$',
);

/// The characters an authority of a database URL may hold: a host (name or bracketed IPv6) and a
/// port. No `@` (user info, T6), no `%` (escapes), no `\` and nothing outside ASCII.
final RegExp _authorityChars = RegExp(r'^[A-Za-z0-9.\-:\[\]]+$');

final RegExp _schemePrefix = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://');
final RegExp _portDigits = RegExp(r'^[0-9]{1,5}$');

const List<String> _googleSuffixes = <String>[
  '.firebaseio.com',
  '.firebasedatabase.app',
];
const String _cloudWorkstationSuffix = '.cloudworkstations.dev';
const String _defaultNamespaceSuffix = '-default-rtdb';
const int _httpsPort = 443;

/// Parses [url] as a production database URL (2.1, threat model T6) into a [RepoInfo] with
/// `secure` true and `isUsingEmulator` false.
///
/// Accepts `https://` and `wss://` (and a bare host, read as `https`); the host is lowercased.
/// Namespace: the `ns` parameter when given, else the first label of a `firebaseio.com` /
/// `firebasedatabase.app` host. Throws [FormatException] for: `http`/`ws` (the message points to
/// `useEmulator`, T3), userinfo, a fragment, any query key but `ns`, a non-root path, an empty
/// host, IP literals other than loopback, a port other than 443, a custom domain without `ns`, a
/// namespace that does not match `^[a-z0-9-]{1,63}$` after lowercasing, and the domain
/// `firebase.com` (2.1 step 6). The message never quotes a query value.
///
/// A loopback host (`localhost`, `127.0.0.0/8`, `::1`) may name any port: a TLS front of a local
/// server. Everything else is reached on 443 only.
RepoInfo parseDatabaseUrl(String url) {
  final Uri uri = _parseUrl(url);
  final String scheme = uri.scheme;
  if (scheme == 'http' || scheme == 'ws') {
    throw const FormatException(
      'Database URL must use https: a plain-text database is only reachable through '
      'useEmulator (emulatorDatabase)',
    );
  }
  if (scheme != 'https' && scheme != 'wss') {
    throw const FormatException('Database URL scheme must be https or wss');
  }
  if (uri.hasFragment) {
    throw const FormatException('Database URL must not have a fragment');
  }
  final String? namespaceParameter = _namespaceParameter(uri);
  final String host = uri.host.toLowerCase();
  _checkProductionHost(host);
  final int? port = uri.hasPort ? uri.port : null;
  if (port != null && port != _httpsPort) {
    if (!isLoopbackHost(host)) {
      throw const FormatException('Database URL port must be 443 (or none)');
    }
    _checkPort(port);
  }
  final String? namespace = namespaceParameter ?? _namespaceOfHost(host);
  if (namespace == null) {
    throw const FormatException(
      'Database URL of a custom domain needs the database name as ?ns=<name>',
    );
  }
  return RepoInfo(
    host: joinHostPort(host, port == _httpsPort ? null : port),
    namespace: namespace,
    secure: true,
  );
}

/// The URL that keys the persisted cache of [info] (`PersistenceKey.databaseUrl`): `https://<host>`
/// for a production database, followed by `?ns=<namespace>` when the first label of the host is not
/// the namespace; `http://<host>:<port>?ns=<namespace>` for the emulator (`https` for
/// `*.cloudworkstations.dev`, and the default port left out).
Uri persistenceUrlOf(RepoInfo info) {
  final Uri root = Uri.parse(
    '${info.secure ? 'https' : 'http'}://${info.host}',
  );
  if (!info.isUsingEmulator && info.namespace == info.host.split('.').first) {
    return root;
  }
  return root.replace(queryParameters: <String, String>{'ns': info.namespace});
}

/// The URL under which a `FirebaseDatabase` keys the persisted cache of the database at [url]
/// (`PersistenceKey.databaseUrl`, `FirebaseDatabase.databaseUrl`). A key the client produced gives
/// itself.
///
/// What is read as what:
///
/// * An `http://` or `ws://` URL, or a `*.cloudworkstations.dev` URL with a query, is an emulator
///   key `<scheme>://<host>[:<port>]?ns=<namespace>`: it must have `?ns=`; no port means 80 (443 on
///   a cloud workstation, whose key is `https`).
/// * Anything else (`https://`, `wss://`, a bare host) is a production database URL, read by the
///   rules of the `FirebaseDatabase` constructor: scheme, case of host and namespace, port 443, a
///   trailing `/` and a `?ns=` equal to the first label of the host make no difference. Without a
///   query, a host that does not name its namespace (a custom domain, a loopback host, a cloud
///   workstation) is read with `?ns=<first label>`, as the client leaves that `ns` out of its key.
///
/// On a cloud workstation (`*.cloudworkstations.dev`) a production database and the emulator on
/// the same host and namespace can meet. A production database spelled with `?ns=<first label>`
/// is read as the emulator's key (the client's own key for it has no query); pass
/// `FirebaseDatabase.databaseUrl` for it. And the client itself gives a production database with
/// any other `?ns=` the same key as the emulator on that host at port 443, so the two share one
/// cache.
///
/// Throws a [FormatException] for a URL that the constructor would refuse, or an emulator URL
/// without `?ns=`. The message does not quote the URL.
Uri persistenceDatabaseUrl(Uri url) {
  final Uri uri = _parseUrl(url.toString());
  final String scheme = uri.scheme.toLowerCase();
  final String host = uri.host.toLowerCase();
  final bool hasQuery = uri.query.isNotEmpty;
  final bool emulator =
      scheme == 'http' ||
      scheme == 'ws' ||
      (hasQuery && host.endsWith(_cloudWorkstationSuffix));
  if (!emulator) {
    final Uri production = !hasQuery && _namespaceOfHost(host) == null
        ? uri.replace(
            queryParameters: <String, String>{'ns': host.split('.').first},
          )
        : uri;
    return persistenceUrlOf(parseDatabaseUrl(production.toString()));
  }
  if (uri.hasFragment) {
    throw const FormatException('Database URL must not have a fragment');
  }
  final String? namespace = _namespaceParameter(uri);
  if (namespace == null) {
    throw const FormatException(
      'An emulator database URL needs the database name as ?ns=<name>',
    );
  }
  final int port = uri.hasPort
      ? uri.port
      : (host.endsWith(_cloudWorkstationSuffix) ? _httpsPort : 80);
  final RepoInfo info;
  try {
    info = emulatorDatabase(host, port, namespace: namespace);
  } on ArgumentError catch (e) {
    throw FormatException('Emulator database URL: ${e.message}');
  }
  return persistenceUrlOf(info);
}

/// The [RepoInfo] of the default database of [projectId]:
/// `<projectId>-default-rtdb.firebaseio.com`, namespace `<projectId>-default-rtdb` (1.1,
/// api/Database.ts:135). Throws [ArgumentError] when [projectId] is not a valid label.
RepoInfo defaultDatabase(String projectId) {
  final String namespace = '$projectId$_defaultNamespaceSuffix';
  if (!_dnsLabel.hasMatch(projectId) ||
      !_namespacePattern.hasMatch(namespace)) {
    throw ArgumentError.value(
      projectId,
      'projectId',
      'must be a project id: lowercase letters, digits and "-"',
    );
  }
  return RepoInfo(
    host: '$namespace.firebaseio.com',
    namespace: namespace,
    secure: true,
  );
}

/// The [RepoInfo] of the emulator at [host]:[port] with [namespace] (2.4): `secure` only for
/// `*.cloudworkstations.dev`. Throws [ArgumentError] for an empty host, a port outside
/// `1..65535` or an invalid namespace.
///
/// [host] is a DNS name or an IP literal (IPv6 with or without brackets), lowercased. The
/// namespace is lowercased (the emulator matches it case-insensitively, probe addendum 2,
/// question 13); a project's default one is `<projectId>-default-rtdb` ([defaultDatabase]).
RepoInfo emulatorDatabase(String host, int port, {required String namespace}) {
  final String name = _unbracket(host).toLowerCase();
  final String? problem = _hostProblem(name, anyIp: true);
  if (problem != null) {
    throw ArgumentError.value(host, 'host', problem);
  }
  if (port < 1 || port > 65535) {
    throw ArgumentError.value(port, 'port', 'must be in 1..65535');
  }
  final String lowerNamespace = namespace.toLowerCase();
  if (!_namespacePattern.hasMatch(lowerNamespace)) {
    throw ArgumentError.value(
      namespace,
      'namespace',
      'must be 1 to 63 lowercase letters, digits or "-"',
    );
  }
  return RepoInfo(
    host: joinHostPort(name, port),
    namespace: lowerNamespace,
    secure: name.endsWith(_cloudWorkstationSuffix),
    isUsingEmulator: true,
  );
}

/// Parses an emulator address `host:port`, the value of `FIREBASE_DATABASE_EMULATOR_HOST` (2.4).
///
/// Reading the variable is the caller's explicit step, never a default (threat model T3). Throws
/// [FormatException] for anything but a host and a port in `1..65535`. An IPv6 host is written in
/// brackets (`[::1]:9000`) and returned without them; the host is lowercased.
({String host, int port}) parseEmulatorHost(String value) {
  final ({String host, int? port}) parts = splitHostPort(value);
  final int? port = parts.port;
  if (port == null) {
    throw const FormatException('Emulator address must be host:port');
  }
  final String host = parts.host.toLowerCase();
  final String? problem = _hostProblem(host, anyIp: true);
  if (problem != null) {
    throw FormatException('Emulator address: $problem');
  }
  return (host: host, port: port);
}

/// Splits a [RepoInfo.host] value (`host`, `host:port` or `[ipv6]:port`) into the host, without
/// brackets, and the port. Throws [FormatException] for a malformed value or a port outside
/// `1..65535`; the host itself is not validated.
({String host, int? port}) splitHostPort(String value) {
  final String host;
  final String? portText;
  if (value.startsWith('[')) {
    final int end = value.indexOf(']');
    if (end < 0) {
      throw const FormatException('Missing "]" after an IPv6 host');
    }
    host = value.substring(1, end);
    final String rest = value.substring(end + 1);
    if (rest.isNotEmpty && !rest.startsWith(':')) {
      throw const FormatException('Expected ":port" after an IPv6 host');
    }
    portText = rest.isEmpty ? null : rest.substring(1);
  } else {
    final int colon = value.lastIndexOf(':');
    if (colon >= 0 && value.indexOf(':') != colon) {
      throw const FormatException('An IPv6 host must be written in brackets');
    }
    host = colon < 0 ? value : value.substring(0, colon);
    portText = colon < 0 ? null : value.substring(colon + 1);
  }
  if (host.isEmpty) {
    throw const FormatException('Missing host');
  }
  if (portText == null) {
    return (host: host, port: null);
  }
  if (!_portDigits.hasMatch(portText)) {
    throw const FormatException('Port must be a number in 1..65535');
  }
  final int port = int.parse(portText);
  _checkPort(port);
  return (host: host, port: port);
}

/// [host] with `:`[port] when [port] is not null; an IPv6 host is put in brackets.
String joinHostPort(String host, int? port) {
  final String bracketed = host.contains(':') ? '[$host]' : host;
  return port == null ? bracketed : '$bracketed:$port';
}

/// Whether [host] (lowercase, without brackets) is a loopback host: `localhost`, a canonical
/// IPv4 address in `127.0.0.0/8`, or the IPv6 address `::1` in any spelling (threat model T3).
bool isLoopbackHost(String host) {
  if (host == 'localhost') {
    return true;
  }
  final RegExpMatch? v4 = _ipv4.firstMatch(host);
  if (v4 != null) {
    return _isIpv4(v4) && v4.group(1) == '127';
  }
  if (!host.contains(':')) {
    return false;
  }
  final List<int> bytes;
  try {
    bytes = Uri.parseIPv6Address(host);
  } on FormatException {
    return false;
  }
  for (int i = 0; i < 15; i++) {
    if (bytes[i] != 0) {
      return false;
    }
  }
  return bytes[15] == 1;
}

/// Whether [host] is a bare lowercase DNS name (threat model T1): labels of letters, digits and
/// inner hyphens, at most 253 characters, no empty label (so no trailing dot), and a last label
/// that is not all digits (so an IPv4-looking text is never a name).
bool isDnsHostName(String host) {
  if (host.isEmpty || host.length > 253) {
    return false;
  }
  final List<String> labels = host.split('.');
  for (final String label in labels) {
    if (!_dnsLabel.hasMatch(label)) {
      return false;
    }
  }
  return !RegExp(r'^[0-9]+$').hasMatch(labels.last);
}

Uri _parseUrl(String url) {
  final String text = _schemePrefix.hasMatch(url) ? url : 'https://$url';
  final int start = text.indexOf('://') + 3;
  int end = text.length;
  for (final String stop in const <String>['/', '?', '#']) {
    final int index = text.indexOf(stop, start);
    if (index >= 0 && index < end) {
      end = index;
    }
  }
  final String authority = text.substring(start, end);
  if (authority.isEmpty) {
    throw const FormatException('Database URL has no host');
  }
  if (!_authorityChars.hasMatch(authority)) {
    throw const FormatException(
      'Database URL host may only hold letters, digits, "-", "." and a port '
      '(no user info, no escapes, no international characters)',
    );
  }
  // The raw path, before Uri.parse resolves `/..` and `%2e` away.
  int pathEnd = text.length;
  for (final String stop in const <String>['?', '#']) {
    final int index = text.indexOf(stop, end);
    if (index >= 0 && index < pathEnd) {
      pathEnd = index;
    }
  }
  final String path = text.substring(end, pathEnd);
  if (path.isNotEmpty && path != '/') {
    throw const FormatException(
      'Database URL must not have a path: give the database root and use ref(path)',
    );
  }
  try {
    return Uri.parse(text);
  } on FormatException {
    throw const FormatException('Not a valid database URL');
  }
}

/// The `ns` query value, lowercased and checked; null without a query.
String? _namespaceParameter(Uri uri) {
  if (uri.query.isEmpty) {
    return null;
  }
  final Map<String, List<String>> parameters;
  try {
    parameters = uri.queryParametersAll;
  } on FormatException {
    throw const FormatException('Database URL query is not valid UTF-8');
  } on ArgumentError {
    throw const FormatException('Database URL query is not valid UTF-8');
  }
  for (final String key in parameters.keys) {
    if (key != 'ns') {
      throw const FormatException(
        'Database URL accepts no query parameter but ns',
      );
    }
  }
  final List<String>? values = parameters['ns'];
  if (values == null) {
    return null;
  }
  if (values.length != 1) {
    throw const FormatException('Database URL must give ns once');
  }
  final String namespace = values.single.toLowerCase();
  if (!_namespacePattern.hasMatch(namespace)) {
    throw const FormatException(
      'Database URL ns must be 1 to 63 lowercase letters, digits or "-"',
    );
  }
  return namespace;
}

void _checkProductionHost(String host) {
  if (host.isEmpty) {
    throw const FormatException('Database URL has no host');
  }
  if (isLoopbackHost(host)) {
    return;
  }
  final String? problem = _hostProblem(host, anyIp: false);
  if (problem != null) {
    throw FormatException('Database URL: $problem');
  }
  if (host == 'firebase.com' || host.endsWith('.firebase.com')) {
    throw const FormatException(
      'Database URL: firebase.com databases are no longer supported; use the '
      'firebaseio.com URL from the Firebase console',
    );
  }
}

/// Why [host] (lowercase, without brackets) is not a valid host, or null when it is. IP literals
/// are accepted when [anyIp] (the emulator), else only loopback ones.
String? _hostProblem(String host, {required bool anyIp}) {
  if (host.isEmpty) {
    return 'missing host';
  }
  if (_looksLikeIp(host)) {
    if (!_isValidIp(host)) {
      return 'host is not a valid IP address';
    }
    if (!anyIp && !isLoopbackHost(host)) {
      return 'host must be a name; IP addresses are accepted for loopback only';
    }
    return null;
  }
  if (!isDnsHostName(host)) {
    return 'host is not a valid DNS name';
  }
  return null;
}

/// IPv6 (any colon) or a last label of digits: never a DNS name, whatever a URL parser makes of
/// it (`127.1`, `0x7f.0.0.1`).
bool _looksLikeIp(String host) =>
    host.contains(':') || RegExp(r'^[0-9]+$').hasMatch(host.split('.').last);

bool _isValidIp(String host) {
  if (host.contains(':')) {
    try {
      Uri.parseIPv6Address(host);
      return true;
    } on FormatException {
      return false;
    }
  }
  final RegExpMatch? v4 = _ipv4.firstMatch(host);
  return v4 != null && _isIpv4(v4);
}

bool _isIpv4(RegExpMatch match) {
  for (int group = 1; group <= 4; group++) {
    if (int.parse(match.group(group)!) > 255) {
      return false;
    }
  }
  return true;
}

String? _namespaceOfHost(String host) {
  for (final String suffix in _googleSuffixes) {
    if (host.endsWith(suffix)) {
      final String label = host.substring(0, host.indexOf('.'));
      return _namespacePattern.hasMatch(label) ? label : null;
    }
  }
  return null;
}

String _unbracket(String host) =>
    host.startsWith('[') && host.endsWith(']') && host.length > 1
    ? host.substring(1, host.length - 1)
    : host;

void _checkPort(int port) {
  if (port < 1 || port > 65535) {
    throw const FormatException('Port must be a number in 1..65535');
  }
}
