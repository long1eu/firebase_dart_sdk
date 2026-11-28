// Every method of the official FirebaseAnalytics, driven as an app would,
// down to the request bodies the fake relay receives.

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics_dart/firebase_analytics_dart.dart' as fa;
import 'package:firebase_analytics_dart_platform/firebase_analytics_dart_platform.dart';
import 'package:firebase_analytics_dart_platform/src/firebase_analytics_platform.dart';
import 'package:firebase_analytics_platform_interface/firebase_analytics_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseAnalytics analytics;

  setUp(() async {
    await configureForTests();
    await defaultApp();
    analytics = FirebaseAnalytics.instance;
  });

  group('configuration', () {
    test('the registered platform is the package, one instance per app', () {
      expect(FirebaseAnalyticsDart.isRegistered, isTrue);
      expect(FirebaseAnalyticsPlatform.instance, isA<DartFirebaseAnalytics>());
    });

    test('isSupported is true', () async {
      expect(await analytics.isSupported(), isTrue);
    });

    test('events go to the configured relay with the measurement id of the '
        'app options', () async {
      await analytics.logEvent(name: 'level_up');
      await flushed();
      final Uri url = relay.requests.single.url;
      expect(url.host, relayUri.host);
      expect(url.path, relayUri.path);
      expect(url.queryParameters['measurement_id'], measurementId);
      expect(relay.requests.single.headers['X-Firebase-GMPID'], '1:1:web:1');
    });

    test('configure(measurementId:) wins over the app options', () async {
      await configureForTests(measurementIdOverride: 'G-OTHER9876');
      await analytics.logEvent(name: 'level_up');
      await flushed();
      expect(
        relay.requests.single.url.queryParameters['measurement_id'],
        'G-OTHER9876',
      );
    });

    test('configure after the first client throws a StateError', () async {
      await analytics.setUserId(id: 'u1');
      expect(
        () => FirebaseAnalyticsDart.configure(
          transport: AnalyticsTransport.relay(relayUri),
        ),
        throwsStateError,
      );
    });

    test('without a transport the first call throws a StateError that says '
        'what to do', () async {
      await DartFirebaseAnalytics.debugReset();
      FirebaseAnalyticsDart.configure(useDartCore: true);
      await expectLater(
        analytics.logEvent(name: 'level_up'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('FirebaseAnalyticsDart.configure(transport: ...)'),
          ),
        ),
      );
    });

    test('delegateFor gives one instance and one client per app', () async {
      final FirebaseApp second = await Firebase.initializeApp(
        name: 'second',
        options: options,
      );
      final FirebaseAnalyticsPlatform first =
          FirebaseAnalyticsPlatform.instanceFor(app: Firebase.app());
      final FirebaseAnalyticsPlatform other =
          FirebaseAnalyticsPlatform.instanceFor(app: second);
      expect(other, isNot(same(first)));
      expect(FirebaseAnalyticsPlatform.instanceFor(app: second), same(other));
      final fa.FirebaseAnalytics firstClient =
          await FirebaseAnalyticsDart.clientFor(Firebase.app());
      final fa.FirebaseAnalytics otherClient =
          await FirebaseAnalyticsDart.clientFor(second);
      expect(otherClient, isNot(same(firstClient)));
      expect(otherClient.app.name, 'second');
      expect(
        await FirebaseAnalyticsDart.clientFor(second),
        same(otherClient),
        reason: 'created once, lazily',
      );
    });
  });

  group('events', () {
    test('logEvent reaches the client; callOptions is ignored', () async {
      await analytics.logEvent(
        name: 'level_up',
        parameters: <String, Object>{'level': 3, 'character': 'wizard'},
        callOptions: AnalyticsCallOptions(global: true),
      );
      final Map<String, Object?> params = onlyParams(await flushed());
      expect(relay.eventNames, <String>['level_up']);
      expect(params['level'], 3);
      expect(params['character'], 'wizard');
      expect(params['session_id'], isA<int>());
      expect(params['engagement_time_msec'], isA<int>());
    });

    test('typed helpers arrive as their recommended events', () async {
      await analytics.logLogin(loginMethod: 'password');
      await analytics.logPurchase(
        currency: 'EUR',
        value: 9.5,
        items: <AnalyticsEventItem>[
          AnalyticsEventItem(itemId: 'sku-1', itemName: 'Hat', quantity: 2),
        ],
      );
      final List<Map<String, Object?>> events = await flushed();
      expect(relay.eventNames, <String>['login', 'purchase']);
      expect(
        (events[0]['params']! as Map<String, Object?>)['method'],
        'password',
      );
      final Map<String, Object?> purchase =
          events[1]['params']! as Map<String, Object?>;
      expect(purchase['currency'], 'EUR');
      expect(purchase['value'], 9.5);
      expect(purchase['items'], <Object>[
        <String, Object>{'item_id': 'sku-1', 'item_name': 'Hat', 'quantity': 2},
      ]);
    });

    test('logScreenView is sent as page_view', () async {
      await analytics.logScreenView(
        screenName: 'Settings',
        screenClass: 'SettingsPage',
        parameters: <String, Object>{'tab': 'privacy'},
      );
      final Map<String, Object?> params = onlyParams(await flushed());
      expect(relay.eventNames, <String>['page_view']);
      expect(params['page_title'], 'Settings');
      expect(params['page_location'], 'app://1:1:web:1/Settings');
      expect(params['screen_class'], 'SettingsPage');
      expect(params['tab'], 'privacy');
      expect(params.containsKey('screen_name'), isFalse);
    });

    test(
      'logScreenView without a screen name throws invalid-parameter',
      () async {
        await expectLater(
          analytics.logScreenView(screenClass: 'SettingsPage'),
          throwsAnalyticsCode('invalid-parameter'),
        );
        expect(await flushed(), isEmpty);
      },
    );

    test('logAdImpression throws reserved-name: ad_impression is for app '
        'streams only', () async {
      await expectLater(
        analytics.logAdImpression(
          adPlatform: 'admob',
          currency: 'EUR',
          value: 1,
        ),
        throwsAnalyticsCode('reserved-name'),
      );
      expect(await flushed(), isEmpty);
    });

    test('logInAppPurchase on iOS (the package selected by configure) throws '
        'reserved-name: in_app_purchase is for app streams only', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await expectLater(
        analytics.logInAppPurchase(currency: 'EUR', price: 1, quantity: 1),
        throwsAnalyticsCode('reserved-name'),
      );
      expect(await flushed(), isEmpty);
    });

    test('on Windows and Linux, FirebaseAnalytics itself refuses the iOS-only '
        'methods before they reach the package', () async {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        // logInAppPurchase throws synchronously, the others asynchronously.
        await expectLater(
          () => analytics.logInAppPurchase(
            currency: 'EUR',
            price: 1,
            quantity: 1,
          ),
          throwsUnimplementedError,
        );
        await expectLater(
          () => analytics.logTransaction('1000000000000001'),
          throwsA(
            isA<UnimplementedError>().having(
              (UnimplementedError e) => e.message,
              'message',
              isNot(contains('firebase_analytics_dart_platform')),
            ),
          ),
        );
        await expectLater(
          () => analytics.initiateOnDeviceConversionMeasurementWithEmailAddress(
            'a@example.com',
          ),
          throwsUnimplementedError,
        );
      }
      expect(await flushed(), isEmpty);
    });

    test('a rule of the client surfaces with its code and message', () async {
      // FlutterFire checks the firebase_ prefix only; the client refuses
      // google_ for event names too.
      await expectLater(
        analytics.logEvent(name: 'google_signal'),
        throwsA(
          isA<FirebaseException>()
              .having((FirebaseException e) => e.code, 'code', 'reserved-name')
              .having(
                (FirebaseException e) => e.message,
                'message',
                isNotEmpty,
              ),
        ),
      );
    });

    test(
      'logTransaction reaching the package throws UnimplementedError',
      () async {
        final Matcher unimplemented = throwsA(
          isA<UnimplementedError>().having(
            (UnimplementedError e) => e.message,
            'message',
            contains('StoreKit'),
          ),
        );
        await expectLater(
          FirebaseAnalyticsPlatform.instanceFor(
            app: Firebase.app(),
          ).logTransaction(transactionId: '1000000000000001'),
          unimplemented,
        );
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await expectLater(
          analytics.logTransaction('1000000000000001'),
          unimplemented,
        );
      },
    );

    test('the four on-device conversion methods reaching the package throw '
        'UnimplementedError', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final Matcher unimplemented = throwsA(
        isA<UnimplementedError>().having(
          (UnimplementedError e) => e.message,
          'message',
          contains('on-device conversion measurement'),
        ),
      );
      await expectLater(
        analytics.initiateOnDeviceConversionMeasurementWithEmailAddress(
          'a@example.com',
        ),
        unimplemented,
      );
      await expectLater(
        analytics.initiateOnDeviceConversionMeasurementWithPhoneNumber(
          '+40700000000',
        ),
        unimplemented,
      );
      await expectLater(
        analytics.initiateOnDeviceConversionMeasurementWithHashedEmailAddress(
          'abc',
        ),
        unimplemented,
      );
      await expectLater(
        analytics.initiateOnDeviceConversionMeasurementWithHashedPhoneNumber(
          'abc',
        ),
        unimplemented,
      );
    });
  });

  group('identity and properties', () {
    test('setUserId sets and clears user_id', () async {
      await analytics.setUserId(id: 'user-1');
      await analytics.logEvent(name: 'first');
      await analytics.setUserId();
      await analytics.logEvent(name: 'second');
      await flushed();
      final List<Map<String, Object?>> bodies = relay.bodies;
      expect(bodies, hasLength(2));
      expect(bodies[0]['user_id'], 'user-1');
      expect(bodies[1].containsKey('user_id'), isFalse);
    });

    test('setUserProperty sets and removes a property', () async {
      await analytics.setUserProperty(name: 'plan', value: 'pro');
      await analytics.logEvent(name: 'first');
      await analytics.setUserProperty(name: 'plan', value: null);
      await analytics.logEvent(name: 'second');
      await flushed();
      final List<Map<String, Object?>> bodies = relay.bodies;
      expect(bodies[0]['user_properties'], <String, Object>{
        'plan': <String, Object>{'value': 'pro'},
      });
      expect(bodies[1]['user_properties'], anyOf(isNull, isEmpty));
    });

    test('setDefaultEventParameters adds to every event', () async {
      await analytics.setDefaultEventParameters(<String, Object?>{
        'app_version': '1.4.0',
      });
      await analytics.logEvent(name: 'level_up');
      expect(onlyParams(await flushed())['app_version'], '1.4.0');
    });

    test('appInstanceId is the client_id of the requests; resetAnalyticsData '
        'makes a new one', () async {
      final String? id = await analytics.appInstanceId;
      expect(id, isNotNull);
      await analytics.logEvent(name: 'level_up');
      await flushed();
      expect(relay.bodies.single['client_id'], id);

      await analytics.resetAnalyticsData();
      final String? next = await analytics.appInstanceId;
      expect(next, isNotNull);
      expect(next, isNot(id));
    });

    test('getSessionId is the session_id of the events', () async {
      expect(await analytics.getSessionId(), isNull);
      await analytics.logEvent(name: 'level_up');
      final int? session = await analytics.getSessionId();
      expect(session, isNotNull);
      expect(onlyParams(await flushed())['session_id'], session);
    });
  });

  group('consent and collection', () {
    test('adUserData and adPersonalizationSignals are sent as consent; the '
        'web storage flags are accepted and ignored', () async {
      await analytics.setConsent(
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: true,
        functionalityStorageConsentGranted: false,
        personalizationStorageConsentGranted: false,
        securityStorageConsentGranted: false,
      );
      await analytics.logEvent(name: 'level_up');
      await flushed();
      expect(relay.bodies.single['consent'], <String, Object>{
        'ad_user_data': 'DENIED',
        'ad_personalization': 'GRANTED',
      });
    });

    test('adStorage alone sends no consent', () async {
      await analytics.setConsent(adStorageConsentGranted: false);
      await analytics.logEvent(name: 'level_up');
      await flushed();
      expect(relay.bodies.single.containsKey('consent'), isFalse);
    });

    test(
      'analyticsStorage denied: nothing is sent and appInstanceId is null',
      () async {
        await analytics.setConsent(analyticsStorageConsentGranted: false);
        await analytics.logEvent(name: 'level_up');
        expect(await analytics.appInstanceId, isNull);
        expect(await analytics.getSessionId(), isNull);
        expect(await flushed(), isEmpty);

        await analytics.setConsent(analyticsStorageConsentGranted: true);
        await analytics.logEvent(name: 'level_up');
        expect(await flushed(), hasLength(1));
      },
    );

    test('setAnalyticsCollectionEnabled(false) stops sending', () async {
      await analytics.logEvent(name: 'queued');
      await analytics.setAnalyticsCollectionEnabled(false);
      await analytics.logEvent(name: 'dropped');
      expect(await flushed(), isEmpty);

      await analytics.setAnalyticsCollectionEnabled(true);
      await analytics.logEvent(name: 'sent');
      await flushed();
      expect(relay.eventNames, <String>['sent']);
    });
  });

  group('setSessionTimeoutDuration', () {
    test('before the first event it creates the client again with the new '
        'timeout and keeps the state', () async {
      await analytics.setUserId(id: 'user-1');
      final fa.FirebaseAnalytics before = await FirebaseAnalyticsDart.clientFor(
        Firebase.app(),
      );
      expect(before.sessionTimeout, const Duration(minutes: 30));

      await analytics.setSessionTimeoutDuration(const Duration(minutes: 5));
      final fa.FirebaseAnalytics after = await FirebaseAnalyticsDart.clientFor(
        Firebase.app(),
      );
      expect(after, isNot(same(before)));
      expect(after.sessionTimeout, const Duration(minutes: 5));

      await analytics.logEvent(name: 'level_up');
      await flushed();
      expect(relay.bodies.single['user_id'], 'user-1');
    });

    test('before any client exists it only sets the timeout', () async {
      await analytics.setSessionTimeoutDuration(const Duration(minutes: 7));
      final fa.FirebaseAnalytics client = await FirebaseAnalyticsDart.clientFor(
        Firebase.app(),
      );
      expect(client.sessionTimeout, const Duration(minutes: 7));
    });

    test('after the first event it throws a StateError', () async {
      await analytics.logEvent(name: 'level_up');
      await expectLater(
        analytics.setSessionTimeoutDuration(const Duration(minutes: 5)),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('before the first logEvent'),
          ),
        ),
      );
      final fa.FirebaseAnalytics client = await FirebaseAnalyticsDart.clientFor(
        Firebase.app(),
      );
      expect(client.sessionTimeout, const Duration(minutes: 30));
    });

    test('a refused event counts as the first event too', () async {
      await expectLater(
        analytics.logAdImpression(adPlatform: 'admob'),
        throwsAnalyticsCode('reserved-name'),
      );
      await expectLater(
        analytics.setSessionTimeoutDuration(const Duration(minutes: 5)),
        throwsStateError,
      );
    });

    test('a timeout that is not positive throws an ArgumentError', () async {
      await expectLater(
        analytics.setSessionTimeoutDuration(Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('app lifecycle', () {
    test(
      'going inactive sends the queue; resumed counts as active again',
      () async {
        final TestWidgetsFlutterBinding binding =
            TestWidgetsFlutterBinding.instance;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await analytics.logEvent(name: 'level_up');
        expect(relay.requests, isEmpty, reason: 'waiting for the batch delay');

        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        // setAppActive(false) flushes without being awaited.
        for (int i = 0; i < 20 && relay.requests.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(relay.eventNames, <String>['level_up']);

        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await analytics.logEvent(name: 'next');
        expect(relay.eventNames, <String>['level_up'], reason: 'active again');
        await flushed();
        expect(relay.eventNames, <String>['level_up', 'next']);
      },
    );
  });
}
