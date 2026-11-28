import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';

/// The longest name of a Cloud Function.
const int _maxNameLength = 63;

/// The characters a function name may not hold: the URL delimiters, `%`, `:`, whitespace and the
/// control characters (C0, DEL and C1).
final RegExp _forbiddenInName = RegExp(r'[/?#%:\s\x00-\x1f\x7f-\x9f]');

/// The URL of the callable [name] (URL rule 1).
///
/// With [emulator]: `http://<emulator>/<projectId>/<region>/<name>`. Else with [customDomain],
/// which must have passed [checkCustomDomain]: its origin and path, then `<name>`. Else
/// `https://<region>-<projectId>.cloudfunctions.net/<name>`. [region] must have passed
/// [checkRegion] and [name] [checkName]; every part goes through the `Uri` constructor, so none
/// reaches the URL unencoded.
///
/// Throws a [StateError] when the URL needs the project id and [projectId] is null or empty, and
/// an [ArgumentError] when the project id cannot be part of the production host.
Uri callableUrl({
  required String? projectId,
  required String region,
  required String name,
  Uri? customDomain,
  EmulatorHost? emulator,
}) {
  if (emulator != null) {
    return Uri(
      scheme: 'http',
      host: emulator.host,
      port: emulator.port,
      pathSegments: <String>[_requireProjectId(projectId), region, name],
    );
  }
  if (customDomain != null) {
    return customDomain.replace(
      pathSegments: <String>[..._nonEmptySegments(customDomain), name],
    );
  }
  final String? host = productionHost(
    projectId: _requireProjectId(projectId),
    region: region,
  );
  if (host == null) {
    throw ArgumentError(
      'The project id and the region cannot form the host '
      '<region>-<projectId>.cloudfunctions.net (one DNS label of at most 63 characters). '
      'Use customDomain or httpsCallableFromUrl.',
    );
  }
  return Uri(scheme: 'https', host: host, pathSegments: <String>[name]);
}

/// The production host `<region>-<projectId>.cloudfunctions.net`, or null when the two values
/// cannot form it: [projectId] is null, empty or not a DNS label (a domain-scoped id such as
/// `example.com:p`), or the joined label is longer than 63 characters.
String? productionHost({required String? projectId, required String region}) {
  if (projectId == null || !isHostLabel(projectId)) {
    return null;
  }
  final String label = '$region-$projectId';
  if (!isHostLabel(region) || !isHostLabel(label)) {
    return null;
  }
  return '$label.cloudfunctions.net';
}

String _requireProjectId(String? projectId) {
  if (projectId == null || projectId.isEmpty) {
    throw StateError(
      'The FirebaseOptions of the app have no projectId; a callable called by name needs it.',
    );
  }
  return projectId;
}

Iterable<String> _nonEmptySegments(Uri url) {
  return url.pathSegments.where((String segment) => segment.isNotEmpty);
}

/// [customDomain] in the form calls are built from (URL rule 2).
///
/// It must be absolute, with the scheme `https`, or `http` when its host is loopback; with a host;
/// without user info, a query or a fragment. A path is kept, without its trailing slashes and
/// without empty segments: `https://x/api/` becomes `https://x/api`.
///
/// Throws an [ArgumentError] otherwise. The message names the rule and never repeats the URL,
/// which may hold a password.
Uri checkCustomDomain(Uri customDomain) {
  _checkTarget(customDomain, 'customDomain');
  final bool isHttps = customDomain.scheme == 'https';
  if (!isHttps && !isLoopbackHost(customDomain.host)) {
    throw ArgumentError(
      'customDomain must use https, or http to a loopback host.',
    );
  }
  return customDomain.replace(
    pathSegments: _nonEmptySegments(customDomain).toList(),
  );
}

/// [url] as `httpsCallableFromUrl` accepts it (URL rule 3); it is returned unchanged.
///
/// It must be absolute, with a host, without user info, a query or a fragment, and with the scheme
/// `https`, or `http` when its host is loopback or [emulator] owns it. So it always satisfies
/// `mayCarryTokens`.
///
/// Throws an [ArgumentError] otherwise. The message names the rule and never repeats the URL,
/// which may hold a password or a secret in its query.
Uri checkCallableUrl(Uri url, {EmulatorHost? emulator}) {
  _checkTarget(url, 'url');
  if (!mayCarryTokens(url, emulator: emulator)) {
    throw ArgumentError(
      'url must use https, or http to a loopback host or to the configured emulator.',
    );
  }
  return url;
}

/// What URL rules 2 and 3 share: an absolute `http` or `https` URL with a host and without user
/// info, a query or a fragment.
void _checkTarget(Uri url, String parameter) {
  final bool isWebScheme = url.scheme == 'https' || url.scheme == 'http';
  if (!isWebScheme || url.host.isEmpty) {
    throw ArgumentError(
      '$parameter must be an absolute https URL with a host.',
    );
  }
  if (url.userInfo.isNotEmpty || url.hasQuery || url.hasFragment) {
    throw ArgumentError(
      '$parameter must not have user info, a query or a fragment.',
    );
  }
}

/// [region] when it can be part of a host (URL rule 4): one DNS label.
///
/// Throws an [ArgumentError] otherwise; for a value with `:` or `/`, which is how a URL passed as
/// a region looks, the message says to use `customDomain`.
String checkRegion(String region) {
  if (isHostLabel(region)) {
    return region;
  }
  if (region.contains(':') || region.contains('/')) {
    throw ArgumentError.value(
      region,
      'region',
      'is not a region; for a URL or a host use customDomain',
    );
  }
  throw ArgumentError.value(
    region,
    'region',
    'must be 1 to 63 characters of a-z, 0-9 and -, not starting or ending with -',
  );
}

/// [name] when it is the name of a callable: 1 to 63 characters, not `.` or `..`, and none of
/// `/`, `?`, `#`, `%`, `:`, whitespace or control characters.
///
/// Throws an [ArgumentError] otherwise.
String checkName(String name) {
  if (name.isEmpty || name.length > _maxNameLength) {
    throw ArgumentError.value(
      name.length,
      'name',
      'must be 1 to $_maxNameLength characters long; that is its length',
    );
  }
  if (name == '.' || name == '..' || _forbiddenInName.hasMatch(name)) {
    throw ArgumentError(
      "name must not be '.' or '..' and must not contain '/', '?', '#', '%', ':', whitespace or "
      'control characters.',
    );
  }
  return name;
}
