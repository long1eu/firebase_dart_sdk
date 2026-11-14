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

// Port of packages/firestore/test/unit/api/long_polling_options.test.ts of the
// JS SDK. `longPollingOptionsEqual` is `==` here. The `cloneLongPollingOptions`
// tests have no counterpart: the Dart class is immutable, and has no other
// properties to drop.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

void main() {
  group('long_polling_options', () {
    test('longPollingOptionsEqual() should return true for empty objects', () {
      expect(
        const ExperimentalLongPollingOptions(),
        const ExperimentalLongPollingOptions(),
      );
    });

    test('longPollingOptionsEqual() should return true if both objects have '
        'the same timeoutSeconds', () {
      const ExperimentalLongPollingOptions options1 =
          ExperimentalLongPollingOptions(timeoutSeconds: 123);
      const ExperimentalLongPollingOptions options2 =
          ExperimentalLongPollingOptions(timeoutSeconds: 123);
      expect(options1, options2);
      expect(options1.hashCode, options2.hashCode);
    });

    test('longPollingOptionsEqual() should return false if the objects have '
        'different timeoutSeconds', () {
      const ExperimentalLongPollingOptions options1 =
          ExperimentalLongPollingOptions(timeoutSeconds: 123);
      const ExperimentalLongPollingOptions options2 =
          ExperimentalLongPollingOptions(timeoutSeconds: 321);
      expect(options1, isNot(options2));
      expect(options1, isNot(const ExperimentalLongPollingOptions()));
    });
  });
}
