// The disk cache across a restart of the app, in two runs of the test (two
// processes) with the same CACHE_DIR and RUN_ID:
//
//   # 1. online: push a note through the UI, wait for the server.
//   flutter test integration_test/disk_cache_test.dart -d windows \
//     --dart-define=DISK_CACHE=true --dart-define=CACHE_DIR=C:\tmp\ffdw \
//     --dart-define=RUN_ID=r1 --dart-define=PHASE=write
//   # 2. a new process offline from the start (stop the emulator too, to be
//   #    sure): the note comes from the SQLite file.
//   flutter test integration_test/disk_cache_test.dart -d windows \
//     --dart-define=DISK_CACHE=true --dart-define=CACHE_DIR=C:\tmp\ffdw \
//     --dart-define=RUN_ID=r1 --dart-define=PHASE=read \
//     --dart-define=START_OFFLINE=true
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfire_database_on_windows/bootstrap.dart';
import 'package:flutterfire_database_on_windows/main.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

const String phase = String.fromEnvironment('PHASE', defaultValue: 'write');
const String runId = String.fromEnvironment('RUN_ID', defaultValue: 'r1');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('disk cache, phase $phase', (WidgetTester tester) async {
    expect(AppConfig.diskCache, isTrue, reason: 'run with DISK_CACHE=true');
    await bootstrap();
    await tester.pumpWidget(const FlutterfireDatabaseOnWindowsApp());
    final String text = 'persisted-$runId';

    if (phase == 'write') {
      await pumpUntil(tester, connection('Connected'));
      await typeInto(tester, 'noteField', text);
      await tester.tap(byKey('pushButton'));
      await pumpUntil(tester, find.text(text));
      // A read from the server after the write: the server has it, and the
      // client has had the acknowledgement, which removes it from the
      // pending writes on disk and keeps it in the cached data.
      expect(await serverNotes(text), isNotEmpty);
    } else {
      expect(AppConfig.startOffline, isTrue);
      // The previous process may still hold the lease of the file; the new
      // one takes it after one observation period (about 7.5 s).
      await pumpUntil(
        tester,
        find.text(text),
        timeout: const Duration(seconds: 45),
      );
      expect(connection('Offline'), findsOneWidget);
    }
  });
}
