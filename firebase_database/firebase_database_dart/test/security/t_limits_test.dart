// Owner T. The framing rows of the threat model's `limits_test.dart` (T9, T10), in a file of their
// own because other owners write the other rows. Pure Dart: runs on the VM and in the browser.

import 'dart:async';

import 'package:firebase_database_dart/src/realtime/framing.dart';
import 'package:test/test.dart';

/// What the assembler made of one frame sent while nothing was buffered.
enum _Outcome { count, ignored, message, protocolError }

_Outcome _classify(String frame) {
  final FrameAssembler assembler = FrameAssembler(
    maxMessageBytes: 1 << 20,
    maxDepth: 64,
  );
  try {
    final Map<String, Object?>? message = assembler.add(frame);
    if (message != null) {
      return _Outcome.message;
    }
    return assembler.isBuffering ? _Outcome.count : _Outcome.ignored;
  } on FramingException {
    return _Outcome.protocolError;
  }
}

void main() {
  test(
    'frame counts: only ^[1-9][0-9]{0,5}\$ starts a buffer, 0 is ignored (T9)',
    () {
      const Map<String, _Outcome> table = <String, _Outcome>{
        '1': _Outcome.count,
        '9': _Outcome.count,
        '10': _Outcome.count,
        '999999': _Outcome.count,
        '0': _Outcome.ignored,
        '1000000': _Outcome.protocolError,
        '00': _Outcome.protocolError,
        '01': _Outcome.protocolError,
        '-1': _Outcome.protocolError,
        '1e3': _Outcome.protocolError,
        '0x10': _Outcome.protocolError,
        '1.0': _Outcome.protocolError,
        ' 1': _Outcome.protocolError,
        '1 ': _Outcome.protocolError,
        '': _Outcome.protocolError,
        ' ': _Outcome.protocolError,
        'NaN': _Outcome.protocolError,
        '{}': _Outcome.message,
      };
      table.forEach((String frame, _Outcome expected) {
        expect(_classify(frame), expected, reason: 'frame "$frame"');
      });
    },
  );

  test('a count of 999999 then frames past the cap fails before the join, '
      'under 2 x cap held', () {
    const int cap = 1 << 20;
    const int frameUnits = 64 * 1024;
    final String piece = 'x' * frameUnits;
    final FrameAssembler assembler = FrameAssembler(
      maxMessageBytes: cap,
      maxDepth: 64,
    );
    expect(assembler.add('999999'), isNull);
    int accepted = 0;
    expect(() {
      for (int i = 0; i < 999999; i++) {
        assembler.add(piece);
        accepted++;
      }
    }, throwsA(isA<FramingException>()));
    // The pieces held never exceeded the cap; the one that crossed it was refused.
    expect(accepted * frameUnits, lessThanOrEqualTo(cap));
    expect((accepted + 1) * frameUnits, greaterThan(cap));
    expect(assembler.isBuffering, isFalse);
  });

  test('a single frame over the cap is refused', () {
    final FrameAssembler assembler = FrameAssembler(
      maxMessageBytes: 1000,
      maxDepth: 64,
    );
    expect(
      () => assembler.add('{"a":"${'x' * 1000}"}'),
      throwsA(isA<FramingException>()),
    );
  });

  test(
    '100 000 nested arrays/objects are a FramingException, no StackOverflowError, '
    'nothing reaches the zone (T10)',
    () {
      final List<Object> zoneErrors = <Object>[];
      runZonedGuarded(() {
        for (final String nested in <String>[
          '${'[' * 100000}${']' * 100000}',
          '${'{"a":' * 100000}1${'}' * 100000}',
          '{"t":"d","d":${'[' * 100000}',
        ]) {
          final FrameAssembler assembler = FrameAssembler(
            maxMessageBytes: 1 << 24,
            maxDepth: 64,
          );
          expect(() => assembler.add(nested), throwsA(isA<FramingException>()));
          // The same text cut into pieces is refused the same way.
          final FrameSplitter splitter = const FrameSplitter(
            maxFrameUnits: 16384,
          );
          final List<String> frames = splitter.framesFor(nested);
          expect(() {
            for (final String frame in frames) {
              assembler.add(frame);
            }
          }, throwsA(isA<FramingException>()));
        }
      }, (Object error, StackTrace _) => zoneErrors.add(error));
      expect(zoneErrors, isEmpty);
    },
  );
}
