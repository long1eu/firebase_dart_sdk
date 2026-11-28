// Where the browser tests find the Data Connect emulator.
//
// A browser test cannot read the environment, so tool/test_browser_data_connect.sh writes the
// address of the emulator it started ("host:port") to test/browser/emulator_host.txt, which the test
// runner serves next to the tests. Without that file (a local run) the integration tests skip with a
// reason; the script fails when its emulator run shows a skip, so CI cannot pass that way.

import 'package:http/http.dart' as http;

String? _host;
Future<void>? _loading;

/// Reads test/browser/emulator_host.txt; call it in `setUpAll`. Later calls wait for the first.
Future<void> loadEmulatorHost() => _loading ??= () async {
  final http.Client client = http.Client();
  try {
    final http.Response response = await client.get(
      Uri.base.resolve('emulator_host.txt'),
    );
    final String body = response.body.trim();
    _host = response.statusCode == 200 && body.isNotEmpty ? body : null;
  } on http.ClientException {
    _host = null;
  } finally {
    client.close();
  }
}();

/// The emulator address as "host:port", or null when [loadEmulatorHost] found no file.
///
/// A test passes `skip: emulatorSkipReason` when this is null.
String? get emulatorHost => _host;

/// The reason to skip an emulator test when there is no emulator address, or null when there is one.
String? get emulatorSkipReason => _host == null
    ? 'test/browser/emulator_host.txt is missing: run the browser tests with '
          'tool/test_browser_data_connect.sh.'
    : null;
