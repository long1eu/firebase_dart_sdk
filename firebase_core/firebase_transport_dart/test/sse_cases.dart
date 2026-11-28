/// The server-sent events cases of shared spec §5.15, as data.
///
/// `sse_test.dart` runs them against `SseDecoder`; the Functions and AI Logic suites import this
/// file by a path relative to the repository and run them against their own use of the decoder.
/// This file imports nothing outside the Dart SDK, so it resolves from any package.
///
/// Each case feeds `chunks` to one decoder, one `add` per chunk, then calls `close` when
/// `close` is true. `expected` holds one entry per item returned, in order, from
/// every `add` and from `close`: `event:<data>`, `malformed`, `event-too-large` or
/// `stream-too-large`. Every case uses the caps [sseCaseMaxEventBytes] and
/// [sseCaseMaxStreamBytes].
library;

import 'dart:convert';

/// One case: the chunks of a body, whether the body ends, and the items expected.
typedef SseCase = ({
  String name,
  List<List<int>> chunks,
  bool close,
  List<String> expected,
});

/// The `maxEventBytes` of every case.
const int sseCaseMaxEventBytes = 32;

/// The `maxStreamBytes` of every case.
const int sseCaseMaxStreamBytes = 128;

List<int> _text(String text) => utf8.encode(text);

List<int> _bytes(String before, List<int> bytes, [String after = '']) {
  return <int>[..._text(before), ...bytes, ..._text(after)];
}

/// Eight comment lines of 13 bytes each: 104 bytes.
final String _comments104 = ': 0123456789\n' * 8;

/// The cases, in the order of §11.4's list for `sse_test.dart`, then the extra ones.
final List<SseCase> sseCases = <SseCase>[
  (
    name: 'LF line ends',
    chunks: <List<int>>[_text('data: a\n\ndata: b\n\n')],
    close: true,
    expected: <String>['event:a', 'event:b'],
  ),
  (
    name: 'CR line ends',
    chunks: <List<int>>[_text('data: a\r\rdata: b\r\r')],
    close: true,
    expected: <String>['event:a', 'event:b'],
  ),
  (
    name: 'CR LF line ends',
    chunks: <List<int>>[_text('data: a\r\n\r\ndata: b\r\n\r\n')],
    close: true,
    expected: <String>['event:a', 'event:b'],
  ),
  (
    name: 'CR and LF split across chunks are one line end',
    chunks: <List<int>>[_text('data: a\r'), _text('\n\r'), _text('\n')],
    close: true,
    expected: <String>['event:a'],
  ),
  (
    name: 'a multi-byte character split across chunks',
    chunks: <List<int>>[
      for (final int byte in _text('data: é€😀\n\n')) <int>[byte],
    ],
    close: true,
    expected: <String>['event:é€😀'],
  ),
  (
    name: 'a byte-order mark',
    chunks: <List<int>>[
      _bytes('', <int>[0xef, 0xbb, 0xbf], 'data: a\n\n'),
    ],
    close: true,
    expected: <String>['event:a'],
  ),
  (
    name: 'comments',
    chunks: <List<int>>[_text(': hello\ndata: a\n: between\n\n:\n\n')],
    close: true,
    expected: <String>['event:a'],
  ),
  (
    name: 'a field without a colon',
    chunks: <List<int>>[_text('data\n\nevent\ndata\ndata: b\n\n')],
    close: true,
    expected: <String>['event:', 'event:\nb'],
  ),
  (
    name: 'one leading space removed and a second kept',
    chunks: <List<int>>[_text('data:  a\n\ndata:a\n\n')],
    close: true,
    expected: <String>['event: a', 'event:a'],
  ),
  (
    name: 'multi-line data',
    chunks: <List<int>>[_text('data: a\ndata:\ndata: c\n\n')],
    close: true,
    expected: <String>['event:a\n\nc'],
  ),
  (
    name: 'an empty event',
    chunks: <List<int>>[_text('\n\n\r\n\rid: 1\nevent: e\n\n')],
    close: true,
    expected: <String>[],
  ),
  (
    name: 'event, id, retry ignored',
    chunks: <List<int>>[
      _text('event: e\nid: 1\nretry: 10\ndata: a\nfoo: bar\n\n'),
    ],
    close: true,
    expected: <String>['event:a'],
  ),
  (
    name: 'invalid UTF-8',
    chunks: <List<int>>[
      _bytes('data: ', <int>[0xc3, 0x28], '\n\n'),
    ],
    close: false,
    expected: <String>['malformed'],
  ),
  (
    name: 'close inside a line',
    chunks: <List<int>>[_text('data: a')],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'close inside an event',
    chunks: <List<int>>[_text('data: a\n')],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'close after a complete event',
    chunks: <List<int>>[_text('data: a\n\n')],
    close: true,
    expected: <String>['event:a'],
  ),
  (
    name: 'maxEventBytes by one long line',
    chunks: <List<int>>[
      _text('data: ${'x' * 26}\n\n'),
      _text('data: ${'y' * 27}\n\n'),
    ],
    close: true,
    expected: <String>['event:${'x' * 26}', 'event-too-large'],
  ),
  (
    name: 'maxEventBytes by many data lines',
    chunks: <List<int>>[
      _text('${'data: abcdefg\n' * 3}\n'),
      _text('data: abcdefg\n' * 4),
    ],
    close: true,
    expected: <String>['event:abcdefg\nabcdefg\nabcdefg', 'event-too-large'],
  ),
  (
    name: 'maxStreamBytes: the byte past the cap is not decoded',
    chunks: <List<int>>[
      _text('data: a\n\n'),
      _text('$_comments104: 1234\n'),
      _text('data: b\n'),
      _text('\n'),
    ],
    close: true,
    expected: <String>['event:a', 'stream-too-large'],
  ),
  (
    name: 'nothing after a final item',
    chunks: <List<int>>[
      _text('data: a\n\n'),
      _text('data: ${'z' * 30}\n\n'),
      _text('data: c\n\n'),
    ],
    close: true,
    expected: <String>['event:a', 'event-too-large'],
  ),
  // Beyond the list of §11.4.
  (
    name: 'mixed line ends in one event',
    chunks: <List<int>>[_text('data: a\rdata: b\ndata: c\r\n\n')],
    close: true,
    expected: <String>['event:a\nb\nc'],
  ),
  (
    name: 'a CR at the end of a chunk followed by text',
    chunks: <List<int>>[_text('data: a\r'), _text('data: b\r\r')],
    close: true,
    expected: <String>['event:a\nb'],
  ),
  (
    name: 'a byte-order mark split across chunks',
    chunks: <List<int>>[
      <int>[0xef],
      <int>[0xbb, 0xbf],
      _text('data: a\n\n'),
    ],
    close: true,
    expected: <String>['event:a'],
  ),
  (
    name: 'only a leading byte-order mark is ignored',
    chunks: <List<int>>[
      _bytes('', <int>[0xef, 0xbb, 0xbf], 'data: \u{feff}a\n\n'),
    ],
    close: true,
    expected: <String>['event:\u{feff}a'],
  ),
  (
    name: 'a colon in the value is kept',
    chunks: <List<int>>[_text('data: {"a":1}\n\n')],
    close: true,
    expected: <String>['event:{"a":1}'],
  ),
  (
    name: 'field names are exact',
    chunks: <List<int>>[_text('Data: x\ndata : y\ndatax: z\ndata: a\n\n')],
    close: true,
    expected: <String>['event:a'],
  ),
  (
    name: 'the edges of valid UTF-8',
    chunks: <List<int>>[
      _bytes('data: ', <int>[
        ...<int>[0xc2, 0x80],
        ...<int>[0xe0, 0xa0, 0x80],
        ...<int>[0xed, 0x9f, 0xbf],
        ...<int>[0xee, 0x80, 0x80],
        ...<int>[0xf4, 0x8f, 0xbf, 0xbf],
      ], '\n\n'),
    ],
    close: true,
    expected: <String>['event:\u{80}\u{800}\u{d7ff}\u{e000}\u{10ffff}'],
  ),
  (
    name: 'invalid UTF-8: a stray continuation byte after an event',
    chunks: <List<int>>[
      _bytes('data: a\n\n', <int>[0x80]),
    ],
    close: true,
    expected: <String>['event:a', 'malformed'],
  ),
  (
    name: 'invalid UTF-8: an overlong two-byte form',
    chunks: <List<int>>[
      _bytes('data: ', <int>[0xc0, 0xaf]),
    ],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'invalid UTF-8: an overlong three-byte form',
    chunks: <List<int>>[
      _bytes('data: ', <int>[0xe0, 0x80, 0xaf]),
    ],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'invalid UTF-8: a surrogate',
    chunks: <List<int>>[
      _bytes('data: ', <int>[0xed, 0xa0, 0x80]),
    ],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'invalid UTF-8: above U+10FFFF',
    chunks: <List<int>>[
      _bytes('data: ', <int>[0xf4, 0x90, 0x80, 0x80]),
    ],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'invalid UTF-8: a lead byte inside a sequence',
    chunks: <List<int>>[
      _bytes('data: ', <int>[0xe2, 0xc3, 0xa9]),
    ],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'a chunk value that is not a byte',
    chunks: <List<int>>[
      _text('data: a\n\n'),
      <int>[256],
    ],
    close: true,
    expected: <String>['event:a', 'malformed'],
  ),
  (
    name: 'a negative chunk value',
    chunks: <List<int>>[
      <int>[-1],
    ],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'close inside a comment line',
    chunks: <List<int>>[_text(': ping')],
    close: true,
    expected: <String>['malformed'],
  ),
  (
    name: 'close inside a multi-byte character',
    chunks: <List<int>>[
      _bytes('data: a\n\n', <int>[0xe2, 0x82]),
    ],
    close: true,
    expected: <String>['event:a', 'malformed'],
  ),
  (
    name: 'maxEventBytes counts a comment line',
    chunks: <List<int>>[_text(':${'x' * 32}\n')],
    close: true,
    expected: <String>['event-too-large'],
  ),
  (
    name: 'maxEventBytes: a line of exactly the cap',
    chunks: <List<int>>[_text('data: ${'x' * 26}\n\n')],
    close: true,
    expected: <String>['event:${'x' * 26}'],
  ),
  (
    name: 'maxStreamBytes: a stream of exactly the cap',
    chunks: <List<int>>[
      _text('data: a\n\n'),
      _text('$_comments104: 123\n'),
      _text('data: b\n'),
      _text('\n'),
    ],
    close: true,
    expected: <String>['event:a', 'event:b'],
  ),
  (
    name: 'maxStreamBytes in one chunk',
    chunks: <List<int>>[_text('\n' * 200)],
    close: true,
    expected: <String>['stream-too-large'],
  ),
  (
    name: 'nothing after a final item in the same chunk',
    chunks: <List<int>>[
      _bytes('data: a\n\n', <int>[0xff], 'data: b\n\n'),
    ],
    close: true,
    expected: <String>['event:a', 'malformed'],
  ),
];
