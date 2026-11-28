import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:test/test.dart';

void main() {
  final ErrorEvent full = ErrorEvent(
    eventTime: DateTime.utc(2026, 11, 28, 10),
    message: 'StateError: Bad state\n    at main (package:a/main.dart:1:1)',
    fingerprint: 'StateError|package:a/main.dart:1',
    reportLocation: const SourceLocation(
      filePath: 'package:a/main.dart',
      lineNumber: 1,
      functionName: 'main',
    ),
    user: 'user-1',
    httpRequest: const HttpRequestContext(
      method: 'GET',
      url: 'https://example.com/a',
      responseStatusCode: 500,
    ),
    fatal: true,
  );

  test('the report JSON is a ReportedErrorEvent', () {
    expect(
      full.toReportJson(service: 'svc', version: '1.0.0'),
      <String, Object?>{
        'eventTime': '2026-11-28T10:00:00.000Z',
        'serviceContext': <String, Object?>{
          'service': 'svc',
          'version': '1.0.0',
        },
        'message': full.message,
        'context': <String, Object?>{
          'user': 'user-1',
          'httpRequest': <String, Object?>{
            'method': 'GET',
            'url': 'https://example.com/a',
            'responseStatusCode': 500,
          },
          'reportLocation': <String, Object?>{
            'filePath': 'package:a/main.dart',
            'lineNumber': 1,
            'functionName': 'main',
          },
        },
      },
    );
  });

  test(
    'no resourceType, no context when there is none, no version when null',
    () {
      final ErrorEvent bare = ErrorEvent(
        eventTime: DateTime.utc(2026),
        message: 'm',
        fingerprint: 'f',
      );
      final Map<String, Object?> json = bare.toReportJson(service: 'svc');
      expect(
        json.keys,
        unorderedEquals(<String>['eventTime', 'serviceContext', 'message']),
      );
      expect(json['serviceContext'], <String, Object?>{'service': 'svc'});
    },
  );

  test('the store JSON round-trips', () {
    expect(ErrorEvent.fromStoreJson(full.toStoreJson()), full);
    final ErrorReportingState state = ErrorReportingState(
      user: 'u',
      collectionEnabled: false,
      queue: <ErrorEvent>[full],
    );
    final ErrorReportingState back = ErrorReportingState.fromJson(
      state.toJson(),
    );
    expect(back.user, 'u');
    expect(back.collectionEnabled, isFalse);
    expect(back.queue, <ErrorEvent>[full]);
  });

  test('stored events that cannot be read are skipped', () {
    final ErrorReportingState state = ErrorReportingState.fromJson(
      <String, Object?>{
        'queue': <Object?>[
          42,
          const <String, Object?>{'message': 'no time'},
          const <String, Object?>{'eventTime': 'not a date', 'message': 'm'},
          full.toStoreJson(),
        ],
      },
    );
    expect(state.queue, <ErrorEvent>[full]);
    expect(() => ErrorReportingState.fromJson('nope'), throwsFormatException);
  });

  test('copyWith replaces and clears fields', () {
    final ErrorEvent scrubbed = full.copyWith(
      message: 'x',
      clearUser: true,
      clearHttpRequest: true,
    );
    expect(scrubbed.message, 'x');
    expect(scrubbed.user, isNull);
    expect(scrubbed.httpRequest, isNull);
    expect(scrubbed.reportLocation, full.reportLocation);
    expect(scrubbed.fatal, isTrue);
  });

  test('toString shows the header only', () {
    expect(full.toString(), 'ErrorEvent(StateError: Bad state)');
  });
}
