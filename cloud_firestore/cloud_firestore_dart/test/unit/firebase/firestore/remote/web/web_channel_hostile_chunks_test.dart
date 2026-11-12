// Security review: the chunk framing of a WebChannel response comes from the
// network. A length that is negative, absurdly large or not a number must be
// reported as a FormatException (which ends the session with `unavailable`),
// not as a RangeError and not by buffering the response forever.

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel.dart';
import 'package:test/test.dart';

void main() {
  test('well formed chunks are still parsed', () {
    final WebChannelChunkParser parser = WebChannelChunkParser();
    expect(parser.add('8\n[[1,[]'), isEmpty);
    expect(parser.hasPartialChunk, isTrue);
    expect(parser.add(']]5\n[1,2]'), <Object?>[
      <Object?>[
        <Object?>[1, <Object?>[]]
      ],
      <Object?>[1, 2],
    ]);
    expect(parser.hasPartialChunk, isFalse);
  });

  test('a negative chunk length is a FormatException', () {
    expect(() => WebChannelChunkParser().add('-5\n[[1,["noop"]]]'),
        throwsFormatException);
    expect(() => WebChannelChunkParser().add('-1\n'), throwsFormatException);
  });

  test('a chunk length above the limit is a FormatException', () {
    expect(
        () => WebChannelChunkParser()
            .add('${WebChannelChunkParser.maxChunkLength + 1}\n['),
        throwsFormatException);
    expect(() => WebChannelChunkParser().add('99999999999999\n['),
        throwsFormatException);
  });

  test('a length that is not a decimal number is a FormatException', () {
    for (final String length in <String>[
      'abc',
      '0x10',
      '1e3',
      '',
      '+5',
      '1 2'
    ]) {
      expect(() => WebChannelChunkParser().add('$length\n[]'),
          throwsFormatException,
          reason: '"$length"');
    }
  });

  test('a body without a chunk length is a FormatException', () {
    expect(() => WebChannelChunkParser().add('<html>not a webchannel body'),
        throwsFormatException);
  });
}
