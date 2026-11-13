// Property: a sequence of random writes gives the same document
//  (A) in the local view, which is computed from the overlay of the pending
//      writes (the document is read from the cache while offline),
//  (B) when the mutations are applied one by one to the base document, and
//  (C) on the backend after the writes are committed, and
//  (D) in the cache after the writes are acknowledged, before the document
//      is read back.
//
// Server timestamps are compared by their position only (a pending server
// timestamp locally, a timestamp on the backend).

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/property.dart';
import '../../../util/property_backend.dart'
    show configureGeneratorsForBackend;

/// One write: how to issue it through the public API, the mutation the SDK
/// builds for it, and a description.
class Write {
  Write(this.description, this.issue, this.mutation);

  final String description;
  final Future<void> Function() issue;
  final Mutation mutation;
}

class Scenario {
  Scenario(this.base, this.writes);

  /// The data of the document before the writes, or null if it is missing.
  final Map<String, Object?>? base;
  final List<Write Function(DocumentReference<Map<String, Object?>> doc)>
  writes;
  final List<String> descriptions = <String>[];

  @override
  String toString() =>
      'base: ${base == null ? 'no document' : describe(base)}\n'
      '    writes:\n      ${descriptions.join('\n      ')}';
}

Object _sentinel(Gen gen) {
  num number() => gen.chance(50)
      ? (gen.chance(60) ? gen.between(-5, 5) : gen.integer())
      : (gen.chance(60) ? gen.between(-50, 50) / 10 : gen.float());
  List<Object?> elements() => <Object?>[
    for (int i = gen.between(1, 3); i > 0; i--)
      gen.pick(const <Object?>[
        1, 1.0, 2, 'a', null, true, 0, -0.0, 'b', double.nan, //
        <String, Object?>{'k': 1}, <String, Object?>{'k': 1.0},
      ]),
  ];
  Object named(Object sentinel, String text) {
    _sentinelText[sentinel] = text;
    return sentinel;
  }

  switch (gen.below(6)) {
    case 0:
      return FieldValue.serverTimestamp();
    case 1:
      final List<Object?> e = elements();
      return named(FieldValue.arrayUnion(e), 'arrayUnion(${describe(e)})');
    case 2:
      final List<Object?> e = elements();
      return named(FieldValue.arrayRemove(e), 'arrayRemove(${describe(e)})');
    case 3:
      final num n = number();
      return named(FieldValue.increment(n), 'increment(${describe(n)})');
    case 4:
      final num n = number();
      return named(FieldValue.minimum(n), 'minimum(${describe(n)})');
    default:
      final num n = number();
      return named(FieldValue.maximum(n), 'maximum(${describe(n)})');
  }
}

final Expando<String> _sentinelText = Expando<String>();

String _show(Object? value) {
  if (value is FieldValue) {
    return _sentinelText[value] ?? value.methodName;
  } else if (value is Map) {
    return '{${value.entries.map((MapEntry<Object?, Object?> e) => '${e.key}: ${_show(e.value)}').join(', ')}}';
  }
  return describe(value);
}

/// A value for a field: mostly values that the transforms can work on.
Object? _fieldValue(Gen gen) {
  switch (gen.below(8)) {
    case 0:
      return gen.between(-5, 5);
    case 1:
      return gen.between(-50, 50) / 10;
    case 2:
      return <Object?>[
        for (int i = gen.below(4); i > 0; i--)
          gen.pick(const <Object?>[
            1, 1.0, 2, 'a', null, true, 0, -0.0, double.nan, //
            <String, Object?>{'k': 1},
          ]),
      ];
    case 3:
      return gen.integer();
    case 4:
      return gen.float();
    default:
      return gen.value(depth: 1);
  }
}

Map<String, Object?> _setData(Gen gen, {required bool sentinels}) {
  Object? field() =>
      sentinels && gen.chance(30) ? _sentinel(gen) : _fieldValue(gen);
  return <String, Object?>{
    for (int i = gen.below(gen.size.clamp(1, 4) + 1); i > 0; i--)
      gen.fieldName(): gen.chance(20)
          ? <String, Object?>{
              for (int j = gen.between(1, 2); j > 0; j--)
                gen.pick(const <String>['x', 'y']): field(),
            }
          : field(),
  };
}

Scenario scenario(Gen gen) {
  final Scenario result = Scenario(
    gen.chance(60) ? _setData(gen, sentinels: false) : null,
    <Write Function(DocumentReference<Map<String, Object?>>)>[],
  );

  for (int i = gen.between(1, gen.size.clamp(1, 5)); i > 0; i--) {
    switch (gen.below(10)) {
      case 0:
        result.descriptions.add('delete()');
        result.writes.add(
          (DocumentReference<Map<String, Object?>> doc) => Write(
            'delete()',
            doc.delete,
            DeleteMutation(doc.key, Precondition.none),
          ),
        );
        break;
      case 1:
      case 2:
      case 3:
        // No transforms in a set that overwrites: see the "known
        // difference" test below.
        final Map<String, Object?> data = _setData(gen, sentinels: false);
        result.descriptions.add('set(${_show(data)})');
        result.writes.add(
          (DocumentReference<Map<String, Object?>> doc) => Write(
            'set',
            () => doc.set(data),
            doc.firestore.dataConverter
                .parseSetData(data)
                .toMutation(doc.key, Precondition.none),
          ),
        );
        break;
      case 4:
      case 5:
        final Map<String, Object?> data = _setData(gen, sentinels: true);
        if (gen.chance(30)) {
          data[gen.fieldName()] = FieldValue.delete();
        }
        result.descriptions.add('set(${_show(data)}, merge)');
        result.writes.add(
          (DocumentReference<Map<String, Object?>> doc) => Write(
            'set merge',
            () => doc.set(data, SetOptions.mergeAllFields),
            doc.firestore.dataConverter
                .parseMergeData(data, null)
                .toMutation(doc.key, Precondition.none),
          ),
        );
        break;
      default:
        final Map<String, Object?> data = <String, Object?>{};
        for (int j = gen.between(1, 3); j > 0; j--) {
          final String path = gen.pick(const <String>[
            'a', 'b', 'c', 'd', 'e', 'a.x', 'b.y', 'c.x.z', 'e.x', //
          ]);
          // The SDK rejects a path together with one of its prefixes.
          if (data.keys.any(
            (String other) =>
                other == path ||
                other.startsWith('$path.') ||
                path.startsWith('$other.'),
          )) {
            continue;
          }
          data[path] = gen.chance(20)
              ? FieldValue.delete()
              : gen.chance(40)
              ? _sentinel(gen)
              : _fieldValue(gen);
        }
        result.descriptions.add('update(${_show(data)})');
        result.writes.add(
          (DocumentReference<Map<String, Object?>> doc) => Write(
            'update',
            () => doc.update(data),
            doc.firestore.dataConverter
                .parseUpdateData(data)
                .toMutation(doc.key, Precondition(exists: true)),
          ),
        );
    }
  }
  return result;
}

/// The differences between a local value and the value of the backend,
/// where a pending server timestamp matches any timestamp.
String? difference(
  model.FieldValue? local,
  model.FieldValue? server, {
  required bool serverSide,
  String path = '',
}) {
  if (local == null || server == null) {
    return local == null && server == null
        ? null
        : '$path: ${local ?? 'missing'} vs ${server ?? 'missing'}';
  }
  if (local is model.ServerTimestampValue) {
    if (serverSide) {
      return server is model.TimestampValue
          ? null
          : '$path: pending server timestamp vs $server';
    }
    return server is model.ServerTimestampValue
        ? difference(
            local.previousFieldValue,
            server.previousFieldValue,
            serverSide: serverSide,
            path: '$path(previous)',
          )
        : '$path: pending server timestamp vs $server';
  }
  if (local is model.ObjectValue && server is model.ObjectValue) {
    final Set<String> keys = <String>{
      for (final MapEntry<String, model.FieldValue> e in local.internalValue)
        e.key,
      for (final MapEntry<String, model.FieldValue> e in server.internalValue)
        e.key,
    };
    for (final String key in keys) {
      final String? result = difference(
        local.internalValue[key],
        server.internalValue[key],
        serverSide: serverSide,
        path: path.isEmpty ? key : '$path.$key',
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }
  if (local is model.ArrayValue && server is model.ArrayValue) {
    if (local.internalValue.length != server.internalValue.length) {
      return '$path: $local vs $server';
    }
    for (int i = 0; i < local.internalValue.length; i++) {
      final String? result = difference(
        local.internalValue[i],
        server.internalValue[i],
        serverSide: serverSide,
        path: '$path[$i]',
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }
  return local == server && local.runtimeType == server.runtimeType
      ? null
      : '$path: $local (${local.runtimeType}) vs $server (${server.runtimeType})';
}

/// Property tests write many documents and compare with the emulator: they
/// never run against a real project.
final String? needsEmulator = IntegrationTestUtil.emulatorHost == null
    ? 'Runs against the emulator only: set FIRESTORE_EMULATOR_HOST.'
    : null;

void main() {
  configureGeneratorsForBackend();
  IntegrationTestUtil.currentDatabasePath = 'integration/property_mutation';

  late Firestore firestore;

  setUp(() async {
    firestore = await IntegrationTestUtil.testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<void> check(Scenario scenario) async {
    final DocumentReference<Map<String, Object?>> doc = firestore
        .collection('property_mutation')
        .doc(autoId());
    if (scenario.base != null) {
      await doc.set(scenario.base!);
    }
    final Document? base = (await doc.get(Source.server)).document;

    await firestore.disableNetwork();
    final List<Future<void>> pending = <Future<void>>[];
    final List<Mutation> mutations = <Mutation>[];
    for (final Write Function(DocumentReference<Map<String, Object?>>) build
        in scenario.writes) {
      final Write write = build(doc);
      mutations.add(write.mutation);
      // A write that the backend rejects (an update of a missing document)
      // completes with an error once the client is online again.
      pending.add(write.issue().then<void>((_) {}, onError: (Object _) {}));
    }

    // (A) The local view, from the overlay.
    final Document? viaOverlay = (await doc.get(Source.cache)).document;

    // (B) One mutation at a time.
    MaybeDocument? current = base;
    FieldMask? mask = FieldMask.empty;
    for (final Mutation mutation in mutations) {
      (current, mask) = mutation.applyToLocalViewWithMask(
        current,
        current,
        mask,
        Timestamp.now(),
      );
    }
    final Document? oneByOne = current is Document ? current : null;

    expect(
      viaOverlay == null,
      oneByOne == null,
      reason:
          'existence: via overlay ${viaOverlay?.data}, '
          'one by one ${oneByOne?.data}',
    );
    if (viaOverlay != null) {
      expect(
        difference(viaOverlay.data, oneByOne!.data, serverSide: false),
        isNull,
        reason:
            'overlay vs one by one\n'
            '    via overlay: ${viaOverlay.data}\n'
            '    one by one:  ${oneByOne.data}',
      );
    }

    // (C) The backend.
    await firestore.enableNetwork();
    await Future.wait(pending);
    // (D) The cached document after the acknowledgements: the client
    // computes it from the results of the writes, before anything is read
    // back.
    final Document? acknowledged = (await doc.get(Source.cache)).document;
    final Document? onServer = (await doc.get(Source.server)).document;
    expect(
      acknowledged == null,
      onServer == null,
      reason:
          'existence: cache after the acknowledgements '
          '${acknowledged?.data}, backend ${onServer?.data}',
    );
    if (acknowledged != null) {
      expect(
        difference(acknowledged.data, onServer!.data, serverSide: false),
        isNull,
        reason:
            'cache after the acknowledgements vs backend\n'
            '    cache:   ${acknowledged.data}\n'
            '    backend: ${onServer.data}',
      );
    }
    expect(
      onServer == null,
      oneByOne == null,
      reason:
          'existence: backend ${onServer?.data}, '
          'one by one ${oneByOne?.data}',
    );
    if (onServer != null) {
      expect(
        difference(oneByOne!.data, onServer.data, serverSide: true),
        isNull,
        reason:
            'local vs backend\n'
            '    local:   ${oneByOne.data}\n'
            '    backend: ${onServer.data}',
      );
    }
  }

  // As in the JS and Android SDKs: a transform in a set() that overwrites
  // the document is applied locally to the value the field had before, while
  // the backend applies it to the new document, in which the field is
  // missing. The local view is corrected when the write is acknowledged.
  test(
    'known difference: a transform in an overwriting set()',
    skip: needsEmulator,
    () async {
      final DocumentReference<Map<String, Object?>> doc = firestore
          .collection('property_mutation')
          .doc(autoId());
      await doc.set(<String, Object?>{'count': 5, 'other': 1});
      await doc.get(Source.server);

      await firestore.disableNetwork();
      final Future<void> write = doc.set(<String, Object?>{
        'count': FieldValue.increment(1),
      });
      expect((await doc.get(Source.cache)).data, <String, Object?>{'count': 6});

      await firestore.enableNetwork();
      await write;
      expect((await doc.get(Source.server)).data, <String, Object?>{
        'count': 1,
      });
      expect((await doc.get(Source.cache)).data, <String, Object?>{'count': 1});
    },
  );

  test(
    'pending writes: overlay, one by one and the backend agree',
    skip: needsEmulator,
    () async {
      await forAllAsync<Scenario>(
        'mutation sequences',
        count: cases(60),
        generate: scenario,
        check: check,
        show: (Scenario s) => s.toString(),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
