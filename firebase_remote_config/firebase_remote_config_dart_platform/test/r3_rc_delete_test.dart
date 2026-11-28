// Round 3: deleting and re-creating apps on the Linux (Dart) core (spec 5.12,
// as-built A18). The native-style core is in r3_rc_native_core_test.dart.

@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart'
    as rc;
import 'package:firebase_remote_config_dart_platform/src/firebase_remote_config_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';
import 'harness.dart';

/// The adapter instance behind [app].
DartFirebaseRemoteConfig platformOf(FirebaseApp app) =>
    DartFirebaseRemoteConfig.forApp(app);

/// A service whose dispose holds `FirebaseApp.delete` between the disposal of
/// the services and the delete of the app.
final class _HoldDelete implements FirebaseService {}

/// Options with another app id than [options].
const FirebaseOptions otherOptions = FirebaseOptions(
  apiKey: apiKey,
  appId: '1:1:web:2',
  messagingSenderId: '1',
  projectId: projectId,
);

final RemoteConfigSettings noInterval = RemoteConfigSettings(
  fetchTimeout: const Duration(seconds: 60),
  minimumFetchInterval: Duration.zero,
);

/// Lets pending work run, in real time steps of 10 ms, until [condition]
/// holds or 1 s has passed.
Future<void> waitFor(bool Function() condition) async {
  for (int i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  registerForTests();

  test('A18 a read or fetch during the delete window gets defaults or internal '
      'and creates no clients; after the delete and a re-create, a use '
      'creates clients again', () async {
    final FirebaseApp app = await newApp();
    final DartFirebaseRemoteConfig platform = platformOf(app);
    await platform.setDefaults(<String, dynamic>{'greeting': 'default'});
    backend.entries = <String, String>{'greeting': 'remote'};
    expect(await platform.fetchAndActivate(), isTrue);
    expect(platform.getString('greeting'), 'remote');
    final rc.FirebaseRemoteConfig before = platform.client;

    final Completer<void> hold = Completer<void>();
    app.registerService<_HoldDelete>(
      _HoldDelete(),
      dispose: (_HoldDelete _) => hold.future,
    );
    final Future<void> deleting = app.delete();
    await Future<void>.delayed(Duration.zero);
    final int requests = backend.requests.length;

    // The services are disposed, the app is still listed.
    expect(Firebase.app(app.name).name, app.name);
    expect(platform.getString('greeting'), 'default');
    expect(platform.getValue('greeting').source, ValueSource.valueDefault);
    expect(platform.getAll().keys, <String>['greeting']);
    expect(platform.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
    expect(
      platform.lastFetchTime,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    await expectLater(platform.fetch(), throwsRemoteConfigCode('internal'));
    await expectLater(
      platform.fetchAndActivate(),
      throwsRemoteConfigCode('internal'),
    );
    expect(() => platform.client, throwsA(isRemoteConfigCode('internal')));
    expect(backend.requests, hasLength(requests), reason: 'no new clients');

    hold.complete();
    await deleting;
    expect(() => platform.client, throwsA(isA<FirebaseException>()));

    final FirebaseApp again = await Firebase.initializeApp(
      name: app.name,
      options: options,
    );
    expect(platformOf(again), same(platform));
    final rc.FirebaseRemoteConfig after = platform.client;
    expect(after, isNot(same(before)));
    expect(platform.client, same(after));
    await platform.setConfigSettings(noInterval);
    backend.entries = <String, String>{'greeting': 'again'};
    final int fetches = backend.fetches.length;
    expect(await platform.fetchAndActivate(), isTrue);
    expect(backend.fetches, hasLength(fetches + 1));
    expect(platform.getString('greeting'), 'again');
    await again.delete();
  });

  test('A18 Firebase.app().delete() of the default app off the web throws; '
      'the client stays identical and an onConfigUpdated subscription stays '
      'open', () async {
    final FirebaseApp app = await Firebase.initializeApp(options: options);
    final DartFirebaseRemoteConfig platform = platformOf(app);
    final rc.FirebaseRemoteConfig before = platform.client;
    final List<Object> errors = <Object>[];
    bool done = false;
    final StreamSubscription<RemoteConfigUpdate> subscription =
        FirebaseRemoteConfig.instance.onConfigUpdated.listen(
          (RemoteConfigUpdate _) {},
          onError: errors.add,
          onDone: () => done = true,
        );
    await waitFor(() => backend.openStreams.isNotEmpty);
    expect(backend.openStreams, hasLength(1));

    await expectLater(
      Firebase.app().delete(),
      throwsA(isA<FirebaseException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(platform.client, same(before));
    expect(platformOf(Firebase.app()).client, same(before));
    expect(backend.openStreams, hasLength(1), reason: 'not aborted');
    expect(backend.to(realtimeHost), hasLength(1), reason: 'no reconnect');
    expect(errors, isEmpty);
    expect(done, isFalse);

    // The client still works.
    await platform.setConfigSettings(noInterval);
    backend.entries = <String, String>{'greeting': 'still'};
    expect(await platform.fetchAndActivate(), isTrue);
    expect(platform.getString('greeting'), 'still');

    // Not awaited: the cancel future can complete outside this zone.
    unawaited(subscription.cancel());
  });

  test('A18 on the Linux core a re-create with other options gets new '
      'clients', () async {
    final FirebaseApp app = await newApp();
    final rc.FirebaseRemoteConfig before = platformOf(app).client;
    await app.delete();

    final FirebaseApp again = await Firebase.initializeApp(
      name: app.name,
      options: otherOptions,
    );
    final DartFirebaseRemoteConfig platform = platformOf(again);
    final rc.FirebaseRemoteConfig after = platform.client;
    expect(after, isNot(same(before)));
    expect(after.app, isNot(same(before.app)));
    expect(after.app.options.appId, otherOptions.appId);

    backend.entries = <String, String>{'greeting': 'other'};
    await platform.fetch();
    expect(backend.fetches.last.json['app_id'], otherOptions.appId);
    expect(await platform.activate(), isTrue);
    expect(platform.getString('greeting'), 'other');
    await again.delete();
  });
}
