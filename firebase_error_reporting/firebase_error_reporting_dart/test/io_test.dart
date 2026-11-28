@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:firebase_error_reporting_dart/io.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void _failLater(Object? _) {
  Future<void>(() => throw StateError('in the isolate'));
}

void main() {
  late Directory directory;
  setUp(
    () => directory = Directory.systemTemp.createTempSync('error_reporting_'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  group('FileErrorReportingStore', () {
    test('starts empty and round-trips the state', () async {
      final FileErrorReportingStore store = FileErrorReportingStore(directory);
      expect((await store.load()).queue, isEmpty);
      final ErrorEvent event = ErrorEvent(
        eventTime: DateTime.utc(2026, 11, 28),
        message: 'StateError: x',
        fingerprint: 'f',
      );
      await store.save(
        ErrorReportingState(
          user: 'u',
          collectionEnabled: true,
          queue: <ErrorEvent>[event],
        ),
      );
      final ErrorReportingState back = await FileErrorReportingStore(
        directory,
      ).load();
      expect(back.user, 'u');
      expect(back.collectionEnabled, isTrue);
      expect(back.queue, <ErrorEvent>[event]);
      expect(
        File(
          '${directory.path}/firebase_error_reporting.json.tmp',
        ).existsSync(),
        isFalse,
      );
    });

    test('a corrupt file throws, so the reporter starts empty', () async {
      File(
        '${directory.path}/firebase_error_reporting.json',
      ).writeAsStringSync('{not json');
      expect(FileErrorReportingStore(directory).load(), throwsFormatException);
    });

    test('a file over 8 MiB is not read', () async {
      File('${directory.path}/firebase_error_reporting.json').writeAsBytesSync(
        List<int>.filled(FileErrorReportingStore.maxFileBytes + 1, 32),
      );
      expect(
        FileErrorReportingStore(directory).load(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('a reporter on the file sends the queue of an earlier run', () async {
      final Server failing = Server(<int>[503]);
      final ErrorReporter first = ErrorReporter(
        newApp(),
        service: 's',
        transport: ErrorReportingTransport.direct(apiKey: 'k'),
        store: FileErrorReportingStore(directory),
        httpClient: failing.client,
        onDiagnostic: (_) {},
      );
      await first.recordError(StateError('kept'), appStack);
      await first.close(timeout: const Duration(seconds: 1));

      final Server working = Server();
      final ErrorReporter second = ErrorReporter(
        newApp(),
        service: 's',
        transport: ErrorReportingTransport.direct(apiKey: 'k'),
        store: FileErrorReportingStore(directory),
        httpClient: working.client,
        onDiagnostic: (_) {},
      );
      await second.flush();
      expect(working.requests.single.message, contains('Bad state: kept'));
      await second.close();
    });
  });

  test(
    'C2: concurrent saves leave a readable file holding every event',
    () async {
      final List<String> diagnostics = <String>[];
      final ErrorReporter reporter = ErrorReporter(
        newApp(),
        service: 's',
        transport: ErrorReportingTransport.direct(apiKey: 'k'),
        store: FileErrorReportingStore(directory),
        httpClient: Server(<int>[503]).client,
        sendDelay: const Duration(hours: 1),
        maxQueueLength: 1000,
        maxEventsPerMinute: 1000,
        maxSimilarEventsPerMinute: 1000,
        onDiagnostic: diagnostics.add,
      );
      for (int round = 0; round < 30; round++) {
        await Future.wait(<Future<void>>[
          for (int i = 0; i < 10; i++)
            reporter.recordError(
              StateError('e$round-$i'),
              StackTrace.fromString(
                '#0      f (package:a/a.dart:${i + 1}:1)\n',
              ),
            ),
        ]);
        final ErrorReportingState saved = await FileErrorReportingStore(
          directory,
        ).load();
        expect(
          saved.queue,
          hasLength((round + 1) * 10),
          reason: 'round $round',
        );
      }
      expect(
        directory.listSync().where(
          (FileSystemEntity e) => e.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
      expect(diagnostics, isEmpty);
    },
  );

  test(
    'C4: a state over the limit is saved without its oldest events, and can be read back',
    () async {
      final FileErrorReportingStore store = FileErrorReportingStore(directory);
      final String big = '"\\' * (40 * 1024);
      await store.save(
        ErrorReportingState(
          queue: <ErrorEvent>[
            for (int i = 0; i < 100; i++)
              ErrorEvent(
                eventTime: DateTime.utc(2026, 11, 28, 0, 0, i),
                message: '$i $big',
                fingerprint: 'f',
              ),
          ],
        ),
      );
      final File file = File('${directory.path}/firebase_error_reporting.json');
      expect(
        file.lengthSync(),
        lessThanOrEqualTo(FileErrorReportingStore.maxFileBytes),
      );
      final ErrorReportingState back = await store.load();
      expect(back.queue, isNotEmpty);
      expect(back.queue.last.message, startsWith('99 '));
    },
  );

  test('watchIsolate records the uncaught errors of another isolate', () async {
    final Server server = Server();
    final ErrorReporter reporter = ErrorReporter(
      newApp(),
      service: 's',
      transport: ErrorReportingTransport.direct(apiKey: 'k'),
      httpClient: server.client,
      sendDelay: Duration.zero,
      onDiagnostic: (_) {},
    );
    final Isolate isolate = await Isolate.spawn(
      _failLater,
      null,
      paused: true,
      errorsAreFatal: false,
    );
    final void Function() stop = reporter.watchIsolate(isolate);
    isolate.resume(isolate.pauseCapability!);
    for (int i = 0; i < 100 && server.requests.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    stop();
    isolate.kill();
    expect(
      server.requests.single.message,
      startsWith('IsolateError: Bad state: in the isolate'),
    );
    await reporter.close();
  });
}
