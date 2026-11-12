// Security review: a bundle is untrusted input (it is usually downloaded).
// A malformed or hostile one must be rejected quickly, with an ArgumentError
// from the reader (a FirestoreError from the public API), without unbounded
// buffering, quadratic work or a stack overflow.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

const String root = 'projects/p/databases/(default)/documents';
const String metadata =
    '{"metadata":{"id":"b","createTime":{"seconds":1,"nanos":0},"version":1,'
    '"totalDocuments":1,"totalBytes":1}}';

String element(String json) => '${utf8.encode(json).length}$json';

String document(String valueJson) =>
    '{"document":{"name":"$root/c/d","updateTime":{"seconds":1,"nanos":0},'
    '"fields":{"f":$valueJson}}}';

BundleReader reader(Stream<List<int>> data) => BundleReader(
    BundleSerializer(RemoteSerializer(DatabaseId.forProject('p'))), data);

Future<int> readAll(BundleReader reader) async {
  await reader.getBundleMetadata();
  int count = 0;
  while (await reader.getNextElement() != null) {
    count++;
  }
  return count;
}

Stream<List<int>> bytes(String text) =>
    Stream<List<int>>.value(utf8.encode(text));

final Matcher throwsInvalidBundle = throwsA(isA<ArgumentError>().having(
    (ArgumentError e) => '${e.message}',
    'message',
    contains('Invalid bundle')));

void main() {
  group('length prefix', () {
    test('a stream without an element is rejected after a few bytes', () async {
      // 4 MB of digits in 1 KB chunks and no '{'. The reader used to buffer
      // all of it, rescanning and copying the buffer for every chunk.
      int delivered = 0;
      final Stream<List<int>> endless = Stream<List<int>>.fromIterable(
          Iterable<List<int>>.generate(4096, (_) {
        delivered++;
        return Uint8List(1024)..fillRange(0, 1024, 0x31);
      }));

      await expectLater(readAll(reader(endless)), throwsInvalidBundle);
      expect(delivered, lessThanOrEqualTo(2),
          reason: 'The reader kept reading after the prefix was too long.');
    });

    test('a prefix that is not a plain decimal number is rejected', () async {
      for (final String prefix in <String>[
        '-5',
        '+5',
        ' 5',
        '0x10',
        '1e3',
        '99999999999999999999',
        '',
      ]) {
        await expectLater(
            readAll(reader(bytes('$prefix$metadata'))), throwsInvalidBundle,
            reason: 'prefix "$prefix"');
      }
    });

    test('an element longer than the limit is rejected before it is read',
        () async {
      int delivered = 0;
      final String head =
          '${element(metadata)}${BundleReader.maxElementBytes + 1}{"document":';
      final Stream<List<int>> data = Stream<List<int>>.fromIterable(
          Iterable<List<int>>.generate(100000, (int i) {
        delivered++;
        return i == 0 ? utf8.encode(head) : Uint8List(1024);
      }));

      await expectLater(readAll(reader(data)), throwsInvalidBundle);
      expect(delivered, lessThanOrEqualTo(2));
    });
  });

  test('a large element in small chunks is read in linear time', () async {
    // 6 MB delivered in 512 byte chunks: about 12000 chunks. Merging the
    // buffer for every chunk copied tens of gigabytes.
    final String big = document('{"stringValue":"${'a' * (6 * 1024 * 1024)}"}');
    final List<int> all = utf8.encode('${element(metadata)}${element(big)}');
    final Stream<List<int>> chunks = Stream<List<int>>.fromIterable(<List<int>>[
      for (int i = 0; i < all.length; i += 512)
        all.sublist(i, i + 512 > all.length ? all.length : i + 512),
    ]);

    final Stopwatch watch = Stopwatch()..start();
    expect(await readAll(reader(chunks)), 1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  group('element content', () {
    test('wrong JSON types are an invalid bundle, not a TypeError', () async {
      for (final String hostile in <String>[
        element('{"metadata":5}'),
        element('[1,2]'),
        element('"text"'),
        '${element(metadata)}${element('{"namedQuery":[1]}')}',
        '${element(metadata)}${element('{"documentMetadata":"x"}')}',
        '${element(metadata)}${element('{"document":${'[' * 1000}${']' * 1000}}')}',
        '${element(metadata)}${element('{"documentMetadata":{"name":"$root/c/d","readTime":{"seconds":1},"queries":[1]}}')}',
        '${element(metadata)}${element('{"document":{"name":7}}')}',
        '${element(metadata)}${element(document('{"arrayValue":{"values":[5]}}'))}',
        '${element(metadata)}${element(document('{"mapValue":{"fields":{"a":"b"}}}'))}',
        '${element(metadata)}${element(document('"text"'))}',
      ]) {
        await expectLater(readAll(reader(bytes(hostile))), throwsArgumentError,
            reason: hostile.length > 120 ? hostile.substring(0, 120) : hostile);
      }
    });

    test('deeply nested values are rejected without overflowing the stack',
        () async {
      String nested(int depth, String open, String close) =>
          '${open * depth}{"integerValue":"1"}${close * depth}';

      for (final int depth in <int>[1000, 200000]) {
        await expectLater(
            readAll(reader(bytes('${element(metadata)}'
                '${element(document(nested(depth, '{"arrayValue":{"values":[', ']}}')))}'))),
            throwsArgumentError,
            reason: 'arrays, depth $depth');
        await expectLater(
            readAll(reader(bytes('${element(metadata)}'
                '${element(document(nested(depth, '{"mapValue":{"fields":{"a":', '}}}')))}'))),
            throwsArgumentError,
            reason: 'maps, depth $depth');
      }
    });

    test('values nested as deep as Firestore allows are still read', () async {
      // The backend allows 20 levels.
      final String value =
          '${'{"mapValue":{"fields":{"a":' * 20}{"integerValue":"1"}${'}}}' * 20}';
      expect(
          await readAll(
              reader(bytes('${element(metadata)}${element(document(value))}'))),
          1);
    });

    test('deeply nested composite filters are rejected', () async {
      const int depth = 100000;
      final String filter =
          '${'{"compositeFilter":{"op":"AND","filters":[' * depth}'
          '{"fieldFilter":{"field":{"fieldPath":"a"},"op":"EQUAL","value":{"integerValue":"1"}}}'
          '${']}}' * depth}';
      final String query = '{"namedQuery":{"name":"q","readTime":{"seconds":1},'
          '"bundledQuery":{"parent":"$root","structuredQuery":{'
          '"from":[{"collectionId":"c"}],"where":$filter},"limitType":"FIRST"}}}';
      await expectLater(
          readAll(reader(bytes('${element(metadata)}${element(query)}'))),
          throwsArgumentError);
    });

    test('the error for an unknown element does not repeat a huge element',
        () async {
      final String huge = '{"x":"${'a' * 1000000}"}';
      await expectLater(
          readAll(reader(bytes('${element(metadata)}${element(huge)}'))),
          throwsA(isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}'.length,
              'message length',
              lessThan(500))));
    });
  });
}
