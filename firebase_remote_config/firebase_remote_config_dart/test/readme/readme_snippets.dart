// GENERATED from the README files by test/readme_snippets_test.dart. Do not edit: change the
// README and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import, unnecessary_import
// ignore_for_file: unused_element

import 'dart:async';
import 'dart:io';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_installations_dart/web.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:rxdart/rxdart.dart';

late FirebaseApp app;
late KeyValueStore store;
late FirebaseInstallations installations;
late FirebaseRemoteConfig remoteConfig;

class AppDependencies extends PlatformDependencies {
  final BehaviorSubject<bool> background = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<bool> connectivity = BehaviorSubject<bool>.seeded(true);

  @override
  BehaviorSubject<bool> get onBackgroundChanged => background;

  @override
  BehaviorSubject<bool> get onNetworkConnected => connectivity;
}

// README.md:62
Future<void> remoteConfigReadmeLine62() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the API key of the app, 39 characters>',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: MemoryKeyValueStore(),
  );
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
    app,
    installations: installations,
    defaults: <String, Object>{'welcome_message': 'Hello', 'max_items': 20},
  );
}

// README.md:98
Future<void> remoteConfigReadmeLine98() async {
  final FetchResult result = await remoteConfig.fetch();
  switch (result) {
    case FetchResult.updated:
      print('A template arrived.');
    case FetchResult.unchanged:
      print('The stored template is current.');
    case FetchResult.cached:
      print('No request: the last fetch is younger than the minimum interval.');
  }
  final bool activated = await remoteConfig.activate();
  print('activated: $activated');
}

// README.md:117
Future<void> remoteConfigReadmeLine117() async {
  final StreamSubscription<void> activations = remoteConfig.onActivated.listen((_) {
    print('New values are active.');
  });
}

// README.md:128
Future<void> remoteConfigReadmeLine128() async {
  await remoteConfig.reset();
  print(remoteConfig.info.lastFetchStatus); // RemoteConfigFetchStatus.noFetchYet
}

// README.md:139
Future<void> remoteConfigReadmeLine139() async {
  final String message = remoteConfig.getString('welcome_message');
  final int maxItems = remoteConfig.getInt('max_items');
  final RemoteConfigValue value = remoteConfig.getValue('welcome_message');
  print('$message, $maxItems, from ${value.source.name}');
}

// README.md:146
Future<void> remoteConfigReadmeLine146() async {
  final List<String> themeKeys = remoteConfig.getKeysByPrefix('theme_');
  final RemoteConfigValue fromDefaults = remoteConfig.getValueFrom(
    'welcome_message',
    ValueSource.valueDefault,
  );
  final Object? layout = remoteConfig.getValue('layout').asJson();
  final List<int> bytes = remoteConfig.getValue('welcome_message').asBytes();
  print('$themeKeys, ${fromDefaults.text}, $layout, ${bytes.length}');
}

// README.md:182
Future<void> remoteConfigReadmeLine182() async {
  await remoteConfig.setCustomSignals(<String, Object?>{
    'subscription_tier': 'pro',
    'app_build': 412,
    'old_signal': null, // removes it
  });
}

// README.md:205
Future<void> remoteConfigReadmeLine205() async {
  final StreamSubscription<RemoteConfigUpdate> subscription = remoteConfig.onConfigUpdated.listen(
    (RemoteConfigUpdate update) async {
      print('Updated: ${update.updatedKeys}');
      await remoteConfig.activate();
    },
    onError: (Object error) => print('Realtime: $error'),
  );
}

// README.md:239
Future<void> remoteConfigReadmeLine239() async {
  final StreamSubscription<Set<RolloutAssignment>> rollouts = remoteConfig.onRolloutsStateChanged.listen(
    (Set<RolloutAssignment> assignments) {
      for (final RolloutAssignment assignment in assignments) {
        print('${assignment.rolloutId}: ${assignment.variantId} (${assignment.parameterKey})');
      }
    },
  );
}

// ../../firebase_installations/firebase_installations_dart/README.md:48
Future<void> installationsReadmeLine48() async {
  Future<void> main() async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: your own key
        appId: '1:1234567890:web:abc',
        projectId: 'my-project',
      ),
    );
    final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final FirebaseInstallations installations = FirebaseInstallations(
      app,
      // HOME is not set on Windows; fall back to USERPROFILE.
      store: FileKeyValueStore('$home/.config/my_tool/firebase'),
    );
    print(await installations.getId());
    await installations.close();
    await installations.store.close();
  }
}

// ../../firebase_installations/firebase_installations_dart/README.md:101
Future<void> installationsReadmeLine101() async {
  final String id = await installations.getId();
}

// ../../firebase_installations/firebase_installations_dart/README.md:110
Future<void> installationsReadmeLine110() async {
  final String token = await installations.getToken();
  final String fresh = await installations.getToken(forceRefresh: true);
  final ({String id, String token}) pair = await installations.getIdAndToken();
}

// ../../firebase_installations/firebase_installations_dart/README.md:122
Future<void> installationsReadmeLine122() async {
  installations.onIdChange.listen((String id) => print('new id: $id'));
}

// ../../firebase_installations/firebase_installations_dart/README.md:131
Future<void> installationsReadmeLine131() async {
  await installations.delete();
}

// ../../firebase_installations/firebase_installations_dart/README.md:141
Future<void> installationsReadmeLine141() async {
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: store,
    headers: const <String, String>{
      'X-Android-Package': 'com.example.app',
      'X-Android-Cert': '0123456789ABCDEF0123456789ABCDEF01234567',
    },
  );
}

// ../../docs/guides/remote_config.md:76
Future<void> remoteConfigGuideLine76() async {
  Future<void> onTheVm() async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
        appId: '1:123456789012:web:0123456789abcdef',
        projectId: 'my-project',
      ),
    );
    final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final FileKeyValueStore store = FileKeyValueStore('$home/.my_app/firebase');
    final FirebaseInstallations installations = FirebaseInstallations(app, store: store);
    final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
      app,
      installations: installations,
      defaults: const <String, Object>{'welcome_message': 'Hello', 'new_checkout': false},
    );

    await remoteConfig.fetchAndActivate();
    print(remoteConfig.getString('welcome_message'));

    await remoteConfig.close();
    await installations.close();
    await store.close();
  }
}

// ../../docs/guides/remote_config.md:111
Future<void> remoteConfigGuideLine111() async {
  Future<void> inTheBrowser(FirebaseApp app) async {
    final KeyValueStore store = IndexedDbKeyValueStore();
    final FirebaseInstallations installations = FirebaseInstallations(app, store: store);
    final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(app, installations: installations);
    await remoteConfig.fetchAndActivate();
  }
}

// ../../docs/guides/remote_config.md:172
Future<void> remoteConfigGuideLine172() async {
  final FirebaseRemoteConfig withDefaults = FirebaseRemoteConfig(
    app,
    installations: installations,
    defaults: const <String, Object>{
      'welcome_message': 'Hello',
      'max_items': 20,
      'ratio': 0.5,
      'new_checkout': false,
    },
  );
}

// ../../docs/guides/remote_config.md:194
Future<void> remoteConfigGuideLine194() async {
  Future<void> refresh(FirebaseRemoteConfig remoteConfig) async {
    final FetchResult result = await remoteConfig.fetch();
    switch (result) {
      case FetchResult.updated:
        print('A new template was stored.');
      case FetchResult.unchanged:
        print('The server says the template has not changed.');
      case FetchResult.cached:
        print('The last fetch is recent enough; no request was sent.');
    }
    final bool activated = await remoteConfig.activate();
    print(activated ? 'New values are active.' : 'Nothing new to activate.');
  }
}

// ../../docs/guides/remote_config.md:223
Future<void> remoteConfigGuideLine223() async {
  Future<void> forceRefresh(FirebaseRemoteConfig remoteConfig) async {
    await remoteConfig.fetch(
      minimumFetchInterval: const Duration(minutes: 5),
      timeout: const Duration(seconds: 20),
    );
  }
}

// ../../docs/guides/remote_config.md:245
Future<void> remoteConfigGuideLine245() async {
  FirebaseRemoteConfig configured(FirebaseApp app, FirebaseInstallations installations) {
    return FirebaseRemoteConfig(
      app,
      installations: installations,
      minimumFetchInterval: const Duration(hours: 1),
      fetchTimeout: const Duration(seconds: 30),
      languageCode: 'en-US',
    );
  }
}

// ../../docs/guides/remote_config.md:262
Future<void> remoteConfigGuideLine262() async {
  void readValues(FirebaseRemoteConfig remoteConfig) {
    final String message = remoteConfig.getString('welcome_message');
    final bool checkout = remoteConfig.getBool('new_checkout');
    final int items = remoteConfig.getInt('max_items');
    final double ratio = remoteConfig.getDouble('ratio');

    final RemoteConfigValue value = remoteConfig.getValue('welcome_message');
    print('$message ${value.source.name} ${value.asBool()} $checkout $items $ratio');

    for (final MapEntry<String, RemoteConfigValue> entry in remoteConfig.getAll().entries) {
      print('${entry.key} = ${entry.value.text} (${entry.value.source.name})');
    }
  }
}

// ../../docs/guides/remote_config.md:282
Future<void> remoteConfigGuideLine282() async {
  void readMore(FirebaseRemoteConfig remoteConfig) {
    final List<String> themeKeys = remoteConfig.getKeysByPrefix('theme_');
    final RemoteConfigValue remoteOnly =
        remoteConfig.getValueFrom('welcome_message', ValueSource.valueRemote);
    final Object? layout = remoteConfig.getValue('layout').asJson();
    final List<int> bytes = remoteConfig.getValue('welcome_message').asBytes();
    print('$themeKeys ${remoteOnly.source.name} $layout ${bytes.length}');
  }
}

// ../../docs/guides/remote_config.md:337
Future<void> remoteConfigGuideLine337() async {
  Future<void> tell(FirebaseRemoteConfig remoteConfig) async {
    await remoteConfig.setCustomSignals(<String, Object?>{
      'plan': 'pro',
      'seats': 12,
      'ratio': 0.25,
      'old_signal': null,
    });
    print(remoteConfig.customSignals);
  }
}

// ../../docs/guides/remote_config.md:364
Future<void> remoteConfigGuideLine364() async {
  StreamSubscription<RemoteConfigUpdate> watch(FirebaseRemoteConfig remoteConfig) {
    return remoteConfig.onConfigUpdated.listen(
      (RemoteConfigUpdate update) async {
        print('Changed: ${update.updatedKeys}');
        await remoteConfig.activate();
      },
      onError: (Object error) {
        if (error is FirebaseRemoteConfigException) {
          print('Realtime problem: ${error.code}');
        }
      },
    );
  }
}

// ../../docs/guides/remote_config.md:397
Future<void> remoteConfigGuideLine397() async {
  FirebaseApp appWithLifecycle(AppDependencies dependencies) {
    return FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
        appId: '1:123456789012:web:0123456789abcdef',
        projectId: 'my-project',
      ),
      dependencies: dependencies,
    );
  }
}

// ../../docs/guides/remote_config.md:510
Future<void> remoteConfigGuideLine510() async {
  Future<void> safeFetch(FirebaseRemoteConfig remoteConfig) async {
    try {
      await remoteConfig.fetchAndActivate();
    } on FirebaseRemoteConfigException catch (error) {
      switch (error.code) {
        case 'fetch-throttle':
          print('Try again after ${error.throttledUntil}.');
        case 'installations-error':
          print('No installation: ${error.cause}');
        default:
          print('${error.code} ${error.httpStatus}');
      }
    }
  }
}

// ../../docs/guides/remote_config.md:547
Future<void> remoteConfigGuideLine547() async {
  FirebaseInstallations restricted(FirebaseApp app, KeyValueStore store) {
    return FirebaseInstallations(
      app,
      store: store,
      headers: const <String, String>{
        'X-Android-Package': 'com.example.app',
        'X-Android-Cert': 'ABCDEF0123456789ABCDEF0123456789ABCDEF01',
      },
    );
  }
}
