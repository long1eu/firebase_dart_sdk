// Random offline writes for the tests of `mergeUnsentWrites` (PersistentCacheSettings.mergeUnsentWrites): sequences of
// single writes to a few documents, as the app makes them through the public API. The same sequence can be applied
// to a DocumentReference (the emulator tests) or turned into the mutations the client queues (the unit tests).

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';

import 'property.dart';

enum WriteKind { set, merge, mergeFields, update, delete }

/// One single write (not part of a `WriteBatch`) to document [document] of the sequence.
final class OfflineWrite {
  const OfflineWrite(this.kind, this.document, this.data, [this.mergeFields]);

  final WriteKind kind;
  final int document;

  /// For an update the keys are dot-separated field paths.
  final Map<String, Object?> data;
  final List<String>? mergeFields;

  Future<void> applyTo(DocumentReference<Map<String, Object?>> ref) =>
      switch (kind) {
        WriteKind.set => ref.set(data),
        WriteKind.merge => ref.set(data, const SetOptions(merge: true)),
        WriteKind.mergeFields => ref.set(
          data,
          SetOptions(mergeFields: mergeFields),
        ),
        WriteKind.update => ref.update(data),
        WriteKind.delete => ref.delete(),
      };

  Mutation toMutation(DocumentKey key) => switch (kind) {
    WriteKind.set => _converter
        .parseSetData(data)
        .toMutation(key, Precondition.none),
    WriteKind.merge => _converter
        .parseMergeData(data, null)
        .toMutation(key, Precondition.none),
    WriteKind.mergeFields => _converter
        .parseMergeData(data, SetOptions(mergeFields: mergeFields).fieldMask)
        .toMutation(key, Precondition.none),
    WriteKind.update => _converter
        .parseUpdateData(data)
        .toMutation(key, Precondition(exists: true)),
    WriteKind.delete => DeleteMutation(key, Precondition.none),
  };

  @override
  String toString() =>
      'd$document.${kind.name}(${showWriteData(data)}'
      '${mergeFields == null ? '' : ', mergeFields: $mergeFields'})';
}

final UserDataConverter _converter = UserDataConverter(
  DatabaseId.forProject('project'),
);

/// The names of the sentinels made by this file, for [showWriteData].
final Expando<String> _names = Expando<String>();

FieldValue _named(FieldValue value, String name) {
  _names[value] = name;
  return value;
}

/// [data] with the sentinels written as the call that made them.
String showWriteData(Object? data) => switch (data) {
  final FieldValue value => _names[value] ?? value.methodName,
  final Map<String, Object?> map =>
    '{${map.entries.map((MapEntry<String, Object?> e) => '${e.key}: ${showWriteData(e.value)}').join(', ')}}',
  final List<Object?> list => '[${list.map(showWriteData).join(', ')}]',
  final String string => "'$string'",
  _ => '$data',
};

/// Integers at the edges of what the backend and JavaScript hold: increments of them saturate, or lose precision as
/// doubles.
const List<int> _largeInts = <int>[
  9007199254740991,
  -9007199254740991,
  9007199254740992,
  4611686018427387904,
  9223372036854775807,
  -9223372036854775808,
];

const List<double> _doubles = <double>[
  0.5,
  1.0,
  2.5,
  -1.5,
  0.1,
  9007199254740992.0,
  1e300,
];

/// Array elements: 1 and 1.0 are equal for the backend's array transforms.
List<Object?> _elements(Gen gen) => <Object?>[
  for (int i = gen.below(4); i > 0; i--)
    gen.pick(<Object?>[
      1,
      2,
      1.0,
      2.5,
      'x',
      null,
      <String, Object?>{'k': 1},
    ]),
];

Object? _value(Gen gen, {int depth = 0}) {
  switch (gen.below(14)) {
    case 0:
    case 1:
    case 2:
    case 3:
      return gen.between(-2, 6);
    case 4:
      return gen.pick(_largeInts);
    case 5:
    case 6:
      return gen.pick(_doubles);
    case 7:
      return gen.pick(<String>['x', 'y']);
    case 8:
      return gen.pick(<Object?>[null, true]);
    case 9:
      return _elements(gen);
    case 10:
    case 11:
      if (depth < 2) {
        return <String, Object?>{
          for (int i = gen.below(3); i > 0; i--)
            gen.pick(<String>['x', 'z', 't']): _value(gen, depth: depth + 1),
        };
      }
      return gen.between(-2, 6);
    default:
      return <String, Object?>{};
  }
}

FieldValue _transform(Gen gen, {required bool timestamp}) {
  switch (gen.below(timestamp ? 11 : 9)) {
    case 0:
    case 1:
      final int operand = gen.between(-3, 5);
      return _named(FieldValue.increment(operand), 'increment($operand)');
    case 2:
      final int operand = gen.pick(_largeInts);
      return _named(FieldValue.increment(operand), 'increment($operand)');
    case 3:
      final double operand = gen.pick(<double>[
        0.5,
        1.5,
        -0.25,
        9007199254740992.0,
        1e300,
      ]);
      return _named(FieldValue.increment(operand), 'increment($operand)');
    case 4:
    case 5:
      final List<Object?> elements = _elements(gen);
      return _named(
        FieldValue.arrayUnion(elements),
        'arrayUnion(${showWriteData(elements)})',
      );
    case 6:
      final List<Object?> elements = _elements(gen);
      return _named(
        FieldValue.arrayRemove(elements),
        'arrayRemove(${showWriteData(elements)})',
      );
    case 7:
      final num operand = gen.chance(50) ? gen.between(-2, 6) : 2.5;
      return _named(FieldValue.minimum(operand), 'minimum($operand)');
    case 8:
      final num operand = gen.chance(50) ? gen.between(-2, 6) : 2.5;
      return _named(FieldValue.maximum(operand), 'maximum($operand)');
    default:
      return FieldValue.serverTimestamp();
  }
}

/// A leaf of the data of a write at [path]: a value, a transform, or (when [deletes]) a field delete.
/// [noTimestamp] is the field that queries order by: a pending server timestamp sorts by its estimate, which the
/// setting changes (documented), so no server timestamp is written there.
Object? _leaf(
  Gen gen,
  String path, {
  required bool deletes,
  required String noTimestamp,
}) {
  final int roll = gen.below(100);
  if (deletes && roll < 12) {
    return FieldValue.delete();
  }
  if (roll < 45) {
    return _transform(gen, timestamp: path != noTimestamp);
  }
  return _value(gen);
}

/// Data for a set (with [deletes], a set with merge): top-level fields a, b, t and n, where n is often a map of x, t
/// and m (itself a map of z).
Map<String, Object?> _setData(
  Gen gen, {
  required bool deletes,
  required String noTimestamp,
}) {
  Object? leaf(String path) =>
      _leaf(gen, path, deletes: deletes, noTimestamp: noTimestamp);
  final Map<String, Object?> data = <String, Object?>{};
  for (int i = gen.below(4); i >= 0; i--) {
    final String field = gen.pick(<String>['a', 'b', 't', 'n']);
    if (field == 'n' && gen.chance(60)) {
      data['n'] = <String, Object?>{
        for (int j = gen.below(3); j >= 0; j--)
          if (gen.pick(<String>['x', 't', 'm']) case final String child)
            child: child == 'm' && gen.chance(60)
                ? <String, Object?>{'z': leaf('n.m.z')}
                : leaf('n.$child'),
      };
    } else {
      data[field] = leaf(field);
    }
  }
  return data;
}

const List<String> _updatePaths = <String>[
  'a',
  'b',
  't',
  'n',
  'n.x',
  'n.t',
  'n.m',
  'n.m.z',
];

Map<String, Object?> _updateData(Gen gen, {required String noTimestamp}) {
  final Map<String, Object?> data = <String, Object?>{};
  for (int i = gen.below(3); i >= 0; i--) {
    final String path = gen.pick(_updatePaths);
    // Paths that overlap one another are an error of the API.
    if (data.keys.any(
      (String other) =>
          other == path ||
          other.startsWith('$path.') ||
          path.startsWith('$other.'),
    )) {
      continue;
    }
    // A map whose only fields are transforms writes an empty map and transforms its fields.
    data[path] = path == 'n' && gen.chance(25)
        ? <String, Object?>{
            'x': _transform(gen, timestamp: true),
            if (gen.chance(50)) 'z': _value(gen),
          }
        : _leaf(gen, path, deletes: true, noTimestamp: noTimestamp);
  }
  return data;
}

/// The top-level and nested paths that [data] gives a value or a sentinel to.
List<String> _paths(Map<String, Object?> data, [String prefix = '']) => <String>[
  for (final MapEntry<String, Object?> entry in data.entries) ...<String>[
    '$prefix${entry.key}',
    if (entry.value case final Map<String, Object?> map)
      ..._paths(map, '$prefix${entry.key}.'),
  ],
];

/// One write to one of [documents] documents, the first one most often (so that chains of writes to one document are
/// long). Writes that the API refuses are not generated.
OfflineWrite offlineWrite(
  Gen gen, {
  int documents = 3,
  String noTimestamp = 'a',
}) {
  final int document = gen.chance(60) ? 0 : gen.below(documents);
  while (true) {
    final int roll = gen.below(100);
    final OfflineWrite write;
    if (roll < 20) {
      write = OfflineWrite(
        WriteKind.set,
        document,
        _setData(gen, deletes: false, noTimestamp: noTimestamp),
      );
    } else if (roll < 40) {
      write = OfflineWrite(
        WriteKind.merge,
        document,
        _setData(gen, deletes: true, noTimestamp: noTimestamp),
      );
    } else if (roll < 48) {
      final Map<String, Object?> data = _setData(
        gen,
        deletes: true,
        noTimestamp: noTimestamp,
      );
      final List<String> paths = _paths(data);
      final List<String> fields = <String>[
        for (final String path in paths)
          if (gen.chance(50)) path,
      ];
      if (fields.isEmpty && paths.isNotEmpty) {
        fields.add(gen.pick(paths));
      }
      write = OfflineWrite(WriteKind.mergeFields, document, data, fields);
    } else if (roll < 88) {
      final Map<String, Object?> data = _updateData(
        gen,
        noTimestamp: noTimestamp,
      );
      if (data.isEmpty) {
        continue;
      }
      write = OfflineWrite(WriteKind.update, document, data);
    } else {
      write = OfflineWrite(
        WriteKind.delete,
        document,
        const <String, Object?>{},
      );
    }
    try {
      write.toMutation(DocumentKey.fromSegments(<String>['coll', 'd']));
    } catch (_) {
      // For example a delete sentinel that mergeFields does not name.
      continue;
    }
    return write;
  }
}

/// The data of a document as it is before the app goes offline (a set with values only), or null for a document
/// that does not exist.
Map<String, Object?>? startingDocument(Gen gen) {
  if (gen.chance(30)) {
    return null;
  }
  return <String, Object?>{
    for (int i = gen.below(5); i >= 0; i--)
      if (gen.pick(<String>['a', 'b', 't', 'n']) case final String field)
        field: field == 'n' && gen.chance(60)
            ? <String, Object?>{
                'x': _value(gen),
                if (gen.chance(50)) 't': _value(gen),
                if (gen.chance(40)) 'm': <String, Object?>{'z': _value(gen)},
              }
            : _value(gen),
  };
}

/// A sequence of [count] offline writes to [documents] documents and the starting state of each document.
final class OfflineSequence {
  OfflineSequence(this.start, this.writes);

  factory OfflineSequence.generate(Gen gen, {int documents = 3, int? count}) =>
      OfflineSequence(
        <Map<String, Object?>?>[
          for (int i = 0; i < documents; i++) startingDocument(gen),
        ],
        <OfflineWrite>[
          for (int i = count ?? 1 + gen.below(4 + gen.size * 4); i > 0; i--)
            offlineWrite(gen, documents: documents),
        ],
      );

  final List<Map<String, Object?>?> start;
  final List<OfflineWrite> writes;

  @override
  String toString() =>
      'start: [${start.map(showWriteData).join(', ')}]\n  writes:\n    ${writes.join('\n    ')}';
}
