// What the test files share: the fake relay, the configuration and the
// default app.

import 'dart:convert';

import 'package:firebase_analytics_dart_platform/firebase_analytics_dart_platform.dart';
import 'package:firebase_analytics_dart_platform/src/firebase_analytics_platform.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The measurement id of the app's options.
const String measurementId = 'G-TEST12345';

const FirebaseOptions options = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
  measurementId: measurementId,
);

/// The relay the tests configure. It is never reached: [FakeRelay] answers
/// in its place.
final Uri relayUri = Uri.parse('https://relay.example.com/collect');

/// A relay in memory: records every request and answers 204.
class FakeRelay {
  /// The requests, in order.
  final List<http.Request> requests = <http.Request>[];

  /// The client the package sends through.
  late final MockClient client = MockClient((http.Request request) async {
    requests.add(request);
    return http.Response('', 204);
  });

  /// The decoded bodies of [requests].
  List<Map<String, Object?>> get bodies => <Map<String, Object?>>[
    for (final http.Request request in requests)
      (jsonDecode(request.body) as Map<String, Object?>),
  ];

  /// Every event of every body, in order.
  List<Map<String, Object?>> get events => <Map<String, Object?>>[
    for (final Map<String, Object?> body in bodies)
      for (final Object? event in body['events']! as List<Object?>)
        event! as Map<String, Object?>,
  ];

  /// The names of [events].
  List<String> get eventNames => <String>[
    for (final Map<String, Object?> event in events) event['name']! as String,
  ];

  void reset() => requests.clear();
}

final FakeRelay relay = FakeRelay();

/// The warnings of the clients.
final List<String> warnings = <String>[];

/// Forgets every client and configures the package again against [relay],
/// with a new memory store and the Dart core.
Future<void> configureForTests({
  Duration sessionTimeout = const Duration(minutes: 30),
  String? measurementIdOverride,
}) async {
  await DartFirebaseAnalytics.debugReset();
  relay.reset();
  warnings.clear();
  FirebaseAnalyticsDart.configure(
    transport: AnalyticsTransport.relay(relayUri),
    measurementId: measurementIdOverride,
    store: AnalyticsStore.memory(),
    httpClient: relay.client,
    sessionTimeout: sessionTimeout,
    onWarning: warnings.add,
    useDartCore: true,
  );
}

/// The default app, created on first call.
Future<FirebaseApp> defaultApp() async {
  if (Firebase.apps.isEmpty) {
    return Firebase.initializeApp(options: options);
  }
  return Firebase.app();
}

/// Sends what the client of the default app has queued, and returns the
/// events [relay] has received so far.
Future<List<Map<String, Object?>>> flushed() async {
  await (await FirebaseAnalyticsDart.clientFor(Firebase.app())).flush();
  return relay.events;
}

/// The parameters of the only event [relay] received.
Map<String, Object?> onlyParams(List<Map<String, Object?>> events) {
  expect(events, hasLength(1));
  return events.single['params']! as Map<String, Object?>;
}

/// A [FirebaseException] of `firebase_core` (not the client's exception)
/// with the plugin `firebase_analytics` and [code].
Matcher throwsAnalyticsCode(String code) => throwsA(
  isA<FirebaseException>()
      .having((FirebaseException e) => e.plugin, 'plugin', 'firebase_analytics')
      .having((FirebaseException e) => e.code, 'code', code)
      .having(
        (FirebaseException e) => e.runtimeType,
        'type',
        FirebaseException,
      ),
);
