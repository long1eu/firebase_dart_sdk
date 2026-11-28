import 'package:firebase_transport_dart/firebase_transport_dart.dart';
import 'package:test/test.dart';

import 'sse_cases.dart';

/// The text `sse_cases.dart` uses for [item].
String _describe(SseItem item) {
  return switch (item) {
    SseEvent(:final String data) => 'event:$data',
    SseMalformed() => 'malformed',
    SseEventTooLarge() => 'event-too-large',
    SseStreamTooLarge() => 'stream-too-large',
  };
}

void main() {
  group('cases', () {
    for (final SseCase sseCase in sseCases) {
      test(sseCase.name, () {
        final SseDecoder decoder = SseDecoder(
          maxEventBytes: sseCaseMaxEventBytes,
          maxStreamBytes: sseCaseMaxStreamBytes,
        );
        final List<String> items = <String>[
          for (final List<int> chunk in sseCase.chunks)
            ...decoder.add(chunk).map(_describe),
          if (sseCase.close) ...decoder.close().map(_describe),
        ];

        expect(items, sseCase.expected);
      });
    }
  });

  test('ArgumentError for maxEventBytes of 0 or less', () {
    for (final int cap in <int>[0, -1]) {
      expect(
        () => SseDecoder(maxEventBytes: cap, maxStreamBytes: 10),
        throwsA(
          isA<ArgumentError>()
              .having((ArgumentError e) => e.name, 'name', 'maxEventBytes')
              .having((ArgumentError e) => e.invalidValue, 'invalidValue', cap),
        ),
      );
    }
  });

  test('ArgumentError for maxStreamBytes of 0 or less', () {
    for (final int cap in <int>[0, -1]) {
      expect(
        () => SseDecoder(maxEventBytes: 10, maxStreamBytes: cap),
        throwsA(
          isA<ArgumentError>()
              .having((ArgumentError e) => e.name, 'name', 'maxStreamBytes')
              .having((ArgumentError e) => e.invalidValue, 'invalidValue', cap),
        ),
      );
    }
  });

  test('caps of 1 are accepted', () {
    final SseDecoder decoder = SseDecoder(maxEventBytes: 1, maxStreamBytes: 1);

    expect(decoder.add(<int>[0x0a]), isEmpty);
    expect(decoder.add(<int>[0x0a]).map(_describe), <String>[
      'stream-too-large',
    ]);
  });

  test(
    'after a final item every later add and close returns an empty list',
    () {
      final SseDecoder decoder = SseDecoder(
        maxEventBytes: 32,
        maxStreamBytes: 128,
      );

      expect(decoder.add(<int>[0xff]).map(_describe), <String>['malformed']);
      expect(decoder.add('data: a\n\n'.codeUnits), isEmpty);
      expect(decoder.close(), isEmpty);
      expect(decoder.close(), isEmpty);
    },
  );

  test('close twice returns one malformed item', () {
    final SseDecoder decoder = SseDecoder(
      maxEventBytes: 32,
      maxStreamBytes: 128,
    );
    decoder.add('data: a'.codeUnits);

    expect(decoder.close().map(_describe), <String>['malformed']);
    expect(decoder.close(), isEmpty);
    expect(decoder.add('\n\n'.codeUnits), isEmpty);
  });
}
