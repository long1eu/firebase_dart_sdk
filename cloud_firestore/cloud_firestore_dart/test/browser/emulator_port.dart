// Where the browser tests find the private Firestore emulator.
//
// A browser test cannot read the environment, and `dart test` cannot pass
// defines to the compilers, so tool/test_browser.sh writes the port it uses
// (FIRESTORE_EMULATOR_PORT, default 8090) to test/browser/emulator_port.txt,
// which the test runner serves next to the tests. Without that file the port
// is the FIRESTORE_EMULATOR_PORT define, or 8090.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

const String emulatorHost = String.fromEnvironment(
  'FIRESTORE_EMULATOR_HOST_NAME',
  defaultValue: '127.0.0.1',
);

/// The port of the emulator; final once [loadEmulatorPort] completed.
int emulatorPort = const int.fromEnvironment(
  'FIRESTORE_EMULATOR_PORT',
  defaultValue: 8090,
);

Future<void>? _loading;

/// Sets [emulatorPort] from test/browser/emulator_port.txt, if there is one.
/// Call it in `setUpAll` before [emulatorPort] is used; later calls wait for
/// the first.
Future<void> loadEmulatorPort() => _loading ??= () async {
  try {
    final web.Response response = await web.window
        .fetch(Uri.base.resolve('emulator_port.txt').toString().toJS)
        .toDart;
    if (!response.ok) {
      return;
    }
    final int? port = int.tryParse(
      (await response.text().toDart).toDart.trim(),
    );
    if (port != null) {
      emulatorPort = port;
    }
  } catch (_) {
    // No file: the default stays.
  }
}();
