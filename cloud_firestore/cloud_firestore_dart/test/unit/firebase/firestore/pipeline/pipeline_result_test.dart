// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// Response decoding, after the JS SDK's test/unit/api/pipeline_impl.test.ts
// ("returns execution time with empty results") and lite-api/pipeline_impl.ts.

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import 'pipeline_test_util.dart';

proto.Timestamp ts(int seconds, [int nanos = 0]) => proto.Timestamp()
  ..seconds = Int64(seconds)
  ..nanos = nanos;

PipelineSnapshot decode(List<proto.ExecutePipelineResponse> responses) {
  return decodePipelineResponses(source().collection('foo'), fakeFirestore,
      encoder().serializer, responses);
}

void main() {
  const String prefix = 'projects/new-project/databases/(default)/documents';

  test('returns the execution time with empty results', () {
    final PipelineSnapshot snapshot = decode(<proto.ExecutePipelineResponse>[
      proto.ExecutePipelineResponse()..executionTime = ts(100, 5000),
    ]);
    expect(snapshot.results, isEmpty);
    expect(snapshot.executionTime, const Timestamp(100, 5000));
  });

  test('has no execution time when the server sends none', () {
    final PipelineSnapshot snapshot = decode(<proto.ExecutePipelineResponse>[
      proto.ExecutePipelineResponse()
        ..results
            .add(proto.Document()..fields['documents_modified'] = integer(1)),
    ]);
    expect(snapshot.executionTime, isNull);
    expect(snapshot.results.single.data(),
        <String, Object?>{'documents_modified': 1});
    expect(decode(<proto.ExecutePipelineResponse>[]).executionTime, isNull);
  });

  test('collects the results of all responses in order', () {
    final PipelineSnapshot snapshot = decode(<proto.ExecutePipelineResponse>[
      proto.ExecutePipelineResponse()
        ..executionTime = ts(1)
        ..results.addAll(<proto.Document>[
          proto.Document()..fields['n'] = integer(1),
          proto.Document()..fields['n'] = integer(2),
        ]),
      proto.ExecutePipelineResponse()..executionTime = ts(2),
      proto.ExecutePipelineResponse()
        ..executionTime = ts(3)
        ..results.add(proto.Document()..fields['n'] = integer(3)),
    ]);
    expect(
        snapshot.results.map((PipelineResult r) => r.get('n')), <int>[1, 2, 3]);
    expect(snapshot.executionTime, const Timestamp(1, 0));
    expect(snapshot.pipeline.toString(), 'Pipeline(collection)');
  });

  test('a document result has a reference and times', () {
    final PipelineResult result = decode(<proto.ExecutePipelineResponse>[
      proto.ExecutePipelineResponse()
        ..results.add(proto.Document()
          ..name = '$prefix/books/b1'
          ..createTime = ts(10)
          ..updateTime = ts(20)
          ..fields['title'] = str('T')),
    ]).results.single;

    expect(result.id, 'b1');
    expect(result.ref!.path, 'books/b1');
    expect(result.createTime, const Timestamp(10, 0));
    expect(result.updateTime, const Timestamp(20, 0));
    expect(result.data(), <String, Object?>{'title': 'T'});
  });

  test('a computed result has no reference and no times', () {
    final PipelineResult result = decode(<proto.ExecutePipelineResponse>[
      proto.ExecutePipelineResponse()
        ..results.add(proto.Document()..fields['avg'] = dbl(2.5)),
    ]).results.single;

    expect(result.id, isNull);
    expect(result.ref, isNull);
    expect(result.createTime, isNull);
    expect(result.updateTime, isNull);
    expect(result.data(), <String, Object?>{'avg': 2.5});
  });

  test('converts values and reads nested fields', () {
    final PipelineResult result = decode(<proto.ExecutePipelineResponse>[
      proto.ExecutePipelineResponse()
        ..results.add(proto.Document()
          ..fields.addAll(<String, pb.Value>{
            'null': pb.Value()..nullValue = pb.Value().nullValue,
            'list': arrayValue(<pb.Value>[integer(1), str('a')]),
            'map': mapValue(<String, pb.Value>{
              'inner': mapValue(<String, pb.Value>{'x': boolean(true)}),
            }),
            'when': pb.Value()..timestampValue = ts(5),
            'ref': ref('$prefix/c/d'),
            'vector': mapValue(<String, pb.Value>{
              '__type__': str('__vector__'),
              'value': arrayValue(<pb.Value>[dbl(1), dbl(2)]),
            }),
            // BSON types decode to their value classes.
            'unknown': mapValue(<String, pb.Value>{'__int__': integer(7)}),
          })),
    ]).results.single;

    expect(result.get('null'), isNull);
    expect(result.get('missing'), isNull);
    expect(result.get('list'), <Object?>[1, 'a']);
    expect(result.get('map.inner.x'), isTrue);
    expect(result.get(FieldPath.of(<String>['map', 'inner'])),
        <String, Object?>{'x': true});
    expect(result.get(field('map.inner.x')), isTrue);
    expect(result.get('when'), const Timestamp(5, 0));
    expect((result.get('ref')! as DocumentReference<Object?>).path, 'c/d');
    expect(result.get('vector'), VectorValue(<double>[1, 2]));
    expect(result.get('unknown'), Int32Value(7));
    expect(result.data().keys,
        containsAll(<String>['null', 'list', 'map', 'when', 'ref', 'vector']));
    expect(() => result.get(1), throwsArgumentError);
  });
}
