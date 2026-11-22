// Owner K. decodeServerMessage, wirePathFromServer and isValidServerData (rtdb_protocol.md 4 and 5,
// threat model T11, test plan S5 and idea 3). The fuzz group mutates every field of every valid
// message to every other JSON type.
import 'dart:convert';

import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/realtime/server_message.dart';
import 'package:test/test.dart';

final String _failure = DatabaseErrorCode.operationFailed.wireStatus;

Matcher _violation() => isA<Ignored>().having(
  (Ignored i) => i.isProtocolError,
  'isProtocolError',
  isTrue,
);

Matcher _ignoredQuietly() => isA<Ignored>().having(
  (Ignored i) => i.isProtocolError,
  'isProtocolError',
  isFalse,
);

Matcher _failedResponse(int r) => isA<Response>()
    .having((Response x) => x.r, 'r', r)
    .having((Response x) => x.status, 'status', _failure)
    .having((Response x) => x.data, 'data', isNull);

void main() {
  group('responses (B-4.0, B-4.0a)', () {
    test('an ok answer carries r, status and data', () {
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'r': 4,
        'b': <String, Object?>{
          's': 'ok',
          'd': <String, Object?>{'x': 1},
        },
      });
      expect(
        message,
        isA<Response>()
            .having((Response x) => x.r, 'r', 4)
            .having((Response x) => x.status, 'status', 'ok')
            .having((Response x) => x.data, 'data', <String, Object?>{'x': 1}),
      );
    });

    test('r 0 (a request sent without r) is a response', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'r': 0,
          'b': <String, Object?>{'s': 'ok', 'd': ''},
        }),
        isA<Response>().having((Response x) => x.r, 'r', 0),
      );
    });

    test('an error answer keeps the status and a cleaned reason', () {
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'r': 2,
        'b': <String, Object?>{
          's': 'permission_denied',
          'd': 'Permission\ndenied',
        },
      });
      expect(
        message,
        isA<Response>()
            .having((Response x) => x.status, 'status', 'permission_denied')
            .having((Response x) => x.data, 'data', r'Permission\u000Adenied'),
      );
    });

    test('a non-string reason of an error answer is dropped', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'r': 2,
          'b': <String, Object?>{
            's': 'datastale',
            'd': <String, Object?>{'x': 1},
          },
        }),
        isA<Response>()
            .having((Response x) => x.status, 'status', 'datastale')
            .having((Response x) => x.data, 'data', isNull),
      );
    });

    test('a body that is not an object fails the request (iOS U-I06)', () {
      expect(
        decodeServerMessage(<String, Object?>{'r': 3, 'b': 'not a dict'}),
        _failedResponse(3),
      );
    });

    test('a status that is not a string fails the request (iOS U-I07)', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'r': 3,
          'b': <String, Object?>{'s': 5},
        }),
        _failedResponse(3),
      );
    });

    test('ok data with a non-finite number fails the request (T11)', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'r': 3,
          'b': <String, Object?>{
            's': 'ok',
            'd': <String, Object?>{'x': double.infinity},
          },
        }),
        _failedResponse(3),
      );
    });

    test('ok data keeps keys that are not data keys (an auth answer)', () {
      final Map<String, Object?> claims = <String, Object?>{
        'https://example.com/roles': <Object?>['admin'],
      };
      expect(
        decodeServerMessage(<String, Object?>{
          'r': 1,
          'b': <String, Object?>{
            's': 'ok',
            'd': <String, Object?>{
              'auth': <String, Object?>{'token': claims},
            },
          },
        }),
        isA<Response>().having((Response x) => x.status, 'status', 'ok'),
      );
    });

    test('a malformed request number is a protocol error (iOS U-I09)', () {
      for (final Object? r in <Object?>[
        <Object?>[1],
        '1',
        1.5,
        -1,
        null,
      ]) {
        expect(
          decodeServerMessage(<String, Object?>{
            'r': r,
            'b': <String, Object?>{'s': 'ok'},
          }),
          _violation(),
          reason: '$r',
        );
      }
    });
  });

  group('data pushes (B-5.1)', () {
    test('d at a path without the leading slash reaches the seam as /a/b', () {
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'a': 'd',
        'b': <String, Object?>{
          'p': 'ws/a',
          'd': <String, Object?>{'x': 1},
        },
      });
      expect(
        message,
        isA<DataPush>()
            .having((DataPush p) => p.path, 'path', '/ws/a')
            .having((DataPush p) => p.isMerge, 'isMerge', isFalse)
            .having((DataPush p) => p.action, 'action', 'd')
            .having((DataPush p) => p.tag, 'tag', isNull)
            .having((DataPush p) => p.data, 'data', <String, Object?>{'x': 1}),
      );
    });

    test('the root "" becomes /', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'd',
          'b': <String, Object?>{'p': '', 'd': 1},
        }),
        isA<DataPush>().having((DataPush p) => p.path, 'path', '/'),
      );
    });

    test('a tag is kept; tag 0 and null are untagged', () {
      DataPush push(Object? tag) =>
          decodeServerMessage(<String, Object?>{
                'a': 'd',
                'b': <String, Object?>{'p': 'people', 'd': 1, 't': tag},
              })
              as DataPush;
      expect(push(3).tag, 3);
      expect(push(0).tag, isNull);
      expect(push(null).tag, isNull);
    });

    test('null data is a delete', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'd',
          'b': <String, Object?>{'p': 'a', 'd': null},
        }),
        isA<DataPush>().having((DataPush p) => p.data, 'data', isNull),
      );
    });

    test('m keeps its relative-path keys as the server sent them (A.3)', () {
      final Map<String, Object?> data = <String, Object?>{
        'p': 'gone',
        'm/a': 1,
        'm/b': 2,
        'keep': null,
      };
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'a': 'm',
        'b': <String, Object?>{'p': 'od', 'd': data, 't': 2},
      });
      expect(
        message,
        isA<DataPush>()
            .having((DataPush p) => p.path, 'path', '/od')
            .having((DataPush p) => p.isMerge, 'isMerge', isTrue)
            .having((DataPush p) => p.action, 'action', 'm')
            .having((DataPush p) => p.tag, 'tag', 2)
            .having((DataPush p) => p.data, 'data', data),
      );
    });

    test('m whose data is not an object is dropped (iOS U-I08)', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'm',
          'b': <String, Object?>{'p': '/', 'd': 'not a dict'},
        }),
        _violation(),
      );
    });

    test('a priority child path and .value/.priority leaves are data', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'd',
          'b': <String, Object?>{'p': 'a/.priority', 'd': 5},
        }),
        isA<DataPush>().having((DataPush p) => p.path, 'path', '/a/.priority'),
      );
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'd',
          'b': <String, Object?>{
            'p': 'a',
            'd': <String, Object?>{
              'x': <String, Object?>{'.value': 2, '.priority': 'x'},
              '.priority': 5.0,
            },
          },
        }),
        isA<DataPush>(),
      );
    });
  });

  group('listen revoked, revokes, security debug (B-5.2, B-5.3)', () {
    test('c with q keeps the query objects as sent, sin/ein included', () {
      final List<Map<String, Object?>> q = <Map<String, Object?>>[
        <String, Object?>{
          'i': '.key',
          'sin': true,
          'ein': true,
          'l': 1,
          'vf': 'l',
        },
      ];
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'c',
          'b': <String, Object?>{'p': 'd', 'q': q},
        }),
        isA<ListenRevokedPush>()
            .having((ListenRevokedPush p) => p.path, 'path', '/d')
            .having((ListenRevokedPush p) => p.queries, 'queries', q)
            .having((ListenRevokedPush p) => p.action, 'action', 'c'),
      );
    });

    test('c with q null (measured) or absent has no queries', () {
      for (final Map<String, Object?> body in <Map<String, Object?>>[
        <String, Object?>{'p': 'd', 'q': null},
        <String, Object?>{'p': 'd'},
      ]) {
        expect(
          decodeServerMessage(<String, Object?>{'a': 'c', 'b': body}),
          isA<ListenRevokedPush>().having(
            (ListenRevokedPush p) => p.queries,
            'queries',
            isNull,
          ),
        );
      }
    });

    test('ac and apc carry a status and a cleaned explanation', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'ac',
          'b': <String, Object?>{'s': 'invalid_token', 'd': 'expired\r\n'},
        }),
        isA<AuthRevokedPush>()
            .having((AuthRevokedPush p) => p.status, 'status', 'invalid_token')
            .having(
              (AuthRevokedPush p) => p.explanation,
              'explanation',
              r'expired\u000D\u000A',
            )
            .having((AuthRevokedPush p) => p.action, 'action', 'ac'),
      );
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'apc',
          'b': <String, Object?>{'s': 'invalid_token'},
        }),
        isA<AppCheckRevokedPush>()
            .having((AppCheckRevokedPush p) => p.explanation, 'explanation', '')
            .having((AppCheckRevokedPush p) => p.action, 'action', 'apc'),
      );
    });

    test('a revoke with a non-string status is dropped (iOS U-I10)', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'ac',
          'b': <String, Object?>{'s': 5},
        }),
        _violation(),
      );
    });

    test('sd carries its cleaned message; a non-string one is dropped', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'sd',
          'b': <String, Object?>{'msg': 'rule\t1'},
        }),
        isA<SecurityDebugPush>()
            .having(
              (SecurityDebugPush p) => p.message,
              'message',
              r'rule\u00091',
            )
            .having((SecurityDebugPush p) => p.action, 'action', 'sd'),
      );
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'sd',
          'b': <String, Object?>{'msg': 5},
        }),
        _violation(),
      );
    });
  });

  group('range merges, as measured (probe addendum B)', () {
    test('a single entry without s and e is the whole data', () {
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'a': 'rm',
        'b': <String, Object?>{
          'p': 'ch',
          'd': <Object?>[
            <String, Object?>{
              'm': <String, Object?>{'c0': 'v-c0', 'c1': 'v-c1'},
            },
          ],
          't': 1,
        },
      });
      expect(
        message,
        isA<RangeMergePush>()
            .having((RangeMergePush p) => p.path, 'path', '/ch')
            .having((RangeMergePush p) => p.tag, 'tag', 1)
            .having((RangeMergePush p) => p.action, 'action', 'rm'),
      );
      final WireRangeMerge merge = (message as RangeMergePush).merges.single;
      expect(merge.exclusiveStart, isNull);
      expect(merge.inclusiveEnd, isNull);
      expect(merge.data, <String, Object?>{'c0': 'v-c0', 'c1': 'v-c1'});
    });

    test('a leaf in a single entry', () {
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'a': 'rm',
        'b': <String, Object?>{
          'p': 'one',
          'd': <Object?>[
            <String, Object?>{'m': 'leaf'},
          ],
        },
      });
      expect((message as RangeMergePush).merges.single.data, 'leaf');
    });

    test('first e only, middle s and e, last s only; paths as /a/b', () {
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'a': 'rm',
        'b': <String, Object?>{
          'p': 'ch',
          'd': <Object?>[
            <String, Object?>{
              'e': 'ch/c4',
              'm': <String, Object?>{'c0': 'v'},
            },
            <String, Object?>{
              's': 'ch/c4',
              'e': 'ch/c9',
              'm': <String, Object?>{},
            },
            <String, Object?>{'s': 'ch/c9', 'm': null},
          ],
        },
      });
      final List<WireRangeMerge> merges = (message as RangeMergePush).merges;
      expect(merges, hasLength(3));
      expect(merges[0].exclusiveStart, isNull);
      expect(merges[0].inclusiveEnd, '/ch/c4');
      expect(merges[1].exclusiveStart, '/ch/c4');
      expect(merges[1].inclusiveEnd, '/ch/c9');
      expect(merges[2].exclusiveStart, '/ch/c9');
      expect(merges[2].inclusiveEnd, isNull);
    });

    test(
      'an empty list (a hash match) is ignored without a protocol error',
      () {
        expect(
          decodeServerMessage(<String, Object?>{
            'a': 'rm',
            'b': <String, Object?>{'p': 'ch', 'd': <Object?>[]},
          }),
          _ignoredQuietly(),
        );
      },
    );

    test('shapes that were not measured are protocol errors', () {
      final List<List<Object?>> shapes = <List<Object?>>[
        <Object?>[
          <String, Object?>{'s': 'a', 'm': 1},
        ],
        <Object?>[
          <String, Object?>{'e': 'a', 'm': 1},
        ],
        <Object?>[
          <String, Object?>{'s': 'a', 'e': 'b', 'm': 1},
          <String, Object?>{'s': 'b', 'm': 1},
        ],
        <Object?>[
          <String, Object?>{'e': 'a', 'm': 1},
          <String, Object?>{'m': 1},
        ],
        <Object?>[
          <String, Object?>{'e': 'a', 'm': 1},
          <String, Object?>{'e': 'b', 'm': 1},
          <String, Object?>{'s': 'b', 'm': 1},
        ],
        <Object?>[
          <String, Object?>{'m': 1, 'x': 1},
        ],
        <Object?>[<String, Object?>{}],
        <Object?>['not a dict'],
        <Object?>[
          <String, Object?>{'e': 5, 'm': 1},
          <String, Object?>{'s': 'a', 'm': 1},
        ],
        <Object?>[
          <String, Object?>{'e': 'a#b', 'm': 1},
          <String, Object?>{'s': 'a', 'm': 1},
        ],
      ];
      for (final List<Object?> shape in shapes) {
        expect(
          decodeServerMessage(<String, Object?>{
            'a': 'rm',
            'b': <String, Object?>{'p': 'ch', 'd': shape},
          }),
          _violation(),
          reason: jsonEncode(shape),
        );
      }
    });
  });

  group('other messages (B-5.4)', () {
    test('an unknown action is ignored without a protocol error', () {
      final ServerMessage message = decodeServerMessage(<String, Object?>{
        'a': 'zz-secret-action',
        'b': <String, Object?>{},
      });
      expect(message, _ignoredQuietly());
      expect('$message', isNot(contains('secret')));
    });

    test('an error message becomes a cleaned ServerError (iOS U-I01)', () {
      expect(
        decodeServerMessage(<String, Object?>{'error': 'boom\u001b[31m'}),
        isA<ServerError>().having(
          (ServerError e) => e.message,
          'message',
          r'boom\u001B[31m',
        ),
      );
    });

    test('a non-object data message is a protocol error (iOS U-I05)', () {
      for (final Object? json in <Object?>[
        <Object?>[1, 2],
        'not a dict',
        null,
        1,
      ]) {
        expect(decodeServerMessage(json), _violation(), reason: '$json');
      }
    });

    test('a map with non-string keys is a protocol error', () {
      expect(decodeServerMessage(<Object?, Object?>{1: 'a'}), _violation());
    });

    test('a message with neither r, error nor a is a protocol error', () {
      expect(
        decodeServerMessage(<String, Object?>{'b': <String, Object?>{}}),
        _violation(),
      );
    });

    test('a push body that is not an object is a protocol error', () {
      expect(
        decodeServerMessage(<String, Object?>{'a': 'd', 'b': 'not a dict'}),
        _violation(),
      );
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 5,
          'b': <String, Object?>{},
        }),
        _violation(),
      );
    });
  });

  group('wirePathFromServer (A.3)', () {
    test('adds the leading slash, maps the root, keeps a slash', () {
      expect(wirePathFromServer('a/b'), '/a/b');
      expect(wirePathFromServer(''), '/');
      expect(wirePathFromServer('/a/b'), '/a/b');
      expect(wirePathFromServer('/'), '/');
    });
  });

  group('isValidServerData', () {
    test('accepts JSON data and refuses bad keys and numbers', () {
      expect(isValidServerData(null), isTrue);
      expect(
        isValidServerData(<String, Object?>{
          'a': <Object?>[1, 'x', true, null, 1.5],
        }),
        isTrue,
      );
      expect(isValidServerData(<String, Object?>{'a.b': 1}), isFalse);
      expect(isValidServerData(<String, Object?>{'.sv': 'timestamp'}), isFalse);
      expect(isValidServerData(<Object?>[double.nan]), isFalse);
      expect(isValidServerData(Object()), isFalse);
    });
  });

  group('table-driven fuzz (test plan idea 3)', _fuzz);
}

/// A field of a valid message: where it is, the mutations that keep the message valid, and what
/// the others decode to.
final class _Field {
  const _Field(
    this.path,
    this.valid, {
    this.invalid,
    this.overrides = const <String, Matcher Function()>{},
  });

  final List<Object> path;
  final Set<String> valid;

  /// The matcher of an invalid mutation; a protocol-error [Ignored] when null.
  final Matcher Function()? invalid;

  /// Matchers for single mutations that decode to something else.
  final Map<String, Matcher Function()> overrides;
}

final class _Case {
  const _Case(this.name, this.message, this.decodesTo, this.fields);

  final String name;
  final Map<String, Object?> message;
  final Matcher Function() decodesTo;
  final List<_Field> fields;
}

/// Marks a removed field.
const Object _missing = _Missing();

final class _Missing {
  const _Missing();
}

/// Every JSON type (and two non-JSON doubles), fresh on each call.
Map<String, Object? Function()> get _mutations => <String, Object? Function()>{
  'missing': () => _missing,
  'null': () => null,
  'bool': () => true,
  'int': () => 7,
  'zero': () => 0,
  'negative int': () => -1,
  'double': () => 1.5,
  'infinity': () => double.infinity,
  'nan': () => double.nan,
  'string': () => 'x',
  'empty string': () => '',
  'bad path string': () => 'a#b',
  'list': () => <Object?>[],
  'list of string': () => <Object?>['x'],
  'map': () => <String, Object?>{},
};

const Set<String> _anyJson = <String>{
  'null',
  'bool',
  'int',
  'zero',
  'negative int',
  'double',
  'string',
  'empty string',
  'bad path string',
  'list',
  'list of string',
  'map',
};

const Set<String> _pathLike = <String>{'string', 'empty string'};
const Set<String> _stringLike = <String>{
  'string',
  'empty string',
  'bad path string',
};
const Set<String> _tagLike = <String>{'missing', 'null', 'int', 'zero'};

final List<_Case> _cases = <_Case>[
  _Case(
    'response',
    <String, Object?>{
      'r': 1,
      'b': <String, Object?>{
        's': 'ok',
        'd': <String, Object?>{'x': 1},
      },
    },
    () => isA<Response>(),
    <_Field>[
      const _Field(<Object>['r'], <String>{'int', 'zero'}),
      _Field(
        const <Object>['b'],
        const <String>{},
        invalid: () => _failedResponse(1),
      ),
      _Field(
        const <Object>['b', 's'],
        _stringLike,
        invalid: () => _failedResponse(1),
      ),
      _Field(
        const <Object>['b', 'd'],
        <String>{..._anyJson, 'missing'},
        invalid: () => _failedResponse(1),
      ),
    ],
  ),
  _Case(
    'data push',
    <String, Object?>{
      'a': 'd',
      'b': <String, Object?>{
        'p': 'a/b',
        'd': <String, Object?>{'x': 1},
        't': 3,
      },
    },
    () => isA<DataPush>().having((DataPush p) => p.isMerge, 'isMerge', false),
    <_Field>[
      _Field(
        const <Object>['a'],
        const <String>{},
        overrides: <String, Matcher Function()>{
          'string': _ignoredQuietly,
          'empty string': _ignoredQuietly,
          'bad path string': _ignoredQuietly,
        },
      ),
      const _Field(<Object>['b'], <String>{}),
      const _Field(<Object>['b', 'p'], _pathLike),
      const _Field(<Object>['b', 'd'], _anyJson),
      const _Field(<Object>['b', 't'], _tagLike),
    ],
  ),
  _Case(
    'merge push',
    <String, Object?>{
      'a': 'm',
      'b': <String, Object?>{
        'p': 'a',
        'd': <String, Object?>{'x': 1, 'y/z': null},
        't': 2,
      },
    },
    () => isA<DataPush>().having((DataPush p) => p.isMerge, 'isMerge', true),
    <_Field>[
      const _Field(<Object>['b', 'p'], _pathLike),
      const _Field(<Object>['b', 'd'], <String>{'map'}),
      _Field(const <Object>['b', 'd', 'x'], <String>{..._anyJson, 'missing'}),
      const _Field(<Object>['b', 't'], _tagLike),
    ],
  ),
  _Case(
    'listen revoked',
    <String, Object?>{
      'a': 'c',
      'b': <String, Object?>{
        'p': 'a',
        'q': <Object?>[
          <String, Object?>{'i': '.key', 'l': 1},
        ],
      },
    },
    () => isA<ListenRevokedPush>(),
    <_Field>[
      const _Field(<Object>['b', 'p'], _pathLike),
      const _Field(<Object>['b', 'q'], <String>{'missing', 'null', 'list'}),
      const _Field(<Object>['b', 'q', 0], <String>{'map', 'missing'}),
      _Field(
        const <Object>['b', 'q', 0, 'l'],
        <String>{..._anyJson, 'missing'},
      ),
    ],
  ),
  for (final String action in <String>['ac', 'apc'])
    _Case(
      'revoke $action',
      <String, Object?>{
        'a': action,
        'b': <String, Object?>{'s': 'invalid_token', 'd': 'expired'},
      },
      () =>
          action == 'ac' ? isA<AuthRevokedPush>() : isA<AppCheckRevokedPush>(),
      <_Field>[
        const _Field(<Object>['b', 's'], _stringLike),
        _Field(
          const <Object>['b', 'd'],
          <String>{..._stringLike, 'missing', 'null'},
        ),
      ],
    ),
  _Case(
    'security debug',
    <String, Object?>{
      'a': 'sd',
      'b': <String, Object?>{'msg': 'rules'},
    },
    () => isA<SecurityDebugPush>(),
    <_Field>[
      const _Field(<Object>['b', 'msg'], _stringLike),
    ],
  ),
  _Case(
    'range merge',
    <String, Object?>{
      'a': 'rm',
      'b': <String, Object?>{
        'p': 'ch',
        'd': <Object?>[
          <String, Object?>{
            'e': 'ch/c4',
            'm': <String, Object?>{'c0': 'v'},
          },
          <String, Object?>{'s': 'ch/c4', 'e': 'ch/c9', 'm': 1},
          <String, Object?>{'s': 'ch/c9', 'm': null},
        ],
        't': 1,
      },
    },
    () => isA<RangeMergePush>(),
    <_Field>[
      const _Field(<Object>['b', 'p'], _pathLike),
      _Field(
        const <Object>['b', 'd'],
        const <String>{},
        overrides: <String, Matcher Function()>{'list': _ignoredQuietly},
      ),
      const _Field(<Object>['b', 'd', 0], <String>{}),
      const _Field(<Object>['b', 'd', 0, 'e'], _pathLike),
      const _Field(<Object>['b', 'd', 1, 's'], _pathLike),
      const _Field(<Object>['b', 'd', 1, 'e'], _pathLike),
      const _Field(<Object>['b', 'd', 1, 'm'], _anyJson),
      const _Field(<Object>['b', 'd', 2, 's'], _pathLike),
      const _Field(<Object>['b', 't'], _tagLike),
    ],
  ),
  _Case(
    'server error',
    <String, Object?>{'error': 'boom'},
    () => isA<ServerError>(),
    <_Field>[
      const _Field(<Object>['error'], _stringLike),
    ],
  ),
];

void _fuzz() {
  for (final _Case c in _cases) {
    test('${c.name}: the valid message decodes', () {
      expect(decodeServerMessage(_copy(c.message)), c.decodesTo());
    });

    test('${c.name}: the whole message as another JSON type', () {
      for (final MapEntry<String, Object? Function()> m in _mutations.entries) {
        final Object? value = m.value();
        if (identical(value, _missing)) {
          continue;
        }
        expect(() => decodeServerMessage(value), returnsNormally);
        expect(decodeServerMessage(value), _violation(), reason: m.key);
      }
    });

    for (final _Field field in c.fields) {
      test('${c.name}: ${field.path.join('.')} as every JSON type', () {
        for (final MapEntry<String, Object? Function()> m
            in _mutations.entries) {
          final Map<String, Object?> message = _copy(c.message);
          _set(message, field.path, m.value());
          late final ServerMessage decoded;
          expect(
            () => decoded = decodeServerMessage(message),
            returnsNormally,
            reason: m.key,
          );
          final Matcher expected =
              field.overrides[m.key]?.call() ??
              (field.valid.contains(m.key)
                  ? c.decodesTo()
                  : (field.invalid?.call() ?? _violation()));
          expect(decoded, expected, reason: '${field.path} = ${m.key}');
        }
      });
    }
  }
}

Map<String, Object?> _copy(Map<String, Object?> message) =>
    jsonDecode(jsonEncode(message)) as Map<String, Object?>;

void _set(Object? root, List<Object> path, Object? value) {
  Object? node = root;
  for (final Object step in path.sublist(0, path.length - 1)) {
    node = node is List<Object?>
        ? node[step as int]
        : (node! as Map<String, Object?>)[step as String];
  }
  final Object last = path.last;
  if (node is List<Object?>) {
    if (identical(value, _missing)) {
      node.removeAt(last as int);
    } else {
      node[last as int] = value;
    }
    return;
  }
  final Map<String, Object?> map = node! as Map<String, Object?>;
  if (identical(value, _missing)) {
    map.remove(last);
  } else {
    map[last as String] = value;
  }
}
