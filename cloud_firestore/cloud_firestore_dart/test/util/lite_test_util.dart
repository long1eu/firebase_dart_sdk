// Helpers of the Firestore Lite integration tests: instances made through the
// public API of `package:cloud_firestore_dart/lite.dart`, against the
// emulator of FIRESTORE_EMULATOR_HOST.

import 'dart:io';

import 'package:cloud_firestore_dart/lite.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart'
    show liteTransportOverride;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'io_web_http_client.dart';
import 'prod_provider/firestore_provider.dart';
import 'test_backend.dart';

/// The reason to skip the Firestore Lite integration tests, or null when the
/// emulator is configured. They never run against a real project.
String? get liteEmulatorSkipReason => TestBackend().emulatorHost != null
    ? null
    : '${TestBackend.emulatorHostVariable} is not set';

/// With `FIRESTORE_TEST_TRANSPORT=rest` (or `webchannel`, the value the
/// suite of the main library uses for its web transport run) Firestore Lite
/// runs over the transport it uses on the web: REST, here over `dart:io`
/// HTTP. Returns whether it is in use.
bool useLiteWebTransportIfRequested() {
  final String? transport = Platform.environment['FIRESTORE_TEST_TRANSPORT'];
  if (transport != 'rest' &&
      transport != 'webchannel' &&
      transport != 'webchannel-longpolling') {
    return false;
  }
  liteTransportOverride =
      (DatabaseInfo databaseInfo, ChannelOptionsProvider options) =>
          RestTransport(IoWebHttpClient(), databaseInfo, options);
  return true;
}

/// The settings for the emulator of FIRESTORE_EMULATOR_HOST.
FirestoreSettings liteEmulatorSettings({Object? mockUserToken}) {
  final EmulatorAddress address = EmulatorAddress.parse(
    TestBackend().emulatorHost!,
  );
  return FirestoreSettings().withEmulator(
    address.host,
    address.port,
    mockUserToken: mockUserToken,
  );
}

/// A new app for the test project. It is deleted when the test ends.
FirebaseApp newLiteTestApp({String? projectId}) {
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: 'fake-api-key',
      applicationId: 'appId',
      projectId: projectId ?? FirestoreProvider().projectId,
    ),
    dependencies: null,
    name: 'lite-${const Uuid().v4()}',
  );
  addTearDown(app.delete);
  return app;
}

/// A new Firestore Lite instance with an app of its own, talking to the
/// emulator. It is terminated when the test ends.
Firestore newLiteTestFirestore({Object? mockUserToken}) {
  useLiteWebTransportIfRequested();
  final Firestore firestore = Firestore.instanceFor(
    app: newLiteTestApp(),
    settings: liteEmulatorSettings(mockUserToken: mockUserToken),
  );
  addTearDown(firestore.terminate);
  return firestore;
}

/// A reference to a collection no other test uses.
CollectionReference<Map<String, Object?>> newLiteTestCollection([
  Firestore? firestore,
]) {
  return (firestore ?? newLiteTestFirestore()).collection(
    'lite-${const Uuid().v4()}',
  );
}

/// A collection no other test uses, with a document for each of [docs]
/// (written in one batch).
Future<CollectionReference<Map<String, Object?>>> newLiteTestCollectionWith(
  List<Map<String, Object?>> docs,
) async {
  final CollectionReference<Map<String, Object?>> collection =
      newLiteTestCollection();
  if (docs.isNotEmpty) {
    final WriteBatch batch = collection.firestore.batch();
    for (final Map<String, Object?> data in docs) {
      batch.set(collection.doc(), data);
    }
    await batch.commit();
  }
  return collection;
}

/// A reference to a document no other test uses, written with [data] if
/// given.
Future<DocumentReference<Map<String, Object?>>> newLiteTestDoc([
  Map<String, Object?>? data,
]) async {
  final DocumentReference<Map<String, Object?>> doc = newLiteTestCollection()
      .doc();
  if (data != null) {
    await doc.set(data);
  }
  return doc;
}
