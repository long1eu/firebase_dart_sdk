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

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:path/path.dart';

import 'spec_runner_core.dart';

/// Registers one `test()` per spec case found in `test/res/json/*.json` (the CURRENT upstream spec format), grouped by
/// file. Specs that can not run are registered with `skip:` and a reason (see spec_skip_list.dart).
///
/// Run a single spec with e.g. `dart test test/unit/firebase/firestore/spec -n "Listens: Can listen/unlisten"`.
void registerSpecTests({
  required String variant,
  required Future<Persistence> Function(bool useEagerGc, String name)
  getPersistence,
  required Map<String, String> excludedTags,
  Future<Persistence> Function(
    String name,
    String clientId,
    int Function() clock,
  )?
  getSharedPersistence,
}) {
  final Directory jsonDir = Directory(
    '${Directory.current.path}/test/res/json',
  );
  final List<File> jsonFiles =
      jsonDir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.json'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  final Map<String, Map<String, dynamic>> files =
      <String, Map<String, dynamic>>{
        for (final File f in jsonFiles)
          basenameWithoutExtension(f.path):
              jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      };

  registerSpecTestFiles(
    files: files,
    variant: variant,
    getPersistence: getPersistence,
    excludedTags: excludedTags,
    getSharedPersistence: getSharedPersistence,
  );
}
