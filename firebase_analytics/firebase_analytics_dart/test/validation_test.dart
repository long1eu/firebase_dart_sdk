import 'dart:convert';

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_analytics_dart/src/limits.dart';
import 'package:firebase_analytics_dart/src/validation.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

int _appCount = 0;

FirebaseApp _newApp() => FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'key',
    appId: '1:123:dart:abc',
    projectId: 'demo-test',
  ),
  name: 'analytics-validation-${_appCount++}',
);

/// Fails unless [future] completes with a [FirebaseAnalyticsException] of [code].
Future<void> _expectCode(Future<void> future, String code) async {
  await expectLater(
    future,
    throwsA(
      isA<FirebaseAnalyticsException>()
          .having((FirebaseAnalyticsException e) => e.code, 'code', code)
          .having(
            (FirebaseAnalyticsException e) => e.plugin,
            'plugin',
            'firebase_analytics',
          ),
    ),
  );
}

void main() {
  late FirebaseApp app;
  late List<http.Request> requests;
  late FirebaseAnalytics analytics;
  late bool closed;

  setUp(() {
    app = _newApp();
    requests = <http.Request>[];
    closed = false;
    analytics = FirebaseAnalytics(
      app,
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 'secret'),
      store: AnalyticsStore.memory(),
      httpClient: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
      onWarning: (_) {},
    );
  });

  tearDown(() async {
    if (!closed) {
      await analytics.close();
    }
    await app.delete();
  });

  /// Closes the client, which sends what is queued, and returns the events that were sent.
  Future<List<Map<String, Object?>>> sentEvents() async {
    await analytics.close();
    closed = true;
    return <Map<String, Object?>>[
      for (final http.Request r in requests)
        for (final Object? e
            in (jsonDecode(r.body) as Map<String, Object?>)['events']! as List)
          e! as Map<String, Object?>,
    ];
  }

  Map<String, Object?> paramsOf(Map<String, Object?> event) =>
      event['params']! as Map<String, Object?>;

  group('event names', () {
    test('40 characters are allowed, 41 are not', () async {
      await analytics.logEvent(name: 'a' * 40);
      await _expectCode(
        analytics.logEvent(name: 'a' * 41),
        'invalid-event-name',
      );
    });

    test('letters, digits and underscores, starting with a letter', () async {
      await analytics.logEvent(name: 'Level_up_2');
      for (final String name in <String>[
        '',
        'level-up',
        'level up',
        'level.up',
        'lével',
        '1level',
        '9',
        'level\n',
      ]) {
        await _expectCode(analytics.logEvent(name: name), 'invalid-event-name');
      }
    });

    test('every reserved name is refused', () async {
      final Set<String> names = <String>{
        ...reservedEventNames,
        'screen_view',
        'ad_impression',
        'in_app_purchase',
        'first_open',
        'session_start',
        'user_engagement',
        'app_exception',
        'notification_receive',
      };
      for (final String name in names) {
        await _expectCode(analytics.logEvent(name: name), 'reserved-name');
      }
    });

    test('the reserved prefixes are refused', () async {
      // `_` is also not a letter, which is checked first.
      await _expectCode(
        analytics.logEvent(name: '_custom'),
        'invalid-event-name',
      );
      for (final String name in <String>[
        'firebase_custom',
        'google_custom',
        'ga_custom',
      ]) {
        await _expectCode(analytics.logEvent(name: name), 'reserved-name');
      }
      // A prefix without its underscore is an ordinary name.
      await analytics.logEvent(name: 'gacustom');
      await analytics.logEvent(name: 'firebasecustom');
    });
  });

  group('parameters', () {
    test('names of 40 characters are allowed, 41 are not', () async {
      await analytics.logEvent(
        name: 'e',
        parameters: <String, Object?>{'p' * 40: 1},
      );
      await _expectCode(
        analytics.logEvent(
          name: 'e',
          parameters: <String, Object?>{'p' * 41: 1},
        ),
        'invalid-parameter',
      );
      for (final String name in <String>['', '1p', 'p-q', 'p q', 'pé']) {
        await _expectCode(
          analytics.logEvent(name: 'e', parameters: <String, Object?>{name: 1}),
          'invalid-parameter',
        );
      }
    });

    test('string values of 100 characters are allowed, 101 are not', () async {
      await analytics.logEvent(
        name: 'e',
        parameters: <String, Object?>{'p': 'a' * 100},
      );
      await _expectCode(
        analytics.logEvent(
          name: 'e',
          parameters: <String, Object?>{'p': 'a' * 101},
        ),
        'invalid-parameter',
      );
    });

    test('lengths are counted in percent-encoded form', () async {
      expect(measuredLength('a'), 1);
      expect(measuredLength('é'), 6);
      expect(measuredLength('é' * 16), 96);
      expect(measuredLength('é' * 17), 102);
      expect(measuredLength(' '), 3);

      await analytics.logEvent(
        name: 'e',
        parameters: <String, Object?>{'p': 'é' * 16},
      );
      await _expectCode(
        analytics.logEvent(
          name: 'e',
          parameters: <String, Object?>{'p': 'é' * 17},
        ),
        'invalid-parameter',
      );
      // 34 spaces measure 102.
      await _expectCode(
        analytics.logEvent(
          name: 'e',
          parameters: <String, Object?>{'p': ' ' * 34},
        ),
        'invalid-parameter',
      );
    });

    test('bool is sent as 1 or 0 and a null value is left out', () async {
      await analytics.logEvent(
        name: 'e',
        parameters: <String, Object?>{
          'yes': true,
          'no': false,
          'gone': null,
          'text': 'x',
          'int': 3,
          'double': 1.5,
        },
      );
      final List<Map<String, Object?>> events = await sentEvents();
      expect(events, hasLength(1));
      final Map<String, Object?> params = paramsOf(events.single);
      expect(params['yes'], 1);
      expect(params['no'], 0);
      expect(params.containsKey('gone'), isFalse);
      expect(params['text'], 'x');
      expect(params['int'], 3);
      expect(params['double'], 1.5);
    });

    test('numbers that are not finite are refused', () async {
      for (final double value in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        await _expectCode(
          analytics.logEvent(
            name: 'e',
            parameters: <String, Object?>{'p': value},
          ),
          'invalid-parameter',
        );
      }
    });

    test('integers beyond 2^53 are refused', () async {
      await analytics.logEvent(
        name: 'e',
        parameters: <String, Object?>{
          'max': 9007199254740991,
          'min': -9007199254740991,
        },
      );
      for (final int value in <int>[9007199254740992, -9007199254740992]) {
        await _expectCode(
          analytics.logEvent(
            name: 'e',
            parameters: <String, Object?>{'p': value},
          ),
          'invalid-parameter',
        );
      }
    });

    test('other types are refused', () async {
      for (final Object value in <Object>[
        <int>[1],
        <String, Object>{'a': 1},
        DateTime(2026),
      ]) {
        await _expectCode(
          analytics.logEvent(
            name: 'e',
            parameters: <String, Object?>{'p': value},
          ),
          'invalid-parameter',
        );
      }
    });

    test('reserved parameter names are refused', () async {
      for (final String name in <String>[
        'firebase_conversion',
        'session_id',
        'engagement_time_msec',
        'firebase_x',
        'google_x',
        'ga_x',
      ]) {
        await _expectCode(
          analytics.logEvent(name: 'e', parameters: <String, Object?>{name: 1}),
          'reserved-name',
        );
        await _expectCode(
          analytics.setDefaultEventParameters(<String, Object?>{name: 1}),
          'reserved-name',
        );
      }
      // `_` and `.` are not allowed by the name pattern, which is checked first.
      for (final String name in <String>['_x', 'gtag.x']) {
        await _expectCode(
          analytics.logEvent(name: 'e', parameters: <String, Object?>{name: 1}),
          'invalid-parameter',
        );
      }
    });

    test('23 parameters are allowed, 24 are not', () async {
      Map<String, Object?> params(int n, [String prefix = 'p']) =>
          <String, Object?>{for (int i = 0; i < n; i++) '$prefix$i': i};

      await analytics.logEvent(name: 'e', parameters: params(23));
      await _expectCode(
        analytics.logEvent(name: 'e', parameters: params(24)),
        'too-many-parameters',
      );
    });

    test('default parameters count against the limit', () async {
      await analytics.setDefaultEventParameters(<String, Object?>{
        for (int i = 0; i < 20; i++) 'd$i': i,
      });
      await analytics.logEvent(
        name: 'e',
        parameters: <String, Object?>{'a': 1, 'b': 2, 'c': 3},
      );
      await _expectCode(
        analytics.logEvent(
          name: 'e',
          parameters: <String, Object?>{'a': 1, 'b': 2, 'c': 3, 'd': 4},
        ),
        'too-many-parameters',
      );
      // An event parameter of a default's name replaces it and does not count twice.
      await analytics.logEvent(
        name: 'e',
        parameters: <String, Object?>{'d0': 1, 'a': 1, 'b': 2, 'c': 3},
      );
      await _expectCode(
        analytics.setDefaultEventParameters(<String, Object?>{
          for (int i = 0; i < 24; i++) 'x$i': i,
        }),
        'too-many-parameters',
      );
    });
  });

  group('items', () {
    test('a list of maps with item_id or item_name', () async {
      await analytics.logEvent(
        name: 'purchase',
        parameters: <String, Object?>{
          'items': <Map<String, Object?>>[
            <String, Object?>{'item_id': 'sku1', 'price': 9.99, 'quantity': 2},
            <String, Object?>{'item_name': 'Shirt', 'on_sale': true},
          ],
        },
      );
      final List<Map<String, Object?>> events = await sentEvents();
      final List<Object?> items = paramsOf(events.single)['items']! as List;
      expect(items, <Object?>[
        <String, Object?>{'item_id': 'sku1', 'price': 9.99, 'quantity': 2},
        <String, Object?>{'item_name': 'Shirt', 'on_sale': 1},
      ]);
    });

    test('an item without item_id or item_name is refused', () async {
      await _expectCode(
        analytics.logEvent(
          name: 'purchase',
          parameters: <String, Object?>{
            'items': <Map<String, Object?>>[
              <String, Object?>{'price': 1},
            ],
          },
        ),
        'invalid-parameter',
      );
      await _expectCode(
        analytics.logEvent(
          name: 'purchase',
          parameters: <String, Object?>{
            'items': <Map<String, Object?>>[
              <String, Object?>{'item_id': null, 'price': 1},
            ],
          },
        ),
        'invalid-parameter',
      );
    });

    test('items that are not a list of maps are refused', () async {
      for (final Object value in <Object>[
        'sku1',
        <String, Object>{'item_id': 'a'},
        <Object>['sku1'],
        <Object>[
          <int, Object>{1: 'a'},
        ],
      ]) {
        await _expectCode(
          analytics.logEvent(
            name: 'purchase',
            parameters: <String, Object?>{'items': value},
          ),
          'invalid-parameter',
        );
      }
    });

    test('item values follow the parameter rules', () async {
      for (final Map<String, Object?> item in <Map<String, Object?>>[
        <String, Object?>{'item_id': 'a' * 101},
        <String, Object?>{'item_id': 'a', 'price': double.nan},
        <String, Object?>{'item_id': 'a', 'p' * 41: 1},
        <String, Object?>{'item_id': 'a', 'items': <Object>[]},
      ]) {
        await _expectCode(
          analytics.logEvent(
            name: 'purchase',
            parameters: <String, Object?>{
              'items': <Object>[item],
            },
          ),
          'invalid-parameter',
        );
      }
      await _expectCode(
        analytics.logEvent(
          name: 'purchase',
          parameters: <String, Object?>{
            'items': <Object>[
              <String, Object?>{'item_id': 'a', 'firebase_x': 1},
            ],
          },
        ),
        'reserved-name',
      );
    });

    test('10 custom item parameters are allowed, 11 are not', () async {
      Map<String, Object?> item(int custom) => <String, Object?>{
        'item_id': 'a',
        'item_name': 'b',
        'price': 1,
        for (int i = 0; i < custom; i++) 'custom$i': i,
      };
      await analytics.logEvent(
        name: 'purchase',
        parameters: <String, Object?>{
          'items': <Object>[item(10)],
        },
      );
      await _expectCode(
        analytics.logEvent(
          name: 'purchase',
          parameters: <String, Object?>{
            'items': <Object>[item(11)],
          },
        ),
        'invalid-parameter',
      );
    });
  });

  group('user properties', () {
    test('names of 24 characters are allowed, 25 are not', () async {
      await analytics.setUserProperty(name: 'p' * 24, value: 'v');
      await _expectCode(
        analytics.setUserProperty(name: 'p' * 25, value: 'v'),
        'invalid-user-property',
      );
      for (final String name in <String>['', '1p', 'p-q', 'pé']) {
        await _expectCode(
          analytics.setUserProperty(name: name, value: 'v'),
          'invalid-user-property',
        );
      }
    });

    test('values of 36 characters are allowed, 37 are not', () async {
      await analytics.setUserProperty(name: 'p', value: 'v' * 36);
      await _expectCode(
        analytics.setUserProperty(name: 'p', value: 'v' * 37),
        'invalid-user-property',
      );
      await analytics.setUserProperty(name: 'p', value: 'é' * 6);
      await _expectCode(
        analytics.setUserProperty(name: 'p', value: 'é' * 7),
        'invalid-user-property',
      );
    });

    test('reserved names and prefixes are refused', () async {
      for (final String name in <String>[
        'user_id',
        'first_open_time',
        'first_visit_time',
        'last_deep_link_referrer',
        'first_open_after_install',
        'firebase_x',
        'google_x',
        'ga_x',
      ]) {
        await _expectCode(
          analytics.setUserProperty(name: name, value: 'v'),
          'reserved-name',
        );
        // Removing is checked the same way.
        await _expectCode(
          analytics.setUserProperty(name: name, value: null),
          'reserved-name',
        );
      }
      await _expectCode(
        analytics.setUserProperty(name: '_x', value: 'v'),
        'invalid-user-property',
      );
    });

    test('at most 25 user properties', () async {
      for (int i = 0; i < AnalyticsLimits.maxUserProperties; i++) {
        await analytics.setUserProperty(name: 'p$i', value: 'v');
      }
      await _expectCode(
        analytics.setUserProperty(name: 'extra', value: 'v'),
        'too-many-user-properties',
      );
      // Changing or removing an existing one is still allowed.
      await analytics.setUserProperty(name: 'p0', value: 'w');
      await analytics.setUserProperty(name: 'p1', value: null);
      await analytics.setUserProperty(name: 'extra', value: 'v');
      await analytics.logEvent(name: 'e');
      final List<http.Request> sent = requests;
      await sentEvents();
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      final Map<String, Object?> properties =
          body['user_properties']! as Map<String, Object?>;
      expect(properties, hasLength(25));
      expect(properties['p0'], <String, Object?>{'value': 'w'});
      expect(properties.containsKey('p1'), isFalse);
      expect(properties['extra'], <String, Object?>{'value': 'v'});
    });
  });

  group('user id', () {
    test('256 characters are allowed, 257 are not', () async {
      await analytics.setUserId('u' * 256);
      await _expectCode(analytics.setUserId('u' * 257), 'invalid-user-id');
      // Counted in percent-encoded form: 43 é measure 258.
      await _expectCode(analytics.setUserId('é' * 43), 'invalid-user-id');
    });

    test('empty is refused and null is allowed', () async {
      await _expectCode(analytics.setUserId(''), 'invalid-user-id');
      await analytics.setUserId('u1');
      await analytics.setUserId(null);
      await analytics.logEvent(name: 'e');
      await sentEvents();
      final Map<String, Object?> body =
          jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body.containsKey('user_id'), isFalse);
    });
  });

  test('the exception is a FirebaseException', () async {
    await expectLater(
      analytics.logEvent(name: ''),
      throwsA(isA<FirebaseException>()),
    );
  });
}
