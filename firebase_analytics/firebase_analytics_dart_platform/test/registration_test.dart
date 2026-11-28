// The registration, the lifecycle hook before the binding exists and the
// default store, in a file of their own: they must run before anything else
// installs the package or initializes the binding.

import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics_dart_platform/firebase_analytics_dart_platform.dart';
import 'package:firebase_analytics_dart_platform/src/core.dart';
import 'package:firebase_analytics_dart_platform/src/firebase_analytics_platform.dart';
import 'package:firebase_analytics_dart_platform/src/lifecycle.dart';
import 'package:firebase_analytics_platform_interface/firebase_analytics_platform_interface.dart'
    show FirebaseAnalyticsPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform, MethodChannelFirebase;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'harness.dart';

/// A path_provider that answers the application support directory with
/// [supportPath].
class FakePathProvider extends PathProviderPlatform {
  FakePathProvider(this.supportPath);

  final String supportPath;

  /// The number of `getApplicationSupportPath` calls.
  int calls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    return supportPath;
  }
}

void main() {
  late Directory support;

  setUpAll(() {
    support = Directory.systemTemp.createTempSync('analytics_adapter_support_');
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
    support.deleteSync(recursive: true);
  });

  test('the pubspec registers FirebaseAnalyticsDart on Windows and Linux, '
      'where firebase_analytics has no implementation', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('implements: firebase_analytics\n'));
    for (final String platform in <String>['linux', 'windows']) {
      expect(
        pubspec,
        contains(
          '      $platform:\n        dartPluginClass: FirebaseAnalyticsDart\n',
        ),
        reason: platform,
      );
    }
    for (final String platform in <String>['android', 'ios', 'macos', 'web']) {
      expect(pubspec, isNot(contains('      $platform:\n')), reason: platform);
    }
  });

  test('registerWith on Windows registers the package and leaves '
      'firebase_core, which has a Windows implementation, alone', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(FirebaseAnalyticsDart.isRegistered, isFalse);

    FirebaseAnalyticsDart.registerWith();
    expect(FirebaseAnalyticsDart.isRegistered, isTrue);
    expect(FirebaseAnalyticsPlatform.instance, isA<DartFirebaseAnalytics>());
    expect(FirebasePlatform.instance, isA<MethodChannelFirebase>());

    // configure keeps the registration and, on Windows, the core.
    final FirebaseAnalyticsPlatform registered =
        FirebaseAnalyticsPlatform.instance;
    FirebaseAnalyticsDart.configure(
      transport: AnalyticsTransport.relay(relayUri),
    );
    expect(FirebaseAnalyticsPlatform.instance, same(registered));
    expect(FirebasePlatform.instance, isA<MethodChannelFirebase>());
  });

  test('registerWith on Linux under flutter test leaves firebase_core alone; '
      'configure installs the Dart core there; a replaced instance is '
      'registered again by configure', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FirebaseAnalyticsPlatform.instance = DartFirebaseAnalytics();
    expect(FirebaseAnalyticsDart.isRegistered, isFalse);

    FirebaseAnalyticsDart.registerWith();
    expect(FirebaseAnalyticsDart.isRegistered, isTrue);
    expect(FirebasePlatform.instance, isA<MethodChannelFirebase>());

    FirebaseAnalyticsPlatform.instance = DartFirebaseAnalytics();
    FirebaseAnalyticsDart.configure(
      transport: AnalyticsTransport.relay(relayUri),
    );
    expect(FirebaseAnalyticsDart.isRegistered, isTrue);
    expect(FirebasePlatform.instance, isA<LinuxFirebaseCore>());
    final FirebasePlatform core = FirebasePlatform.instance;
    installCoreIfNeeded(force: true);
    expect(FirebasePlatform.instance, same(core), reason: 'kept, with apps');
  });

  test('before the binding exists the calls work; the lifecycle hook starts '
      'with the first call after it exists. Without configure(store:) the '
      'state is kept in firebase_dart_analytics under the application '
      'support directory', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final FakePathProvider paths = FakePathProvider(support.path);
    PathProviderPlatform.instance = paths;
    FirebaseAnalyticsDart.configure(
      transport: AnalyticsTransport.relay(relayUri),
      httpClient: relay.client,
    );
    await Firebase.initializeApp(options: options);
    final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

    await analytics.setUserId(id: 'user-1');
    await analytics.logEvent(name: 'before_binding');
    expect(
      AppActivity.instance.isAttached,
      isFalse,
      reason: 'no binding yet, and nothing thrown',
    );

    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await analytics.logEvent(name: 'after_binding');
    expect(AppActivity.instance.isAttached, isTrue);
    expect(AppActivity.instance.active, isTrue);

    await flushed();
    expect(relay.eventNames, <String>['before_binding', 'after_binding']);
    expect(relay.bodies.first['user_id'], 'user-1');

    final Directory store = Directory(
      '${support.path}${Platform.pathSeparator}firebase_dart_analytics',
    );
    expect(store.existsSync(), isTrue);
    expect(
      store.listSync().whereType<File>().where(
        (File file) => file.path.endsWith('.json'),
      ),
      isNotEmpty,
    );
    expect(paths.calls, 1, reason: 'the directory is looked up once');
  });
}
