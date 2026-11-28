// Where the browser tests find the fake server of tool/remote_config_fake_server.dart.
//
// A browser test cannot read the environment, so tool/test_browser_remote_config.sh writes the port
// the server listens on to test/browser/server_port.txt, which the test runner serves next to the
// tests. Without that file the tests fail with a message that names the script.

import 'package:http/http.dart' as http;

const String serverHostName = '127.0.0.1';

int? _port;
Future<void>? _loading;

/// Reads test/browser/server_port.txt; call it in `setUpAll`. Later calls wait for the first.
Future<void> loadServerPort() => _loading ??= () async {
  final http.Client client = http.Client();
  try {
    final http.Response response = await client.get(
      Uri.base.resolve('server_port.txt'),
    );
    _port = response.statusCode == 200
        ? int.tryParse(response.body.trim())
        : null;
  } on http.ClientException {
    _port = null;
  } finally {
    client.close();
  }
}();

/// The port of the fake server; throws when [loadServerPort] found no port file.
int get serverPort =>
    _port ??
    (throw StateError(
      'test/browser/server_port.txt is missing: run the browser tests with '
      'tool/test_browser_remote_config.sh.',
    ));

/// `http://127.0.0.1:<port>` of the fake server.
Uri get serverOrigin => Uri.parse('http://$serverHostName:$serverPort');
