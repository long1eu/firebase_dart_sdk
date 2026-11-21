// Drives the app on the desktop device against the Storage emulator:
//
//   flutter test integration_test/app_test.dart -d linux \
//     --dart-define=EMULATOR_PORT=9199 --dart-define=FOLDER=ffs-test
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfire_storage_on_linux/bootstrap.dart';
import 'package:flutterfire_storage_on_linux/main.dart';
import 'package:integration_test/integration_test.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// Pumps frames until [finder] finds something, or fails after [timeout].
/// `pumpAndSettle` does not fit: the network answers outside the frames.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(bootstrap);

  // Each test starts from an empty folder.
  setUp(() async {
    final ListResult existing = await FirebaseStorage.instance
        .ref(AppConfig.folder)
        .listAll();
    for (final Reference item in existing.items) {
      await item.delete();
    }
  });

  testWidgets('upload through the UI, see it listed, delete it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireStorageOnLinuxApp());
    await pumpUntil(tester, find.text('No images yet'));

    await tester.tap(byKey('uploadButton'));
    await pumpUntil(tester, find.textContaining('Uploaded sample-'));

    final ListResult listed = await FirebaseStorage.instance
        .ref(AppConfig.folder)
        .listAll();
    expect(listed.items, hasLength(1));
    final FullMetadata metadata = await listed.items.single.getMetadata();
    expect(metadata.contentType, 'image/png');
    expect(metadata.size, greaterThan(256 * 1024));
    await pumpUntil(tester, byKey('image-${listed.items.single.name}'));

    await tester.tap(byKey('delete-${listed.items.single.name}'));
    await pumpUntil(tester, find.text('No images yet'));
    expect(
      (await FirebaseStorage.instance.ref(AppConfig.folder).listAll()).items,
      isEmpty,
    );
  });
}
