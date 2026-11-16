// The disk cache across a restart of the app, in two runs of the test (two
// processes) with the same CACHE_DIR and RUN_ID:
//
//   # 1. online: write a document through the UI, wait for the server.
//   flutter test integration_test/disk_cache_test.dart -d linux \
//     --dart-define=DISK_CACHE=true --dart-define=CACHE_DIR=/tmp/ffl-cache \
//     --dart-define=RUN_ID=r1 --dart-define=PHASE=write
//   # 2. a new process with the network disabled from the start (stop the
//   #    emulator too, to be sure): the document comes from the SQLite file.
//   flutter test integration_test/disk_cache_test.dart -d linux \
//     --dart-define=DISK_CACHE=true --dart-define=CACHE_DIR=/tmp/ffl-cache \
//     --dart-define=RUN_ID=r1 --dart-define=PHASE=read \
//     --dart-define=START_OFFLINE=true
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfire_on_linux/bootstrap.dart';
import 'package:flutterfire_on_linux/main.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

const String phase = String.fromEnvironment('PHASE', defaultValue: 'write');
const String runId = String.fromEnvironment('RUN_ID', defaultValue: 'r1');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('disk cache, phase $phase', (WidgetTester tester) async {
    expect(AppConfig.diskCache, isTrue, reason: 'run with DISK_CACHE=true');
    await bootstrap();
    await tester.pumpWidget(const FlutterfireOnLinuxApp());
    final String title = 'persisted-$runId';

    if (phase == 'write') {
      await pumpUntil(tester, statusContains('isFromCache: false'));
      await tester.enterText(byKey('titleField'), title);
      await tester.tap(byKey('addButton'));
      await pumpUntil(tester, find.text(title));
      await pumpUntil(tester, statusContains('hasPendingWrites: false'));
    } else {
      expect(AppConfig.startOffline, isTrue);
      await pumpUntil(tester, find.text(title));
      expect(statusContains('isFromCache: true'), findsOneWidget);
    }
  });
}
