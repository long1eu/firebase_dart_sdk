// Pins the as-built rows A10, A11, A13, A15, A28 and A29 of remote_config.v4-asbuilt.md that no other
// test pins.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/src/bounded.dart';
import 'package:firebase_remote_config_dart/src/exception.dart';
import 'package:firebase_remote_config_dart/src/fetch_client.dart';
import 'package:firebase_remote_config_dart/src/realtime/framer.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/rc_realtime_fakes.dart';
import 'support/rc_realtime_harness.dart';

/// [seconds] as a [Duration], fractions allowed.
Duration s(num seconds) => Duration(microseconds: (seconds * 1000000).round());

Future<http.StreamedResponse> _refuse503(RealtimeConnection connection) =>
    connection.refuse(503);

/// Never answers: the server holds the headers back.
Future<http.StreamedResponse> _noHeaders(RealtimeConnection connection) =>
    Completer<http.StreamedResponse>().future;

/// Answers 503 at once and then stalls in the middle of the error body.
Future<http.StreamedResponse> _stalledErrorBody(RealtimeConnection connection) {
  final StreamController<List<int>> body = StreamController<List<int>>()
    ..add(utf8.encode('{"error":'));
  return Future<http.StreamedResponse>.value(
    http.StreamedResponse(body.stream, 503, request: connection.request),
  );
}

void main() {
  group('A10 watchdog starts when the request is sent', () {
    test('A10 a server that sends no headers for 330 s is cut; the end is '
        'clean, so the next connect waits only the floor', () {
      fakeAsync((FakeAsync async) {
        final DirectRealtime d = DirectRealtime(async);
        d.server.realtimeAnswer = _noHeaders;
        final UpdateLog log = d.listen();
        final RealtimeConnection first = d.server.last;

        d.elapseTo(s(329.9));
        expect(first.aborted, isFalse, reason: 'no byte yet, but not 330 s');
        d.elapseTo(s(330));
        expect(first.aborted, isTrue);

        d.elapseTo(s(330.9));
        expect(d.server.connections, hasLength(1));
        d.elapseTo(s(331));
        expect(d.server.connections, hasLength(2));
        expect(log.errors, isEmpty);
        d.dispose();
      });
    });

    test('A10 the watchdog also cuts a non-200 body that stalls, with that '
        'status\'s outcome (503: the 2-minute server wait)', () {
      fakeAsync((FakeAsync async) {
        final DirectRealtime d = DirectRealtime(async);
        d.server.realtimeAnswer = (RealtimeConnection connection) =>
            connection.openedAt == rcEpoch
            ? _stalledErrorBody(connection)
            : connection.accept();
        final UpdateLog log = d.listen();
        final RealtimeConnection first = d.server.last;

        d.elapseTo(s(329.9));
        expect(first.aborted, isFalse);
        d.elapseTo(s(330));
        expect(first.aborted, isTrue);

        d.elapseTo(s(449.9));
        expect(
          d.server.connections,
          hasLength(1),
          reason: 'a server failure waits 2 minutes, not the floor',
        );
        d.elapseTo(s(450));
        expect(d.server.connectionTimes, <Duration>[Duration.zero, s(450)]);
        expect(log.errors, isEmpty, reason: '503 is retried without an error');
        d.dispose();
      });
    });
  });

  group('A11 network true events', () {
    test('A11 a repeated true does nothing; only false then true clears the '
        'backoff', () {
      fakeAsync((FakeAsync async) {
        final DirectRealtime d = DirectRealtime(async);
        d.server.realtimeAnswer = _refuse503;
        d.listen();
        expect(d.server.connections, hasLength(1));

        d.elapseTo(s(10));
        d.network.add(true);
        d.network.add(true);
        async.elapse(Duration.zero);
        expect(
          d.server.connections,
          hasLength(1),
          reason: 'true after the seed true is not a change',
        );

        d.elapseTo(s(20));
        d.network.add(false);
        d.network.add(true);
        async.elapse(Duration.zero);
        expect(d.server.connections, hasLength(2));
        expect(d.server.connectionTimes.last, s(20));

        // The second 503 waits 4 minutes (the failure count stayed); true events do not end it.
        d.elapseTo(s(30));
        d.network.add(true);
        d.network.add(true);
        async.elapse(Duration.zero);
        expect(d.server.connections, hasLength(2));

        d.elapseTo(s(40));
        d.network.add(false);
        async.elapse(Duration.zero);
        expect(
          d.server.connections,
          hasLength(2),
          reason: 'false opens nothing',
        );
        d.network.add(true);
        async.elapse(Duration.zero);
        expect(d.server.connectionTimes, <Duration>[
          Duration.zero,
          s(20),
          s(40),
        ]);
        d.dispose();
      });
    });

    test('A11 repeated true events while the server asked for a wait do not '
        'shorten it', () {
      fakeAsync((FakeAsync async) {
        final DirectRealtime d = DirectRealtime(async);
        d.server.realtimeAnswer = (RealtimeConnection connection) =>
            connection.openedAt == rcEpoch
            ? connection.acceptAndClose()
            : connection.accept();
        d.listen();
        d.elapseTo(s(0.5));
        for (int i = 0; i < 5; i++) {
          d.network.add(true);
        }
        async.elapse(Duration.zero);

        // A transport failure at 0 s waits 1 s; five true events change nothing.
        expect(d.server.connections, hasLength(1));
        d.elapseTo(s(0.999));
        expect(d.server.connections, hasLength(1));
        d.elapseTo(s(1));
        expect(d.server.connections, hasLength(2));
        d.dispose();
      });
    });
  });

  group('A13 stored records on load', () {
    final DateTime now = DateTime.utc(2026, 11, 28, 12);

    String record(Map<String, Object?> changes) => jsonEncode(<String, Object?>{
      'v': 1,
      'entries': <String, String>{'a': '1'},
      'fetchTime': now.millisecondsSinceEpoch,
      ...changes,
    });

    for (final Object? bad in <Object?>[
      -1,
      9007199254740992,
      '9007199254740992',
      '00000000000000001',
      '-1',
      1.5,
      'abc',
      true,
    ]) {
      test('A13 a stored templateVersion of ${jsonEncode(bad)} makes the '
          'record absent', () {
        expect(
          TemplateRecord.tryParse(
            record(<String, Object?>{'templateVersion': bad}),
            now: now,
          ),
          isNull,
        );
      });
    }

    test('A13 a stored templateVersion of 0 and of 2^53 - 1 is kept', () {
      expect(
        TemplateRecord.tryParse(
          record(<String, Object?>{'templateVersion': 0}),
        )!.templateVersion,
        0,
      );
      expect(
        TemplateRecord.tryParse(
          record(<String, Object?>{'templateVersion': 9007199254740991}),
        )!.templateVersion,
        9007199254740991,
      );
    });

    test('A13 a fetch time later than now is clamped to now on load', () {
      final TemplateRecord? future = TemplateRecord.tryParse(
        record(<String, Object?>{
          'fetchTime': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        }),
        now: now,
      );
      expect(future!.fetchTime, now);
    });

    test('A13 a fetch time equal to or before now is kept', () {
      final DateTime earlier = now.subtract(const Duration(days: 3));
      expect(
        TemplateRecord.tryParse(
          record(<String, Object?>{
            'fetchTime': earlier.millisecondsSinceEpoch,
          }),
          now: now,
        )!.fetchTime,
        earlier,
      );
      expect(
        TemplateRecord.tryParse(
          record(<String, Object?>{}),
          now: now,
        )!.fetchTime,
        now,
      );
    });

    test('A13 a fetch time outside +-8.64e15 ms makes the record absent, one '
        'before the epoch within it is kept', () {
      for (final int millis in <int>[8640000000000001, -8640000000000001]) {
        expect(
          TemplateRecord.tryParse(
            record(<String, Object?>{'fetchTime': millis}),
            now: now,
          ),
          isNull,
        );
      }
      expect(
        TemplateRecord.tryParse(
          record(<String, Object?>{'fetchTime': -1000}),
          now: now,
        )!.fetchTime.millisecondsSinceEpoch,
        -1000,
      );
    });

    test('A13 the last fetch time of the meta record goes through the same '
        'bounds: out of range is absent, a future one is dropped', () {
      String meta(Object? time) => jsonEncode(<String, Object?>{
        'v': 1,
        'lastFetchStatus': 'success',
        'staleGeneration': 0,
        'lastSuccessfulFetchTime': time,
      });

      expect(MetaRecord.tryParse(meta(8640000000000001), now), isNull);
      expect(MetaRecord.tryParse(meta('abc'), now), isNull);
      expect(
        MetaRecord.tryParse(
          meta(now.add(const Duration(minutes: 1)).millisecondsSinceEpoch),
          now,
        )!.lastSuccessfulFetchTime,
        isNull,
      );
      expect(
        MetaRecord.tryParse(
          meta(now.millisecondsSinceEpoch),
          now,
        )!.lastSuccessfulFetchTime,
        now,
      );
    });

    test('A13 the end of a stored throttle window beyond 24 h is clamped; '
        'one out of range makes the record absent', () {
      String throttle(Object? until) =>
          jsonEncode(<String, Object?>{'v': 1, 'count': 2, 'until': until});

      expect(
        ThrottleRecord.tryParse(
          throttle(now.add(const Duration(days: 30)).millisecondsSinceEpoch),
          now,
        )!.until,
        now.add(const Duration(hours: 24)),
      );
      expect(ThrottleRecord.tryParse(throttle(8640000000000001), now), isNull);
    });
  });

  group('A15 featureDisabled in a message', () {
    FramerEvent only(String body) {
      final List<FramerEvent> events = RealtimeFramer().add(body);
      expect(events, hasLength(1));
      return events.single;
    }

    test('A15 a present featureDisabled of null is invalid', () {
      expect(only('{"featureDisabled":null}'), isA<FramedInvalid>());
      expect(
        only('{"featureDisabled":null,"latestTemplateVersionNumber":3}'),
        isA<FramedInvalid>(),
      );
    });

    for (final String wrong in <String>['"true"', '1', '0', '[]', '{}']) {
      test('A15 featureDisabled $wrong (not a bool) is invalid', () {
        expect(only('{"featureDisabled":$wrong}'), isA<FramedInvalid>());
      });
    }

    test('A15 featureDisabled true wins over a malformed version and a '
        'malformed retry interval', () {
      final FramerEvent event = only(
        '{"featureDisabled":true,"latestTemplateVersionNumber":"abc",'
        '"retryIntervalSeconds":[1]}',
      );

      expect(event, isA<FramedMessage>());
      final RealtimeMessage message = (event as FramedMessage).message;
      expect(message.featureDisabled, isTrue);
      expect(message.latestTemplateVersion, isNull);
      expect(message.retryIntervalSeconds, isNull);
    });

    test('A15 featureDisabled true wins over a wrong-typed version', () {
      final FramerEvent event = only(
        '{"latestTemplateVersionNumber":true,"featureDisabled":true}',
      );

      expect((event as FramedMessage).message.featureDisabled, isTrue);
    });

    test('A15 featureDisabled false does not hide a malformed field', () {
      expect(
        only('{"featureDisabled":false,"latestTemplateVersionNumber":"abc"}'),
        isA<FramedInvalid>(),
      );
    });
  });

  group('A28 numbers and the framer limit', () {
    RealtimeMessage message(String body) {
      final List<FramerEvent> events = RealtimeFramer().add(body);
      expect(events, hasLength(1));
      expect(events.single, isA<FramedMessage>());
      return (events.single as FramedMessage).message;
    }

    for (final String ignored in <String>['1e400', '-5', '0', '1.5', '"abc"']) {
      test('A28 retryIntervalSeconds $ignored is ignored; the message and its '
          'version stay valid', () {
        final RealtimeMessage read = message(
          '{"latestTemplateVersionNumber":7,"retryIntervalSeconds":$ignored}',
        );

        expect(read.retryIntervalSeconds, isNull);
        expect(read.latestTemplateVersion, 7);
        expect(read.featureDisabled, isFalse);
      });
    }

    test('A28 a whole-valued JSON number (1.0, 1e3, 2.0e0) parses as an int '
        'in the message fields', () {
      expect(
        message('{"latestTemplateVersionNumber":1.0}').latestTemplateVersion,
        1,
      );
      expect(
        message('{"latestTemplateVersionNumber":1e3}').latestTemplateVersion,
        1000,
      );
      expect(
        message('{"retryIntervalSeconds":1e3}').retryIntervalSeconds,
        1000,
      );
      expect(message('{"retryIntervalSeconds":2.0e0}').retryIntervalSeconds, 2);
    });

    test('A28 a whole-valued JSON number parses as an int in parseBoundedInt; '
        'a fraction does not', () {
      expect(parseBoundedInt(1.0, min: 0, max: 10), 1);
      expect(parseBoundedInt(1e3, min: 0, max: 10000), 1000);
      expect(parseBoundedInt(jsonDecode('1e3'), min: 0, max: 10000), 1000);
      expect(parseBoundedInt(jsonDecode('5.0'), min: 0, max: 10), 5);
      expect(parseBoundedInt(1.5, min: 0, max: 10), isNull);
      expect(
        parseBoundedInt(double.infinity, min: 0, max: maxSafeInteger),
        isNull,
      );
      expect(parseBoundedInt(double.nan, min: 0, max: 10), isNull);
    });

    test('A28 a retryIntervalSeconds above the range clamps to 86400', () {
      expect(
        message('{"retryIntervalSeconds":1e20}').retryIntervalSeconds,
        86400,
      );
      expect(
        message('{"retryIntervalSeconds":86401}').retryIntervalSeconds,
        86400,
      );
    });

    // A message is "{" + content + "}": content = 5 characters for `"x":"`, the body, and 1 for `"`.
    String padded(String unit, int units) => '{"x":"${unit * units}"}';

    test('A28 the limit counts UTF-16 characters: 16384 characters between '
        'the braces are a message, 16385 are an overflow', () {
      final List<FramerEvent> within = RealtimeFramer().add(
        padded('a', 16384 - 6),
      );
      expect(within.single, isA<FramedMessage>());

      final List<FramerEvent> over = RealtimeFramer().add(
        padded('a', 16385 - 6),
      );
      expect(over.single, isA<FramedOverflow>());
    });

    test('A28 a character of three UTF-8 bytes counts once', () {
      // 16378 euro signs are 49 KB of UTF-8 but 16384 UTF-16 characters of content.
      final List<FramerEvent> within = RealtimeFramer().add(
        padded('€', 16384 - 6),
      );
      expect(within.single, isA<FramedMessage>());

      final List<FramerEvent> over = RealtimeFramer().add(
        padded('€', 16385 - 6),
      );
      expect(over.single, isA<FramedOverflow>());
    });

    test('A28 a character outside the BMP counts twice (two UTF-16 units)', () {
      // 8189 emoji are 16378 UTF-16 characters: 16384 with the 6 around them.
      final List<FramerEvent> within = RealtimeFramer().add(
        padded('\u{1F600}', 8189),
      );
      expect(within.single, isA<FramedMessage>());

      final List<FramerEvent> over = RealtimeFramer().add(
        padded('\u{1F600}', 8190),
      );
      expect(
        over.single,
        isA<FramedOverflow>(),
        reason: '16386 UTF-16 characters, though only 8196 code points',
      );
    });

    test('A28 the limit holds across chunks', () {
      final RealtimeFramer framer = RealtimeFramer();
      final String body = padded('€', 16385 - 6);
      final List<FramerEvent> events = <FramerEvent>[
        ...framer.add(body.substring(0, 9000)),
        ...framer.add(body.substring(9000)),
      ];

      expect(events.single, isA<FramedOverflow>());
    });
  });

  group('A29 fetch answers', () {
    final DateTime fetchedAt = DateTime.utc(2026, 11, 28, 12);

    /// What a fetch to a server answering [body] with [status] and [headers] produces.
    Future<FetchOutcome> fetch(
      String body, {
      int status = 200,
      Map<String, String> headers = const <String, String>{},
      List<String>? drops,
    }) {
      final MockClient client = MockClient.streaming(
        (http.BaseRequest request, http.ByteStream requestBody) async =>
            http.StreamedResponse(
              Stream<List<int>>.value(utf8.encode(body)),
              status,
              headers: <String, String>{
                'content-type': 'application/json',
                ...headers,
              },
            ),
      );
      final FetchClient fetchClient = FetchClient(
        client: client,
        origin: Uri.parse('https://fetch.rc.test'),
        projectId: 'demo-gap',
        apiKey: 'AIzaSyGapKey',
        appId: '1:1:web:1',
        extraHeaders: const <String, String>{},
        clock: () => fetchedAt,
        onDrop: drops?.add,
      );
      return fetchClient.fetch(
        const FetchRequest(
          installationId: 'fAAAAAAAAAAAAAAAAAAAAA',
          installationToken: 'token',
          languageCode: 'en',
          customSignals: <String, String>{},
          fetchType: 'BASE/1',
          deadline: Duration(seconds: 60),
        ),
      );
    }

    FirebaseRemoteConfigException failure(FetchOutcome outcome) {
      expect(outcome, isA<FetchFailed>());
      return (outcome as FetchFailed).error;
    }

    TemplateRecord updated(FetchOutcome outcome) {
      expect(outcome, isA<FetchUpdated>());
      return (outcome as FetchUpdated).record;
    }

    test('A29 an unknown state is fetch-client-parse', () async {
      for (final String state in <String>['FUTURE_STATE', 'update', '']) {
        final FirebaseRemoteConfigException error = failure(
          await fetch(
            jsonEncode(<String, Object?>{
              'state': state,
              'entries': <String, String>{'a': '1'},
            }),
          ),
        );

        expect(error.code, 'fetch-client-parse', reason: 'state "$state"');
        expect(error.httpStatus, 200);
      }
    });

    test('A29 a state that is not a string is fetch-client-parse', () async {
      for (final Object bad in <Object>[
        1,
        true,
        <String>['UPDATE'],
      ]) {
        expect(
          failure(
            await fetch(jsonEncode(<String, Object?>{'state': bad})),
          ).code,
          'fetch-client-parse',
        );
      }
    });

    test('A29 "state": null is absent: the body is an UPDATE', () async {
      final TemplateRecord record = updated(
        await fetch('{"state":null,"entries":{"a":"1"},"templateVersion":"4"}'),
      );

      expect(record.entries, <String, String>{'a': '1'});
      expect(record.templateVersion, 4);
      expect(record.fetchTime, fetchedAt);
    });

    test('A29 an ASCII ETag is stored', () async {
      final TemplateRecord record = updated(
        await fetch(
          '{"entries":{}}',
          headers: <String, String>{'etag': 'W/"abc-123"'},
        ),
      );

      expect(record.etag, 'W/"abc-123"');
    });

    test(
      'A29 a non-ASCII ETag is not stored; the fetch still succeeds',
      () async {
        final TemplateRecord record = updated(
          await fetch(
            '{"entries":{"a":"1"}}',
            headers: <String, String>{'etag': 'W/"café"'},
          ),
        );

        expect(record.etag, isNull);
        expect(record.entries, <String, String>{'a': '1'});
      },
    );

    test('A29 an ETag with a control character, an empty one and one over '
        '1024 characters are not stored', () {
      for (final String etag in <String>[
        'a\u0001b',
        '',
        'e' * 1025,
        '\u007f',
      ]) {
        expect(validEtag(etag), isNull, reason: 'etag of ${etag.length}');
      }
      expect(validEtag('e' * 1024), 'e' * 1024);
      expect(
        TemplateRecord.tryParse(
          jsonEncode(<String, Object?>{
            'v': 1,
            'entries': <String, String>{},
            'fetchTime': 0,
            'etag': 'café',
          }),
        )!.etag,
        isNull,
      );
    });

    test('A29 missing metadata fields are tolerated: a rollout without '
        'affectedParameterKeys keeps an empty list, an experiment without '
        'optional fields is kept, nothing is dropped', () async {
      final List<String> drops = <String>[];
      final TemplateRecord record = updated(
        await fetch(
          jsonEncode(<String, Object?>{
            'entries': <String, String>{'a': '1'},
            'experimentDescriptions': <Object?>[
              <String, Object?>{'experimentId': 'exp1', 'variantId': 'v1'},
            ],
            'rolloutMetadata': <Object?>[
              <String, Object?>{'rolloutId': 'r1', 'variantId': 'v1'},
            ],
            'personalizationMetadata': <String, Object?>{
              'a': <String, Object?>{},
            },
          }),
          drops: drops,
        ),
      );

      expect(drops, isEmpty);
      expect(record.rolloutMetadata, hasLength(1));
      expect(record.rolloutMetadata.single['affectedParameterKeys'], isEmpty);
      expect(record.rolloutMetadata.single['rolloutId'], 'r1');
      // SPEC: A29 says affectedParameterKeys -> []; for experiments the code leaves the key out
      // (only rollouts get []). The item is kept; the expectation is the tolerance.
      expect(record.experimentDescriptions, hasLength(1));
      expect(record.experimentDescriptions.single['experimentId'], 'exp1');
      expect(record.experimentDescriptions.single['variantId'], 'v1');
      expect(record.personalizationMetadata, <String, Map<String, Object?>>{
        'a': <String, Object?>{},
      });
    });

    test(
      'A29 an experimentStartTime that is not RFC 3339 is kept as sent',
      () async {
        final List<String> drops = <String>[];
        final TemplateRecord record = updated(
          await fetch(
            jsonEncode(<String, Object?>{
              'entries': <String, String>{},
              'experimentDescriptions': <Object?>[
                <String, Object?>{
                  'experimentId': 'exp1',
                  'variantId': 'v1',
                  'experimentStartTime': 'last tuesday',
                  'affectedParameterKeys': <String>['a'],
                },
              ],
            }),
            drops: drops,
          ),
        );

        expect(drops, isEmpty);
        expect(
          record.experimentDescriptions.single['experimentStartTime'],
          'last tuesday',
        );
        expect(
          record.experimentDescriptions.single['affectedParameterKeys'],
          <String>['a'],
        );
      },
    );

    test(
      'A29 an experiment without its ids is dropped alone and reported',
      () async {
        final List<String> drops = <String>[];
        final TemplateRecord record = updated(
          await fetch(
            jsonEncode(<String, Object?>{
              'entries': <String, String>{},
              'experimentDescriptions': <Object?>[
                <String, Object?>{'variantId': 'v1'},
                <String, Object?>{'experimentId': 'exp2', 'variantId': 'v2'},
              ],
            }),
            drops: drops,
          ),
        );

        expect(drops, isNotEmpty);
        expect(record.experimentDescriptions, hasLength(1));
        expect(record.experimentDescriptions.single['experimentId'], 'exp2');
      },
    );
  });
}
