// A Flutter program that uses the official firebase_analytics API, with
// firebase_analytics_dart sending the events over the Measurement Protocol.
//
// On Windows and Linux Flutter registers the package before main() runs; the
// FirebaseAnalyticsDart.configure() call says where the events go, and on the
// other platforms it also replaces the official implementation. Events go to a
// relay you run, which checks the request, adds the API secret of your GA4 web
// data stream and forwards it to Google Analytics (see the README of
// firebase_analytics_dart).

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics_dart_platform/firebase_analytics_dart_platform.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseAnalyticsDart.configure(
    transport: AnalyticsTransport.relay(
      Uri.parse('https://example.com/collect'),
    ),
  );
  await Firebase.initializeApp(
    // Use your own options (flutterfire configure) for a real project, with
    // the measurement id of a GA4 web data stream.
    options: const FirebaseOptions(
      apiKey: 'my-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      messagingSenderId: '1234567890',
      projectId: 'my-project',
      measurementId: 'G-XXXXXXXXXX',
    ),
  );
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  await analytics.setUserProperty(name: 'plan', value: 'pro');
  await analytics.logLogin(loginMethod: 'password');
  await analytics.logScreenView(screenName: 'Home', screenClass: 'HomePage');
  await analytics.logEvent(
    name: 'level_up',
    parameters: <String, Object>{'level': 3},
  );
}
