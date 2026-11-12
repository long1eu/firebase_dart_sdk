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

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_source.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:fixnum/fixnum.dart';
import 'package:test/fake.dart';

final DatabaseId testDatabaseId =
    DatabaseId.forDatabase('new-project', '(default)');

class FakeFirestore extends Fake implements Firestore {
  FakeFirestore([DatabaseId? databaseId])
      : databaseId = databaseId ?? testDatabaseId;

  @override
  final DatabaseId databaseId;
}

final FakeFirestore fakeFirestore = FakeFirestore();

PipelineSource source() => PipelineSource(fakeFirestore);

PipelineEncoder encoder() => PipelineEncoder(testDatabaseId);

/// The wire form of the stages of [pipeline].
List<pb.Pipeline_Stage> stagesOf(Pipeline pipeline) =>
    pipeline.toProto(encoder()).stages;

/// The wire form of [expression].
pb.Value encode(Expression expression) => expression.toProto(encoder());

pb.Value str(String value) => pb.Value()..stringValue = value;

pb.Value integer(int value) => pb.Value()..integerValue = Int64(value);

pb.Value dbl(double value) => pb.Value()..doubleValue = value;

pb.Value boolean(bool value) => pb.Value()..booleanValue = value;

pb.Value ref(String value) => pb.Value()..referenceValue = value;

pb.Value fieldRef(String path) => pb.Value()..fieldReferenceValue = path;

pb.Value fn(String name, [List<pb.Value> args = const <pb.Value>[]]) {
  return pb.Value()
    ..functionValue = (pb.Function_()
      ..name = name
      ..args.addAll(args));
}

pb.Value arrayValue(List<pb.Value> values) {
  return pb.Value()..arrayValue = (pb.ArrayValue()..values.addAll(values));
}

pb.Value mapValue(Map<String, pb.Value> fields) {
  return pb.Value()..mapValue = (pb.MapValue()..fields.addAll(fields));
}

pb.Pipeline_Stage stage(String name,
    [List<pb.Value> args = const <pb.Value>[],
    Map<String, pb.Value> options = const <String, pb.Value>{}]) {
  return pb.Pipeline_Stage()
    ..name = name
    ..args.addAll(args)
    ..options.addAll(options);
}
