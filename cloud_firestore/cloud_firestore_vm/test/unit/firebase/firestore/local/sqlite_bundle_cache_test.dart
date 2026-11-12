// Copyright 2021 Google LLC
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

import 'package:uuid/uuid.dart';

import 'cases/bundle_cache_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  defineBundleCacheTests(() => createSQLitePersistence(
      'firebase/firestore/local/sqlite_bundle_cache_test-${const Uuid().v4()}.db'));
}
