// GENERATED from the README files by test/readme_snippets_test.dart. Do not edit: change the
// README and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import, unnecessary_import
// ignore_for_file: unused_element

import 'dart:async';
import 'dart:io';
import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_analytics_dart/io.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

late FirebaseApp app;
late AnalyticsStore store;
late FirebaseAnalytics analytics;

// README.md:21
Future<void> analyticsReadmeLine21() async {
  Future<void> main() async {
    final FirebaseApp app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'my-api-key',
        appId: '1:1234567890:web:0123456789abcdef',
        projectId: 'my-project',
        measurementId: 'G-XXXXXXXXXX',
      ),
    );
    final FirebaseAnalytics analytics = FirebaseAnalytics(
      app,
      transport: AnalyticsTransport.relay(Uri.parse('https://example.com/collect')),
    );
    await analytics.logEvent(name: 'level_up', parameters: <String, Object>{'level': 3});
    await analytics.close();
  }
}

// ../../docs/guides/analytics.md:58
Future<void> analyticsGuideLine58() async {
  Future<FirebaseAnalytics> create() async {
    final FirebaseApp app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'my-api-key',
        appId: '1:1234567890:web:0123456789abcdef',
        projectId: 'my-project',
        measurementId: 'G-XXXXXXXXXX',
      ),
    );
    return FirebaseAnalytics(
      app,
      transport: AnalyticsTransport.relay(Uri.parse('https://relay.example.com/collect')),
    );
  }
}

// ../../docs/guides/analytics.md:84
Future<void> analyticsGuideLine84() async {
  FirebaseAnalytics withFiles(FirebaseApp app) {
    final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return FirebaseAnalytics(
      app,
      transport: AnalyticsTransport.relay(Uri.parse('https://relay.example.com/collect')),
      store: FileAnalyticsStore(Directory('$home/.my_app/analytics')),
    );
  }
}

// ../../docs/guides/analytics.md:106
Future<void> analyticsGuideLine106() async {
  Future<void> logging(FirebaseAnalytics analytics) async {
    await analytics.logEvent(name: 'level_up', parameters: <String, Object?>{'level': 3, 'character': 'mage'});
    await analytics.logScreenView(screenName: 'home', screenClass: 'HomeScreen');
  }
}

// ../../docs/guides/analytics.md:121
Future<void> analyticsGuideLine121() async {
  Future<void> userState(FirebaseAnalytics analytics) async {
    await analytics.setUserId('user-1234'); // not an email address or other personal data
    await analytics.setUserProperty(name: 'plan', value: 'free'); // a null value removes it
    await analytics.setDefaultEventParameters(<String, Object?>{'app_flavor': 'beta'});
  }
}

// ../../docs/guides/analytics.md:134
Future<void> analyticsGuideLine134() async {
  Future<void> privacy(FirebaseAnalytics analytics) async {
    await analytics.setAnalyticsCollectionEnabled(false); // drops the queue and stops sending
    await analytics.setConsent(analyticsStorage: false, adUserData: false, adPersonalization: false);
    await analytics.resetAnalyticsData(); // a new client id, no user id, no properties, no queue
  }
}

// ../../docs/guides/analytics.md:155
Future<void> analyticsGuideLine155() async {
  void lifecycle(FirebaseAnalytics analytics, bool inForeground) {
    analytics.setAppActive(inForeground);
  }
}

// ../../docs/guides/analytics.md:163
Future<void> analyticsGuideLine163() async {
  Future<void> finish(FirebaseAnalytics analytics) async {
    await analytics.flush(); // send what is queued now; never throws
    await analytics.close(); // flush, save, release the HTTP client
  }
}

// ../../docs/guides/analytics.md:190
Future<void> analyticsGuideLine190() async {
  Future<void> safeLog(FirebaseAnalytics analytics, String name) async {
    try {
      await analytics.logEvent(name: name);
    } on FirebaseAnalyticsException catch (e) {
      print('Not logged: ${e.code}');
    }
  }
}
