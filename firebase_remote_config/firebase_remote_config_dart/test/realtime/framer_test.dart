import 'dart:convert';

import 'package:firebase_remote_config_dart/src/realtime/framer.dart';
import 'package:test/test.dart';

/// Feeds decoded text to the framer as the realtime client does: UTF-8 with malformed input allowed,
/// decoded chunk by chunk, so a character split across chunks is joined before it reaches the framer.
final class _Pipeline {
  _Pipeline() {
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_TextSink(_onText));
  }

  final RealtimeFramer framer = RealtimeFramer();
  final List<FramerEvent> events = <FramerEvent>[];
  final StringBuffer text = StringBuffer();
  late final ByteConversionSink _decoder;

  void _onText(String chunk) {
    text.write(chunk);
    events.addAll(framer.add(chunk));
  }

  /// Adds one chunk of body bytes and returns the events it completed.
  List<FramerEvent> add(List<int> bytes) {
    final int before = events.length;
    _decoder.add(bytes);
    return events.sublist(before);
  }

  void close() => _decoder.close();
}

final class _TextSink implements Sink<String> {
  _TextSink(this._onText);

  final void Function(String text) _onText;

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}
}

/// The events of [body] given to a fresh framer in one chunk.
List<FramerEvent> _frame(String body) => RealtimeFramer().add(body);

/// The events of [body] sent as UTF-8 bytes in one chunk through the decoding pipeline.
List<FramerEvent> _frameBytes(String body) {
  final _Pipeline pipeline = _Pipeline();
  final List<FramerEvent> events = pipeline.add(utf8.encode(body));
  pipeline.close();
  return events;
}

RealtimeMessage _onlyMessage(List<FramerEvent> events) {
  expect(events, hasLength(1));
  final FramerEvent event = events.single;
  expect(event, isA<FramedMessage>());
  return (event as FramedMessage).message;
}

void _expectOnlyInvalid(List<FramerEvent> events) {
  expect(events, hasLength(1));
  expect(events.single, isA<FramedInvalid>());
}

List<int?> _versions(List<FramerEvent> events) => <int?>[
  for (final FramerEvent event in events)
    (event as FramedMessage).message.latestTemplateVersion,
];

/// A valid message whose text between the braces is exactly [contentLength] characters long.
String _paddedMessage(int contentLength) {
  const String head = '"x":"';
  const String tail = '"';
  return '{$head${'a' * (contentLength - head.length - tail.length)}$tail}';
}

void main() {
  group('5.9 framing: chunks and messages', () {
    test('5.9 framing: two messages in one chunk, no newline between them', () {
      final List<FramerEvent> events = _frame(
        '{"latestTemplateVersionNumber":"3"}{"latestTemplateVersionNumber":"4"}',
      );

      expect(events, hasLength(2));
      expect(_versions(events), <int>[3, 4]);
    });

    test('5.9 framing: three messages in one chunk keep their order', () {
      final List<FramerEvent> events = _frame(
        '{"latestTemplateVersionNumber":"7"}\n'
        '{"latestTemplateVersionNumber":"5"}'
        '{"latestTemplateVersionNumber":"6"}',
      );

      expect(_versions(events), <int>[7, 5, 6]);
    });

    test('5.9 framing: a partial message waits for the rest', () {
      final RealtimeFramer framer = RealtimeFramer();

      expect(framer.add('[{"latestTemplate'), isEmpty);
      expect(framer.add('VersionNumber'), isEmpty);
      final List<FramerEvent> events = framer.add('": "5"}');

      expect(_onlyMessage(events).latestTemplateVersion, 5);
    });

    test('5.9 framing: a message completed in a chunk that starts another '
        'returns the first and waits for the second', () {
      final RealtimeFramer framer = RealtimeFramer();

      expect(framer.add('{"latestTemplateVersionNumber":'), isEmpty);
      expect(
        _versions(framer.add('"8"},{"latestTemplateVersionNumber":"9')),
        <int>[8],
      );
      expect(_versions(framer.add('"}')), <int>[9]);
    });

    test('5.9 framing: a message split one character per chunk', () {
      final RealtimeFramer framer = RealtimeFramer();
      final List<FramerEvent> events = <FramerEvent>[];
      for (final String character
          in '{"latestTemplateVersionNumber":"12"}'.split('')) {
        events.addAll(framer.add(character));
      }

      expect(_onlyMessage(events).latestTemplateVersion, 12);
    });

    test('5.9 framing: text between and around messages is dropped', () {
      final List<FramerEvent> events = _frame(
        '[\n  ,,garbage]}\n{"latestTemplateVersionNumber":"1"}\n,\n'
        'more text ] [ }\n{"latestTemplateVersionNumber":"2"}\n]\n',
      );

      expect(_versions(events), <int>[1, 2]);
    });

    test('5.9 framing: a chunk without a "{" gives no event', () {
      final RealtimeFramer framer = RealtimeFramer();

      expect(framer.add(''), isEmpty);
      expect(framer.add('[\n'), isEmpty);
      expect(framer.add(',\n'), isEmpty);
      expect(framer.add(']'), isEmpty);
      expect(framer.add('}}}'), isEmpty);
    });

    test('5.9 framing / 5.11 rule 7: 64 KiB of text before a "{" is dropped '
        'without an overflow', () {
      final RealtimeFramer framer = RealtimeFramer();
      final List<FramerEvent> events = <FramerEvent>[];
      for (int i = 0; i < 16; i++) {
        events.addAll(framer.add('[\n,]x' * 819));
      }
      events.addAll(framer.add('{"latestTemplateVersionNumber":"4"}'));

      expect(_onlyMessage(events).latestTemplateVersion, 4);
    });

    test('appendix A: the measured production body gives one message, '
        'version 2', () {
      final _Pipeline pipeline = _Pipeline();

      final List<FramerEvent> first = pipeline.add(
        utf8.encode('[{\n  "latestTemplateVersionNumber": "2"\n}\n'),
      );
      final List<FramerEvent> second = pipeline.add(utf8.encode(']'));
      pipeline.close();

      final RealtimeMessage message = _onlyMessage(first);
      expect(message.latestTemplateVersion, 2);
      expect(message.featureDisabled, isFalse);
      expect(message.retryIntervalSeconds, isNull);
      expect(second, isEmpty);
      expect(pipeline.events, hasLength(1));
    });
  });

  group('5.9 framing: UTF-8 decoding', () {
    test('5.9 framing: a character split across two byte chunks is joined '
        'before framing', () {
      const String body = '{"note":"ă€😀","latestTemplateVersionNumber":"6"}';
      final List<int> bytes = utf8.encode(body);
      // Split inside each multi-byte character: after the first byte of 'ă', of '€' and of '😀'.
      final int a = bytes.indexOf(0xC4) + 1;
      final int euro = bytes.indexOf(0xE2) + 1;
      final int emoji = bytes.indexOf(0xF0) + 2;
      final _Pipeline pipeline = _Pipeline();

      expect(pipeline.add(bytes.sublist(0, a)), isEmpty);
      expect(pipeline.add(bytes.sublist(a, euro)), isEmpty);
      expect(pipeline.add(bytes.sublist(euro, emoji)), isEmpty);
      final List<FramerEvent> events = pipeline.add(bytes.sublist(emoji));
      pipeline.close();

      expect(pipeline.text.toString(), body);
      expect(pipeline.text.toString(), isNot(contains('�')));
      expect(_onlyMessage(events).latestTemplateVersion, 6);
    });

    test('5.9 framing: malformed UTF-8 does not throw and the message is '
        'still read', () {
      final List<int> bytes = <int>[
        ...utf8.encode('{"note":"'),
        0xFF,
        0xC3,
        ...utf8.encode('","latestTemplateVersionNumber":"7"}'),
      ];
      final _Pipeline pipeline = _Pipeline();

      final List<FramerEvent> events = pipeline.add(bytes);
      pipeline.close();

      expect(pipeline.text.toString(), contains('�'));
      expect(_onlyMessage(events).latestTemplateVersion, 7);
    });

    test('5.9 framing: malformed UTF-8 between messages is dropped', () {
      final List<int> bytes = <int>[
        ...utf8.encode('{"latestTemplateVersionNumber":"1"}'),
        0xFE,
        0xFF,
        0x80,
        ...utf8.encode('{"latestTemplateVersionNumber":"2"}'),
      ];
      final _Pipeline pipeline = _Pipeline();

      final List<FramerEvent> events = pipeline.add(bytes);
      pipeline.close();

      expect(_versions(events), <int>[1, 2]);
    });
  });

  group('5.9 framing: the 16 KiB cap (5.11 rule 7)', () {
    test('5.9 framing: "{" plus 64 KiB without "}" in 4 KiB chunks gives one '
        'overflow, by the chunk that crosses 16 KiB', () {
      final RealtimeFramer framer = RealtimeFramer();
      final List<List<FramerEvent>> perChunk = <List<FramerEvent>>[];
      perChunk.add(framer.add('{${'a' * 4095}'));
      for (int i = 1; i < 16; i++) {
        perChunk.add(framer.add('a' * 4096));
      }
      perChunk.add(framer.add('}{"latestTemplateVersionNumber":"3"}'));

      final List<FramerEvent> all = <FramerEvent>[
        for (final List<FramerEvent> events in perChunk) ...events,
      ];
      expect(all, hasLength(1));
      expect(all.single, isA<FramedOverflow>());
      // Chunks 1-4 hold 16383 characters after the "{"; the fifth crosses 16 KiB. The buffer never
      // holds more than 16 KiB plus one chunk.
      for (int i = 0; i < 4; i++) {
        expect(perChunk[i], isEmpty, reason: 'chunk ${i + 1}');
      }
      expect(perChunk[4].single, isA<FramedOverflow>());
    });

    test('5.9 framing: "{" plus 64 KiB without "}" in one chunk gives one '
        'overflow', () {
      final RealtimeFramer framer = RealtimeFramer();

      final List<FramerEvent> events = framer.add('{${'a' * (64 * 1024)}');

      expect(events, hasLength(1));
      expect(events.single, isA<FramedOverflow>());
    });

    test('5.9 framing: after an overflow the framer accepts no more text', () {
      final RealtimeFramer framer = RealtimeFramer();
      expect(
        framer.add('{${'a' * (maxRealtimeMessage + 1)}').single,
        isA<FramedOverflow>(),
      );

      expect(framer.add('}'), isEmpty);
      expect(framer.add('{"latestTemplateVersionNumber":"3"}'), isEmpty);
      expect(framer.add('{"featureDisabled":true}'), isEmpty);
    });

    test('5.9 framing: exactly 16 KiB between the braces is a message', () {
      final String body = _paddedMessage(maxRealtimeMessage);
      expect(body.length, maxRealtimeMessage + 2);

      final List<FramerEvent> events = _frame(body);

      expect(_onlyMessage(events).latestTemplateVersion, isNull);
    });

    test('5.9 framing: exactly 16 KiB between the braces, sent in pieces, is '
        'a message', () {
      final String body = _paddedMessage(maxRealtimeMessage);
      final RealtimeFramer framer = RealtimeFramer();
      final List<FramerEvent> events = <FramerEvent>[];
      for (int start = 0; start < body.length; start += 1000) {
        final int end = start + 1000 < body.length ? start + 1000 : body.length;
        events.addAll(framer.add(body.substring(start, end)));
      }

      expect(events.single, isA<FramedMessage>());
    });

    test('5.9 framing: 16 KiB + 1 between the braces is an overflow', () {
      final List<FramerEvent> events = _frame(
        _paddedMessage(maxRealtimeMessage + 1),
      );

      expect(events, hasLength(1));
      expect(events.single, isA<FramedOverflow>());
    });

    test('5.9 framing: the cap counts from the latest "{", not from earlier '
        'messages', () {
      final RealtimeFramer framer = RealtimeFramer();
      final List<FramerEvent> events = <FramerEvent>[];
      for (int i = 0; i < 8; i++) {
        events.addAll(framer.add(_paddedMessage(maxRealtimeMessage)));
      }

      expect(events, hasLength(8));
      expect(events, everyElement(isA<FramedMessage>()));
    });
  });

  group('5.9 framing: message fields', () {
    test('5.9 fields: latestTemplateVersionNumber as a decimal string', () {
      expect(
        _onlyMessage(
          _frame('{"latestTemplateVersionNumber":"42"}'),
        ).latestTemplateVersion,
        42,
      );
    });

    test('5.9 fields: latestTemplateVersionNumber as a JSON integer', () {
      expect(
        _onlyMessage(
          _frame('{"latestTemplateVersionNumber":42}'),
        ).latestTemplateVersion,
        42,
      );
    });

    test('5.9 fields: latestTemplateVersionNumber 0 and 2^53 - 1 are in '
        'range', () {
      expect(
        _onlyMessage(
          _frame('{"latestTemplateVersionNumber":0}'),
        ).latestTemplateVersion,
        0,
      );
      expect(
        _onlyMessage(
          _frame('{"latestTemplateVersionNumber":"9007199254740991"}'),
        ).latestTemplateVersion,
        9007199254740991,
      );
      expect(
        _onlyMessage(
          _frame('{"latestTemplateVersionNumber":9007199254740991}'),
        ).latestTemplateVersion,
        9007199254740991,
      );
    });

    for (final String bad in <String>[
      '"9007199254740992"',
      '"-1"',
      '-1',
      '"+1"',
      '"1.5"',
      '1.5',
      '"0x10"',
      '" 1"',
      '""',
      'true',
      'null',
      '[1]',
    ]) {
      test('5.9 fields: latestTemplateVersionNumber $bad is '
          'update-message-invalid', () {
        _expectOnlyInvalid(_frame('{"latestTemplateVersionNumber":$bad}'));
      });
    }

    test('5.9 fields: featureDisabled true', () {
      final RealtimeMessage message = _onlyMessage(
        _frame('{"featureDisabled":true}'),
      );

      expect(message.featureDisabled, isTrue);
      expect(message.latestTemplateVersion, isNull);
    });

    test('5.9 fields: featureDisabled false is an ordinary message', () {
      final RealtimeMessage message = _onlyMessage(
        _frame('{"featureDisabled":false,"latestTemplateVersionNumber":"3"}'),
      );

      expect(message.featureDisabled, isFalse);
      expect(message.latestTemplateVersion, 3);
    });

    for (final String bad in <String>['"true"', '1', '0', 'null', '[true]']) {
      test('5.9 fields: featureDisabled $bad is update-message-invalid', () {
        _expectOnlyInvalid(_frame('{"featureDisabled":$bad}'));
      });
    }

    test('5.9 fields: retryIntervalSeconds as an integer and as a digit '
        'string', () {
      expect(
        _onlyMessage(
          _frame('{"retryIntervalSeconds":240}'),
        ).retryIntervalSeconds,
        240,
      );
      expect(
        _onlyMessage(
          _frame('{"retryIntervalSeconds":"240"}'),
        ).retryIntervalSeconds,
        240,
      );
    });

    for (final String ignored in <String>[
      '0',
      '-5',
      '1.5',
      '"abc"',
      '"-5"',
      'true',
      'null',
      '[240]',
    ]) {
      test('5.9 fields: retryIntervalSeconds $ignored is ignored, not '
          'invalid', () {
        final RealtimeMessage message = _onlyMessage(
          _frame(
            '{"latestTemplateVersionNumber":"2","retryIntervalSeconds":$ignored}',
          ),
        );

        expect(message.retryIntervalSeconds, isNull);
        expect(message.latestTemplateVersion, 2);
      });
    }

    test('5.9 fields: unknown fields are ignored', () {
      final RealtimeMessage message = _onlyMessage(
        _frame(
          '{"somethingNew":"x","list":[1,2,3],"n":null,'
          '"latestTemplateVersionNumber":"5","flag":true}',
        ),
      );

      expect(message.latestTemplateVersion, 5);
      expect(message.featureDisabled, isFalse);
    });

    test('5.9 fields: an empty object is a message with no fields', () {
      final RealtimeMessage message = _onlyMessage(_frame('{}'));

      expect(message.featureDisabled, isFalse);
      expect(message.latestTemplateVersion, isNull);
      expect(message.retryIntervalSeconds, isNull);
    });
  });

  group('5.9 framing: invalid slices', () {
    test('5.9 framing: a slice that is not JSON is update-message-invalid', () {
      _expectOnlyInvalid(_frame('{not json}'));
    });

    test('5.9 framing: a nested object ends the message early and fails '
        'closed', () {
      final List<FramerEvent> events = _frame(
        '{"a":{"b":1},"latestTemplateVersionNumber":"2"}',
      );

      _expectOnlyInvalid(events);
    });

    test('5.9 framing / §8: a "}" inside a string ends the message early and '
        'fails closed', () {
      _expectOnlyInvalid(
        _frame('{"note":"a}b","latestTemplateVersionNumber":"2"}'),
      );
    });

    test('5.9 framing: an invalid slice does not stop later messages', () {
      final List<FramerEvent> events = _frame(
        '{bad}{"latestTemplateVersionNumber":"2"}{also bad}'
        '{"latestTemplateVersionNumber":"3"}',
      );

      expect(events, hasLength(4));
      expect(events[0], isA<FramedInvalid>());
      expect((events[1] as FramedMessage).message.latestTemplateVersion, 2);
      expect(events[2], isA<FramedInvalid>());
      expect((events[3] as FramedMessage).message.latestTemplateVersion, 3);
    });

    test('5.9 framing: every invalid slice is reported, one event each', () {
      final List<FramerEvent> events = _frame('{x}{y}{z}');

      expect(events, hasLength(3));
      expect(events, everyElement(isA<FramedInvalid>()));
    });

    test('5.9 framing: parseRealtimeMessage reads a slice directly', () {
      expect(
        parseRealtimeMessage('{"latestTemplateVersionNumber":"1"}'),
        isA<FramedMessage>(),
      );
      expect(parseRealtimeMessage('{'), isA<FramedInvalid>());
      expect(parseRealtimeMessage('[]'), isA<FramedInvalid>());
      expect(parseRealtimeMessage('"text"'), isA<FramedInvalid>());
    });
  });

  group('5.9 framing: Android fixtures '
      '(AND-RC-TEST/FirebaseRemoteConfigTest.java)', () {
    test(':1306 realtime_stream_listen_and_end_connection → version 1', () {
      final RealtimeMessage message = _onlyMessage(
        _frameBytes('{ "latestTemplateVersionNumber": 1 }'),
      );

      expect(message.latestTemplateVersion, 1);
      expect(message.featureDisabled, isFalse);
      expect(message.retryIntervalSeconds, isNull);
    });

    test(':1514 realtime_stream_listen_and_failsafe_enabled → '
        'featureDisabled', () {
      final RealtimeMessage message = _onlyMessage(
        _frameBytes('{ "featureDisabled": true }'),
      );

      expect(message.featureDisabled, isTrue);
      expect(message.latestTemplateVersion, isNull);
    });

    test(':1528 realtime_stream_listen_and_failsafe_disabled → version 2', () {
      final RealtimeMessage message = _onlyMessage(
        _frameBytes(
          '{ "featureDisabled": false,  "latestTemplateVersionNumber": 2 }',
        ),
      );

      expect(message.featureDisabled, isFalse);
      expect(message.latestTemplateVersion, 2);
    });

    test(':1566 realtimeStreamListen_andUnableToParseMessage → '
        'update-message-invalid', () {
      _expectOnlyInvalid(
        _frameBytes(
          '{ "featureDisabled": false,  "latestTemplateVersionNumber: 2 } }',
        ),
      );
    });

    test(':1586 realtime_updatesBackoffMetadataWithProvidedRetryInterval → '
        'version 1 with a retry interval of 240 s', () {
      final RealtimeMessage message = _onlyMessage(
        _frameBytes(
          '{ "latestTemplateVersionNumber": 1, "retryIntervalSeconds": 240 }',
        ),
      );

      expect(message.latestTemplateVersion, 1);
      expect(message.retryIntervalSeconds, 240);
      expect(message.featureDisabled, isFalse);
    });
  });
}
