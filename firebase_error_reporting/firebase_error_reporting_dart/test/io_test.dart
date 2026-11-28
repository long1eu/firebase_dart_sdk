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

    test('a file over 4 MiB is not read', () async {
      File(
        '${directory.path}/firebase_error_reporting.json',
      ).writeAsBytesSync(List<int>.filled(4 * 1024 * 1024 + 1, 32));
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
