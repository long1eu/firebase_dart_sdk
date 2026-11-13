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
// firebase-firestore/src/androidTest/java/com/google/firebase/firestore/PipelineSearchTest.kt
//
// The cases keep their Kotlin names; android_pipeline_test_util.dart has the
// functions they call. They run against the Enterprise edition emulator of
// FIRESTORE_ENTERPRISE_EMULATOR_HOST (tool/start_enterprise_emulator.sh);
// without it they are skipped.
//
// Android runs these cases against its nightly backend only. The Enterprise
// edition emulator (v1.22.0) does not support search: a pipeline with a
// search stage fails. The cases record the emulator's answer: where the
// pipeline fails with it the case passes, where it runs (a backend with
// search) Android's checks apply. The answer (v1.22.0): INVALID_ARGUMENT
// "The function 'document_matches' does not exist." (or 'geo_distance'). The two `TODO(search)` cases that are
// commented out in Android are not ported.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables, unawaited_futures
// ignore_for_file: unnecessary_await_in_return, unnecessary_parenthesis
// ignore_for_file: unnecessary_statements

import 'package:test/test.dart' show group, setUp, setUpAll, tearDown, test;

import '../util/integration_test_util.dart';
import 'android_pipeline_test_util.dart';

const String collectionName = "TextSearchIntegrationTests";

final Map<String, Map<String, Object?>> restaurantDocs = <String, Object?>{
  "sunnySideUp": <String, Object?>{
    "name": "The Sunny Side Up",
    "description":
        "A cozy neighborhood diner serving classic breakfast favorites all day long, from fluffy pancakes to savory omelets.",
    "location": GeoPoint(39.7541, -105.0002),
    "menu":
        "<h3>Breakfast Classics</h3><ul><li>Denver Omelet - \$12</li><li>Buttermilk Pancakes - \$10</li><li>Steak and Eggs - \$16</li></ul><h3>Sides</h3><ul><li>Hash Browns - \$4</li><li>Thick-cut Bacon - \$5</li><li>Drip Coffee - \$2</li></ul>",
    "average_price_per_person": 15,
  },
  "goldenWaffle": <String, Object?>{
    "name": "The Golden Waffle",
    "description":
        "Specializing exclusively in Belgian-style waffles. Open daily from 6:00 AM to 11:00 AM.",
    "location": GeoPoint(39.7183, -104.9621),
    "menu":
        "<h3>Signature Waffles</h3><ul><li>Strawberry Delight - \$11</li><li>Chicken and Waffles - \$14</li><li>Chocolate Chip Crunch - \$10</li></ul><h3>Drinks</h3><ul><li>Fresh OJ - \$4</li><li>Artisan Coffee - \$3</li></ul>",
    "average_price_per_person": 13,
  },
  "lotusBlossomThai": <String, Object?>{
    "name": "Lotus Blossom Thai",
    "description":
        "Authentic Thai cuisine featuring hand-crushed spices and traditional family recipes from the Chiang Mai region.",
    "location": GeoPoint(39.7315, -104.9847),
    "menu":
        "<h3>Appetizers</h3><ul><li>Spring Rolls - \$7</li><li>Chicken Satay - \$9</li></ul><h3>Main Course</h3><ul><li>Pad Thai - \$15</li><li>Green Curry - \$16</li><li>Drunken Noodles - \$15</li></ul>",
    "average_price_per_person": 22,
  },
  "mileHighCatch": <String, Object?>{
    "name": "Mile High Catch",
    "description":
        "Freshly sourced seafood offering a wide variety of Pacific fish and Atlantic shellfish in an upscale atmosphere.",
    "location": GeoPoint(39.7401, -104.9903),
    "menu":
        "<h3>From the Raw Bar</h3><ul><li>Oysters (Half Dozen) - \$18</li><li>Lobster Cocktail - \$22</li></ul><h3>Entrees</h3><ul><li>Pan-Seared Salmon - \$28</li><li>King Crab Legs - \$45</li><li>Fish and Chips - \$19</li></ul>",
    "average_price_per_person": 45,
  },
  "peakBurgers": <String, Object?>{
    "name": "Peak Burgers",
    "description":
        "Casual burger joint focused on locally sourced Colorado beef and hand-cut fries.",
    "location": GeoPoint(39.7622, -105.0125),
    "menu":
        "<h3>Burgers</h3><ul><li>The Peak Double - \$12</li><li>Bison Burger - \$15</li><li>Veggie Stack - \$11</li></ul><h3>Sides</h3><ul><li>Truffle Fries - \$6</li><li>Onion Rings - \$5</li></ul>",
    "average_price_per_person": 18,
  },
  "solTacos": <String, Object?>{
    "name": "El Sol Tacos",
    "description":
        "A vibrant street-side taco stand serving up quick, delicious, and traditional Mexican street food.",
    "location": GeoPoint(39.6952, -105.0274),
    "menu":
        "<h3>Tacos (\$3.50 each)</h3><ul><li>Al Pastor</li><li>Carne Asada</li><li>Pollo Asado</li><li>Nopales (Cactus)</li></ul><h3>Beverages</h3><ul><li>Horchata - \$4</li><li>Mexican Coke - \$3</li></ul>",
    "average_price_per_person": 12,
  },
  "eastsideTacos": <String, Object?>{
    "name": "Eastside Cantina",
    "description":
        "Authentic street tacos and hand-shaken margaritas on the vibrant east side of the city.",
    "location": GeoPoint(39.735, -104.885),
    "menu":
        "<h3>Tacos</h3><ul><li>Carnitas Tacos - \$4</li><li>Barbacoa Tacos - \$4.50</li><li>Shrimp Tacos - \$5</li></ul><h3>Drinks</h3><ul><li>House Margarita - \$9</li><li>Jarritos - \$3</li></ul>",
    "average_price_per_person": 18,
  },
  "eastsideChicken": <String, Object?>{
    "name": "Eastside Chicken",
    "description": "Fried chicken to go - next to Eastside Cantina.",
    "location": GeoPoint(39.735, -104.885),
    "menu":
        "<h3>Fried Chicken</h3><ul><li>Drumstick - \$4</li><li>Wings - \$1</li><li>Sandwich - \$9</li></ul><h3>Drinks</h3><ul><li>House Margarita - \$9</li><li>Jarritos - \$3</li></ul>",
    "average_price_per_person": 12,
  },
}.cast<String, Map<String, Object?>>();

/// Whether [execute] fails with the emulator's answer to a search stage:
/// INVALID_ARGUMENT "The function 'document_matches' does not exist." (or
/// 'geo_distance'). False when the pipeline runs.
Future<bool> emulatorRejectsSearch(Future<PipelineSnapshot> execute) async {
  try {
    await execute;
    return false;
  } on FirestoreError catch (e) {
    print('EMU_ANSWER ${e.code} ${e.message}');
    if (e.code == FirestoreErrorCode.invalidArgument &&
        RegExp(
          "The function '(document_matches|geo_distance)' does not exist",
        ).hasMatch(e.message)) {
      return true;
    }
    rethrow;
  }
}

void assertResultIds(PipelineSnapshot snapshot, List<String> ids) {
  final List<String?> resultIds = <String?>[
    for (final PipelineResult result in snapshot.results)
      if (result.id != null) result.id,
  ];
  assertThat(resultIds).isEqualTo(ids);
}

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/android_pipeline_search';
  late Firestore firestore;

  group(
    'PipelineSearchTest',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () {
      // Android's @BeforeClass setupRestaurantDocs: the documents are written
      // once.
      setUpAll(() async {
        final Firestore writer =
            await IntegrationTestUtil.testEnterpriseFirestore();
        final CollectionReference<Map<String, Object?>> restaurants = writer
            .collection(collectionName);
        for (final MapEntry<String, Map<String, Object?>> doc
            in restaurantDocs.entries) {
          await restaurants.document(doc.key).set(doc.value);
        }
      });

      setUp(() async {
        firestore = await IntegrationTestUtil.testEnterpriseFirestore();
      });

      tearDown(() async {
        await IntegrationTestUtil.tearDown();
      });

      Pipeline restaurants() => firestore.pipeline().collection(collectionName);

      /// Runs [pipeline]; null when the emulator gives its answer to search.
      Future<PipelineSnapshot?> run(Pipeline pipeline) async {
        final Future<PipelineSnapshot> execute = pipeline.execute();
        if (await emulatorRejectsSearch(execute)) {
          return null;
        }
        return execute;
      }

      test('searchWithLanguageCode', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search("al pastor", languageCode: "en"),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, ["solTacos"]);
        }
      });

      test('searchWithLanguageCodeUnknown', () async {
        // Android expects an error; the emulator fails it too.
        await assertThrows(
          null,
          () => restaurants()
              .search("al pastor", languageCode: "unknown")
              .execute(),
        );
      });

      test('searchFullDocument', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search(documentMatches("waffles")),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, ["goldenWaffle"]);
        }
      });

      test('geoNearQuery', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search(
            field(
              "location",
            ).geoDistance(GeoPoint(39.6985, -105.024)).lessThanOrEqual(1000),
          ),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, ["solTacos"]);
        }
      });

      test('negateMatch', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search(documentMatches("coffee -waffles")),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, ["sunnySideUp"]);
        }
      });

      test('rqueryAsQueryParam', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search("chicken wings"),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, ["eastsideChicken"]);
        }
      });

      test('addFields_score', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants()
              .search(
                documentMatches("waffles"),
                addFields: [score().as("searchScore")],
              )
              .select(["name", "searchScore", "snippet"]),
        );
        if (snapshot != null) {
          assertThat(snapshot.results).hasSize(1);
          final PipelineResult result = snapshot.results[0];
          assertThat(result.get("name")).isEqualTo("The Golden Waffle");
          assertThat(result.get("searchScore")! as double).isGreaterThan(0.0);
        }
      });

      test('sort_byScore', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search(
            documentMatches("tacos"),
            sort: [score().descending()],
          ),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, ["eastsideTacos", "solTacos"]);
        }
      });

      test('sort_byDistance', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search(
            field(
              "location",
            ).geoDistance(GeoPoint(39.6985, -105.024)).lessThanOrEqual(5600),
            sort: [
              field(
                "location",
              ).geoDistance(GeoPoint(39.6985, -105.024)).ascending(),
            ],
          ),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, [
            "solTacos",
            "lotusBlossomThai",
            "mileHighCatch",
          ]);
        }
      });

      test('limit_limitsTheNumberOfDocumentsReturned', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search(
            field("location")
                .geoDistance(GeoPoint(39.6985, -105.024))
                .lessThanOrEqual(100000000),
            sort: [
              field(
                "location",
              ).geoDistance(GeoPoint(39.6985, -105.024)).ascending(),
            ],
            limit: 3,
          ),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, [
            "solTacos",
            "lotusBlossomThai",
            "mileHighCatch",
          ]);
        }
      });

      test(
        'limit_limitsTheNumberOfDocumentsScoredWithRetrievalDepth',
        () async {
          PipelineSnapshot? snapshot = await run(
            restaurants().search(
              documentMatches("taco"),
              retrievalDepth: 2,
              sort: [score().descending()],
            ),
          );
          if (snapshot != null) {
            assertResultIds(snapshot, ["solTacos", "eastsideTacos"]);
          }

          snapshot = await run(
            restaurants().search(
              documentMatches("taco"),
              retrievalDepth: 1,
              sort: [score().descending()],
            ),
          );
          if (snapshot != null) {
            assertResultIds(snapshot, ["eastsideTacos"]);
          }
        },
      );

      test('offset_skipsNDocuments', () async {
        final PipelineSnapshot? snapshot = await run(
          restaurants().search("chicken", limit: 2, offset: 2),
        );
        if (snapshot != null) {
          assertResultIds(snapshot, ["goldenWaffle"]);
        }
      });
    },
  );
}
