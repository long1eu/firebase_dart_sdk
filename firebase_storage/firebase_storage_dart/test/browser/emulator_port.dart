// Where the browser tests find the private Storage emulator.
//
// A browser test cannot read the environment, so tool/test_browser.sh writes the port it uses
// (STORAGE_EMULATOR_PORT, default 9385) to test/browser/emulator_port.txt, which the test
// runner serves next to the tests. Without that file the port is 9385.

import 'package:http/http.dart' as http;

const String emulatorHostName = '127.0.0.1';

/// The port of the emulator; final once [loadEmulatorPort] completed.
int emulatorPort = 9385;

Future<void>? _loading;

/// Sets [emulatorPort] from test/browser/emulator_port.txt, if there is one. Call it in
/// `setUpAll`; later calls wait for the first.
Future<void> loadEmulatorPort() => _loading ??= () async {
  final http.Client client = http.Client();
  try {
    final http.Response response = await client.get(
      Uri.base.resolve('emulator_port.txt'),
    );
    final int? port = response.statusCode == 200
        ? int.tryParse(response.body.trim())
        : null;
    if (port != null) {
      emulatorPort = port;
    }
  } on http.ClientException {
    // No file: the default stays.
  } finally {
    client.close();
  }
}();

/// `host:port` of the emulator, as `FirebaseStorage(emulatorHost: ...)` takes it.
String get emulatorHost => '$emulatorHostName:$emulatorPort';
