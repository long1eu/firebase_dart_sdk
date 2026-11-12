// Helpers of the browser tests: clients made through the public API, against
// the Firestore emulator on 127.0.0.1:8080. No `dart:io` here.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

const String emulatorHost = String.fromEnvironment(
    'FIRESTORE_EMULATOR_HOST_NAME',
    defaultValue: '127.0.0.1');
const int emulatorPort =
    int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8080);
const String projectId =
    String.fromEnvironment('FIRESTORE_PROJECT_ID', defaultValue: 'demo-test');

final Random _random = Random();
int _apps = 0;

/// A new client with its own app and its own cache (in memory unless
/// [openDatabase] is given). It is terminated when the test ends.
Future<Firestore> newClient({OpenDatabase? openDatabase}) async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      applicationId: '1:1234567890:dart:browser',
      projectId: projectId,
    ),
    name: 'browser-${_apps++}-${_random.nextInt(0x7fffffff)}',
  );
  final Firestore firestore = await Firestore.instanceFor(
    app: app,
    openDatabase: openDatabase,
    settings: FirestoreSettings(
            cacheSettings:
                openDatabase == null ? const MemoryCacheSettings() : null)
        .withEmulator(emulatorHost, emulatorPort),
  );
  addTearDown(firestore.terminate);
  return firestore;
}

/// A collection name no other test uses.
String newCollectionName() =>
    'browser-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';

/// Collects the events of [stream] and waits for one that matches.
class EventLog<T> {
  EventLog(Stream<T> stream) {
    _sub = stream.listen((T event) {
      events.add(event);
      _changed.add(null);
    }, onError: (Object error) {
      errors.add(error);
      _changed.add(null);
    });
    addTearDown(cancel);
  }

  final List<T> events = <T>[];
  final List<Object> errors = <Object>[];
  final StreamController<void> _changed = StreamController<void>.broadcast();
  late final StreamSubscription<T> _sub;

  /// The first event (already received or still to come) that [test] accepts.
  Future<T> waitFor(bool Function(T event) test,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final Stopwatch watch = Stopwatch()..start();
    int checked = 0;
    while (true) {
      for (; checked < events.length; checked++) {
        if (test(events[checked])) {
          return events[checked];
        }
      }
      if (errors.isNotEmpty) {
        throw StateError('The stream failed: ${errors.first}');
      }
      final Duration left = timeout - watch.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException(
            'No matching event among ${events.length} events', timeout);
      }
      await _changed.stream.first.timeout(left, onTimeout: () {});
    }
  }

  Future<void> cancel() => _sub.cancel();
}
