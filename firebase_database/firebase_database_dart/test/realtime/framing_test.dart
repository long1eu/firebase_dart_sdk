// Owner T. FrameSplitter and FrameAssembler (`rtdb_protocol.md` 3.1; test plan B-3.1a to B-3.1e;
// threat model T9, T10). Pure functions: runs on the VM and in the browser.

import 'dart:convert';
import 'dart:math';

import 'package:firebase_database_dart/src/realtime/framing.dart';
import 'package:test/test.dart';

const int _max = 16384;
const String _emoji = '\u{1F600}';

/// Whether [piece] survives UTF-8 encoding unchanged (a lone surrogate becomes U+FFFD).
bool _isWholeCodePoints(String piece) =>
    utf8.decode(utf8.encode(piece)) == piece;

/// A JSON envelope whose text is exactly [units] code units long, made of [filler] repeated.
String _jsonOfLength(int units, {String filler = 'x'}) {
  const String head = '{"t":"d","d":"';
  const String tail = '"}';
  final int body = units - head.length - tail.length;
  final StringBuffer text = StringBuffer(head);
  while (text.length < head.length + body) {
    text.write(filler);
  }
  text.write(tail);
  return text.toString();
}

FrameAssembler _assembler({int maxMessageBytes = 1 << 20, int maxDepth = 64}) =>
    FrameAssembler(maxMessageBytes: maxMessageBytes, maxDepth: maxDepth);

void main() {
  group('FrameSplitter', () {
    const FrameSplitter splitter = FrameSplitter(maxFrameUnits: _max);

    test(
      'a message of up to 16384 units is one frame without a count (B-3.1a)',
      () {
        final String json = _jsonOfLength(_max);
        expect(json.length, _max);
        expect(splitter.framesFor(json), <String>[json]);
        expect(splitter.framesFor('{}'), <String>['{}']);
      },
    );

    test('16385 units: the count 2, then 16384 and 1 units (B-3.1b)', () {
      final String json = _jsonOfLength(_max + 1);
      final List<String> frames = splitter.framesFor(json);
      expect(frames.first, '2');
      expect(frames.skip(1).map((String f) => f.length), <int>[_max, 1]);
      expect(frames.skip(1).join(), json);
    });

    test(
      '32768 units, an exact multiple: the count 2 and two full pieces (B-3.1b)',
      () {
        final String json = _jsonOfLength(2 * _max);
        final List<String> frames = splitter.framesFor(json);
        expect(frames.first, '2');
        expect(frames.skip(1).map((String f) => f.length), <int>[_max, _max]);
      },
    );

    test('32769 units: three pieces, the last of one unit (B-3.1b)', () {
      final List<String> frames = splitter.framesFor(
        _jsonOfLength(2 * _max + 1),
      );
      expect(frames.first, '3');
      expect(frames.last.length, 1);
    });

    test(
      'an emoji across units 16383/16384 moves whole to the next piece (B-3.1c)',
      () {
        // Units 0..16382 are ASCII, the surrogate pair sits at 16383 and 16384.
        final String json =
            '${'{"a":"'.padRight(16383, 'x')}$_emoji${'x' * 100}"}';
        expect(json.codeUnitAt(16383), inInclusiveRange(0xD800, 0xDBFF));
        final List<String> frames = splitter.framesFor(json);
        expect(frames.first, '2');
        expect(frames[1].length, 16383);
        expect(frames[2].startsWith(_emoji), isTrue);
        expect(frames.skip(1).every(_isWholeCodePoints), isTrue);
        expect(frames.skip(1).join(), json);
      },
    );

    test(
      'an emoji at units 16382/16383 fills the first piece exactly (B-3.1c)',
      () {
        final String json =
            '${'{"a":"'.padRight(16382, 'x')}$_emoji${'x' * 100}"}';
        final List<String> frames = splitter.framesFor(json);
        expect(frames[1].length, _max);
        expect(frames[1].endsWith(_emoji), isTrue);
        expect(frames.skip(1).every(_isWholeCodePoints), isTrue);
      },
    );

    test(
      'a message made only of emoji never cuts a pair, pieces stay within the limit',
      () {
        final String json = '{"a":"${_emoji * 40000}"}';
        final List<String> frames = splitter.framesFor(json);
        for (final String piece in frames.skip(1)) {
          expect(piece.length, lessThanOrEqualTo(_max));
          expect(_isWholeCodePoints(piece), isTrue);
        }
        expect(frames.skip(1).join(), json);
        expect(int.parse(frames.first), frames.length - 1);
      },
    );

    test('counts of 1 to 6 digits', () {
      const FrameSplitter tiny = FrameSplitter(maxFrameUnits: 2);
      for (final int pieces in <int>[5, 12, 123, 1234, 12345, 123456]) {
        final List<String> frames = tiny.framesFor('x' * (2 * pieces));
        expect(frames.first, '$pieces');
        expect(frames.length, pieces + 1);
      }
    });

    test(
      'more than 999999 pieces is refused (the count has at most 6 digits)',
      () {
        const FrameSplitter tiny = FrameSplitter(maxFrameUnits: 2);
        expect(tiny.framesFor('x' * (2 * 999999)).first, '999999');
        expect(
          () => tiny.framesFor('x' * (2 * 999999 + 1)),
          throwsArgumentError,
        );
      },
    );
  });

  group('FrameAssembler', () {
    test('a frame that is a whole JSON object is a message', () {
      expect(
        _assembler().add('{"t":"c","d":{"t":"o","d":null}}'),
        <String, Object?>{
          't': 'c',
          'd': <String, Object?>{'t': 'o', 'd': null},
        },
      );
    });

    test(
      'a count, then the pieces: the message after the last piece (B-3.1d)',
      () {
        final FrameAssembler assembler = _assembler();
        expect(assembler.add('3'), isNull);
        expect(assembler.isBuffering, isTrue);
        expect(assembler.add('{"t":"d",'), isNull);
        expect(assembler.add('"d":{"a"'), isNull);
        expect(assembler.add(':1}}'), <String, Object?>{
          't': 'd',
          'd': <String, Object?>{'a': 1},
        });
        expect(assembler.isBuffering, isFalse);
      },
    );

    test('counts of 1 to 6 digits reassemble (B-3.1d)', () {
      for (final int pieces in <int>[1, 12, 123, 1234, 12345, 123456]) {
        final String value = 'y' * pieces;
        final String json = '{"d":"$value"}';
        final FrameAssembler assembler = _assembler();
        expect(assembler.add('$pieces'), isNull);
        Map<String, Object?>? message;
        for (int i = 0; i < pieces; i++) {
          // One unit per piece, the rest of the text in the last one.
          final String piece = i < pieces - 1 ? json[i] : json.substring(i);
          message = assembler.add(piece);
          if (i < pieces - 1) {
            expect(message, isNull);
          }
        }
        expect(message, <String, Object?>{'d': value});
      }
    });

    test('a frame 0 while nothing is buffered is ignored (B-3.1e)', () {
      final FrameAssembler assembler = _assembler();
      expect(assembler.add('0'), isNull);
      expect(assembler.isBuffering, isFalse);
      expect(assembler.add('{"a":1}'), <String, Object?>{'a': 1});
    });

    test('a frame 0 while buffering is a piece', () {
      final FrameAssembler assembler = _assembler();
      assembler.add('3');
      assembler.add('{"a":');
      expect(assembler.add('0'), isNull);
      expect(assembler.add('}'), <String, Object?>{'a': 0});
    });

    test(
      'a short frame that is not a count is a one-frame message (B-3.1e)',
      () {
        for (final String frame in <String>[
          '00',
          '01',
          '-1',
          '1e3',
          '0x10',
          ' 1',
          '+1',
        ]) {
          final FrameAssembler assembler = _assembler();
          expect(
            () => assembler.add(frame),
            throwsA(isA<FramingException>()),
            reason: frame,
          );
          expect(assembler.isBuffering, isFalse, reason: frame);
        }
        expect(_assembler().add('{}'), <String, Object?>{});
      },
    );

    test('a digit frame while buffering is a piece, not a new count', () {
      final FrameAssembler assembler = _assembler();
      assembler.add('2');
      expect(assembler.add('{"a":12'), isNull);
      expect(assembler.add('3}'), <String, Object?>{'a': 123});
    });

    test(
      'bad JSON, an array and a string are refused, and the assembler recovers',
      () {
        final FrameAssembler assembler = _assembler();
        for (final String frame in <String>[
          'not json',
          '[1,2]',
          '"x"',
          '',
          '1234567',
        ]) {
          expect(
            () => assembler.add(frame),
            throwsA(isA<FramingException>()),
            reason: frame,
          );
        }
        assembler.add('2');
        assembler.add('[1,');
        expect(() => assembler.add('2]'), throwsA(isA<FramingException>()));
        expect(assembler.isBuffering, isFalse);
        expect(assembler.add('{"ok":true}'), <String, Object?>{'ok': true});
      },
    );

    test(
      'the size is counted in UTF-8 bytes while the pieces arrive, before the join',
      () {
        // 2 pieces of 4 emoji = 16 UTF-16 units but 32 bytes.
        final FrameAssembler assembler = _assembler(maxMessageBytes: 30);
        assembler.add('3');
        expect(assembler.add('{"a":"${_emoji * 4}'), isNull);
        expect(
          () => assembler.add('${_emoji * 4}"}'),
          throwsA(isA<FramingException>()),
        );
        expect(assembler.isBuffering, isFalse);
      },
    );

    test('a message of exactly the limit passes, one byte more does not', () {
      const String json = '{"a":"xxxx"}';
      expect(_assembler(maxMessageBytes: json.length).add(json), isNotNull);
      expect(
        () => _assembler(maxMessageBytes: json.length - 1).add(json),
        throwsA(isA<FramingException>()),
      );
      final FrameAssembler split = _assembler(maxMessageBytes: json.length);
      split.add('2');
      split.add(json.substring(0, 5));
      expect(split.add(json.substring(5)), isNotNull);
    });

    test('nesting up to the depth limit passes, one level more is refused', () {
      String nested(int depth) => '${'{"a":' * depth}1${'}' * depth}';
      expect(_assembler(maxDepth: 64).add(nested(64)), isNotNull);
      expect(
        () => _assembler(maxDepth: 64).add(nested(65)),
        throwsA(isA<FramingException>()),
      );
    });

    test(
      'brackets inside strings, with escaped quotes, do not count as depth',
      () {
        final FrameAssembler assembler = _assembler(maxDepth: 1);
        expect(
          assembler.add(r'{"a":"[[[{{{\"[[[\\","b":"}}]]"}'),
          <String, Object?>{'a': r'[[[{{{"[[[\', 'b': '}}]]'},
        );
      },
    );

    test('reset drops the buffered pieces', () {
      final FrameAssembler assembler = _assembler();
      assembler.add('2');
      assembler.add('{"a":');
      assembler.reset();
      expect(assembler.isBuffering, isFalse);
      expect(assembler.add('{"b":2}'), <String, Object?>{'b': 2});
    });

    test('the exception never holds the frame text', () {
      const String secret = 'secret-token-value';
      final FrameAssembler assembler = _assembler(maxMessageBytes: 10);
      for (final String frame in <String>[
        secret,
        '{"cred":"$secret"}',
        '["$secret"]',
      ]) {
        try {
          assembler.add(frame);
          fail('no exception for $frame');
        } on FramingException catch (e) {
          expect('$e ${e.message}', isNot(contains(secret)));
        }
      }
    });
  });

  test('split then assembled gives the message back, for random text', () {
    final Random random = Random(7);
    const FrameSplitter splitter = FrameSplitter(maxFrameUnits: 7);
    for (int round = 0; round < 200; round++) {
      final StringBuffer value = StringBuffer();
      for (int i = random.nextInt(60); i > 0; i--) {
        value.write(switch (random.nextInt(4)) {
          0 => _emoji,
          1 => 'é',
          2 => '€',
          _ => 'a',
        });
      }
      final Map<String, Object?> message = <String, Object?>{
        'v': value.toString(),
      };
      final FrameAssembler assembler = _assembler();
      Map<String, Object?>? result;
      for (final String frame in splitter.framesFor(jsonEncode(message))) {
        expect(_isWholeCodePoints(frame), isTrue);
        result = assembler.add(frame);
      }
      expect(result, message);
    }
  });

  test(
    'utf8Length matches the encoder, a lone surrogate counting as U+FFFD',
    () {
      for (final String text in <String>[
        '',
        'abc',
        'é',
        '€',
        _emoji,
        'a\uD800b',
        '\uDC00',
      ]) {
        expect(utf8Length(text), utf8.encode(text).length, reason: text);
      }
    },
  );
}
