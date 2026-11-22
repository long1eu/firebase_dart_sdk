// Deleting a FlutterFire app with a firebase_core that, like the native
// implementations on macOS, Windows, Android and iOS, knows nothing of the
// firebase_app_dart app of the same name.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// A core that keeps its apps in memory and deletes only its own app.
class NativeLikeCore extends FirebasePlatform {
  final Map<String, _NativeLikeApp> _apps = <String, _NativeLikeApp>{};

  @override
  List<FirebaseAppPlatform> get apps =>
      List<FirebaseAppPlatform>.unmodifiable(_apps.values);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final String appName = name ?? defaultFirebaseAppName;
    return _apps[appName] ??= _NativeLikeApp(this, appName, options!);
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      _apps[name] ?? (throw noAppExists(name));
}

class _NativeLikeApp extends FirebaseAppPlatform {
  _NativeLikeApp(this._core, super.name, super.options);

  final NativeLikeCore _core;

  @override
  Future<void> delete() async {
    _core._apps.remove(name);
  }
}

void main() {
  registerForTests();

  late FirebasePlatform dartCore;
  setUpAll(() {
    dartCore = FirebasePlatform.instance;
    FirebasePlatform.instance = NativeLikeCore();
  });
  tearDownAll(() => FirebasePlatform.instance = dartCore);

  test(
    'deleting the app closes its client, a new app gets a new one',
    () async {
      const String name = 'native-like';
      final FirebaseApp first = await Firebase.initializeApp(
        name: name,
        options: options,
      );
      await FirebaseDatabase.instanceFor(app: first).goOnline();
      final fs.FirebaseDatabase client = FirebaseDatabaseDart.clientFor(first);

      await first.delete();

      expect(
        dart_app.Firebase.apps.map((dart_app.FirebaseApp app) => app.name),
        contains(name),
        reason: 'this core leaves the firebase_app_dart app alone',
      );
      await expectLater(
        client.ref('a').get(),
        throwsA(
          isA<fs.FirebaseDatabaseException>().having(
            (fs.FirebaseDatabaseException e) => e.code,
            'code',
            'database-closed',
          ),
        ),
      );

      final FirebaseApp again = await Firebase.initializeApp(
        name: name,
        options: options,
      );
      final Future<void> write = FirebaseDatabase.instanceFor(
        app: again,
      ).ref('a').set(1);
      await settle();
      server.ackLastWrite();
      await write;

      expect(createdClients, hasLength(2));
    },
  );
}
