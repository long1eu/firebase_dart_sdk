// Fuzz: the bundle reader and serializer on malformed bundles.
//
// A bundle is untrusted input (it is usually downloaded). Valid bundles of
// generated documents and queries are mutated (bytes, length prefixes, JSON
// trees, truncation) and delivered in chunks of random sizes. The reader must
// read every element, or reject the bundle cleanly (see isCleanRejection in
// test/util/fuzz.dart) in bounded time; every element it returns must behave
// like a valid one. Loading through the SyncEngine must end the task, with a
// FirestoreError whose cause is a clean rejection on failure.
//
// bundle_hostile_input_test.dart covers the hand-written hostile cases.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_builder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart'
    show DocumentSnapshotInternal;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:grpc/grpc.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import '../../util/fuzz.dart';
import '../../util/property.dart';
import '../../util/property_model.dart';
import '../firebase/firestore/local/persistence_test_helpers.dart';

final BundleSerializer serializer = BundleSerializer(
  RemoteSerializer(modelDatabaseId),
);

/// How long one bundle of a few kilobytes may take to read or load. A
/// rejection that takes longer is a hang (or quadratic work).
const Duration caseTimeout = Duration(seconds: 5);

/// A valid bundle of generated documents and named queries.
String validBundle(Gen gen) {
  final BundleBuilder builder = BundleBuilder(
    RemoteSerializer(modelDatabaseId),
    'bundle-${gen.seed}',
  );
  for (int i = gen.below(4); i > 0; i--) {
    builder.addDocument(gen.document());
  }
  for (int i = gen.below(3); i > 0; i--) {
    final Query query = gen.query();
    if (query.isDocumentQuery || query.isCollectionGroupQuery) {
      continue;
    }
    builder.addNamedQuery('q$i', query, <Document>[
      for (int j = gen.below(3); j > 0; j--) gen.document(),
    ], gen.chance(50) ? gen.snapshotVersion() : gen.snapshotVersion());
  }
  return builder.build();
}

/// The elements of [bundle] (it must be well formed): their JSON strings
/// without the length prefixes.
List<String> elementsOf(String bundle) {
  final List<int> bytes = utf8.encode(bundle);
  final List<String> elements = <String>[];
  int position = 0;
  while (position < bytes.length) {
    final int open = bytes.indexOf(0x7b, position);
    final int length = int.parse(utf8.decode(bytes.sublist(position, open)));
    elements.add(utf8.decode(bytes.sublist(open, open + length)));
    position = open + length;
  }
  return elements;
}

String prefixed(String json) => '${utf8.encode(json).length}$json';

/// JSON values that do not belong where they end up.
Object? hostileJson(Gen gen, [int depth = 0]) {
  switch (gen.below(depth < 3 ? 12 : 8)) {
    case 0:
      return null;
    case 1:
      return gen.chance(50);
    case 2:
      return gen.integer();
    case 3:
      return gen.pick(const <Object>[
        1e308,
        -1e308,
        0.5,
        -0.0,
        1e-320,
        9007199254740993.0,
        1.5e300,
      ]);
    case 4:
      return gen.string();
    case 5:
      return gen.pick(const <String>[
        '', '1', '-1', '1e400', 'NaN', 'Infinity', '9223372036854775808', //
        '-9223372036854775809', '0x10', '2020-01-01T00:00:00Z',
        '0000-01-01T00:00:00Z', '9999-12-31T23:59:59.999999999Z',
        '10000-01-01T00:00:00Z', '2020-13-45T25:61:61Z', '2020-01-01',
        '2020-01-01T00:00:00.1234567891Z',
        'projects/project/databases/(default)/documents',
        'projects/project/databases/(default)/documents/c',
        'projects/other/databases/(default)/documents/c/d', 'AAAA', '!!',
        'FIRST', 'LAST', 'EQUAL', 'ARRAY_CONTAINS_ANY', 'NOT_IN', 'AND', 'OR',
        'IS_NAN', 'DESCENDING', '__name__', 'a.b', '`', '__max__',
      ]);
    case 6:
      return <Object?>[];
    case 7:
      return <String, Object?>{};
    case 8:
      return <Object?>[
        for (int i = gen.below(3); i > 0; i--) hostileJson(gen, depth + 1),
      ];
    case 9:
      return <String, Object?>{
        for (int i = gen.below(3); i > 0; i--)
          gen.pick(const <String>[
            'seconds', 'nanos', 'integerValue', 'stringValue', 'mapValue', //
            'arrayValue', 'fields', 'values', 'fieldPath', 'op', 'value',
            'filters', 'nullValue', 'timestampValue', 'referenceValue',
          ]): hostileJson(
            gen,
            depth + 1,
          ),
      };
    case 10:
      // Deep nesting, spliced in by [encodeHostile]: jsonEncode itself
      // overflows the stack on deep trees.
      return '$_deepMarker${gen.pick(const <int>[50, 101, 1000, 100000])}'
          '${gen.chance(50) ? 'm' : 'a'}';
    default:
      return gen.pick(const <Object>[
        <String, Object?>{'seconds': '1', 'nanos': 1},
        <String, Object?>{'seconds': 1e20, 'nanos': -1},
        <String, Object?>{'seconds': -62135596801},
        <String, Object?>{'seconds': 253402300800},
        <String, Object?>{'nanos': 1000000000},
        <String, Object?>{'integerValue': '1e3'},
        <String, Object?>{'doubleValue': 'Infinity'},
        <String, Object?>{'doubleValue': 'x'},
        <String, Object?>{'bytesValue': '!'},
        <String, Object?>{
          'geoPointValue': <String, Object?>{'latitude': 91},
        },
        <String, Object?>{
          'geoPointValue': <String, Object?>{'longitude': 'NaN'},
        },
        <String, Object?>{
          'referenceValue': 'projects/project/databases/(default)/documents/c',
        },
        <String, Object?>{'referenceValue': 'x'},
        <String, Object?>{'timestampValue': '2020-02-30T00:00:00Z'},
        <String, Object?>{
          'mapValue': <String, Object?>{
            'fields': <String, Object?>{
              '__int__': <String, Object?>{'integerValue': '2147483648'},
            },
          },
        },
      ]);
  }
}

const String _deepMarker = '\u0000deep:';

/// The JSON of [json] with every deep nesting marker of [hostileJson]
/// replaced by a value nested that deep.
String encodeHostile(Object? json) => jsonEncode(json).replaceAllMapped(
  RegExp(r'"\\u0000deep:([0-9]+)([am])"'),
  (Match match) {
    final int depth = int.parse(match[1]!);
    final bool maps = match[2] == 'm';
    final String open = maps
        ? '{"mapValue":{"fields":{"a":'
        : '{"arrayValue":{"values":[';
    final String close = maps ? '}}}' : ']}}';
    return '${open * depth}{"integerValue":"1"}${close * depth}';
  },
);

/// [json] (a decoded element) with one node replaced, removed or duplicated.
Object? mutateJson(Gen gen, Object? json, [int depth = 0]) {
  if (json is Map<String, Object?> && json.isNotEmpty && gen.chance(75)) {
    final Map<String, Object?> copy = Map<String, Object?>.of(json);
    final String key = gen.pick(copy.keys.toList());
    switch (gen.below(10)) {
      case 0:
        copy.remove(key);
        break;
      case 1:
        copy[gen.pick(const <String>['', 'x', '__proto__', 'fields'])] =
            hostileJson(gen);
        break;
      case 2:
        copy[key] = hostileJson(gen);
        break;
      default:
        copy[key] = mutateJson(gen, copy[key], depth + 1);
    }
    return copy;
  }
  if (json is List<Object?> && json.isNotEmpty && gen.chance(75)) {
    final List<Object?> copy = List<Object?>.of(json);
    final int index = gen.below(copy.length);
    switch (gen.below(6)) {
      case 0:
        copy.removeAt(index);
        break;
      case 1:
        copy.insert(index, copy[index]);
        break;
      default:
        copy[index] = mutateJson(gen, copy[index], depth + 1);
    }
    return copy;
  }
  return hostileJson(gen);
}

/// A malformed bundle derived from a valid one.
Uint8List hostileBundle(Gen gen) => switch (gen.below(6)) {
  5 => gen.mutateBytes(
    utf8.encode(validBundle(gen)),
    dictionary: utf8.encode('{}[]":,0123456789-.e\\'),
  ),
  _ => utf8.encode(_hostileBundle(gen)),
};

/// A malformed bundle derived from a valid one, still valid UTF-8.
String _hostileBundle(Gen gen) {
  final String valid = validBundle(gen);
  final List<String> elements = elementsOf(valid);
  switch (gen.below(4)) {
    case 0:
      // Mutated JSON in one or two elements, with correct length prefixes.
      final List<String> mutated = List<String>.of(elements);
      for (int i = gen.between(1, 2); i > 0; i--) {
        final int index = gen.below(elements.length);
        mutated[index] = encodeHostile(
          mutateJson(gen, jsonDecode(elements[index])),
        );
      }
      return mutated.map(prefixed).join();
    case 1:
      // A wrong length prefix.
      final int index = gen.below(elements.length);
      final int length = utf8.encode(elements[index]).length;
      final String prefix = gen.pick(<String>[
        '0', '00$length', '${length - 1}', '${length + 1}', '${length * 2}', //
        '${BundleReader.maxElementBytes}',
        '${BundleReader.maxElementBytes + 1}',
        '-$length', '+$length', ' $length', '$length ', '1e2', '', 'x',
        '99999999999', '18446744073709551617',
      ]);
      return <String>[
        for (int i = 0; i < elements.length; i++)
          i == index ? '$prefix${elements[i]}' : prefixed(elements[i]),
      ].join();
    case 2:
      // Reordered, dropped or duplicated elements.
      final List<String> shuffled = List<String>.of(elements);
      for (int i = gen.between(1, 3); i > 0; i--) {
        final int a = gen.below(shuffled.length);
        switch (gen.below(3)) {
          case 0:
            shuffled.insert(gen.below(shuffled.length + 1), shuffled[a]);
            break;
          case 1:
            if (shuffled.length > 1) {
              shuffled.removeAt(a);
            }
            break;
          default:
            final int b = gen.below(shuffled.length);
            final String t = shuffled[a];
            shuffled[a] = shuffled[b];
            shuffled[b] = t;
        }
      }
      return shuffled.map(prefixed).join();
    default:
      // Truncated anywhere.
      final List<int> bytes = utf8.encode(valid);
      return utf8.decode(
        bytes.sublist(0, gen.below(bytes.length)),
        allowMalformed: true,
      );
  }
}

/// [bytes] in chunks of random sizes, from single bytes to all at once.
Stream<List<int>> chunked(Gen gen, Uint8List bytes) {
  final int mode = gen.below(4);
  final List<List<int>> chunks = <List<int>>[];
  for (int i = 0; i < bytes.length;) {
    final int size = switch (mode) {
      0 => bytes.length,
      1 => 1,
      2 => gen.between(1, 7),
      _ => gen.between(0, 300),
    };
    final int end = (i + size).clamp(0, bytes.length);
    // An empty chunk now and then.
    chunks.add(bytes.sublist(i, end));
    i = end;
  }
  return Stream<List<int>>.fromIterable(chunks);
}

/// An element read from a bundle must behave like a valid one.
void expectUsable(BundleElement element) {
  if (element is BundleDocument) {
    final Document document = element.document;
    final Object? data = acceptOrReject<Object?>(
      () => DocumentSnapshotInternal.fromDocument<Map<String, Object?>>(
        modelFirestore,
        document,
        isFromCache: false,
        hasPendingWrites: false,
      ).data,
      () => '$document',
    );
    if (data != null) {
      expect(document.data.compareTo(document.data), 0);
    }
  } else if (element is NamedQuery) {
    final Query query = element.bundledQuery.query;
    acceptOrReject(() {
      final String canonicalId = query.toTarget().canonicalId;
      expect(query.comparator, isNotNull);
      return canonicalId;
    }, () => '$query');
  }
}

class Case {
  Case(this.bytes, this.gen);

  final Uint8List bytes;
  final Gen gen;

  String get bundle => utf8.decode(bytes, allowMalformed: true);

  @override
  String toString() => bundle.length > 3000
      ? '${bundle.substring(0, 3000)}... (${bundle.length} characters)'
      : bundle;
}

Future<List<BundleElement>?> readBundle(Case c) {
  final BundleReader reader = BundleReader(serializer, chunked(c.gen, c.bytes));
  return acceptOrRejectAsync(() async {
    final List<BundleElement> elements = <BundleElement>[
      await reader.getBundleMetadata(),
    ];
    BundleElement? element;
    while ((element = await reader.getNextElement()) != null) {
      elements.add(element!);
    }
    return elements;
  }, () => '$c').timeout(
    caseTimeout,
    onTimeout: () => throw TimeoutException('Reading the bundle hangs: $c'),
  );
}

class _FakeRemoteStore extends Fake implements RemoteStore {
  @override
  Future<void> listen(QueryData queryData) async {}
}

class _Callback implements SyncEngineCallback {
  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {}

  @override
  void onError(Query query, GrpcError error) {}

  @override
  void handleOnlineStateChange(OnlineState onlineState) {}
}

void main() {
  test('the reader reads valid bundles in chunks of any size', () async {
    await forAllAsync<Case>(
      'valid bundle',
      count: cases(150),
      generate: (Gen gen) => Case(utf8.encode(validBundle(gen)), gen),
      check: (Case c) async {
        final List<BundleElement>? elements = await readBundle(c);
        expect(elements, isNotNull, reason: 'a valid bundle is rejected');
        expect(elements!.length, elementsOf(c.bundle).length);
        elements.forEach(expectUsable);
      },
    );
  });

  test('the reader reads or cleanly rejects malformed bundles', () async {
    await forAllAsync<Case>(
      'malformed bundle',
      count: cases(1500),
      generate: (Gen gen) => Case(hostileBundle(gen), gen),
      check: (Case c) async {
        (await readBundle(c))?.forEach(expectUsable);
      },
    );
  });

  test('loading a malformed bundle ends with a clean FirestoreError', () async {
    final Persistence persistence = await createEagerGCMemoryPersistence();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final SyncEngine syncEngine = SyncEngine(
      localStore,
      _FakeRemoteStore(),
      User.unauthenticated,
    )..syncEngineListener = _Callback();
    addTearDown(persistence.shutdown);

    await forAllAsync<Case>(
      'load malformed bundle',
      count: cases(300),
      generate: (Gen gen) => Case(hostileBundle(gen), gen),
      check: (Case c) async {
        final LoadBundleTask task = LoadBundleTaskInternal.create();
        await syncEngine
            .loadBundle(BundleReader(serializer, chunked(c.gen, c.bytes)), task)
            .timeout(
              caseTimeout,
              onTimeout: () =>
                  throw TimeoutException('Loading the bundle hangs: $c'),
            );
        expect(task.isComplete, isTrue);
        if (task.isSuccessful) {
          return;
        }
        try {
          await task.future;
        } on FirestoreError catch (error) {
          expect(error.code, FirestoreErrorCode.invalidArgument);
          final Object? cause = error.cause;
          if (cause != null &&
              !isCleanRejection(cause, error.stackTrace ?? StackTrace.empty)) {
            fail(
              'The bundle failed to load with ${cause.runtimeType}: $cause\n'
              '  at: ${error.stackTrace}\n  bundle: $c',
            );
          }
        }
      },
    );
  });
}
