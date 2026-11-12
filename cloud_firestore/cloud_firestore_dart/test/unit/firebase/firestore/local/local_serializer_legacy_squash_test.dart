// Copyright 2018 Google LLC
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

// Port of the legacy-transform squashing tests of upstream LocalSerializerTest
// (testSetMutationAndTransFormMutationAreSquashed, ...,
// testMultipleMutationsAreSquashed) that the Dart port lacks in this exact form.

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

const String _prefix = 'projects/p/databases/d/documents';

class _TestWriteBuilder {
  final proto.Write builder = proto.Write.create();

  _TestWriteBuilder addSet() {
    builder.update = proto.Document.create()
      ..name = '$_prefix/foo/bar'
      ..fields['a'] = (proto_.Value.create()..stringValue = 'b')
      ..fields['num'] = (proto_.Value.create()..integerValue = Int64(1));
    return this;
  }

  _TestWriteBuilder addPatch() {
    builder
      ..update = (proto.Document.create()
        ..name = '$_prefix/bar/baz'
        ..fields['a'] = (proto_.Value.create()..stringValue = 'b')
        ..fields['num'] = (proto_.Value.create()..integerValue = Int64(1)))
      ..updateMask = (proto.DocumentMask.create()..fieldPaths.add('a'))
      ..currentDocument = (proto.Precondition.create()..exists = true);
    return this;
  }

  _TestWriteBuilder addDelete() {
    builder.delete = '$_prefix/baz/quux';
    return this;
  }

  _TestWriteBuilder addUpdateTransforms() {
    builder.updateTransforms.addAll(<proto_.DocumentTransform_FieldTransform>[
      proto_.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'integer'
        ..increment = (proto_.Value.create()..integerValue = Int64(42)),
      proto_.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'double'
        ..increment = (proto_.Value.create()..doubleValue = 13.37),
    ]);
    return this;
  }

  _TestWriteBuilder addLegacyTransform() {
    builder
      ..transform = (proto.DocumentTransform.create()
        ..document = '$_prefix/docs/1'
        ..fieldTransforms.addAll(<proto_.DocumentTransform_FieldTransform>[
          proto_.DocumentTransform_FieldTransform.create()
            ..fieldPath = 'integer'
            ..increment = (proto_.Value.create()..integerValue = Int64(42)),
          proto_.DocumentTransform_FieldTransform.create()
            ..fieldPath = 'double'
            ..increment = (proto_.Value.create()..doubleValue = 13.37),
        ]))
      ..currentDocument = (proto.Precondition.create()..exists = true);
    return this;
  }

  proto.Write build() => builder.clone()..freeze();
}

void main() {
  late RemoteSerializer remoteSerializer;
  late LocalSerializer serializer;
  final Timestamp writeTime = Timestamp.now();
  final proto.Timestamp writeTimeProto = proto.Timestamp.create()
    ..seconds = Int64(writeTime.seconds)
    ..nanos = writeTime.nanoseconds;

  proto.Write setProto() => _TestWriteBuilder().addSet().build();
  proto.Write patchProto() => _TestWriteBuilder().addPatch().build();
  proto.Write deleteProto() => _TestWriteBuilder().addDelete().build();
  proto.Write transformProto() =>
      _TestWriteBuilder().addLegacyTransform().build();

  proto.WriteBatch batchOf(List<proto.Write> writes) => proto.WriteBatch.create()
    ..batchId = 42
    ..writes.addAll(writes)
    ..localWriteTime = writeTimeProto;

  setUp(() {
    remoteSerializer = RemoteSerializer(DatabaseId.forDatabase('p', 'd'));
    serializer = LocalSerializer(remoteSerializer);
  });

  test('testSetMutationAndTransFormMutationAreSquashed', () {
    final MutationBatch decoded = serializer
        .decodeMutationBatch(batchOf(<proto.Write>[setProto(), transformProto()]));
    expect(decoded.mutations, hasLength(1));
    expect(decoded.mutations[0], isA<SetMutation>());
    final proto.Write encoded =
        remoteSerializer.encodeMutation(decoded.mutations[0]);
    final proto.Write expected =
        _TestWriteBuilder().addSet().addUpdateTransforms().build();
    expect(encoded, expected);
  });

  test('testPatchMutationAndTransFormMutationAreSquashed', () {
    final MutationBatch decoded = serializer.decodeMutationBatch(
        batchOf(<proto.Write>[patchProto(), transformProto()]));
    expect(decoded.mutations, hasLength(1));
    expect(decoded.mutations[0], isA<PatchMutation>());
    final proto.Write encoded =
        remoteSerializer.encodeMutation(decoded.mutations[0]);
    final proto.Write expected =
        _TestWriteBuilder().addPatch().addUpdateTransforms().build();
    expect(encoded, expected);
  });

  // Deliberate difference from upstream: upstream's decodeMutationBatch asserts
  // (testTransformAndTransformThrowError, testDeleteAndTransformThrowError)
  // when a legacy transform write does not follow a set or patch. This port
  // instead decodes such a write as a patch on an existing document with the
  // transforms (see testDecodesLegacyTransformAloneAsExistingDocumentPatch),
  // which is what the old TransformMutation meant, so an old persisted cache
  // never fails to open.

  test('testMultipleMutationsAreSquashed', () {
    // INPUT:
    // Set -> Set -> Transform -> Delete -> Patch -> Transform -> Patch
    // OUTPUT (squashed):
    // Set -> Set -> Delete -> Patch -> Patch
    final MutationBatch decoded =
        serializer.decodeMutationBatch(batchOf(<proto.Write>[
      setProto(),
      setProto(),
      transformProto(),
      deleteProto(),
      patchProto(),
      transformProto(),
      patchProto(),
    ]));
    expect(decoded.mutations, hasLength(5));
    final List<proto.Write> allExpected = <proto.Write>[
      _TestWriteBuilder().addSet().build(),
      _TestWriteBuilder().addSet().addUpdateTransforms().build(),
      _TestWriteBuilder().addDelete().build(),
      _TestWriteBuilder().addPatch().addUpdateTransforms().build(),
      _TestWriteBuilder().addPatch().build(),
    ];
    for (int i = 0; i < decoded.mutations.length; i++) {
      final Mutation mutation = decoded.mutations[i];
      expect(remoteSerializer.encodeMutation(mutation), allExpected[i]);
    }
  });
}
