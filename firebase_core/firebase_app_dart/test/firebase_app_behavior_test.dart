// ignore_for_file: close_sinks, cascade_invocations

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/src/platform_dependencies.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

const FirebaseOptions _options =
    FirebaseOptions(apiKey: 'k', applicationId: 'app');

class _Deps extends PlatformDependencies {
  final BehaviorSubject<bool> background = BehaviorSubject<bool>.seeded(false);

  @override
  BehaviorSubject<bool> get onBackgroundChanged => background;
}

class _FailingTokenProvider implements InternalTokenProvider {
  int calls = 0;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) {
    calls++;
    return Future<GetTokenResult>.error(StateError('no token'));
  }

  @override
  Stream<InternalTokenResult> get onTokenChanged =>
      const Stream<InternalTokenResult>.empty();

  @override
  String? get uid => null;
}

void main() {
  tearDown(FirebaseApp.clearInstancesForTest);

  group('registry', () {
    test('instance throws until the default app exists', () {
      expect(() => FirebaseApp.instance, throwsStateError);
      final FirebaseApp app = FirebaseApp.withOptions(_options);
      expect(FirebaseApp.instance, same(app));
      expect(app.isDefaultApp, isTrue);
    });

    test('getInstance lists the available names, sorted', () {
      FirebaseApp.withOptions(_options, name: 'b');
      FirebaseApp.withOptions(_options, name: 'a');
      expect(
          () => FirebaseApp.getInstance('c'),
          throwsA(isA<StateError>().having((StateError e) => e.message,
              'message', contains('Available app names: a, b.'))));
    });

    test('names are trimmed', () {
      final FirebaseApp app = FirebaseApp.withOptions(_options, name: ' x ');
      expect(app.name, 'x');
      expect(FirebaseApp.getInstance('x  '), same(app));
      expect(app.isDefaultApp, isFalse);
    });

    test('equality is by name and toString names the app', () {
      final FirebaseApp app = FirebaseApp.withOptions(_options, name: 'n');
      expect(app, equals(FirebaseApp.getInstance('n')));
      expect(app.hashCode, 'n'.hashCode * 31);
      expect(app.toString(), contains('n'));
    });
  });

  group('data collection', () {
    test('defaults to enabled and persists changes in the dependency storage',
        () async {
      final _Deps deps = _Deps();
      final FirebaseApp app =
          FirebaseApp.withOptions(_options, dependencies: deps);
      expect(app.dataCollectionDefaultEnabled, isTrue);

      final List<bool> changes = <bool>[];
      final StreamSubscription<bool> sub =
          app.onDataCollectionChange.listen(changes.add);
      app.setDataCollectionDefaultEnabled(enabled: false);
      // Setting the same value again is not a change.
      app.setDataCollectionDefaultEnabled(enabled: false);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(changes, <bool>[false]);
      expect(app.dataCollectionDefaultEnabled, isFalse);
      expect(deps.get('firebase_data_collection_default_enabled'), 'false');

      // A new app over the same storage starts from the persisted value.
      app.delete();
      final FirebaseApp again =
          FirebaseApp.withOptions(_options, dependencies: deps);
      expect(again.dataCollectionDefaultEnabled, isFalse);
    });

    test('a deleted app refuses data collection calls', () {
      final FirebaseApp app = FirebaseApp.withOptions(_options);
      app.delete();
      expect(() => app.dataCollectionDefaultEnabled, throwsStateError);
      expect(() => app.setDataCollectionDefaultEnabled(enabled: false),
          throwsStateError);
      expect(() => app.setAutomaticResourceManagementEnabled(enabled: true),
          throwsStateError);
    });
  });

  group('automatic resource management', () {
    test('toggling it while in the background re-announces the state',
        () async {
      final _Deps deps = _Deps();
      final FirebaseApp app =
          FirebaseApp.withOptions(_options, dependencies: deps);
      deps.background.add(true);

      final List<bool> events = <bool>[];
      final StreamSubscription<bool> sub =
          app.onBackgroundChanged.skip(1).listen(events.add);
      app.setAutomaticResourceManagementEnabled(enabled: true);
      app.setAutomaticResourceManagementEnabled(enabled: true); // no change
      app.setAutomaticResourceManagementEnabled(enabled: false);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, <bool>[true, false]);
    });

    test('toggling it in the foreground emits nothing', () async {
      final _Deps deps = _Deps();
      final FirebaseApp app =
          FirebaseApp.withOptions(_options, dependencies: deps);
      final List<bool> events = <bool>[];
      final StreamSubscription<bool> sub =
          app.onBackgroundChanged.skip(1).listen(events.add);
      app.setAutomaticResourceManagementEnabled(enabled: true);
      app.setAutomaticResourceManagementEnabled(enabled: false);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isEmpty);
    });
  });

  group('default platform dependencies', () {
    test('the app is its own in-memory storage', () async {
      final FirebaseApp app = FirebaseApp.withOptions(_options);
      expect(app.storage, same(app));
      await app.storage.set('a', '1');
      expect(app.storage.get('a'), '1');
      await app.storage.set('a', null);
      expect(app.storage.get('a'), isNull);
      expect(await app.headersBuilder(), isEmpty);
      expect(app.appCheckProvider, isNull);
    });

    test('without a token provider token calls fail with a StateError',
        () async {
      final FirebaseApp app = FirebaseApp.withOptions(_options);
      expect(app.authProvider, same(app));
      await expectLater(app.authProvider.getAccessToken(forceRefresh: false),
          throwsStateError);
      expect(() => app.authProvider.uid, throwsStateError);
      expect(await app.authProvider.onTokenChanged.isEmpty, isTrue);
    });

    test('setting a failing token provider does not leak its warm-up error',
        () async {
      final FirebaseApp app = FirebaseApp.withOptions(_options);
      final _FailingTokenProvider provider = _FailingTokenProvider();
      // An unhandled asynchronous error would fail this test.
      app.authProvider = provider;
      await Future<void>.delayed(Duration.zero);
      expect(provider.calls, 1);
      expect(app.authProvider, same(provider));
    });

    test('PlatformDependencies defaults', () async {
      final PlatformDependencies deps = PlatformDependencies();
      expect(deps.onBackgroundChanged.value, isFalse);
      expect(deps.onNetworkConnected.value, isTrue);
      expect(deps.headersBuilder, isNull);
      expect(deps.authProvider, isNull);
      expect(deps.appCheckProvider, isNull);
      expect(deps.storage, same(deps));
      await deps.set('k', 'v');
      expect(deps.get('k'), 'v');
      await deps.set('k', null);
      expect(deps.get('k'), isNull);
    });
  });
}
