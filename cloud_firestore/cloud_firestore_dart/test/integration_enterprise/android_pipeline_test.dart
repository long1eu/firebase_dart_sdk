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
// firebase-firestore/src/androidTest/java/com/google/firebase/firestore/PipelineTest.java
//
// The cases keep their Java names; android_pipeline_test_util.dart has the
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

import 'package:test/test.dart' show group, setUp, tearDown, test;

import '../util/integration_test_util.dart';
import 'android_pipeline_test_util.dart';

final Map<String, Map<String, Object?>> bookDocs =
    <String, Map<String, Object?>>{
      "book1": <String, Object?>{
        "title": "The Hitchhiker's Guide to the Galaxy",
        "author": "Douglas Adams",
        "genre": "Science Fiction",
        "published": 1979,
        "rating": 4.2,
        "tags": <Object?>["comedy", "space", "adventure"],
        "awards": <String, Object?>{"hugo": true, "nebula": false},
        "embedding": FieldValue.vector(<double>[
          10.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
        ]),
        "nestedField": <String, Object?>{
          "level.1": <String, Object?>{"level.2": true},
        },
      },
      "book2": <String, Object?>{
        "title": "Pride and Prejudice",
        "author": "Jane Austen",
        "genre": "Romance",
        "published": 1813,
        "rating": 4.5,
        "tags": <Object?>["classic", "social commentary", "love"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          10.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
        ]),
        "awards": <String, Object?>{"none": true},
      },
      "book3": <String, Object?>{
        "title": "One Hundred Years of Solitude",
        "author": "Gabriel García Márquez",
        "genre": "Magical Realism",
        "published": 1967,
        "rating": 4.3,
        "tags": <Object?>["family", "history", "fantasy"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          10.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
        ]),
        "awards": <String, Object?>{"nobel": true, "nebula": false},
      },
      "book4": <String, Object?>{
        "title": "The Lord of the Rings",
        "author": "J.R.R. Tolkien",
        "genre": "Fantasy",
        "published": 1954,
        "rating": 4.7,
        "tags": <Object?>["adventure", "magic", "epic"],
        "sales": <Object?>[100, 200, 50],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          1.0,
          10.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
        ]),
        "awards": <String, Object?>{"hugo": false, "nebula": false},
      },
      "book5": <String, Object?>{
        "title": "The Handmaid's Tale",
        "author": "Margaret Atwood",
        "genre": "Dystopian",
        "published": 1985,
        "rating": 4.1,
        "tags": <Object?>["feminism", "totalitarianism", "resistance"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          1.0,
          1.0,
          10.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
        ]),
        "awards": <String, Object?>{
          "arthur c. clarke": true,
          "booker prize": false,
        },
      },
      "book6": <String, Object?>{
        "title": "Crime and Punishment",
        "author": "Fyodor Dostoevsky",
        "genre": "Psychological Thriller",
        "published": 1866,
        "rating": 4.3,
        "tags": <Object?>["philosophy", "crime", "redemption"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          10.0,
          1.0,
          1.0,
          1.0,
          1.0,
        ]),
        "awards": <String, Object?>{"none": true},
      },
      "book7": <String, Object?>{
        "title": "To Kill a Mockingbird",
        "author": "Harper Lee",
        "genre": "Southern Gothic",
        "published": 1960,
        "rating": 4.2,
        "tags": <Object?>["racism", "injustice", "coming-of-age"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          10.0,
          1.0,
          1.0,
          1.0,
        ]),
        "awards": <String, Object?>{"pulitzer": true},
      },
      "book8": <String, Object?>{
        "title": "1984",
        "author": "George Orwell",
        "genre": "Dystopian",
        "published": 1949,
        "rating": 4.2,
        "tags": <Object?>["surveillance", "totalitarianism", "propaganda"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          10.0,
          1.0,
          1.0,
        ]),
        "awards": <String, Object?>{"prometheus": true},
      },
      "book9": <String, Object?>{
        "title": "The Great Gatsby",
        "author": "F. Scott Fitzgerald",
        "genre": "Modernist",
        "published": 1925,
        "rating": 4.0,
        "tags": <Object?>["wealth", "american dream", "love"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          10.0,
          1.0,
        ]),
        "awards": <String, Object?>{"none": true},
      },
      "book10": <String, Object?>{
        "title": "Dune",
        "author": "Frank Herbert",
        "genre": "Science Fiction",
        "published": 1965,
        "rating": 4.6,
        "tags": <Object?>["politics", "desert", "ecology"],
        "embedding": FieldValue.vector(<double>[
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          1.0,
          10.0,
        ]),
        "awards": <String, Object?>{"hugo": true, "nebula": true},
      },
      "book11": <String, Object?>{
        "title": "Timestamp Book",
        "author": "Timestamp Author",
        "timestamp": DateTime.now(),
      },
    };

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/android_pipeline';
  late CollectionReference<Map<String, Object?>> randomCol;
  late Firestore firestore;

  group('PipelineTest', skip: IntegrationTestUtil.enterpriseEmulatorSkipReason, () {
    setUp(() async {
      randomCol = await testCollectionWithDocs(bookDocs);
      firestore = randomCol.firestore;
    });

    tearDown(() async {
      await IntegrationTestUtil.tearDown();
    });

    test('emptyResults', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .limit(0)
          .execute();
      assertThat((await execute).results).isEmpty();
    });

    test('fullResults', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .execute();
      assertThat((await execute).results).hasSize(11);
    });

    test('aggregateResultsCountAll', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .aggregate([countAll().as("count")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"count": 11},
      ]);
    });

    test('aggregateResultsMany', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("genre").equal("Science Fiction"))
          .aggregate([
            countAll().as("count"),
            ex("rating").average().as("avgRating"),
            field("rating").maximum().as("maxRating"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"count": 10, "avgRating": 4.4, "maxRating": 4.6},
      ]);
    }, skip: "Not supported yet");

    test('groupAndAccumulateResults', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex(field("published")).lessThan(1984))
          .aggregate(
            [ex("rating").average().as("avgRating")],
            groups: ["genre"],
          )
          .where(ex("avgRating").greaterThan(4.3))
          .sort([field("avgRating").descending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"avgRating": 4.7, "genre": "Fantasy"},
        <String, Object?>{"avgRating": 4.5, "genre": "Romance"},
        <String, Object?>{"avgRating": 4.4, "genre": "Science Fiction"},
      ]);
    });

    test('groupAndAccumulateResultsGeneric', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .rawStage("where", [ex(field("published")).lessThan(1984)])
          .rawStage("aggregate", [
            <String, Object?>{"avgRating": ex("rating").average()},
            <String, Object?>{"genre": field("genre")},
          ])
          .rawStage("where", [ex("avgRating").greaterThan(4.3)])
          .rawStage("sort", [field("avgRating").descending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"avgRating": 4.7, "genre": "Fantasy"},
        <String, Object?>{"avgRating": 4.5, "genre": "Romance"},
        <String, Object?>{"avgRating": 4.4, "genre": "Science Fiction"},
      ]);
    });

    test('minAndMaxAccumulations', () async {
      Future<PipelineSnapshot> execute =
          firestore.pipeline().collection(randomCol).aggregate([
            countAll().as("count"),
            field("rating").maximum().as("maxRating"),
            field("published").minimum().as("minPublished"),
          ]).execute();
      dynamic results = (await execute).results;
      assertThat(
        results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"count": 11, "maxRating": 4.7, "minPublished": 1813},
      ]);
    });

    test('canSelectFields', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select(["title", "author"])
          .sort([field("author").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "title": "The Hitchhiker's Guide to the Galaxy",
          "author": "Douglas Adams",
        },
        <String, Object?>{
          "title": "The Great Gatsby",
          "author": "F. Scott Fitzgerald",
        },
        <String, Object?>{"title": "Dune", "author": "Frank Herbert"},
        <String, Object?>{
          "title": "Crime and Punishment",
          "author": "Fyodor Dostoevsky",
        },
        <String, Object?>{
          "title": "One Hundred Years of Solitude",
          "author": "Gabriel García Márquez",
        },
        <String, Object?>{"title": "1984", "author": "George Orwell"},
        <String, Object?>{
          "title": "To Kill a Mockingbird",
          "author": "Harper Lee",
        },
        <String, Object?>{
          "title": "The Lord of the Rings",
          "author": "J.R.R. Tolkien",
        },
        <String, Object?>{
          "title": "Pride and Prejudice",
          "author": "Jane Austen",
        },
        <String, Object?>{
          "title": "The Handmaid's Tale",
          "author": "Margaret Atwood",
        },
        <String, Object?>{
          "title": "Timestamp Book",
          "author": "Timestamp Author",
        },
      ]).inOrder();
    });

    test('whereWithAnd', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            and(
              ex("rating").greaterThan(4.5),
              ex("genre").equal("Science Fiction"),
            ),
          )
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(ID_CORRESPONDENCE).containsExactly(["book10"]);
    });

    test('whereWithOr', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            or(ex("genre").equal("Romance"), ex("genre").equal("Dystopian")),
          )
          .select(["title"])
          .sort([field("title").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "1984"},
        <String, Object?>{"title": "Pride and Prejudice"},
        <String, Object?>{"title": "The Handmaid's Tale"},
      ]);
    });

    test('whereByNorCondition', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            nor(
              ex("genre").equal("Romance"),
              ex("genre").equal("Dystopian"),
              ex("genre").equal("Fantasy"),
              ex("published").greaterThan(1949),
            ),
          )
          .select(["title"])
          .sort([field("title").ascending()])
          .execute();
      assertThat((await execute).results)
          .comparingElementsUsing(DATA_CORRESPONDENCE)
          .containsExactlyElementsIn(<Object?>[
            <String, Object?>{"title": "Crime and Punishment"},
            <String, Object?>{"title": "The Great Gatsby"},
            <String, Object?>{"title": "Timestamp Book"},
          ]);
    });

    test('norConditionWithNull', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "a": false,
              "b": false,
              "c": true,
              "d": constant(null),
            }),
          )
          .select([
            nor(
              field("a").asBoolean(),
              field("b").asBoolean(),
            ).as("twoConditions"),
            nor(
              field("a").asBoolean(),
              field("b").asBoolean(),
              field("c").asBoolean(),
            ).as("threeConditions"),
            nor(
              field("a").asBoolean(),
              field("b").asBoolean(),
              field("d").asBoolean(),
            ).as("threeConditionsWithNull"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "twoConditions": true,
          "threeConditions": false,
          "threeConditionsWithNull": null,
        },
      ]);
    });

    test('selectWithSwitchOn', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(map(<String, Object?>{"value": 2}))
          .select([
            switchOn(
              ex(field("value")).equal(2),
              constant("two"),
              constant("NA"),
            ).as("result1"),
            switchOn(
              ex(field("value")).equal(3),
              constant("three"),
              constant("NA"),
            ).as("result2"),
            switchOn(
              ex(field("value")).equal(1),
              constant("one"),
              ex(field("value")).equal(2),
              constant("two"),
              ex(field("value")).equal(3),
              constant("three"),
              constant("NA"),
            ).as("result3"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"result1": "two", "result2": "NA", "result3": "two"},
      ]);
    });

    test('testSwitchOnWithNoDefaultValueAndNoMatchingCondition', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(map(<String, Object?>{"value": 5}))
          .select([
            switchOn(
              ex(field("value")).equal(1),
              constant("one"),
              ex(field("value")).equal(2),
              constant("two"),
            ).as("result"),
          ])
          .execute();
      dynamic exception = await assertThrows(null, () async => (await execute));
      assertThat(
        exception,
      ).hasMessageThat().contains("all switch cases evaluate to false");
    });

    test('offsetAndLimits', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([ex("author").ascending()])
          .offset(5)
          .limit(3)
          .select(["title", "author"])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "1984", "author": "George Orwell"},
        <String, Object?>{
          "title": "To Kill a Mockingbird",
          "author": "Harper Lee",
        },
        <String, Object?>{
          "title": "The Lord of the Rings",
          "author": "J.R.R. Tolkien",
        },
      ]);
    });

    test('arrayContainsWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("tags").arrayContains("comedy"))
          .select(["title"])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Hitchhiker's Guide to the Galaxy"},
      ]);
    });

    test('arrayContainsAnyWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("tags").arrayContainsAny(<Object?>["comedy", "classic"]))
          .select(["title"])
          .sort([field("title").descending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Hitchhiker's Guide to the Galaxy"},
        <String, Object?>{"title": "Pride and Prejudice"},
      ]);
    });

    test('arrayContainsAllWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            field("tags").arrayContainsAll(<Object?>["adventure", "magic"]),
          )
          .select(["title"])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Lord of the Rings"},
      ]);
    });

    test('arrayLengthWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([field("tags").arrayLength().as("tagsCount")])
          .where(ex("tagsCount").equal(3))
          .execute();
      assertThat((await execute).results).hasSize(10);
    });

    test('arrayFirstWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayFirst().as("firstTagInstanceMethod"),
            ex("tags").arrayFirst().as("firstTagStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "firstTagInstanceMethod": "adventure",
          "firstTagStaticMethod": "adventure",
        },
      ]);

      // Test with empty/null/non-existent arrays
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "empty": <Object?>[],
              "nullval": constant(null),
            }),
          )
          .select([
            ex("empty").arrayFirst().as("emptyResult"),
            ex("nullval").arrayFirst().as("nullResult"),
            ex("nonExistent").arrayFirst().as("absentResult"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"nullResult": null, "absentResult": null},
      ]);
      // no emptyResult as arrayFirst returns UNSET for empty arrays
    });

    test('arrayFirstNWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayFirstN(2).as("firstTagsInstanceMethod"),
            ex("tags").arrayFirstN(constant(4)).as("firstTagsStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "firstTagsInstanceMethod": <Object?>["adventure", "magic"],
          "firstTagsStaticMethod": <Object?>["adventure", "magic", "epic"],
        },
      ]);

      // Test with empty/null/non-existent arrays
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "empty": <Object?>[],
              "nullval": constant(null),
            }),
          )
          .select([
            ex("empty").arrayFirstN(1).as("emptyResult"),
            ex("nullval").arrayFirstN(1).as("nullResult"),
            ex("nonExistent").arrayFirstN(1).as("absentResult"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "emptyResult": <Object?>[],
          "nullResult": null,
          "absentResult": null,
        },
      ]);
    });

    test('arrayLastWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayLast().as("lastTagInstanceMethod"),
            ex("tags").arrayLast().as("lastTagStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "lastTagInstanceMethod": "epic",
          "lastTagStaticMethod": "epic",
        },
      ]);

      // Test with empty/null/non-existent arrays
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "empty": <Object?>[],
              "nullval": constant(null),
            }),
          )
          .select([
            ex("empty").arrayLast().as("emptyResult"),
            ex("nullval").arrayLast().as("nullResult"),
            ex("nonExistent").arrayLast().as("absentResult"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"nullResult": null, "absentResult": null},
      ]);
      // no emptyResult as arrayLast returns UNSET for empty arrays
    });

    test('arrayLastNWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayLastN(2).as("lastTagsInstanceMethod"),
            ex("tags").arrayLastN(constant(4)).as("lastTagsStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "lastTagsInstanceMethod": <Object?>["magic", "epic"],
          "lastTagsStaticMethod": <Object?>["adventure", "magic", "epic"],
        },
      ]);

      // Test with empty/null/non-existent arrays
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "empty": <Object?>[],
              "nullval": constant(null),
            }),
          )
          .select([
            ex("empty").arrayLastN(1).as("emptyResult"),
            ex("nullval").arrayLastN(1).as("nullResult"),
            ex("nonExistent").arrayLastN(1).as("absentResult"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "emptyResult": <Object?>[],
          "nullResult": null,
          "absentResult": null,
        },
      ]);
    });

    test('arrayMinimumWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayMinimum().as("minimumTagInstanceMethod"),
            ex("tags").arrayMinimum().as("minimumTagStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "minimumTagInstanceMethod": "adventure",
          "minimumTagStaticMethod": "adventure",
        },
      ]);

      // Test with empty/null/non-existent and mixed types
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "empty": <Object?>[],
              "nullval": constant(null),
              "mixed": <Object?>[1, "2", 3, "10"],
            }),
          ) // Numbers < Strings in Firestore.
          .select([
            ex("empty").arrayMinimum().as("emptyResult"),
            ex("nullval").arrayMinimum().as("nullResult"),
            ex("nonExistent").arrayMinimum().as("absentResult"),
            ex("mixed").arrayMinimum().as("mixedResult"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "emptyResult": null,
          "nullResult": null,
          "absentResult": null,
          "mixedResult": 1,
        },
      ]);
    });

    test('arrayMinimumNWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayMinimumN(2).as("minimumTagsInstanceMethod"),
            ex("tags").arrayMinimumN(constant(4)).as("minimumTagsStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "minimumTagsInstanceMethod": <Object?>["adventure", "epic"],
          "minimumTagsStaticMethod": <Object?>["adventure", "epic", "magic"],
        },
      ]);
    });

    test('arrayMaximumWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayMaximum().as("maximumTagInstanceMethod"),
            ex("tags").arrayMaximum().as("maximumTagStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "maximumTagInstanceMethod": "magic",
          "maximumTagStaticMethod": "magic",
        },
      ]);

      // Test with empty/null/non-existent and mixed types
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "empty": <Object?>[],
              "nullval": constant(null),
              "mixed": <Object?>[1, "2", 3, "10"],
            }),
          ) // Strings > Numbers in Firestore.
          .select([
            ex("empty").arrayMaximum().as("emptyResult"),
            ex("nullval").arrayMaximum().as("nullResult"),
            ex("nonExistent").arrayMaximum().as("absentResult"),
            ex("mixed").arrayMaximum().as("mixedResult"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "emptyResult": null,
          "nullResult": null,
          "absentResult": null,
          "mixedResult": "2",
        },
      ]);
    });

    test('arrayMaximumNWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags").arrayMaximumN(2).as("maximumTagsInstanceMethod"),
            ex("tags").arrayMaximumN(constant(4)).as("maximumTagsStaticMethod"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "maximumTagsInstanceMethod": <Object?>["magic", "epic"],
          "maximumTagsStaticMethod": <Object?>["magic", "epic", "adventure"],
        },
      ]);
    });

    test('arrayFilterWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            field("tags")
                .arrayFilter(
                  (_) => ex(variable("tag")).notEqual("magic"),
                  alias: "tag",
                )
                .as("notMagicTags"),
            ex("tags")
                .arrayFilter(
                  (_) => ex(variable("tag")).notEqual("epic"),
                  alias: "tag",
                )
                .as("notEpicTags"),
            field("tags")
                .arrayFilter(
                  (_) => ex(variable("tag")).equal("romance"),
                  alias: "tag",
                )
                .as("noMatchingTags"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "notMagicTags": <Object?>["adventure", "epic"],
          "notEpicTags": <Object?>["adventure", "magic"],
          "noMatchingTags": <Object?>[],
        },
      ]);
    });

    test('arrayFilterWithMixedTypesAndNullsWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[
                1,
                "foo",
                constant(null),
                20.0,
                "bar",
                30,
                "40",
                constant(null),
              ],
            }),
          )
          .select([
            field("arr")
                .arrayFilter(
                  (_) => ex(variable("element")).greaterThan(10),
                  alias: "element",
                )
                .as("filtered"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "filtered": <Object?>[20.0, 30],
        },
      ]);
    });

    test('supportsArrayTransformAndArrayTransformWithIndex', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[10, 20, 30],
            }),
          )
          .select([
            ex("arr")
                .arrayTransform(
                  (_) => ex(variable("element")).multiply(10),
                  alias: "element",
                )
                .as("staticTransform"),
            field("arr")
                .arrayTransform(
                  (_) => ex(variable("element")).multiply(10),
                  alias: "element",
                )
                .as("instanceTransform"),
            ex("arr")
                .arrayTransformWithIndex(
                  (_, __) => ex(variable("element")).add(variable("i")),
                  elementAlias: "element",
                  indexAlias: "i",
                )
                .as("staticTransformWithIndex"),
            field("arr")
                .arrayTransformWithIndex(
                  (_, __) => ex(variable("element")).add(variable("i")),
                  elementAlias: "element",
                  indexAlias: "i",
                )
                .as("instanceTransformWithIndex"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "staticTransform": <Object?>[100, 200, 300],
          "instanceTransform": <Object?>[100, 200, 300],
          "staticTransformWithIndex": <Object?>[10, 21, 32],
          "instanceTransformWithIndex": <Object?>[10, 21, 32],
        },
      ]);
    });

    test('supportsArrayTransformWithEmptyArrayAndNulls', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[1, null, 3],
              "empty": <Object?>[],
            }),
          )
          .select([
            field("arr")
                .arrayTransform(
                  (_) => ex(variable("element")).add(1),
                  alias: "element",
                )
                .as("transformedWithNulls"),
            field("empty")
                .arrayTransform(
                  (_) => ex(variable("element")).add(1),
                  alias: "element",
                )
                .as("transformedEmpty"),
            field("arr")
                .arrayTransformWithIndex(
                  (_, __) => ex(variable("element")).add(variable("idx")),
                  elementAlias: "element",
                  indexAlias: "idx",
                )
                .as("transformedWithIndex"),
            field("empty")
                .arrayTransformWithIndex(
                  (_, __) => ex(variable("element")).add(variable("idx")),
                  elementAlias: "element",
                  indexAlias: "idx",
                )
                .as("transformedEmptyWithIndex"),
          ])
          .execute();
      dynamic expectedMap = <String, Object?>{};
      expectedMap["transformedWithNulls"] = <Object?>[2, null, 4];
      expectedMap["transformedEmpty"] = <Object?>[];
      expectedMap["transformedWithIndex"] = <Object?>[1, null, 5];
      expectedMap["transformedEmptyWithIndex"] = <Object?>[];
      assertThat((await execute).results)
          .comparingElementsUsing(DATA_CORRESPONDENCE)
          .containsExactly([expectedMap]);
    });

    test('arraySliceWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            ex("tags").arraySlice(1, 1).as("staticMethodSlice"),
            ex("tags").arraySlice(1).as("staticMethodSliceToEnd"),
            field("tags").arraySlice(1, 1).as("instanceMethodSlice"),
            field("tags").arraySlice(1).as("instanceMethodSliceToEnd"),
            field("tags").arraySlice(1, 10).as("overflowLength"),
            field("tags").arraySlice(-1, 1).as("negativeOffset"),
            field("tags").arraySlice(-1).as("negativeOffsetSliceToEnd"),
            field("tags").arraySlice(10).as("overflowOffset"),
            field("tags").arraySlice(-10).as("negativeOverflowOffset"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "staticMethodSlice": <Object?>["magic"],
          "staticMethodSliceToEnd": <Object?>["magic", "epic"],
          "instanceMethodSlice": <Object?>["magic"],
          "instanceMethodSliceToEnd": <Object?>["magic", "epic"],
          "overflowLength": <Object?>["magic", "epic"],
          "overflowOffset": <Object?>[],
          "negativeOffset": <Object?>["epic"],
          "negativeOffsetSliceToEnd": <Object?>["epic"],
          "negativeOverflowOffset": <Object?>["adventure", "magic", "epic"],
        },
      ]);
    });

    test('arraySliceThrowsErrorForNegativeLength', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([ex("tags").arraySlice(1, -1).as("negativeLengthSlice")])
          .execute();
      dynamic exception = await assertThrows(null, () async => (await execute));
      assertThat(
        exception,
      ).hasMessageThat().contains("length must be non-negative");
    });

    test('arrayIndexOfWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            ex(field("tags")).arrayIndexOf("adventure").as("indexFirst"),
            ex("tags").arrayIndexOf("magic").as("indexSecond"),
            field("tags").arrayIndexOf("epic").as("indexLast"),
            ex("tags").arrayIndexOf("nonexistent").as("indexNone"),
            ex("empty").arrayIndexOf("anything").as("indexEmpty"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "indexFirst": 0,
          "indexSecond": 1,
          "indexLast": 2,
          "indexNone": -1,
          "indexEmpty": null,
        },
      ]);

      // Test with duplicate values
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[1, 2, 3, 2, 1],
            }),
          )
          .select([ex("arr").arrayIndexOf(2).as("firstIndex")])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"firstIndex": 1},
      ]);

      // Test with null value
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[1, constant(null), 3, 2, 1],
              "nullArr": constant(null),
            }),
          )
          .select([
            ex("arr").arrayIndexOf(null).as("firstIndex"),
            ex("nullArr").arrayIndexOf(null).as("firstIndexNull"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"firstIndex": 1, "firstIndexNull": null},
      ]);
    });

    test('arrayLastIndexOfWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            ex(
              field("tags"),
            ).arrayLastIndexOf("adventure").as("lastIndexFirst"),
            ex("tags").arrayLastIndexOf("magic").as("lastIndexSecond"),
            field("tags").arrayLastIndexOf("epic").as("lastIndexLast"),
            ex("tags").arrayLastIndexOf("nonexistent").as("lastIndexNone"),
            ex("empty").arrayLastIndexOf("anything").as("lastIndexEmpty"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "lastIndexFirst": 0,
          "lastIndexSecond": 1,
          "lastIndexLast": 2,
          "lastIndexNone": -1,
          "lastIndexEmpty": null,
        },
      ]);

      // Test with duplicate values
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[1, 2, 3, 2, 1],
            }),
          )
          .select([ex("arr").arrayLastIndexOf(2).as("lastIndex")])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"lastIndex": 3},
      ]);

      // Test with null value
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[1, constant(null), 3, 2, 1],
              "nullArr": constant(null),
            }),
          )
          .select([
            ex("arr").arrayLastIndexOf(null).as("lastIndex"),
            ex("nullArr").arrayLastIndexOf(null).as("lastIndexNull"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"lastIndex": 1, "lastIndexNull": null},
      ]);
    });

    test('arrayIndexOfAllWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            ex(field("tags")).arrayIndexOfAll("adventure").as("indicesFirst"),
            ex("tags").arrayIndexOfAll("magic").as("indicesSecond"),
            field("tags").arrayIndexOfAll("epic").as("indicesLast"),
            ex("tags").arrayIndexOfAll("nonexistent").as("indicesNone"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "indicesFirst": <Object?>[0],
          "indicesSecond": <Object?>[1],
          "indicesLast": <Object?>[2],
          "indicesNone": <Object?>[],
        },
      ]);

      // Test with duplicate values
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[1, 2, 3, 2, 1],
            }),
          )
          .select([ex("arr").arrayIndexOfAll(2).as("indices")])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "indices": <Object?>[1, 3],
        },
      ]);

      // Test with null value
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "arr": <Object?>[1, constant(null), 3, constant(null), 1],
              "nullArr": constant(null),
            }),
          )
          .select([
            ex("arr").arrayIndexOfAll(null).as("indices"),
            ex("nullArr").arrayIndexOfAll(null).as("indicesNull"),
            ex(
              "nonExistentArray",
            ).arrayIndexOfAll(null).as("indicesNonExistentArray"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "indices": <Object?>[1, 3],
          "indicesNull": null,
          "indicesNonExistentArray": null,
        },
      ]);
    });

    test('arrayConcatWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            field(
              "tags",
            ).arrayConcat(<Object?>["newTag1", "newTag2"]).as("modifiedTags"),
          ])
          .limit(1)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "modifiedTags": <Object?>[
            "comedy",
            "space",
            "adventure",
            "newTag1",
            "newTag2",
          ],
        },
      ]);
    }, skip: "Not supported yet");

    test('arraySumWorks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([ex("sales").arraySum().as("totalSales")])
          .limit(1)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"totalSales": 350},
      ]);
    });

    test('testConcat', () async {
      // String concat
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex(
              field("author"),
            ).concat([" ", field("title")]).as("author_title"),
          ])
          .execute();
      dynamic result = (await execute).results[0].data();
      assertThat(
        result["author_title"],
      ).isEqualTo("Douglas Adams The Hitchhiker's Guide to the Galaxy");

      // Array concat
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex(field("tags"))
                .concat([
                  <Object?>["newTag"],
                ])
                .as("new_tags"),
          ])
          .execute();
      result = (await execute).results[0].data();
      assertThat(
        result["new_tags"],
      ).containsExactly(["comedy", "space", "adventure", "newTag"]).inOrder();

      // Blob concat
      dynamic bytes1 = <int>[1, 2];
      dynamic bytes2 = <int>[3, 4];
      dynamic expected = <int>[1, 2, 3, 4];
      execute = firestore.pipeline().collection(randomCol).limit(1).select([
        ex(
          constant(blobFromBytes(bytes1)),
        ).concat([blobFromBytes(bytes2)]).as("concatenated_blob"),
      ]).execute();
      result = (await execute).results[0].data();
      assertThat((result["concatenated_blob"]).bytes).isEqualTo(expected);

      // Mismatched types should fail
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex(field("title")).concat([field("tags")]).as("mismatched"),
          ])
          .execute();
      assertThat(await waitForException(execute)).isNotNull();
    });

    test('testStrConcat', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([ex(field('__name__')).ascending()])
          .select([
            ex(
              field("author"),
            ).stringConcat([constant(" - "), field("title")]).as("bookInfo"),
          ])
          .limit(1)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "bookInfo": "Douglas Adams - The Hitchhiker's Guide to the Galaxy",
        },
      ]);
    });

    test('testStartsWith', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").startsWith("The"))
          .select(["title"])
          .sort([field("title").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Great Gatsby"},
        <String, Object?>{"title": "The Handmaid's Tale"},
        <String, Object?>{"title": "The Hitchhiker's Guide to the Galaxy"},
        <String, Object?>{"title": "The Lord of the Rings"},
      ]);
    });

    test('testEndsWith', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").endsWith("y"))
          .select(["title"])
          .sort([field("title").descending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Hitchhiker's Guide to the Galaxy"},
        <String, Object?>{"title": "The Great Gatsby"},
      ]);
    });

    test('testLength', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([
            field("title").charLength().as("titleLength"),
            field("title"),
          ])
          .where(ex("titleLength").greaterThan(20))
          .sort([field("title").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "titleLength": 29,
          "title": "One Hundred Years of Solitude",
        },
        <String, Object?>{
          "titleLength": 36,
          "title": "The Hitchhiker's Guide to the Galaxy",
        },
        <String, Object?>{"titleLength": 21, "title": "The Lord of the Rings"},
        <String, Object?>{"titleLength": 21, "title": "To Kill a Mockingbird"},
      ]);
    });

    test('canComputeTheLengthOfStringValue', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .limit(1)
          .select([field("title").length().as("titleLength")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"titleLength": 36},
      ]);
    });

    test('canComputeTheLengthOfStringValueWithTheTopLevelFunction', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .limit(1)
          .select([ex("title").length().as("titleLength")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"titleLength": 36},
      ]);
    });

    test('canComputeTheLengthOfArrayValue', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .limit(1)
          .select([field("tags").length().as("tagsLength")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"tagsLength": 3},
      ]);
    });

    test('canComputeTheLengthOfArrayValueWithTheTopLevelFunction', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .limit(1)
          .select([ex("tags").length().as("tagsLength")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"tagsLength": 3},
      ]);
    });

    test('canComputeTheLengthOfMapValue', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .limit(1)
          .select([field("awards").length().as("awardsLength")])
          .execute();
      // The "awards" map for this book is {"hugo": true, "nebula": false}, which has a length of 2.
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"awardsLength": 2},
      ]);
    });

    test('canComputeTheLengthOfVectorValue', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .limit(1)
          .select([field("embedding").length().as("embeddingLength")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"embeddingLength": 10},
      ]);
    });

    test('testToLowercase', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([field('__name__').ascending()])
          .select([field("title").toLower().as("lowercaseTitle")])
          .limit(1)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "lowercaseTitle": "the hitchhiker's guide to the galaxy",
        },
      ]);
    });

    test('testToUppercase', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([field('__name__').ascending()])
          .select([field("author").toUpper().as("uppercaseAuthor")])
          .limit(1)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"uppercaseAuthor": "DOUGLAS ADAMS"},
      ]);
    });

    test('testTrim', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([field(FieldPath.documentId()).ascending()])
          .limit(1)
          .addFields([
            ex(
              constant("  "),
            ).stringConcat([field("title"), " \t "]).as("spacedTitle"),
          ])
          .select([
            "spacedTitle",
            field("spacedTitle").trim().as("trimmedTitle"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "spacedTitle": "  The Hitchhiker's Guide to the Galaxy \t ",
          "trimmedTitle": "The Hitchhiker's Guide to the Galaxy",
        },
      ]);
    });

    test('testTrimWithCharacters', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([field(FieldPath.documentId()).ascending()])
          .limit(1)
          .addFields([
            ex(
              constant("_-"),
            ).stringConcat([field("title"), "-_"]).as("paddedTitle"),
          ])
          .select([
            field("paddedTitle").trim("_-").as("trimmedTitle"),
            "paddedTitle",
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "paddedTitle": "_-The Hitchhiker's Guide to the Galaxy-_",
          "trimmedTitle": "The Hitchhiker's Guide to the Galaxy",
        },
      ]);
    });

    test('testLTrim', () async {
      // Android skips this case on the emulator ("Not implemented."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "strWhitespace": "  trimMe  ",
              "strChars": "xxxtrimMe",
              "chars": "x",
            }),
          )
          .select([
            ex(constant("  trimMe  ")).ltrim().as("staticLtrimExpr"),
            ex("strWhitespace").ltrim().as("staticLtrimStr"),
            field("strWhitespace").ltrim().as("instLtrim"),
            ex(constant("xxxtrimMe")).ltrim("x").as("staticLtrimValueExprPrim"),
            ex(
              constant("xxxtrimMe"),
            ).ltrim(constant("x")).as("staticLtrimValueExprExpr"),
            ex("strChars").ltrim("x").as("staticLtrimValueStrPrim"),
            ex("strChars").ltrim(field("chars")).as("staticLtrimValueStrExpr"),
            field("strChars").ltrim("x").as("instLtrimValuePrim"),
            field("strChars").ltrim(field("chars")).as("instLtrimValueExpr"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      assertThat(result["staticLtrimExpr"]).isEqualTo("trimMe  ");
      assertThat(result["staticLtrimStr"]).isEqualTo("trimMe  ");
      assertThat(result["instLtrim"]).isEqualTo("trimMe  ");

      assertThat(result["staticLtrimValueExprPrim"]).isEqualTo("trimMe");
      assertThat(result["staticLtrimValueExprExpr"]).isEqualTo("trimMe");
      assertThat(result["staticLtrimValueStrPrim"]).isEqualTo("trimMe");
      assertThat(result["staticLtrimValueStrExpr"]).isEqualTo("trimMe");
      assertThat(result["instLtrimValuePrim"]).isEqualTo("trimMe");
      assertThat(result["instLtrimValueExpr"]).isEqualTo("trimMe");
    });

    test('testRTrim', () async {
      // Android skips this case on the emulator ("Not implemented."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "strWhitespace": "  trimMe  ",
              "strChars": "trimMexxx",
              "chars": "x",
            }),
          )
          .select([
            ex(constant("  trimMe  ")).rtrim().as("staticRtrimExpr"),
            ex("strWhitespace").rtrim().as("staticRtrimStr"),
            field("strWhitespace").rtrim().as("instRtrim"),
            ex(constant("trimMexxx")).rtrim("x").as("staticRtrimValueExprPrim"),
            ex(
              constant("trimMexxx"),
            ).rtrim(constant("x")).as("staticRtrimValueExprExpr"),
            ex("strChars").rtrim("x").as("staticRtrimValueStrPrim"),
            ex("strChars").rtrim(field("chars")).as("staticRtrimValueStrExpr"),
            field("strChars").rtrim("x").as("instRtrimValuePrim"),
            field("strChars").rtrim(field("chars")).as("instRtrimValueExpr"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      assertThat(result["staticRtrimExpr"]).isEqualTo("  trimMe");
      assertThat(result["staticRtrimStr"]).isEqualTo("  trimMe");
      assertThat(result["instRtrim"]).isEqualTo("  trimMe");

      assertThat(result["staticRtrimValueExprPrim"]).isEqualTo("trimMe");
      assertThat(result["staticRtrimValueExprExpr"]).isEqualTo("trimMe");
      assertThat(result["staticRtrimValueStrPrim"]).isEqualTo("trimMe");
      assertThat(result["staticRtrimValueStrExpr"]).isEqualTo("trimMe");
      assertThat(result["instRtrimValuePrim"]).isEqualTo("trimMe");
      assertThat(result["instRtrimValueExpr"]).isEqualTo("trimMe");
    });

    test('testStringRepeat', () async {
      // Android skips this case on the emulator ("Not implemented."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(map(<String, Object?>{"str": "ha", "count": 3}))
          .select([
            ex(constant("ha")).stringRepeat(3).as("staticExprPrim"),
            ex(constant("ha")).stringRepeat(constant(3)).as("staticExprExpr"),
            ex("str").stringRepeat(3).as("staticStrPrim"),
            ex("str").stringRepeat(field("count")).as("staticStrExpr"),
            field("str").stringRepeat(3).as("instPrim"),
            field("str").stringRepeat(field("count")).as("instExpr"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      assertThat(result["staticExprPrim"]).isEqualTo("hahaha");
      assertThat(result["staticExprExpr"]).isEqualTo("hahaha");
      assertThat(result["staticStrPrim"]).isEqualTo("hahaha");
      assertThat(result["staticStrExpr"]).isEqualTo("hahaha");
      assertThat(result["instPrim"]).isEqualTo("hahaha");
      assertThat(result["instExpr"]).isEqualTo("hahaha");
    });

    test('testStringReplaceAll', () async {
      // Android skips this case on the emulator ("Not implemented."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "str": "hello world",
              "old": "o",
              "new": "a",
            }),
          )
          .select([
            ex(
              constant("hello world"),
            ).stringReplaceAll("o", "a").as("staticExprPrim"),
            ex(constant("hello world"))
                .stringReplaceAll(constant("o"), constant("a"))
                .as("staticExprExpr"),
            ex("str").stringReplaceAll("o", "a").as("staticStrPrim"),
            ex(
              "str",
            ).stringReplaceAll(field("old"), field("new")).as("staticStrExpr"),
            field("str").stringReplaceAll("o", "a").as("instPrim"),
            field(
              "str",
            ).stringReplaceAll(field("old"), field("new")).as("instExpr"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      assertThat(result["staticExprPrim"]).isEqualTo("hella warld");
      assertThat(result["staticExprExpr"]).isEqualTo("hella warld");
      assertThat(result["staticStrPrim"]).isEqualTo("hella warld");
      assertThat(result["staticStrExpr"]).isEqualTo("hella warld");
      assertThat(result["instPrim"]).isEqualTo("hella warld");
      assertThat(result["instExpr"]).isEqualTo("hella warld");
    });

    test('testStringReplaceOne', () async {
      // Android skips this case on the emulator ("Not implemented."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "str": "hello world",
              "old": "o",
              "new": "a",
            }),
          )
          .select([
            ex(
              constant("hello world"),
            ).stringReplaceOne("o", "a").as("staticExprPrim"),
            ex(constant("hello world"))
                .stringReplaceOne(constant("o"), constant("a"))
                .as("staticExprExpr"),
            ex("str").stringReplaceOne("o", "a").as("staticStrPrim"),
            ex(
              "str",
            ).stringReplaceOne(field("old"), field("new")).as("staticStrExpr"),
            field("str").stringReplaceOne("o", "a").as("instPrim"),
            field(
              "str",
            ).stringReplaceOne(field("old"), field("new")).as("instExpr"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      assertThat(result["staticExprPrim"]).isEqualTo("hella world");
      assertThat(result["staticExprExpr"]).isEqualTo("hella world");
      assertThat(result["staticStrPrim"]).isEqualTo("hella world");
      assertThat(result["staticStrExpr"]).isEqualTo("hella world");
      assertThat(result["instPrim"]).isEqualTo("hella world");
      assertThat(result["instExpr"]).isEqualTo("hella world");
    });

    test('testStringIndexOf', () async {
      // Android skips this case on the emulator ("Not implemented."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{"str": "hello world", "sub": "world"}),
          )
          .select([
            ex(
              constant("hello world"),
            ).stringIndexOf("world").as("staticExprPrim"),
            ex(
              constant("hello world"),
            ).stringIndexOf(constant("world")).as("staticExprExpr"),
            ex("str").stringIndexOf("world").as("staticStrPrim"),
            ex("str").stringIndexOf(field("sub")).as("staticStrExpr"),
            field("str").stringIndexOf("world").as("instPrim"),
            field("str").stringIndexOf(field("sub")).as("instExpr"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      assertThat(result["staticExprPrim"]).isEqualTo(6);
      assertThat(result["staticExprExpr"]).isEqualTo(6);
      assertThat(result["staticStrPrim"]).isEqualTo(6);
      assertThat(result["staticStrExpr"]).isEqualTo(6);
      assertThat(result["instPrim"]).isEqualTo(6);
      assertThat(result["instExpr"]).isEqualTo(6);
    });

    test('testLike', () async {
      // Android skips this case on the emulator ("Regexes are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").like("%Guide%"))
          .select(["title"])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Hitchhiker's Guide to the Galaxy"},
      ]);
    });

    test('testJoin', () async {
      // Test join with a constant delimiter
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([ex("tags").join(", ").as("joined_tags")])
          .execute();
      dynamic result = (await execute).results[0].data();
      assertThat(result["joined_tags"]).isEqualTo("comedy, space, adventure");

      // Test join with an expression delimiter
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([ex(field("tags")).join(constant(" | ")).as("joined_tags")])
          .execute();
      result = (await execute).results[0].data();
      assertThat(result["joined_tags"]).isEqualTo("comedy | space | adventure");

      // Test extension method
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([field("tags").join(" - ").as("joined_tags")])
          .execute();
      result = (await execute).results[0].data();
      assertThat(result["joined_tags"]).isEqualTo("comedy - space - adventure");
    });

    test('testRegexContains', () async {
      // Android skips this case on the emulator ("Regexes are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").regexContains("(?i)(the|of)"))
          .execute();
      assertThat((await execute).results).hasSize(5);
    });

    test('testRegexFind', () async {
      // Android skips this case on the emulator ("Regexes are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([ex("title").regexFind("^\\w+").as("firstWordInTitle")])
          .sort([field("firstWordInTitle").ascending()])
          .limit(3)
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"firstWordInTitle": "1984"},
        <String, Object?>{"firstWordInTitle": "Crime"},
        <String, Object?>{"firstWordInTitle": "Dune"},
      ]);
    });

    test('testRegexFindAll', () async {
      // Android skips this case on the emulator ("Regexes are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([ex("title").regexFindAll("\\w+").as("wordsInTitle")])
          .sort([field("wordsInTitle").ascending()])
          .limit(3)
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "wordsInTitle": <Object?>["1984"],
        },
        <String, Object?>{
          "wordsInTitle": <Object?>["Crime", "and", "Punishment"],
        },
        <String, Object?>{
          "wordsInTitle": <Object?>["Dune"],
        },
      ]);
    });

    test('testRegexMatches', () async {
      // Android skips this case on the emulator ("Regexes are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").regexContains(".*(?i)(the|of).*"))
          .execute();
      assertThat((await execute).results).hasSize(5);
    });

    test('testArithmeticOperations', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([ex(field('__name__')).ascending()])
          .limit(1)
          .select([
            ex(field("rating")).add(1).as("ratingPlusOne"),
            ex(field("published")).subtract(1900).as("yearsSince1900"),
            field("rating").multiply(10).as("ratingTimesTen"),
            field("rating").divide(2).as("ratingDividedByTwo"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "ratingPlusOne": 5.2,
          "yearsSince1900": 79,
          "ratingTimesTen": 42,
          "ratingDividedByTwo": 2.1,
        },
      ]);
    });

    test('testComparisonOperators', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            and(
              ex("rating").greaterThan(4.2),
              ex(field("rating")).lessThanOrEqual(4.5),
              ex("genre").notEqual("Science Function"),
            ),
          )
          .select(["rating", "title"])
          .sort([field("title").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"rating": 4.3, "title": "Crime and Punishment"},
        <String, Object?>{
          "rating": 4.3,
          "title": "One Hundred Years of Solitude",
        },
        <String, Object?>{"rating": 4.5, "title": "Pride and Prejudice"},
      ]);
    });

    test('testLogicalOperators', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            or(
              and(
                ex("rating").greaterThan(4.5),
                ex("genre").equal("Science Fiction"),
              ),
              ex(field("published")).lessThan(1900),
            ),
          )
          .select(["title"])
          .sort([field("title").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "Crime and Punishment"},
        <String, Object?>{"title": "Dune"},
        <String, Object?>{"title": "Pride and Prejudice"},
      ]);
    });

    test('testChecks', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([ex(field('__name__')).ascending()])
          .where(field("rating").notEqual(double.nan))
          .select([
            field("rating").equal(constant(null)).as("ratingIsNull"),
            field("rating").equal(constant(null)).as("ratingEqNull"),
            not(field("rating").equal(double.nan)).as("ratingIsNotNan"),
          ])
          .limit(1)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "ratingIsNull": false,
          "ratingEqNull": false,
          "ratingIsNotNan": true,
        },
      ]);
    });

    test('testLogicalMax', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(field("author").equal("Douglas Adams"))
          .select([
            field("rating").logicalMaximum([4.5]).as("max_rating"),
            ex(field("published")).logicalMaximum([1900]).as("max_published"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"max_rating": 4.5, "max_published": 1979},
      ]);
    });

    test('testLogicalMin', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(field("author").equal("Douglas Adams"))
          .select([
            field("rating").logicalMinimum([4.5]).as("min_rating"),
            ex(field("published")).logicalMinimum([1900]).as("min_published"),
          ])
          .execute();
      dynamic results = (await execute).results;
      assertThat(
        results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"min_rating": 4.2, "min_published": 1900},
      ]);
    });

    test('testMapGet', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sort([field("title").descending()])
          .select([
            field("awards").mapGet("hugo").as("hugoAward"),
            field("title"),
          ])
          .where(ex("hugoAward").equal(true))
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "hugoAward": true,
          "title": "The Hitchhiker's Guide to the Galaxy",
        },
        <String, Object?>{"hugoAward": true, "title": "Dune"},
      ]);
    });

    test('testMapSet', () async {
      // Android skips this case on the emulator ("Map functions are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      dynamic docData = <String, Object?>{};
      docData["existingField"] = <String, Object?>{"foo": 1};

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .replaceWith(map(docData))
          .limit(1)
          .select([
            ex("existingField").mapSet("bar", 2).as("modifiedField"),
            ex(map(<String, Object?>{})).mapSet("a", 1).as("simple"),
            ex(map(<String, Object?>{"a": 1})).mapSet("b", 2).as("add"),
            ex(map(<String, Object?>{"a": 1})).mapSet("a", 2).as("overwrite"),
            ex(
              map(<String, Object?>{"a": 1, "b": 2}),
            ).mapSet("a", 3, ["c", 4]).as("multi"),
            ex(
              map(<String, Object?>{"a": 1}),
            ).mapSet("a", field("non_existent")).as("remove"),
            ex(map(<String, Object?>{"a": 1})).mapSet("b", null).as("setNull"),
            ex(
              map(<String, Object?>{
                "a": <String, Object?>{"b": 1},
              }),
            ).mapSet("a.b", 2).as("setDotted"),
            ex(map(<String, Object?>{})).mapSet("", "empty").as("setEmptyKey"),
            ex(
              map(<String, Object?>{"a": 1}),
            ).mapSet("b", ex(constant(1)).add(constant(2))).as("setExprVal"),
            ex(map(<String, Object?>{}))
                .mapSet("obj", <String, Object?>{"hidden": true})
                .as("setNestedMap"),
            ex(
              map(<String, Object?>{}),
            ).mapSet("~!@#\$%^&*()_+", "special").as("setSpecialChars"),
            field(
              "existingField",
            ).mapSet("instanceKey", 100).as("instanceSetField"),
            map(<String, Object?>{
              "x": 1,
            }).mapSet(constant("y"), constant(2)).as("instanceSetConstant"),
          ])
          .execute();

      dynamic resultList = (await execute).results;
      assertThat(resultList).isNotEmpty();
      dynamic data = resultList[0].data();

      assertThat(data["modifiedField"]).containsExactly(["foo", 1, "bar", 2]);
      assertThat(data["simple"]).containsExactly(["a", 1]);
      assertThat(data["add"]).containsExactly(["a", 1, "b", 2]);
      assertThat(data["overwrite"]).containsExactly(["a", 2]);
      assertThat(data["multi"]).containsExactly(["a", 3, "b", 2, "c", 4]);
      assertThat(data["remove"]).isEmpty();
      assertThat(data["setNull"]).containsExactly(["a", 1, "b", null]);

      dynamic setDotted = data["setDotted"];
      assertThat(setDotted).containsEntry("a.b", 2);
      assertThat(setDotted["a"]).containsExactly(["b", 1]);

      assertThat(data["setEmptyKey"]).containsExactly(["", "empty"]);
      assertThat(data["setExprVal"]).containsExactly(["a", 1, "b", 3]);
      assertThat(data["setNestedMap"]).isEqualTo(<String, Object?>{
        "obj": <String, Object?>{"hidden": true},
      });
      assertThat(
        data["setSpecialChars"],
      ).containsExactly(["~!@#\$%^&*()_+", "special"]);

      assertThat(
        data["instanceSetField"],
      ).containsExactly(["foo", 1, "instanceKey", 100]);
      assertThat(data["instanceSetConstant"]).containsExactly(["x", 1, "y", 2]);
    });

    test('testMapKeys', () async {
      // Android skips this case on the emulator ("Map functions are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      dynamic docData = <String, Object?>{};
      docData["existingField"] = <String, Object?>{"foo": 1};

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .replaceWith(map(docData))
          .limit(1)
          .select([
            ex("existingField").mapKeys().as("existingKeys"),
            ex(map(<String, Object?>{"a": 1, "b": 2})).mapKeys().as("keys"),
            ex(map(<String, Object?>{})).mapKeys().as("empty_keys"),
            ex(
              map(<String, Object?>{
                "a": <String, Object?>{"nested": true},
              }),
            ).mapKeys().as("nested_keys"),
            field("existingField").mapKeys().as("instanceExistingKeys"),
            map(<String, Object?>{
              "x": 10,
              "y": 20,
            }).mapKeys().as("instanceKeys"),
          ])
          .execute();

      dynamic resultList = (await execute).results;
      assertThat(resultList).isNotEmpty();
      dynamic data = resultList[0].data();

      assertThat(data["existingKeys"]).containsExactly(["foo"]);
      assertThat(data["keys"]).containsExactly(["a", "b"]);
      assertThat(data["empty_keys"]).isEmpty();
      assertThat(data["nested_keys"]).containsExactly(["a"]);

      assertThat(data["instanceExistingKeys"]).containsExactly(["foo"]);
      assertThat(data["instanceKeys"]).containsExactly(["x", "y"]);
    });

    test('testMapValues', () async {
      // Android skips this case on the emulator ("Map functions are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      dynamic docData = <String, Object?>{};
      docData["existingField"] = <String, Object?>{"foo": 1};

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .replaceWith(map(docData))
          .limit(1)
          .select([
            ex("existingField").mapValues().as("existingValues"),
            ex(map(<String, Object?>{"a": 1, "b": 2})).mapValues().as("values"),
            ex(map(<String, Object?>{})).mapValues().as("empty_values"),
            ex(
              map(<String, Object?>{
                "a": <String, Object?>{"nested": true},
              }),
            ).mapValues().as("nested_values"),
            field("existingField").mapValues().as("instanceExistingValues"),
            map(<String, Object?>{
              "x": 10,
              "y": 20,
            }).mapValues().as("instanceValues"),
          ])
          .execute();

      dynamic resultList = (await execute).results;
      assertThat(resultList).isNotEmpty();
      dynamic data = resultList[0].data();

      assertThat(data["existingValues"]).containsExactly([1]);
      assertThat(data["values"]).containsExactly([1, 2]);
      assertThat(data["empty_values"]).isEmpty();
      assertThat(data["nested_values"]).containsExactly([
        <String, Object?>{"nested": true},
      ]);

      assertThat(data["instanceExistingValues"]).containsExactly([1]);
      assertThat(data["instanceValues"]).containsExactly([10, 20]);
    });

    test('testMapEntries', () async {
      // Android skips this case on the emulator ("Map functions are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      dynamic docData = <String, Object?>{};
      docData["existingField"] = <String, Object?>{"foo": 1};

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .replaceWith(map(docData))
          .limit(1)
          .select([
            ex("existingField").mapEntries().as("existingEntries"),
            ex(
              map(<String, Object?>{"a": 1, "b": 2}),
            ).mapEntries().as("entries"),
            ex(map(<String, Object?>{})).mapEntries().as("empty_entries"),
            ex(
              map(<String, Object?>{
                "a": <String, Object?>{"nested": true},
              }),
            ).mapEntries().as("nested_entries"),
            field("existingField").mapEntries().as("instanceExistingEntries"),
            map(<String, Object?>{
              "x": 10,
              "y": 20,
            }).mapEntries().as("instanceEntries"),
          ])
          .execute();

      dynamic resultList = (await execute).results;
      assertThat(resultList).isNotEmpty();
      dynamic data = resultList[0].data();

      assertThat(data["existingEntries"]).containsExactly([
        <String, Object?>{"k": "foo", "v": 1},
      ]);
      dynamic entries = data["entries"];
      assertThat(entries).hasSize(2);

      // Map entry order is not guaranteed, so we check containment instead of strict ordering
      assertThat(entries).contains(<String, Object?>{"k": "a", "v": 1});
      assertThat(entries).contains(<String, Object?>{"k": "b", "v": 2});

      assertThat(data["empty_entries"]).isEmpty();
      assertThat(data["nested_entries"]).containsExactly([
        <String, Object?>{
          "k": "a",
          "v": <String, Object?>{"nested": true},
        },
      ]);

      assertThat(data["instanceExistingEntries"]).containsExactly([
        <String, Object?>{"k": "foo", "v": 1},
      ]);
      dynamic instanceEntries = data["instanceEntries"];
      assertThat(instanceEntries).hasSize(2);
      assertThat(
        instanceEntries,
      ).contains(<String, Object?>{"k": "x", "v": 10});
      assertThat(
        instanceEntries,
      ).contains(<String, Object?>{"k": "y", "v": 20});
    });

    test('testDistanceFunctions', () async {
      dynamic sourceVector = <double>[0.1, 0.1];
      dynamic targetVector = <double>[0.5, 0.8];
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([
            ex(
              constant(FieldValue.vector(sourceVector)),
            ).cosineDistance(targetVector).as("cosineDistance"),
            ex(
              constant(FieldValue.vector(sourceVector)),
            ).dotProduct(targetVector).as("dotProductDistance"),
            ex(
              constant(FieldValue.vector(sourceVector)),
            ).euclideanDistance(targetVector).as("euclideanDistance"),
          ])
          .limit(1)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "cosineDistance": 0.02560880430538015,
          "dotProductDistance": 0.13,
          "euclideanDistance": 0.806225774829855,
        },
      ]);
    });

    test('testNestedFields', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("awards.hugo").equal(true))
          .select(["title", "awards.hugo"])
          .sort([field("title").descending()])
          .execute();

      Map<String, Object?> hitchhikerResult;
      Map<String, Object?> duneResult;

      hitchhikerResult = <String, Object?>{
        "title": "The Hitchhiker's Guide to the Galaxy",
        "awards": <String, Object?>{"hugo": true},
      };
      duneResult = <String, Object?>{
        "title": "Dune",
        "awards": <String, Object?>{"hugo": true},
      };

      assertThat((await execute).results)
          .comparingElementsUsing(DATA_CORRESPONDENCE)
          .containsExactly([hitchhikerResult, duneResult]);
    });

    test('testMapGetWithFieldNameIncludingDotNotation', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("awards.hugo").equal(true))
          .sort([field("title").descending()])
          .select([
            "title",
            field("nestedField.level.1"),
            ex("nestedField").mapGet("level.1").mapGet("level.2").as("nested"),
          ])
          .execute();

      Map<String, Object?> hitchhikerResult;
      Map<String, Object?> duneResult;
      hitchhikerResult = <String, Object?>{
        "title": "The Hitchhiker's Guide to the Galaxy",
        "nestedField": <String, Object?>{"level": <String, Object?>{}},
        "nested": true,
      };
      duneResult = <String, Object?>{
        "title": "Dune",
        "nestedField": <String, Object?>{"level": <String, Object?>{}},
        "nested": null,
      };

      assertThat((await execute).results)
          .comparingElementsUsing(DATA_CORRESPONDENCE)
          .containsExactly([hitchhikerResult, duneResult]);
    });

    test('testListEquals', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            ex("tags").equal(<Object?>["philosophy", "crime", "redemption"]),
          )
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(ID_CORRESPONDENCE).containsExactly(["book6"]);
    });

    test('testMapEquals', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            ex(
              "awards",
            ).equal(<String, Object?>{"nobel": true, "nebula": false}),
          )
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(ID_CORRESPONDENCE).containsExactly(["book3"]);
    });

    test('testAllDataTypes', () async {
      DateTime refDate = DateTime.now();
      dynamic refTimestamp = Timestamp.now();
      GeoPoint refGeoPoint = GeoPoint(1, 2);
      dynamic refBytes = blobFromBytes(<int>[1, 2, 3]);

      dynamic refMap = <String, Object?>{
        "number": 1,
        "string": "a string",
        "boolean": true,
        "null": null,
        "geoPoint": refGeoPoint,
        "timestamp": refTimestamp,
        "date": Timestamp.fromDate(refDate),
        "bytes": refBytes,
      };

      dynamic refArray = <Object?>[
        1,
        "a string",
        true,
        null,
        refTimestamp,
        refGeoPoint,
        Timestamp.fromDate(refDate),
        refBytes,
      ];

      Future<PipelineSnapshot> execute =
          firestore.pipeline().collection(randomCol.path).limit(1).select([
            constant(1).as("number"),
            constant("a string").as("string"),
            constant(true).as("boolean"),
            constant(null).as("null"),
            constant(refTimestamp).as("timestamp"),
            constant(refDate).as("date"),
            constant(refGeoPoint).as("geoPoint"),
            constant(refBytes).as("bytes"),
            map(refMap).as("map"),
            array(refArray).as("array"),
          ]).execute();

      dynamic expectedData = <String, Object?>{};
      expectedData["number"] = 1;
      expectedData["string"] = "a string";
      expectedData["boolean"] = true;
      expectedData["null"] = null;
      expectedData["timestamp"] = refTimestamp;
      expectedData["date"] = Timestamp.fromDate(refDate);
      expectedData["geoPoint"] = refGeoPoint;
      expectedData["bytes"] = refBytes;
      expectedData["map"] = refMap;
      expectedData["array"] = refArray;

      assertThat((await execute).results)
          .comparingElementsUsing(DATA_CORRESPONDENCE)
          .containsExactly([expectedData]);
    });

    test('testResultMetadata', () async {
      dynamic pipeline = firestore.pipeline().collection(randomCol.path);
      dynamic snapshot = (await pipeline.execute());
      assertThat(snapshot.executionTime).isNotNull();

      for (final result in snapshot.results) {
        assertThat(result.createTime).isAtMost(result.updateTime);
        assertThat(
          result.updateTime.compareTo(snapshot.executionTime),
        ).isLessThan(0);
      }

      (await randomCol.document("book1").update(<String, Object?>{
        "rating": 5.0,
      }));
      snapshot = (await pipeline
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .execute());
      for (final result in snapshot.results) {
        assertThat(
          result.createTime.compareTo(result.updateTime),
        ).isLessThan(0);
      }
    });

    test('testResultIsEqual', () async {
      dynamic pipeline = firestore.pipeline().collection(randomCol.path).sort([
        field("title").ascending(),
      ]);
      dynamic snapshot1 = (await pipeline.limit(1).execute());
      dynamic snapshot2 = (await pipeline.limit(1).execute());
      dynamic snapshot3 = (await pipeline.offset(1).limit(1).execute());

      assertThat(snapshot1.results).hasSize(1);
      assertThat(snapshot2.results).hasSize(1);
      assertThat(snapshot3.results).hasSize(1);
      // Android compares results with equals(); Dart has no == on
      // PipelineResult and, as JS, compares them with pipelineResultEqual.
      assertThat(
        pipelineResultEqual(snapshot1.results[0], snapshot2.results[0]),
      ).isTrue();
      assertThat(
        pipelineResultEqual(snapshot1.results[0], snapshot3.results[0]),
      ).isFalse();
    });

    test('testAggregateResultMetadata', () async {
      dynamic pipeline = firestore.pipeline().collection(randomCol).aggregate([
        countAll().as("count"),
      ]);
      dynamic snapshot = (await pipeline.execute());
      assertThat(snapshot.results).hasSize(1);
      assertThat(snapshot.executionTime).isNotNull();

      dynamic aggregateResult = snapshot.results[0];
      assertThat(aggregateResult.createTime).isNull();
      assertThat(aggregateResult.updateTime).isNull();

      // Ensure execution time is recent, within a tolerance.
      dynamic now = DateTime.now().millisecondsSinceEpoch;
      dynamic executionTime = snapshot.executionTime
          .toDate()
          .millisecondsSinceEpoch;
      assertThat(now - executionTime).isLessThan(3000); // 3 seconds tolerance
    });

    test('addAndRemoveFields', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(field("author").notEqual("Timestamp Author"))
          .addFields([
            ex(
              field("author"),
            ).stringConcat(["_", field("title")]).as("author_title"),
            ex(
              field("title"),
            ).stringConcat(["_", field("author")]).as("title_author"),
          ])
          .removeFields([
            "title_author",
            "tags",
            "awards",
            "rating",
            "title",
            "embedding",
          ])
          .removeFields(["published", "genre", "nestedField", "sales"])
          .sort([field("author_title").ascending()])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "author_title": "Douglas Adams_The Hitchhiker's Guide to the Galaxy",
          "author": "Douglas Adams",
        },
        <String, Object?>{
          "author_title": "F. Scott Fitzgerald_The Great Gatsby",
          "author": "F. Scott Fitzgerald",
        },
        <String, Object?>{
          "author_title": "Frank Herbert_Dune",
          "author": "Frank Herbert",
        },
        <String, Object?>{
          "author_title": "Fyodor Dostoevsky_Crime and Punishment",
          "author": "Fyodor Dostoevsky",
        },
        <String, Object?>{
          "author_title":
              "Gabriel García Márquez_One Hundred Years of Solitude",
          "author": "Gabriel García Márquez",
        },
        <String, Object?>{
          "author_title": "George Orwell_1984",
          "author": "George Orwell",
        },
        <String, Object?>{
          "author_title": "Harper Lee_To Kill a Mockingbird",
          "author": "Harper Lee",
        },
        <String, Object?>{
          "author_title": "J.R.R. Tolkien_The Lord of the Rings",
          "author": "J.R.R. Tolkien",
        },
        <String, Object?>{
          "author_title": "Jane Austen_Pride and Prejudice",
          "author": "Jane Austen",
        },
        <String, Object?>{
          "author_title": "Margaret Atwood_The Handmaid's Tale",
          "author": "Margaret Atwood",
        },
      ]).inOrder();
    });

    test('testDistinct', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("published").lessThan(1900))
          .distinct([field("genre").toLower().as("lower_genre")])
          .sort([field("lower_genre").descending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"lower_genre": "romance"},
        <String, Object?>{"lower_genre": "psychological thriller"},
      ]);
    });

    test('testReplaceWith', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .replaceWith("awards")
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"hugo": true, "nebula": false},
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .replaceWith(
            map(<String, Object?>{
              "foo": "bar",
              "baz": map(<String, Object?>{"title": field("title")}),
            }),
          )
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "foo": "bar",
          "baz": <String, Object?>{
            "title": "The Hitchhiker's Guide to the Galaxy",
          },
        },
      ]);
    });

    test('testSampleLimit', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .sample(documents: 3)
          .execute();
      assertThat((await execute).results).hasSize(3);
    });

    test('testUnion', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .union(firestore.pipeline().collection(randomCol))
          .execute();
      assertThat((await execute).results).hasSize(22);
    });

    test('testUnnest', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .unnest(field("tags").as("tag"))
          .execute();
      assertThat((await execute).results).hasSize(3);
    });

    test('testPaginationWithStartAfter', () async {
      dynamic paginationCollection = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          "doc1": <String, Object?>{"order": 1},
          "doc2": <String, Object?>{"order": 2},
          "doc3": <String, Object?>{"order": 3},
          "doc4": <String, Object?>{"order": 4},
        },
      );

      dynamic pipeline = firestore
          .pipeline()
          .collection(paginationCollection)
          .sort([ex("order").ascending()])
          .limit(2);

      dynamic snapshot = (await pipeline.execute());
      assertThat(
        snapshot.results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"order": 1},
        <String, Object?>{"order": 2},
      ]);

      dynamic lastResult = snapshot.results[snapshot.results.length - 1];
      dynamic startedAfter = paginationCollection.orderBy("order").startAfter(
        <Object?>[lastResult.get("order")],
      );
      snapshot = (await firestore
          .pipeline()
          .createFrom(startedAfter)
          .execute());
      assertThat(
        snapshot.results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"order": 3},
        <String, Object?>{"order": 4},
      ]);
    });

    test('testFindNearest', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .findNearest(
            "embedding",
            constant(
              FieldValue.vector(<double>[
                10.0,
                1.0,
                2.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
                1.0,
              ]),
            ),
            DistanceMeasure.euclidean,
            limit: 2,
            distanceField: "computedDistance",
          )
          .select(["title", "computedDistance"])
          .execute();
      dynamic results = (await execute).results;
      assertThat(results).hasSize(2);
      assertThat(
        results[0].data()["title"],
      ).isEqualTo("The Hitchhiker's Guide to the Galaxy");
      assertThat(
        results[0].data()["computedDistance"],
      ).isWithin(0.00001).of(1.0);
      assertThat(
        results[1].data()["title"],
      ).isEqualTo("One Hundred Years of Solitude");
      assertThat(
        results[1].data()["computedDistance"],
      ).isWithin(0.00001).of(12.041594578792296);
    });

    test('testMoreAggregates', () async {
      Future<PipelineSnapshot> execute =
          firestore.pipeline().collection(randomCol).aggregate([
            ex("rating").sum().as("sum_rating"),
            ex("rating").count().as("count_rating"),
            ex("genre").countDistinct().as("distinct_genres"),
          ]).execute();
      dynamic result = (await execute).results[0].data();
      assertThat(result["sum_rating"]).isWithin(0.00001).of(43.1);
      assertThat(result["count_rating"]).isEqualTo(10);
      assertThat(result["distinct_genres"]).isEqualTo(8);
    });

    test('testCountIfAggregate', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .aggregate([
            ex(field("rating")).greaterThan(4.3).countIf().as("count"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"count": 3},
      ]);
    });

    test('testFirstAndLastAccumulators', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex(field("published")).greaterThan(0))
          .sort([ex(field("published")).ascending()])
          .aggregate([
            ex("rating").first().as("firstBookRating"),
            field("title").first().as("firstBookTitle"),
            ex("rating").last().as("lastBookRating"),
            field("title").last().as("lastBookTitle"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "firstBookRating": 4.5,
          "firstBookTitle": "Pride and Prejudice",
          "lastBookRating": 4.1,
          "lastBookTitle": "The Handmaid's Tale",
        },
      ]);
    });

    test('testArrayAggAccumulators', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex(field("published")).greaterThan(0))
          .sort([ex(field("published")).ascending()])
          .aggregate([ex("rating").arrayAgg().as("allRatings")])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "allRatings": <Object?>[
            4.5,
            4.3,
            4.0,
            4.2,
            4.7,
            4.2,
            4.6,
            4.3,
            4.2,
            4.1,
          ],
        },
      ]);
    });

    test('testArrayAggAccumulatorsWithInstanceMethod', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex(field("published")).greaterThan(0))
          .sort([ex(field("published")).ascending()])
          .aggregate([field("rating").arrayAgg().as("allRatings")])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "allRatings": <Object?>[
            4.5,
            4.3,
            4.0,
            4.2,
            4.7,
            4.2,
            4.6,
            4.3,
            4.2,
            4.1,
          ],
        },
      ]);
    });

    test('testArrayAggDistinctAccumulators', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex(field("published")).greaterThan(0))
          .aggregate([ex("rating").arrayAggDistinct().as("allDistinctRatings")])
          .execute();

      dynamic result = (await execute).results[0].data();
      dynamic distinctRatings = result["allDistinctRatings"];
      assertThat(
        distinctRatings,
      ).containsExactly([4.0, 4.1, 4.2, 4.3, 4.5, 4.6, 4.7]);
    });

    test('testArrayAggDistinctAccumulatorsWithInstanceMethod', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex(field("published")).greaterThan(0))
          .aggregate([
            field("rating").arrayAggDistinct().as("allDistinctRatings"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      dynamic distinctRatings = result["allDistinctRatings"];
      assertThat(
        distinctRatings,
      ).containsExactly([4.0, 4.1, 4.2, 4.3, 4.5, 4.6, 4.7]);
    });

    test('testStringFunctions', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([
            field("title").stringReverse().as("reversed_title"),
            field("author"),
          ])
          .where(field("author").equal("Douglas Adams"))
          .execute();
      assertThat(
        (await execute).results[0].data()["reversed_title"],
      ).isEqualTo("yxalaG eht ot ediuG s'rekihhctiH ehT");

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([
            field("author"),
            field("title")
                .stringConcat(["_银河系漫", "游指南"])
                .byteLength()
                .as("title_byte_length"),
          ])
          .where(field("author").equal("Douglas Adams"))
          .execute();
      assertThat(
        (await execute).results[0].data()["title_byte_length"],
      ).isEqualTo(58);
    });

    test('testStrContains', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex(field("title")).stringContains("'s"))
          .select(["title"])
          .sort([field("title").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Handmaid's Tale"},
        <String, Object?>{"title": "The Hitchhiker's Guide to the Galaxy"},
      ]);
    });

    test('testSubstring', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            ex(field("title")).substring(constant(9), constant(2)).as("of"),
            ex("title").substring(16, 5).as("Rings"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"of": "of", "Rings": "Rings"},
      ]);
    });

    test('testSplitStringByStringDelimiter', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([ex(field("title")).split(" ").as("split_title")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_title": <Object?>[
            "The",
            "Hitchhiker's",
            "Guide",
            "to",
            "the",
            "Galaxy",
          ],
        },
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([field("title").split(" ").as("split_title")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_title": <Object?>[
            "The",
            "Hitchhiker's",
            "Guide",
            "to",
            "the",
            "Galaxy",
          ],
        },
      ]);
    });

    test('testSplitStringByExpressionDelimiter', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([ex(field("title")).split(constant(" ")).as("split_title")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_title": <Object?>[
            "The",
            "Hitchhiker's",
            "Guide",
            "to",
            "the",
            "Galaxy",
          ],
        },
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([field("title").split(constant(" ")).as("split_title")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_title": <Object?>[
            "The",
            "Hitchhiker's",
            "Guide",
            "to",
            "the",
            "Galaxy",
          ],
        },
      ]);
    });

    test('testSplitBlobByByteArrayDelimiter', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .addFields([
            constant(
              blobFromBytes(<int>[0x01, 0x02, 0x03, 0x04, 0x01, 0x05]),
            ).as("data"),
          ])
          .select([
            ex(
              field("data"),
            ).split(blobFromBytes(<int>[0x01])).as("split_data"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_data": <Object?>[
            blobFromBytes(<int>[]),
            blobFromBytes(<int>[0x02, 0x03, 0x04]),
            blobFromBytes(<int>[0x05]),
          ],
        },
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .addFields([
            constant(
              blobFromBytes(<int>[0x01, 0x02, 0x03, 0x04, 0x01, 0x05]),
            ).as("data"),
          ])
          .select([
            field("data").split(blobFromBytes(<int>[0x01])).as("split_data"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_data": <Object?>[
            blobFromBytes(<int>[]),
            blobFromBytes(<int>[0x02, 0x03, 0x04]),
            blobFromBytes(<int>[0x05]),
          ],
        },
      ]);
    });

    test('testSplitStringFieldByStringDelimiter', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([ex("title").split(" ").as("split_title")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_title": <Object?>[
            "The",
            "Hitchhiker's",
            "Guide",
            "to",
            "the",
            "Galaxy",
          ],
        },
      ]);
    });

    test('testSplitStringFieldByExpressionDelimiter', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([ex("title").split(constant(" ")).as("split_title")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "split_title": <Object?>[
            "The",
            "Hitchhiker's",
            "Guide",
            "to",
            "the",
            "Galaxy",
          ],
        },
      ]);
    });

    test('testSplitWithMismatchedTypesShouldFail', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex(
              field("title"),
            ).split(blobFromBytes(<int>[0x01])).as("mismatched_split"),
          ])
          .execute();
      assertThat(await waitForException(execute)).isNotNull();
    });

    test('testLogicalAndComparisonOperators', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(
            xor(
              ex("genre").equal("Romance"),
              ex("genre").equal("Dystopian"),
              ex("genre").equal("Fantasy"),
              ex("published").equal(1949),
            ),
          )
          .select(["title"])
          .sort([field("title").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "Pride and Prejudice"},
        <String, Object?>{"title": "The Handmaid's Tale"},
        <String, Object?>{"title": "The Lord of the Rings"},
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("genre").equalAny(<Object?>["Romance", "Dystopian"]))
          .select(["title"])
          .sort([ex("title").descending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"title": "The Handmaid's Tale"},
        <String, Object?>{"title": "Pride and Prejudice"},
        <String, Object?>{"title": "1984"},
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("genre").exists())
          .where(ex("genre").notEqualAny(<Object?>["Romance", "Dystopian"]))
          .select(["genre"])
          .distinct(["genre"])
          .sort([ex("genre").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"genre": "Fantasy"},
        <String, Object?>{"genre": "Magical Realism"},
        <String, Object?>{"genre": "Modernist"},
        <String, Object?>{"genre": "Psychological Thriller"},
        <String, Object?>{"genre": "Science Fiction"},
        <String, Object?>{"genre": "Southern Gothic"},
      ]);
    });

    test('testCondExpression', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(field("title").notEqual("Timestamp Book"))
          .select([
            conditional(
              ex(field("published")).greaterThan(1980),
              "Modern",
              "Classic",
            ).as("era"),
            field("title"),
            field("published"),
          ])
          .sort([field("published").ascending()])
          .limit(2)
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "era": "Classic",
          "title": "Pride and Prejudice",
          "published": 1813,
        },
        <String, Object?>{
          "era": "Classic",
          "title": "Crime and Punishment",
          "published": 1866,
        },
      ]);
    });

    test('testDataManipulationExpressions', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("Timestamp Book"))
          .select([
            ex(
              field("timestamp"),
            ).timestampAdd("day", 1).as("timestamp_plus_day"),
            ex(
              field("timestamp"),
            ).timestampSubtract("hour", 1).as("timestamp_minus_hour"),
          ])
          .execute();
      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
      DateTime originalTimestamp =
          bookDocs["book11"]!["timestamp"]! as DateTime;
      dynamic timestampPlusDay = results[0].data()["timestamp_plus_day"];
      dynamic timestampMinusHour = results[0].data()["timestamp_minus_hour"];
      assertThat(
        timestampPlusDay.toDate().millisecondsSinceEpoch -
            originalTimestamp.millisecondsSinceEpoch,
      ).isEqualTo(24 * 60 * 60 * 1000);
      assertThat(
        originalTimestamp.millisecondsSinceEpoch -
            timestampMinusHour.toDate().millisecondsSinceEpoch,
      ).isEqualTo(60 * 60 * 1000);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex("tags").arrayGet(1).as("second_tag"),
            field("awards")
                .mapMerge(map(<String, Object?>{"new_award": true}))
                .as("merged_awards"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "second_tag": "space",
          "merged_awards": <String, Object?>{
            "hugo": true,
            "nebula": false,
            "new_award": true,
          },
        },
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex("tags").arrayReverse().as("reversed_tags"),
            ex(field("awards")).mapRemove("nebula").as("removed_awards"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "reversed_tags": <Object?>["adventure", "space", "comedy"],
          "removed_awards": <String, Object?>{"hugo": true},
        },
      ]);
    });

    test('testTimestampTrunc', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("Timestamp Book"))
          .select([
            ex(field("timestamp")).timestampTruncate("year").as("trunc_year"),
            ex(field("timestamp")).timestampTruncate("month").as("trunc_month"),
            ex(field("timestamp")).timestampTruncate("day").as("trunc_day"),
            ex(field("timestamp")).timestampTruncate("hour").as("trunc_hour"),
            ex(
              field("timestamp"),
            ).timestampTruncate("minute").as("trunc_minute"),
            ex(
              field("timestamp"),
            ).timestampTruncate("second").as("trunc_second"),
            ex(
              field("timestamp"),
            ).timestampTruncate("year").as("standalone_str"),
            field("timestamp").timestampTruncate("month").as("fluid_str"),
            ex(
              field("timestamp"),
            ).timestampTruncate(constant("day")).as("standalone_expr"),
            field(
              "timestamp",
            ).timestampTruncate(constant("hour")).as("fluid_expr"),
          ])
          .execute();

      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
      dynamic data = results[0].data();
      // Android computes the expected values with a java.util.Calendar in UTC.
      DateTime originalDate = bookDocs["book11"]!["timestamp"]! as DateTime;
      assertThat(
        data["trunc_year"],
      ).isEqualTo(truncateTimestamp(originalDate, "year"));
      assertThat(
        data["standalone_str"],
      ).isEqualTo(truncateTimestamp(originalDate, "year"));
      assertThat(
        data["trunc_month"],
      ).isEqualTo(truncateTimestamp(originalDate, "month"));
      assertThat(
        data["fluid_str"],
      ).isEqualTo(truncateTimestamp(originalDate, "month"));
      assertThat(
        data["trunc_day"],
      ).isEqualTo(truncateTimestamp(originalDate, "day"));
      assertThat(
        data["standalone_expr"],
      ).isEqualTo(truncateTimestamp(originalDate, "day"));
      assertThat(
        data["trunc_hour"],
      ).isEqualTo(truncateTimestamp(originalDate, "hour"));
      assertThat(
        data["fluid_expr"],
      ).isEqualTo(truncateTimestamp(originalDate, "hour"));
      assertThat(
        data["trunc_minute"],
      ).isEqualTo(truncateTimestamp(originalDate, "minute"));
      assertThat(
        data["trunc_second"],
      ).isEqualTo(truncateTimestamp(originalDate, "second"));
    });

    test('testTimestampTruncWithTimezone', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("Timestamp Book"))
          .select([
            field(
              "timestamp",
            ).timestampTruncate("year", "America/Los_Angeles").as("st_str_str"),
            field("timestamp")
                .timestampTruncate("month", "America/Los_Angeles")
                .as("fl_str_str"),
            field("timestamp")
                .timestampTruncate(
                  constant("day"),
                  constant("America/Los_Angeles"),
                )
                .as("st_expr_expr"),
            field("timestamp")
                .timestampTruncate(
                  constant("hour"),
                  constant("America/Los_Angeles"),
                )
                .as("fl_expr_expr"),
          ])
          .execute();

      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
      dynamic data = results[0].data();
      // Android computes the expected values with a java.util.Calendar in
      // America/Los_Angeles.
      DateTime originalDate = bookDocs["book11"]!["timestamp"]! as DateTime;
      assertThat(
        data["st_str_str"],
      ).isEqualTo(truncateTimestamp(originalDate, "year", losAngeles: true));
      assertThat(
        data["fl_str_str"],
      ).isEqualTo(truncateTimestamp(originalDate, "month", losAngeles: true));
      assertThat(
        data["st_expr_expr"],
      ).isEqualTo(truncateTimestamp(originalDate, "day", losAngeles: true));
      assertThat(
        data["fl_expr_expr"],
      ).isEqualTo(truncateTimestamp(originalDate, "hour", losAngeles: true));
    });

    test('testTimestampDiff', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "end": Timestamp(1741437296, 123456789),
              "start": Timestamp(1741428000, 0),
            }),
          )
          .select([
            ex("end").timestampDiff("start", "hour").as("diff_hour"),
            field(
              "end",
            ).timestampDiff(field("start"), "minute").as("diff_minute"),
            ex(field("end")).timestampDiff("start", "second").as("diff_second"),
            field("start").timestampDiff("end", "hour").as("diff_hour_neg"),
          ])
          .execute();

      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
      dynamic data = results[0].data();
      assertThat(data["diff_hour"]).isEqualTo(2);
      assertThat(data["diff_minute"]).isEqualTo(154);
      assertThat(data["diff_second"]).isEqualTo(9296);
      assertThat(data["diff_hour_neg"]).isEqualTo(-2);
    });

    test('testTimestampExtract', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{"ts": Timestamp(1741437296, 123456789)}),
          )
          .select([
            ex("ts").timestampExtract("year").as("year"),
            field("ts").timestampExtract("month").as("month"),
            ex(field("ts")).timestampExtract(constant("day")).as("day"),
            field("ts").timestampExtract(constant("hour")).as("hour"),
            ex("ts").timestampExtract(constant("minute")).as("minute"),
            field("ts").timestampExtract("second").as("second"),
            ex(field("ts")).timestampExtract("millisecond").as("millis"),
            field("ts").timestampExtract("microsecond").as("micros"),
            ex(field("ts")).timestampExtract("dayofyear").as("day_of_year"),
          ])
          .execute();

      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
      dynamic data = results[0].data();
      assertThat(data["year"]).isEqualTo(2025);
      assertThat(data["month"]).isEqualTo(3);
      assertThat(data["day"]).isEqualTo(8);
      assertThat(data["hour"]).isEqualTo(12);
      assertThat(data["minute"]).isEqualTo(34);
      assertThat(data["second"]).isEqualTo(56);
      assertThat(data["millis"]).isEqualTo(123);
      assertThat(data["micros"]).isEqualTo(123456);
      assertThat(data["day_of_year"]).isEqualTo(67);
    });

    test('testTimestampExtractWithTimezone', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{"ts": Timestamp(1741437296, 123456789)}),
          )
          .select([
            ex(
              "ts",
            ).timestampExtract("hour", "America/Los_Angeles").as("st_str_str"),
            field(
              "ts",
            ).timestampExtract("hour", "America/Los_Angeles").as("fl_str_str"),
            ex(field("ts"))
                .timestampExtract(
                  constant("hour"),
                  constant("America/Los_Angeles"),
                )
                .as("st_expr_expr"),
            field("ts")
                .timestampExtract(
                  constant("hour"),
                  constant("America/Los_Angeles"),
                )
                .as("fl_expr_expr"),
          ])
          .execute();

      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
      dynamic data = results[0].data();
      assertThat(data["st_str_str"]).isEqualTo(4);
      assertThat(data["fl_str_str"]).isEqualTo(4);
      assertThat(data["st_expr_expr"]).isEqualTo(4);
      assertThat(data["fl_expr_expr"]).isEqualTo(4);
    });

    test('testMathExpressions', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex(field("rating")).ceil().as("ceil_rating"),
            ex(field("rating")).floor().as("floor_rating"),
            ex(field("rating")).pow(2).as("pow_rating"),
            ex(field("rating")).round().as("round_rating"),
            ex(field("rating")).sqrt().as("sqrt_rating"),
            field("published").mod(10).as("mod_published"),
          ])
          .execute();
      dynamic result = (await execute).results[0].data();
      assertThat(result["ceil_rating"]).isEqualTo(5.0);
      assertThat(result["floor_rating"]).isEqualTo(4.0);
      assertThat(result["pow_rating"]).isWithin(0.00001).of(17.64);
      assertThat(result["round_rating"]).isEqualTo(4.0);
      assertThat(result["sqrt_rating"]).isWithin(0.00001).of(2.04939);
      assertThat(result["mod_published"]).isEqualTo(9);
    });

    test('testAdvancedMathExpressions', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Lord of the Rings"))
          .select([
            ex(field("rating")).exp().as("exp_rating"),
            ex(field("rating")).ln().as("ln_rating"),
            ex(field("rating")).log(10).as("log_rating"),
            field("rating").log10().as("log10_rating"),
          ])
          .execute();
      dynamic result = (await execute).results[0].data();
      assertThat(result["exp_rating"]).isWithin(0.00001).of(109.94717);
      assertThat(result["ln_rating"]).isWithin(0.00001).of(1.54756);
      assertThat(result["log_rating"]).isWithin(0.00001).of(0.67209);
      assertThat(result["log10_rating"]).isWithin(0.00001).of(0.67209);
    });

    test('testRand', () async {
      // Android skips this case on the emulator ("Rand is not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .select([rand().as("randomNumber")])
          .limit(1)
          .execute();

      dynamic results = (await execute).results;

      assertThat(results).hasSize(1);
      dynamic randomNumber = results[0].data()["randomNumber"];
      assertThat(randomNumber).isInstanceOf<double>();
      assertThat(randomNumber).isAtLeast(0.0);
      assertThat(randomNumber).isLessThan(1.0);
    });

    test('testTrunc', () async {
      // Android skips this case on the emulator ("Trunc is not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(field("title").equal("Pride and Prejudice"))
          .limit(1)
          .select([ex("rating").trunc().as("truncatedRating")])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"truncatedRating": 4.0},
      ]);
    });

    test('testTruncWithInstanceMethod', () async {
      // Android skips this case on the emulator ("Trunc is not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(field("title").equal("Pride and Prejudice"))
          .limit(1)
          .select([field("rating").trunc().as("truncatedRating")])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"truncatedRating": 4.0},
      ]);
    });

    test('testTruncToPrecision', () async {
      // Android skips this case on the emulator ("Trunc is not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute =
          firestore.pipeline().collection(randomCol).limit(1).select([
            ex(constant(4.123456)).trunc(0).as("p0"),
            ex(constant(4.123456)).trunc(1).as("p1"),
            ex(constant(4.123456)).trunc(2).as("p2"),
            ex(constant(4.123456)).trunc(4).as("p4"),
          ]).execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"p0": 4.0, "p1": 4.1, "p2": 4.12, "p4": 4.1234},
      ]);
    });

    test('testTruncToPrecisionWithInstanceMethod', () async {
      // Android skips this case on the emulator ("Trunc is not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute =
          firestore.pipeline().collection(randomCol).limit(1).select([
            constant(4.123456).trunc(0).as("p0"),
            constant(4.123456).trunc(1).as("p1"),
            constant(4.123456).trunc(constant(2)).as("p2"),
            constant(4.123456).trunc(4).as("p4"),
          ]).execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"p0": 4.0, "p1": 4.1, "p2": 4.12, "p4": 4.1234},
      ]);
    });

    test('testTimestampConversions', () async {
      Future<PipelineSnapshot> execute =
          firestore.pipeline().collection(randomCol).limit(1).select([
            ex(
              constant(1741380235),
            ).unixSecondsToTimestamp().as("unixSecondsToTimestamp"),
            ex(
              constant(1741380235123),
            ).unixMillisToTimestamp().as("unixMillisToTimestamp"),
            ex(
              constant(Timestamp(1741380235, 123456789)),
            ).timestampToUnixSeconds().as("timestampToUnixSeconds"),
            ex(
              constant(Timestamp(1741380235, 123456789)),
            ).timestampToUnixMillis().as("timestampToUnixMillis"),
          ]).execute();
      dynamic result = (await execute).results[0].data();
      assertThat(
        result["unixSecondsToTimestamp"],
      ).isEqualTo(Timestamp(1741380235, 0));
      assertThat(
        result["unixMillisToTimestamp"],
      ).isEqualTo(Timestamp(1741380235, 123000000));
      assertThat(result["timestampToUnixSeconds"]).isEqualTo(1741380235);
      assertThat(result["timestampToUnixMillis"]).isEqualTo(1741380235123);
    });

    test('testCurrentTimestamp', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .limit(1)
          .select([currentTimestamp().as("now")])
          .execute();
      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
      dynamic nowValue = results[0].data()["now"];
      assertThat(nowValue).isInstanceOf<Timestamp>();
      dynamic nowTimestamp = nowValue;
      // Check that the timestamp is recent (e.g., within the last 5 seconds)
      dynamic diff =
          DateTime.now().millisecondsSinceEpoch -
          nowTimestamp.toDate().millisecondsSinceEpoch;
      assertThat(diff).isAtMost(5000);
    });

    test('testTypeFunction', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .sort([field(FieldPath.documentId()).ascending()])
          .limit(1)
          .select([
            field("title").type().as("titleType"),
            field("published").type().as("publishedType"),
            field("published").add(1.2).type().as("publishedToDoubleType"),
            field("awards").mapGet("hugo").type().as("hugoType"),
            constant(null).type().as("nullType"),
            field("tags").type().as("tagsType"),
            field("awards").type().as("awardsType"),
            constant(DateTime.now()).type().as("timestampType"),
            field("embedding").type().as("embeddingType"),
            field("nestedField").type().as("nestedFieldType"),
          ])
          .execute();

      dynamic result = (await execute).results[0].data();
      assertThat(result["titleType"]).isEqualTo("string");
      assertThat(result["publishedType"]).isEqualTo("int64");
      assertThat(result["publishedToDoubleType"]).isEqualTo("float64");
      assertThat(result["hugoType"]).isEqualTo("boolean");
      assertThat(result["nullType"]).isEqualTo("null");
      assertThat(result["tagsType"]).isEqualTo("array");
      assertThat(result["awardsType"]).isEqualTo("map");
      assertThat(result["timestampType"]).isEqualTo("timestamp");
      assertThat(result["embeddingType"]).isEqualTo("vector");
      assertThat(result["nestedFieldType"]).isEqualTo("map");

      execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .sort([field(FieldPath.documentId()).ascending()])
          .limit(1)
          .select([
            ex("title").type().as("titleType"),
            ex("published").type().as("publishedType"),
            ex(field("awards").mapGet("hugo")).type().as("hugoType"),
            ex(constant(null)).type().as("nullType"),
            ex("tags").type().as("tagsType"),
            ex("awards").type().as("awardsType"),
            ex(constant(DateTime.now())).type().as("timestampType"),
            ex("embedding").type().as("embeddingType"),
            ex("nestedField").type().as("nestedFieldType"),
          ])
          .execute();

      result = (await execute).results[0].data();
      assertThat(result["titleType"]).isEqualTo("string");
      assertThat(result["publishedType"]).isEqualTo("int64");
      assertThat(result["hugoType"]).isEqualTo("boolean");
      assertThat(result["nullType"]).isEqualTo("null");
      assertThat(result["tagsType"]).isEqualTo("array");
      assertThat(result["awardsType"]).isEqualTo("map");
      assertThat(result["timestampType"]).isEqualTo("timestamp");
      assertThat(result["embeddingType"]).isEqualTo("vector");
      assertThat(result["nestedFieldType"]).isEqualTo("map");
    });

    test('testIsType', () async {
      // Android skips this case on the emulator ("Type expressions are not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .replaceWith(
            map(<String, Object?>{
              "int": 1,
              "float": 1.1,
              "str": "a string",
              "bool": true,
              "null": null,
              "geoPoint": GeoPoint(0.1, 0.2),
              "timestamp": Timestamp(123456, 0),
              "bytes": blobFromBytes(<int>[1, 2, 3]),
              "docRef": randomCol.document("bar"),
              "vector": FieldValue.vector(<double>[1.0, 2.0, 3.0]),
              "map": map(<String, Object?>{
                "numberK": 1,
                "stringK": "a string",
              }),
              "array": array(1, 2, true),
            }),
          )
          .select([
            ex("int").isType("int64").as("isInt64"),
            ex("int").isType("number").as("isInt64IsNumber"),
            ex("int").isType("decimal128").as("isInt64IsDecimal128"),
            ex("float").isType("float64").as("isFloat64"),
            ex("float").isType("number").as("isFloat64IsNumber"),
            ex("float").isType("decimal128").as("isFloat64IsDecimal128"),
            ex("str").isType("string").as("isStr"),
            ex("str").isType("int64").as("isStrNum"),
            ex("int").isType("string").as("isNumStr"),
            ex("bool").isType("boolean").as("isBool"),
            ex("null").isType("null").as("isNull"),
            ex("geoPoint").isType("geo_point").as("isGeoPoint"),
            ex("timestamp").isType("timestamp").as("isTimestamp"),
            ex("bytes").isType("bytes").as("isBytes"),
            ex("docRef").isType("reference").as("isDocRef"),
            ex("vector").isType("vector").as("isVector"),
            ex("map").isType("map").as("isMap"),
            ex("array").isType("array").as("isArray"),
            ex(constant(1)).isType("int64").as("exprIsInt64"),
            field("int").isType("int64").as("staticIsInt64"),
          ])
          .limit(1)
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "isInt64": true,
          "isInt64IsNumber": true,
          "isInt64IsDecimal128": false,
          "isFloat64": true,
          "isFloat64IsNumber": true,
          "isFloat64IsDecimal128": false,
          "isStr": true,
          "isStrNum": false,
          "isNumStr": false,
          "isBool": true,
          "isNull": true,
          "isGeoPoint": true,
          "isTimestamp": true,
          "isBytes": true,
          "isDocRef": true,
          "isVector": true,
          "isMap": true,
          "isArray": true,
          "exprIsInt64": true,
          "staticIsInt64": true,
        },
      ]);
    });

    test('testVectorLength', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .select([
            ex(
              constant(FieldValue.vector(<double>[1.0, 2.0, 3.0])),
            ).vectorLength().as("vectorLength"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"vectorLength": 3},
      ]);
    });

    test('canGetTheCollectionIdFromAPath', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .limit(1)
          .select([field("__name__").collectionId().as("collectionId")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"collectionId": randomCol.id},
      ]);
    });

    test('canGetTheCollectionIdFromAPathWithTheTopLevelFunction', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .limit(1)
          .select([ex("__name__").collectionId().as("collectionId")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"collectionId": randomCol.id},
      ]);
    });

    test('testSupportsDocumentId', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .sort([field("rating").descending()])
          .limit(1)
          .select([ex(field("__name__")).documentId().as("docId")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"docId": "book4"},
      ]);

      execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .sort([field("rating").descending()])
          .limit(1)
          .select([field("__name__").documentId().as("docId")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"docId": "book4"},
      ]);
    });

    test('testSupportsParent', () async {
      dynamic reviewRef = randomCol
          .document("book4")
          .collection("reviews")
          .document("review1");

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol.path)
          .limit(1)
          .select([
            ex(constant(reviewRef)).parent().as("parentRefStatic"),
            constant(reviewRef).parent().as("parentRefInstance"),
          ])
          .select([
            field("parentRefStatic").documentId().as("parentIdStatic"),
            field("parentRefInstance").documentId().as("parentIdInstance"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "parentIdStatic": "book4",
          "parentIdInstance": "book4",
        },
      ]);
    });

    test('testDocumentsAsSource', () async {
      Future<PipelineSnapshot> execute = firestore.pipeline().documents([
        randomCol.document("book1"),
        randomCol.document("book2"),
        randomCol.document("book3"),
      ]).execute();
      assertThat((await execute).results).hasSize(3);
    });

    test('testCollectionGroupAsSource', () async {
      dynamic subcollectionId = randomCol.document().id;
      (await randomCol.document("book1").collection(subcollectionId).add(
        <String, Object?>{"order": 1},
      ));
      (await randomCol.document("book2").collection(subcollectionId).add(
        <String, Object?>{"order": 2},
      ));
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collectionGroup(subcollectionId)
          .sort([field("order").ascending()])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"order": 1},
        <String, Object?>{"order": 2},
      ]);
    });

    test('testErrorHandling', () async {
      dynamic exception = await assertThrows(
        null,
        () => firestore
            .pipeline()
            .collection(randomCol)
            .rawStage("invalidStage", [])
            .execute(),
      );
    });

    test('testIfAbsent', () async {
      // Case 1: Field is present, should return the field value.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([field("rating").ifAbsent(0.0).as("rating_or_default")])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"rating_or_default": 4.2},
      ]);

      // Case 2: Field is absent, should return the default value.
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("The Hitchhiker's Guide to the Galaxy"))
          .select([
            ex(
              field("non_existent_field"),
            ).ifAbsent("default").as("field_or_default"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"field_or_default": "default"},
      ]);

      // Case 3: Field is present and null, should return null.
      dynamic values = <String, Object?>{};
      values["title"] = "Book With Null";
      values["optional_field"] = null;
      (await randomCol.document("bookWithNull").set(values));
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("Book With Null"))
          .select([
            ex(
              field("optional_field"),
            ).ifAbsent("default").as("field_or_default"),
          ])
          .execute();
      assertThat((await execute).results[0].get("field_or_default")).isNull();
      (await randomCol.document("bookWithNull").delete());

      // Case 4: Test different overloads.
      // ifAbsent(String, Any)
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("Dune"))
          .select([
            ex("non_existent_field").ifAbsent("default_string").as("res"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"res": "default_string"},
      ]);

      // ifAbsent(String, Expression)
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("Dune"))
          .select([
            ex("non_existent_field").ifAbsent(field("author")).as("res"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"res": "Frank Herbert"},
      ]);

      // ifAbsent(Expression, Expression)
      execute = firestore
          .pipeline()
          .collection(randomCol)
          .where(ex("title").equal("Dune"))
          .select([
            ex(field("non_existent_field")).ifAbsent(field("author")).as("res"),
          ])
          .execute();
      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{"res": "Frank Herbert"},
      ]);
    });

    test('testIfNull', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{"title": "foo", "name": constant(null)}),
          )
          .select([
            ex("title").ifNull("default title").as("staticMethod"),
            field("title").ifNull("default title").as("instanceMethod"),
            field("name").ifNull(field("title")).as("nameOrTitle"),
            field("name").ifNull("default name").as("fieldIsNull"),
            field("absent").ifNull("default name").as("fieldIsAbsent"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "staticMethod": "foo",
          "instanceMethod": "foo",
          "nameOrTitle": "foo",
          "fieldIsNull": "default name",
          "fieldIsAbsent": "default name",
        },
      ]);
    });

    test('testCoalesce', () async {
      // Android skips this case on the emulator ("Coalesce is not supported against the emulator."); the Enterprise
      // emulator v1.22.0 runs it and gives Android\'s expected result.

      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol)
          .limit(1)
          .replaceWith(
            map(<String, Object?>{
              "numberValue": 1,
              "stringValue": "unique_coalesce_hello",
              "booleanValue": false,
              "nullValue": constant(null),
              "nullValue2": constant(null),
            }),
          )
          .select([
            ex(
              field("numberValue"),
            ).coalesce(field("stringValue")).as("staticMethod"),
            field(
              "numberValue",
            ).coalesce(field("stringValue")).as("instanceMethod"),
            ex(
              field("nullValue"),
            ).coalesce(field("stringValue")).as("firstIsNull"),
            ex(field("nullValue"))
                .coalesce(field("nullValue2"), [field("booleanValue")])
                .as("lastIsNotNull"),
            ex(
              field("nullValue"),
            ).coalesce(field("nullValue2")).as("allFieldsNull"),
            ex(field("nullValue"))
                .coalesce(field("nullValue2"), [constant("default")])
                .as("allFieldsNullWithDefault"),
            ex(field("absentField"))
                .coalesce(field("numberValue"), [constant("default")])
                .as("withAbsentField"),
          ])
          .execute();

      assertThat(
        (await execute).results,
      ).comparingElementsUsing(DATA_CORRESPONDENCE).containsExactly([
        <String, Object?>{
          "staticMethod": 1,
          "instanceMethod": 1,
          "firstIsNull": "unique_coalesce_hello",
          "lastIsNotNull": false,
          "allFieldsNull": null,
          "allFieldsNullWithDefault": "default",
          "withAbsentField": 1,
        },
      ]);
    });

    test('testCrossDatabaseRejection', () async {
      dynamic firestore2 = await IntegrationTestUtil.testAlternateFirestore();
      dynamic collection2 = firestore2.collection("test-collection");
      dynamic exception = await assertThrows(null, () async {
        firestore.pipeline().collection(collection2);
      });
      assertThat("$exception").contains("Invalid CollectionReference");
    });

    test('testOptions', () async {
      // Android skips this case on the emulator: "Certain options are not
      // supported against the emulator yet." Dart has no typed aggregate hints
      // (AggregateOptions/AggregateHints): they are sent as raw options.
      dynamic vector = <double>[1.0, 2.0, 3.0];

      dynamic pipeline = firestore
          .pipeline()
          .collection(firestore.collection("k"), forceIndex: "abcdef")
          .findNearest(
            "topicVectors",
            constant(FieldValue.vector(vector)),
            DistanceMeasure.cosine,
            limit: 10,
            distanceField: "distance",
          )
          .unnest(field("awards").as("award"), indexField: "fgoo")
          .aggregate(
            [ex("rating").average().as("avg_rating")],
            groups: ["genre"],
            rawOptions: <String, Object?>{"force_streamable": true},
          );

      // Android expects "Invalid index": the backend tried the index named in
      // forceIndex. The emulator rejects the aggregate hint first
      // (EMULATOR_ANSWER): "Stage 'aggregate(...)' does not support option(s)
      // [force_streamable]".
      dynamic exception = await assertThrows(null, () => pipeline.execute());
      assertThat(
        "$exception",
      ).contains("does not support option(s) [force_streamable]");
    });

    test('testCollectionForceIndex', () async {
      // Android skips this case on the emulator: "Certain options are not
      // supported against the emulator yet."
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(randomCol, forceIndex: "primary")
          .limit(1)
          .execute();

      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
    });

    test('testCollectionGroupForceIndex', () async {
      // Android skips this case on the emulator: "Certain options are not
      // supported against the emulator yet."
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collectionGroup(randomCol.id, forceIndex: "primary")
          .limit(1)
          .execute();

      dynamic results = (await execute).results;
      assertThat(results).hasSize(1);
    });

    test('disallowDuplicateAliasesInAggregate', () async {
      dynamic exception = await assertThrows(null, () async {
        firestore.pipeline().collection(randomCol).aggregate([
          countAll().as("dup"),
          ex("rating").average().as("dup"),
        ]).execute();
      });
      // Android: "Duplicate alias: 'dup'".
      assertThat("$exception").contains("dup");
    });

    test('disallowDuplicateAliasesInSelect', () async {
      dynamic exception = await assertThrows(null, () async {
        firestore.pipeline().collection(randomCol).select([
          field("rating").as("dup"),
          field("published").as("dup"),
        ]).execute();
      });
      // Android: "Duplicate alias: 'dup'".
      assertThat("$exception").contains("dup");
    });

    test('disallowDuplicateAliasesInAddFields', () async {
      dynamic exception = await assertThrows(null, () async {
        firestore.pipeline().collection(randomCol).addFields([
          field("rating").as("dup"),
          field("published").as("dup"),
        ]).execute();
      });
      // Android: "Duplicate alias: 'dup'".
      assertThat("$exception").contains("dup");
    });

    test('disallowDuplicateAliasesInDistinct', () async {
      dynamic exception = await assertThrows(null, () async {
        firestore.pipeline().collection(randomCol).distinct([
          field("rating").as("dup"),
          field("published").as("dup"),
        ]).execute();
      });
      // Android: "Duplicate alias: 'dup'".
      assertThat("$exception").contains("dup");
    });
  });
}
