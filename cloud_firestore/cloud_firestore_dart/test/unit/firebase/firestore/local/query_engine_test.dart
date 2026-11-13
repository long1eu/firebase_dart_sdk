// Copyright 2019 Google LLC
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

// Port of the Android SDK's MemoryQueryEngineTest (and of the JS SDK's "MemoryEagerPersistence" query engine tests):
// the memory cache has no field indexes, so every query runs from the previous results or as a full collection scan.

import 'package:test/test.dart';

import 'cases/query_engine_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  group('MemoryQueryEngine', () {
    queryEngineTestCase(createEagerGCMemoryPersistence);
  });
}
