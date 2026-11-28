import 'dart:convert';

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_analytics_dart/src/device.dart' show languageOf;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

int _apps = 0;

Future<Map<String, Object?>> _sentBody({AnalyticsDevice? device}) async {
  final List<http.Request> requests = <http.Request>[];
  final FirebaseAnalytics analytics = FirebaseAnalytics(
    FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        appId: '1:123:web:abc',
        projectId: 'demo-test',
      ),
      name: 'analytics-device-${_apps++}',
    ),
    measurementId: 'G-TEST1234',
    transport: AnalyticsTransport.direct(apiSecret: 'secret'),
    device: device,
    onWarning: (_) {},
    httpClient: MockClient((http.Request request) async {
      requests.add(request);
      return http.Response('', 204);
    }),
  );
  await analytics.logEvent(name: 'level_up');
  await analytics.close();
  return jsonDecode(requests.single.body) as Map<String, Object?>;
}

void main() {
  test('no device block is sent by default', () async {
    // Strict validation refused a partial block (docs/analytics_protocol.md, section 7).
    expect((await _sentBody()).containsKey('device'), isFalse);
  });

  test(
    'a device block passed to the constructor is sent as given, without empty fields',
    () async {
      final Map<String, Object?> body = await _sentBody(
        device: const AnalyticsDevice(
          category: 'desktop',
          model: 'Box',
          browser: ' ',
          brand: 'B\nX',
        ),
      );
      expect(body['device'], <String, String>{
        'category': 'desktop',
        'model': 'Box',
        'brand': 'BX',
      });
    },
  );

  test('an empty device block sends nothing', () async {
    expect(
      (await _sentBody(device: const AnalyticsDevice())).containsKey('device'),
      isFalse,
    );
  });

  test('languageOf reads ISO 639-1 locale names', () {
    expect(languageOf('en_US.UTF-8'), 'en-US');
    expect(languageOf('de-DE'), 'de-DE');
    expect(languageOf('fr'), 'fr');
    expect(languageOf('C'), isNull);
    expect(languageOf('fil_PH'), isNull);
  });

  test('detect does not throw and gives the operating system on the VM', () {
    final AnalyticsDevice device = AnalyticsDevice.detect();
    expect(device.operatingSystem, isNotNull);
  }, testOn: 'vm');
}
