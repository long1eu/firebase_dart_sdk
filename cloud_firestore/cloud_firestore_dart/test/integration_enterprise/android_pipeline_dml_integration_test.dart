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

// Ported from the Android SDK:
// firebase-firestore/src/androidTest/java/com/google/firebase/firestore/PipelineDmlIntegrationTest.kt
//
// The cases keep their Kotlin names; android_pipeline_test_util.dart has the
// functions they call. They run against the Enterprise edition emulator of
// FIRESTORE_ENTERPRISE_EMULATOR_HOST (tool/start_enterprise_emulator.sh);
// without it they are skipped. Where Android skips a case on the emulator
// (`assumeFalse(isRunningAgainstEmulator())`), the case here records what
// the emulator answers, with a comment.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables, unawaited_futures
// ignore_for_file: unnecessary_await_in_return, unnecessary_parenthesis
// ignore_for_file: unnecessary_statements

import 'package:test/test.dart'
    show expect, group, isA, setUp, tearDown, test, unorderedEquals;

import '../util/integration_test_util.dart';
import 'android_pipeline_test_util.dart';

final Map<String, Map<String, Object?>> testBookDocs =
    <String, Map<String, Object?>>{
      "book1": <String, Object?>{
        "title": "The Hitchhiker's Guide to the Galaxy",
        "author": "Douglas Adams",
        "genre": "Science Fiction",
        "rating": 4.2,
        "awards": <String, Object?>{"hugo": true, "nebula": false},
      },
      "book2": <String, Object?>{
        "title": "Pride and Prejudice",
        "author": "Jane Austen",
        "genre": "Romance",
        "rating": 4.5,
      },
      "book3": <String, Object?>{
        "title": "One Hundred Years of Solitude",
        "author": "Gabriel García Márquez",
        "genre": "Magical Realism",
        "rating": 4.3,
      },
      "book10": <String, Object?>{
        "title": "Dune",
        "author": "Frank Herbert",
        "genre": "Science Fiction",
        "rating": 4.8,
        "awards": <String, Object?>{"hugo": true},
      },
    };

/// The code of the [FirestoreError] [body] fails with.
Future<FirestoreErrorCode> errorCode(Future<Object?> Function() body) async {
  final Object error = await assertThrows(null, body);
  expect(error, isA<FirestoreError>());
  return (error as FirestoreError).code;
}

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/android_pipeline_dml';
  late Firestore db;
  late CollectionReference<Map<String, Object?>> collRef;

  group(
    'PipelineDmlIntegrationTest',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () {
      setUp(() async {
        collRef = await testCollectionWithDocs(testBookDocs);
        db = collRef.firestore;
      });

      tearDown(() async {
        await IntegrationTestUtil.tearDown();
      });

      Pipeline byId(String id) => db
          .pipeline()
          .collection(collRef.path)
          .where(field(FieldPath.documentIdField).equal(collRef.document(id)));

      // ---- Delete Stage ----

      test('testDeleteSingleDocument', () async {
        final PipelineSnapshot snapshot = await byId(
          "book2",
        ).delete().execute();
        assertThat(snapshot).isNotNull();
        final docSnap = await collRef.document("book2").get();
        assertThat(docSnap.exists).isFalse();
      });

      test('testDeleteMultipleDocumentsWithWhereFilter', () async {
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .collection(collRef.path)
            .where(field("genre").equal(constant("Science Fiction")))
            .delete()
            .execute();
        assertThat(snapshot).isNotNull();
        assertThat((await collRef.document("book1").get()).exists).isFalse();
        assertThat((await collRef.document("book10").get()).exists).isFalse();
      });

      test('testDeleteNonExistingDocument', () async {
        final PipelineSnapshot snapshot = await byId(
          "nonExistingId_999",
        ).delete().execute();
        assertThat(snapshot).isNotNull();
      });

      test('testDeleteWithAtomicTrue', () async {
        final PipelineSnapshot snapshot = await byId(
          "book1",
        ).delete().execute(atomic: true);
        assertThat(snapshot).isNotNull();
        assertThat((await collRef.document("book1").get()).exists).isFalse();
      });

      test('testDeleteWithAtomicFalse', () async {
        final PipelineSnapshot snapshot = await byId(
          "book3",
        ).delete().execute(atomic: false);
        assertThat(snapshot).isNotNull();
        assertThat((await collRef.document("book3").get()).exists).isFalse();
      });

      // ---- Update Stage ----

      test('testUpdateSingleDocWithAddFields', () async {
        final PipelineSnapshot snapshot = await byId("book3")
            .addFields([field(FieldPath.documentIdField).documentId().as("id")])
            .update(transformedFields: [constant("baz").as("foo")])
            .execute();
        assertThat(snapshot).isNotNull();
        final docSnap = await collRef.document("book3").get();
        assertThat(docSnap.get("foo")).isEqualTo("baz");
        assertThat(docSnap.get("id")).isEqualTo("book3");
      });

      test('testUpdateMultipleDocsWithRemoveFields', () async {
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .collection(collRef.path)
            .where(field("genre").equal(constant("Science Fiction")))
            .removeFields(["awards"])
            .update(transformedFields: [constant("Updated").as("status")])
            .execute();
        assertThat(snapshot).isNotNull();
        final docSnap1 = await collRef.document("book1").get();
        assertThat(docSnap1.get("status")).isEqualTo("Updated");
        assertThat(docSnap1.data!.containsKey("awards")).isFalse();
        final docSnap10 = await collRef.document("book10").get();
        assertThat(docSnap10.get("status")).isEqualTo("Updated");
        assertThat(docSnap10.data!.containsKey("awards")).isFalse();
      });

      test('testUpdateWithExpressions', () async {
        final PipelineSnapshot snapshot = await byId("book1")
            .update(
              transformedFields: [
                field("rating").add(constant(1.0)).as("rating"),
              ],
            )
            .execute();
        assertThat(snapshot).isNotNull();
        final docSnap = await collRef.document("book1").get();
        assertThat(docSnap.get("rating")).isEqualTo(5.2);
      });

      test('testUpdateWithSingleVarargExpression', () async {
        final PipelineSnapshot snapshot = await byId("book1")
            .update(
              transformedFields: [constant("UpdatedVariadic").as("status")],
            )
            .execute();
        assertThat(snapshot).isNotNull();
        assertThat(
          (await collRef.document("book1").get()).get("status"),
        ).isEqualTo("UpdatedVariadic");
      });

      test('testUpdateWithMultipleVarargExpressions', () async {
        final PipelineSnapshot snapshot = await byId("book1")
            .update(
              transformedFields: [
                constant("UpdatedMulti").as("status"),
                constant(99).as("newField"),
              ],
            )
            .execute();
        assertThat(snapshot).isNotNull();
        final docSnap = await collRef.document("book1").get();
        assertThat(docSnap.get("status")).isEqualTo("UpdatedMulti");
        assertThat(docSnap.get("newField")).isEqualTo(99);
      });

      test('testUpdateNonExistingDocModifiesZeroDocs', () async {
        final PipelineSnapshot snapshot = await byId("nonExistingId_123")
            .update(transformedFields: [constant("Updated").as("status")])
            .execute();
        assertThat(snapshot).isNotNull();
      });

      test('testUpdateAtomically', () async {
        final PipelineSnapshot snapshot = await byId("book1")
            .update(transformedFields: [constant("AtomicUpdate").as("status")])
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        assertThat(
          (await collRef.document("book1").get()).get("status"),
        ).isEqualTo("AtomicUpdate");
      });

      // ---- Insert Stage (all atomic) ----

      test('testInsertAutoGeneratedId', () async {
        final PipelineSnapshot snapshot = await byId("book1")
            .removeFields(["__name__"])
            .insert(collection: collRef.path)
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final allDocs = await collRef.get();
        assertThat(allDocs.docs.length).isEqualTo(5);
      });

      test('testInsertSpecifiedDocumentIdExpression', () async {
        final targetCol = await testCollection();
        final PipelineSnapshot snapshot = await byId("book1")
            .insert(
              collection: targetCol.path,
              documentId: constant("my_custom_id_123"),
            )
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final docSnap = await targetCol.document("my_custom_id_123").get();
        assertThat(docSnap.exists).isTrue();
        assertThat(
          docSnap.get("title"),
        ).isEqualTo("The Hitchhiker's Guide to the Galaxy");
      });

      test('testInsertFailsWhenDocumentAlreadyExists', () async {
        await assertThrows(
          null,
          () => byId("book1")
              .insert(collection: collRef.path, documentId: constant("book2"))
              .execute(atomic: true),
        );
      });

      test('testInsertIntoDifferentCollection', () async {
        final targetCol = await testCollection();
        final PipelineSnapshot snapshot = await byId(
          "book1",
        ).insert(collection: targetCol.path).execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final targetDocs = await targetCol.get();
        assertThat(targetDocs.docs.length).isEqualTo(1);
        assertThat(
          targetDocs.docs[0].get("title"),
        ).isEqualTo("The Hitchhiker's Guide to the Galaxy");
      });

      test('testInsertIntoCollectionReference', () async {
        final targetCol = await testCollection();
        final PipelineSnapshot snapshot = await byId("book1")
            .insert(
              collection: targetCol,
              documentId: constant("book1_ref_copy"),
            )
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final docSnap = await targetCol.document("book1_ref_copy").get();
        assertThat(docSnap.exists).isTrue();
        assertThat(
          docSnap.get("title"),
        ).isEqualTo("The Hitchhiker's Guide to the Galaxy");
      });

      test(
        'testInsertWithOnlyDocumentIdExpressionUsesInputParentCollection',
        () async {
          final PipelineSnapshot snapshot = await byId(
            "book1",
          ).insert(documentId: constant("book1_copy")).execute(atomic: true);
          assertThat(snapshot).isNotNull();
          final docSnap = await collRef.document("book1_copy").get();
          assertThat(docSnap.exists).isTrue();
          assertThat(
            docSnap.get("title"),
          ).isEqualTo("The Hitchhiker's Guide to the Galaxy");
        },
      );

      test('testInsertWithoutTargetFailsForExistingDocuments', () async {
        assertThat(
          await errorCode(() => byId("book1").insert().execute(atomic: true)),
        ).isEqualTo(FirestoreErrorCode.alreadyExists);
      });

      test('testInsertWithoutTargetUsesLiteralName', () async {
        final targetCol = await testCollection();
        final emptyCol = await testCollection();
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{
                "__name__": targetCol.document("named"),
                "name": "Named Literal",
              },
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .insert()
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final docSnap = await targetCol.document("named").get();
        assertThat(docSnap.exists).isTrue();
        assertThat(docSnap.get("name")).isEqualTo("Named Literal");
      });

      test('testInsertWithoutTargetFailsForLiteralWithoutName', () async {
        final emptyCol = await testCollection();
        assertThat(
          await errorCode(
            () => db
                .pipeline()
                .literals([
                  <String, Object?>{"name": "Unnamed Literal"},
                ])
                .union(db.pipeline().collection(emptyCol.path))
                .insert()
                .execute(atomic: true),
          ),
        ).isEqualTo(FirestoreErrorCode.invalidArgument);
      });

      // ---- Upsert Stage ----

      test('testUpsertExistingDocWithVarargs', () async {
        final PipelineSnapshot snapshot = await byId("book1")
            .upsert(
              additionalFields: [
                constant("Comedy Sci-Fi").as("genre"),
                field("rating").add(constant(0.5)).as("rating"),
              ],
            )
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final docSnap = await collRef.document("book1").get();
        assertThat(docSnap.get("genre")).isEqualTo("Comedy Sci-Fi");
        assertThat(docSnap.get("rating")).isEqualTo(4.7);
      });

      test('testUpsertNewDocWhenDoesNotExist', () async {
        const String newDocId = "new_upsert_doc_id";
        final PipelineSnapshot snapshot = await byId("book1")
            .addFields([
              constant("New Book Title").as("title"),
              constant("Sci-Fi").as("genre"),
            ])
            .upsert(collection: collRef.path, documentId: constant(newDocId))
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final docSnap = await collRef.document(newDocId).get();
        assertThat(docSnap.exists).isTrue();
        assertThat(docSnap.get("title")).isEqualTo("New Book Title");
        assertThat(docSnap.get("genre")).isEqualTo("Sci-Fi");
      });

      test('testUpsertIntoCollectionReferenceAfterAddFields', () async {
        final targetCol = await testCollection();
        final PipelineSnapshot snapshot = await byId("book1")
            .addFields([
              constant("Target Upsert Title").as("title"),
              constant("Target Genre").as("genre"),
            ])
            .upsert(collection: targetCol, documentId: constant("target_doc_1"))
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final docSnap = await targetCol.document("target_doc_1").get();
        assertThat(docSnap.exists).isTrue();
        assertThat(docSnap.get("title")).isEqualTo("Target Upsert Title");
        assertThat(docSnap.get("genre")).isEqualTo("Target Genre");
      });

      test(
        'testUpsertIntoDifferentCollectionWithoutAdditionalFields',
        () async {
          final targetCol = await testCollection();
          final PipelineSnapshot snapshot = await byId("book1")
              .upsert(
                collection: targetCol.path,
                documentId: constant("target_doc_2"),
              )
              .execute(atomic: true);
          assertThat(snapshot).isNotNull();
          final docSnap = await targetCol.document("target_doc_2").get();
          assertThat(docSnap.exists).isTrue();
          assertThat(
            docSnap.get("title"),
          ).isEqualTo("The Hitchhiker's Guide to the Galaxy");
        },
      );

      test('testUpsertWithoutTargetUsesLiteralName', () async {
        final targetCol = await testCollection();
        final emptyCol = await testCollection();
        await targetCol.document("named").set(<String, Object?>{"old": true});
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{
                "__name__": targetCol.document("named"),
                "name": "Named Literal",
              },
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .upsert()
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final docSnap = await targetCol.document("named").get();
        assertThat(docSnap.data).containsExactly(["name", "Named Literal"]);
      });

      test('testUpsertWithoutTargetFailsForLiteralWithoutName', () async {
        final emptyCol = await testCollection();
        assertThat(
          await errorCode(
            () => db
                .pipeline()
                .literals([
                  <String, Object?>{"name": "Unnamed Literal"},
                ])
                .union(db.pipeline().collection(emptyCol.path))
                .upsert()
                .execute(atomic: true),
          ),
        ).isEqualTo(FirestoreErrorCode.invalidArgument);
        assertThat((await emptyCol.get()).docs.isEmpty).isTrue();
      });

      test('testUpsertIntoCollectionGeneratesIdForLiteral', () async {
        final targetCol = await testCollection();
        final emptyCol = await testCollection();
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{"name": "Unnamed Literal"},
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .upsert(collection: targetCol.path)
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final targetDocs = await targetCol.get();
        assertThat(targetDocs.docs.length).isEqualTo(1);
        assertThat(targetDocs.docs[0].id).isNotEmpty();
        assertThat(targetDocs.docs[0].get("name")).isEqualTo("Unnamed Literal");
      });

      // ---- Literals Stage (union with a collection for the security rules) ----

      test('testLiteralsBasicDocuments', () async {
        final emptyCol = await testCollection();
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{"name": "Alice", "age": 30},
              <String, Object?>{"name": "Bob", "age": 25},
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .execute();
        assertThat(snapshot.results).hasSize(2);
        // PORTING NOTE: upstream expects the literals in the order given, but a union has no
        // order: the emulator on Linux returned Bob first. The two documents in any order.
        expect(
          snapshot.results.map((PipelineResult result) => result.data()),
          unorderedEquals(<Map<String, Object?>>[
            <String, Object?>{"name": "Alice", "age": 30},
            <String, Object?>{"name": "Bob", "age": 25},
          ]),
        );
      });

      test('testLiteralsWithExpressions', () async {
        final emptyCol = await testCollection();
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{
                "base": 10,
                "doubled": constant(10).multiply(constant(2)),
              },
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .execute();
        assertThat(snapshot.results).hasSize(1);
        assertThat(
          snapshot.results[0].data(),
        ).containsExactly(["base", 10, "doubled", 20]);
      });

      test('testLiteralsWithExpressionNestedInMap', () async {
        final emptyCol = await testCollection();
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{
                "nested": <String, Object?>{
                  "doubled": constant(10).multiply(constant(2)),
                  "label": "x",
                },
              },
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .execute();
        assertThat(snapshot.results).hasSize(1);
        assertThat(snapshot.results[0].data()).containsExactly([
          "nested",
          <String, Object?>{"doubled": 20, "label": "x"},
        ]);
      });

      test('testLiteralsWithExpressionNestedInList', () async {
        final emptyCol = await testCollection();
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{
                "list": <Object?>[constant(10).multiply(constant(2)), 1],
              },
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .execute();
        assertThat(snapshot.results).hasSize(1);
        assertThat(snapshot.results[0].data()).containsExactly([
          "list",
          <Object?>[20, 1],
        ]);
      });

      test('testLiteralsCombinedWithInsert', () async {
        final targetCol = await testCollection();
        final emptyCol = await testCollection();
        final PipelineSnapshot snapshot = await db
            .pipeline()
            .literals([
              <String, Object?>{"name": "Literal Inserted", "age": 42},
            ])
            .union(db.pipeline().collection(emptyCol.path))
            .insert(collection: targetCol.path)
            .execute(atomic: true);
        assertThat(snapshot).isNotNull();
        final targetDocs = await targetCol.get();
        assertThat(targetDocs.docs.length).isEqualTo(1);
        assertThat(
          targetDocs.docs[0].get("name"),
        ).isEqualTo("Literal Inserted");
        assertThat(targetDocs.docs[0].get("age")).isEqualTo(42);
      });
    },
  );
}
