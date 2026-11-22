/// Which database the page talks to, read from the address and, only when the
/// visitor asked for it, from `localStorage`.
///
/// Parameters (all optional):
/// - `emulator=<host>:<port>`: a Realtime Database emulator, for example
///   `127.0.0.1:9100`. `project=<id>` names the project (default
///   `demo-example`).
/// - `databaseUrl=<url>`, `apiKey=<key>`, `project=<id>`: your own project.
///
/// With none of them the page connects to nothing and asks for an emulator.
library;

/// The settings of one connection.
class AppConfig {
  const AppConfig({
    this.emulatorHost,
    this.databaseUrl,
    this.apiKey,
    this.projectId,
  });

  /// Reads [params] (the query parameters of the page address, or the fields
  /// of the form). Blank values count as missing.
  factory AppConfig.fromParameters(Map<String, String> params) {
    String? value(String key) {
      final String? text = params[key]?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return AppConfig(
      emulatorHost: value('emulator'),
      databaseUrl: value('databaseUrl'),
      apiKey: value('apiKey'),
      projectId: value('project'),
    );
  }

  /// `host:port` of an emulator, or null.
  final String? emulatorHost;

  /// `https://<name>.firebaseio.com` or `https://<name>.firebasedatabase.app`.
  final String? databaseUrl;
  final String? apiKey;
  final String? projectId;

  /// Whether there is something to connect to: an emulator host, or a
  /// database URL with an API key.
  bool get isUsable =>
      emulatorHost != null || (databaseUrl != null && apiKey != null);

  /// The text shown for the backend.
  String get label =>
      emulatorHost != null ? 'emulator $emulatorHost' : (databaseUrl ?? 'none');

  /// The settings as query parameters (without the API key, so that a copied
  /// address does not carry it).
  Map<String, String> toStorage() => <String, String>{
    'emulator': ?emulatorHost,
    'databaseUrl': ?databaseUrl,
    'apiKey': ?apiKey,
    'project': ?projectId,
  };

  /// A message when the settings go beyond what the page may connect to (the
  /// emulator must be on this machine, the URL on a Firebase host), else null.
  static String? validate(AppConfig config) {
    final String? host = config.emulatorHost;
    if (host != null) {
      final RegExp pattern = RegExp(r'^(127\.0\.0\.1|localhost):\d{2,5}$');
      return pattern.hasMatch(host)
          ? null
          : 'The emulator host must be 127.0.0.1:<port> or localhost:<port> '
                '(the page may only connect to this machine).';
    }
    final String? url = config.databaseUrl;
    if (url == null) return null;
    final Uri? uri = Uri.tryParse(url);
    final bool allowed =
        uri != null &&
        uri.scheme == 'https' &&
        (uri.host.endsWith('.firebaseio.com') ||
            uri.host.endsWith('.firebasedatabase.app'));
    return allowed
        ? null
        : 'The database URL must be https://<name>.firebaseio.com or '
              'https://<name>.firebasedatabase.app.';
  }
}
