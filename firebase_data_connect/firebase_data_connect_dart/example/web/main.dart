// The same query in a browser, over REST, against the Data Connect emulator.
//
// A browser cannot read the environment, so the emulator address comes from the page's query string:
// serve this program (`dart compile js -O2 example/web/main.dart -o example/web/main.dart.js` and a page
// that loads it) and open the page with `?emulator=127.0.0.1:9499`. The result is printed to the browser
// console. The emulator answers the CORS preflight of the headers the client sends.
//
// Compiling this file also shows the size of the web build: it reaches neither package:grpc nor
// package:protobuf.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

Future<void> main() async {
  final String? emulatorHost = Uri.base.queryParameters['emulator'];
  if (emulatorHost == null) {
    print('Open the page with ?emulator=127.0.0.1:9499');
    return;
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:123456789012:web:0123456789abcdef',
      projectId: 'demo-test',
    ),
  );
  final DataConnect dataConnect = DataConnect(
    app,
    connector: const ConnectorConfig(
      location: 'us-central1',
      serviceId: 'test-service',
      connector: 'test-connector',
    ),
    emulatorHost: emulatorHost,
  );
  try {
    final Map<String, Object?> data = await dataConnect.executeQuery(
      'ListItems',
    );
    print('items: ${data['items']}');
  } on DataConnectException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await dataConnect.close();
  }
}
