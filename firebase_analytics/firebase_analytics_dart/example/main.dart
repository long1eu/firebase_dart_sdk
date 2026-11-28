// A command-line program that logs two events to a GA4 web stream through a relay.
//
//   dart run example/main.dart https://example.com/collect G-XXXXXXXXXX
//
// The relay adds the API secret; see the README for what it must check.

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    print('Usage: dart run example/main.dart <relay URL> <measurement id>');
    return;
  }
  final FirebaseApp app = await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'my-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final FirebaseAnalytics analytics = FirebaseAnalytics(
    app,
    measurementId: args[1],
    transport: AnalyticsTransport.relay(Uri.parse(args[0])),
  );
  await analytics.setUserProperty(name: 'plan', value: 'free');
  await analytics.logEvent(name: 'tutorial_begin');
  await analytics.logScreenView(screenName: 'home', screenClass: 'HomeScreen');
  await analytics.close();
}
