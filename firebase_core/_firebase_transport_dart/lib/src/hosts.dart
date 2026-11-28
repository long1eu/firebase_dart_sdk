final RegExp _hostLabel = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');
final RegExp _decimalPart = RegExp(r'^(0|[1-9][0-9]{0,2})$');
final RegExp _hostAndPort = RegExp(
  r'^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+):([0-9]{1,5})$',
);
final RegExp _hostName = RegExp(r'^[A-Za-z0-9.-]+$');
final RegExp _ipv6Text = RegExp(r'^[0-9A-Fa-f:.]+$');

const List<String> _productionSuffixes = <String>[
  'googleapis.com',
  'google.com',
  'cloudfunctions.net',
  'run.app',
  'firebaseio.com',
  'firebasedatabase.app',
  'firebaseapp.com',
  'web.app',
  'appspot.com',
  'firebasestorage.app',
];

const String _expectedHostAndPort = 'emulator host: expected host:port';
const String _portOutOfRange = 'emulator host: the port must be 1 to 65535';
const String _notIpv6 = 'emulator host: not an IPv6 address';
const String _productionHost =
    'emulator host: a production host is not an emulator';

/// Whether [host] names this machine (rule L). Never throws.
///
/// After lowercasing and removing one pair of surrounding brackets, a host is loopback when it is
/// `localhost`; an IPv4 address of four decimal parts, each `0` or 1 to 3 digits starting with 1
/// to 9 and at most 255, whose first is `127`; or an IPv6 address equal to `::1` in any spelling.
/// Nothing else is: not `a.localhost`, not `localhost.`, not `0.0.0.0`, not `::ffff:127.0.0.1`,
/// not an IPv4 part with a leading zero (`127.0.0.09`, `127.00.0.1`), which some resolvers read
/// as octal, and not a name that resolves to a loopback address (names are not resolved).
bool isLoopbackHost(String host) {
  String text = host.toLowerCase();
  if (text.length >= 2 && text.startsWith('[') && text.endsWith(']')) {
    text = text.substring(1, text.length - 1);
  }
  if (text == 'localhost') {
    return true;
  }
  if (text.contains(':')) {
    return _isIpv6Loopback(text);
  }
  return _isIpv4Loopback(text);
}

bool _isIpv4Loopback(String text) {
  final List<String> parts = text.split('.');
  if (parts.length != 4 || parts.first != '127') {
    return false;
  }
  for (final String part in parts) {
    if (!_decimalPart.hasMatch(part) || int.parse(part) > 255) {
      return false;
    }
  }
  return true;
}

bool _isIpv6Loopback(String text) {
  final List<int>? bytes = _parseIpv6(text);
  if (bytes == null || bytes.length != 16 || bytes[15] != 1) {
    return false;
  }
  for (int i = 0; i < 15; i++) {
    if (bytes[i] != 0) {
      return false;
    }
  }
  return true;
}

/// The 16 bytes of the IPv6 address [text], or null when it is not one. A zone (`%eth0`) is not
/// part of an address here.
List<int>? _parseIpv6(String text) {
  if (!_ipv6Text.hasMatch(text)) {
    return null;
  }
  try {
    return Uri.parseIPv6Address(text);
  } on FormatException {
    return null;
  }
}

/// [host] in the one form hosts are compared in: lowercase, and an IPv6 address (with or without
/// brackets) as its canonical text without brackets, so every spelling of one address is equal.
///
/// A name is only lowercased: an internationalised name is compared as given, so its Unicode and
/// its `xn--` spelling differ. Never throws. Not part of the package's public library.
String canonicalHost(String host) {
  final String lowercase = host.toLowerCase();
  if (!lowercase.contains(':')) {
    return lowercase;
  }
  final bool bracketed = lowercase.startsWith('[') && lowercase.endsWith(']');
  final String address = bracketed
      ? lowercase.substring(1, lowercase.length - 1)
      : lowercase;
  return _canonicalIpv6(address) ?? lowercase;
}

/// The canonical text of the IPv6 address [text]: lowercase groups without leading zeros, the
/// longest run of two or more zero groups (the first of equal ones) written as `::`. That is the
/// form of RFC 5952, except that an embedded IPv4 part is written as two groups too
/// (`::ffff:7f00:1`), not in dotted form. Null when [text] is not an IPv6 address.
String? _canonicalIpv6(String text) {
  final List<int>? bytes = _parseIpv6(text);
  if (bytes == null || bytes.length != 16) {
    return null;
  }
  final List<int> groups = <int>[
    for (int i = 0; i < 16; i += 2) (bytes[i] << 8) | bytes[i + 1],
  ];
  final (int start, int length) = _longestZeroRun(groups);
  if (length < 2) {
    return groups.map(_hex).join(':');
  }
  final String head = groups.sublist(0, start).map(_hex).join(':');
  final String tail = groups.sublist(start + length).map(_hex).join(':');
  return '$head::$tail';
}

String _hex(int group) => group.toRadixString(16);

/// The start and the length of the first longest run of zeros in [groups]; a length of 0 when
/// there is none.
(int, int) _longestZeroRun(List<int> groups) {
  int bestStart = 0;
  int bestLength = 0;
  int runStart = 0;
  for (int i = 0; i <= groups.length; i++) {
    if (i < groups.length && groups[i] == 0) {
      continue;
    }
    if (i - runStart > bestLength) {
      bestStart = runStart;
      bestLength = i - runStart;
    }
    runStart = i + 1;
  }
  return (bestStart, bestLength);
}

/// True for a DNS label: 1 to 63 characters of `a-z`, `0-9` and `-`, not starting or ending with
/// `-`.
///
/// A product checks with it every value an application supplies (a region, a location, a project
/// id) before the value becomes part of a host, and builds the URL with the `Uri` constructor.
bool isHostLabel(String value) => _hostLabel.hasMatch(value);

/// The `host:port` of a Firebase emulator the application configured (rule E).
///
/// The error of a refused value names the rule that failed and never repeats any part of the
/// input, which may hold a password. Its message is one of: `emulator host: expected host:port`,
/// `emulator host: the port must be 1 to 65535`, `emulator host: not an IPv6 address`,
/// `emulator host: a production host is not an emulator`.
final class EmulatorHost {
  /// An emulator at [host], a name or an IP address (an IPv6 address without brackets), and
  /// [port], 1 to 65535.
  ///
  /// Throws an [ArgumentError] when rule E refuses them: see [EmulatorHost.parse].
  factory EmulatorHost(String host, int port) {
    final bool isIpv6 = host.contains(':');
    if (!(isIpv6 ? _ipv6Text : _hostName).hasMatch(host)) {
      throw ArgumentError(_expectedHostAndPort);
    }
    return EmulatorHost._checked(host, port, isIpv6: isIpv6);
  }

  /// Parses `host:port` or `[ipv6]:port`.
  ///
  /// Throws an [ArgumentError] when the text is anything else (a scheme, a path, user info, `%`
  /// or whitespace), when the port is not 1 to 65535, when a bracketed host is not an IPv6
  /// address, when the host starts or ends with a dot or has an empty label, or when the host is
  /// a production host of Google or Firebase or a subdomain of one.
  factory EmulatorHost.parse(String hostAndPort) {
    final RegExpMatch? match = _hostAndPort.firstMatch(hostAndPort);
    if (match == null) {
      throw ArgumentError(_expectedHostAndPort);
    }
    final String host = match.group(1)!;
    final int port = int.parse(match.group(2)!);
    if (host.startsWith('[')) {
      return EmulatorHost._checked(
        host.substring(1, host.length - 1),
        port,
        isIpv6: true,
      );
    }
    return EmulatorHost._checked(host, port, isIpv6: false);
  }

  /// [host] already matches the host pattern of its kind.
  factory EmulatorHost._checked(String host, int port, {required bool isIpv6}) {
    if (port < 1 || port > 65535) {
      throw ArgumentError(_portOutOfRange);
    }
    final String lowercase = host.toLowerCase();
    if (isIpv6) {
      final String? canonical = _canonicalIpv6(lowercase);
      if (canonical == null) {
        throw ArgumentError(_notIpv6);
      }
      return EmulatorHost._(canonical, port);
    }
    if (_isProductionHost(lowercase)) {
      throw ArgumentError(_productionHost);
    }
    if (_hasEmptyLabel(lowercase)) {
      throw ArgumentError(_expectedHostAndPort);
    }
    return EmulatorHost._(lowercase, port);
  }

  const EmulatorHost._(this.host, this.port);

  /// The host in lowercase. An IPv6 address is without brackets and in the canonical text of
  /// RFC 5952, with an embedded IPv4 part as two groups: `0:0:0:0:0:0:0:1` is kept as `::1`.
  final String host;

  /// The port, 1 to 65535.
  final int port;

  /// Whether [host] is a loopback host: `isLoopbackHost(host)`.
  bool get isLoopback => isLoopbackHost(host);

  /// `host:port`, with an IPv6 host in brackets.
  String get authority => host.contains(':') ? '[$host]:$port' : '$host:$port';

  /// True when [url] has this host and this port. A name or an IPv4 address is compared as
  /// lowercase text; an IPv6 address by its parsed value, so every spelling of it matches. The
  /// port is `url.port`, so the default of an `http` or `https` URL applies.
  bool owns(Uri url) => url.port == port && canonicalHost(url.host) == host;

  @override
  bool operator ==(Object other) {
    return other is EmulatorHost && other.host == host && other.port == port;
  }

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => authority;
}

bool _hasEmptyLabel(String host) {
  return host.startsWith('.') || host.endsWith('.') || host.contains('..');
}

bool _isProductionHost(String lowercaseHost) {
  String host = lowercaseHost;
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  for (final String suffix in _productionSuffixes) {
    if (host == suffix || host.endsWith('.$suffix')) {
      return true;
    }
  }
  return false;
}

/// Whether a request to [url] may carry tokens (rule T).
///
/// True only when the URL has a host and no user info, and its scheme is `https` or `wss`; or its
/// scheme is `http` or `ws` and the host is loopback (see [isLoopbackHost]) or [emulator] owns the
/// URL. Every other URL is false.
bool mayCarryTokens(Uri url, {EmulatorHost? emulator}) {
  if (url.host.isEmpty || url.userInfo.isNotEmpty) {
    return false;
  }
  final String scheme = url.scheme.toLowerCase();
  if (scheme == 'https' || scheme == 'wss') {
    return true;
  }
  if (scheme != 'http' && scheme != 'ws') {
    return false;
  }
  return isLoopbackHost(url.host) || (emulator != null && emulator.owns(url));
}

/// [origin] reduced to scheme, host and port, after checking it (rule O). An IPv6 host is given
/// in its canonical text.
///
/// It must be `https`, or `http` to a loopback host (see [isLoopbackHost]), with a host and no user
/// info, path (other than `/`), query or fragment. Throws an [ArgumentError] otherwise; its text
/// names only the scheme and the host (user info may hold a password).
Uri checkOrigin(Uri origin) {
  final String scheme = origin.scheme.toLowerCase();
  final String host = origin.host.toLowerCase();
  if (host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      (origin.path.isNotEmpty && origin.path != '/') ||
      origin.hasQuery ||
      origin.hasFragment) {
    throw ArgumentError.value(
      '${origin.scheme}://${origin.host}',
      'origin',
      'must be a scheme, a host and an optional port, with no path, query, fragment or user info',
    );
  }
  if (scheme != 'https' && !(scheme == 'http' && isLoopbackHost(host))) {
    throw ArgumentError.value(
      '${origin.scheme}://${origin.host}',
      'origin',
      'must use https, or http to a loopback host',
    );
  }
  return _normalOrigin(scheme, origin);
}

/// The one form origins are compared in: [scheme], the canonical host of [url] and its explicit
/// port. `Uri` drops the default port of `http` and `https` by itself.
Uri _normalOrigin(String scheme, Uri url) {
  return Uri(
    scheme: scheme,
    host: canonicalHost(url.host),
    port: url.hasPort ? url.port : null,
  );
}

/// The origin tokens are bound to and compared by: the normal form of the origin of [url].
///
/// The scheme, with `ws` mapped to `http` and `wss` to `https`; the host in lowercase, an IPv6
/// address in its canonical text; the port, which is the explicit port of [url], or 443 or 80 for
/// `https` and `http`. An HTTPS URL and a socket URL on the same host and port therefore have the
/// same token origin, and so have two spellings of one IPv6 address.
///
/// Throws an [ArgumentError] for a `ws` or `wss` URL without an explicit port: Dart knows no
/// default port for those schemes. A port of 0 is no port: `Uri` reports it as absent.
Uri tokenOrigin(Uri url) {
  final String scheme = url.scheme.toLowerCase();
  final bool isSocket = scheme == 'ws' || scheme == 'wss';
  if (isSocket && !url.hasPort) {
    throw ArgumentError.value(
      '$scheme://${url.host}',
      'url',
      'a ws or wss URL must have an explicit port',
    );
  }
  final String mapped = switch (scheme) {
    'ws' => 'http',
    'wss' => 'https',
    _ => scheme,
  };
  return _normalOrigin(mapped, url);
}
