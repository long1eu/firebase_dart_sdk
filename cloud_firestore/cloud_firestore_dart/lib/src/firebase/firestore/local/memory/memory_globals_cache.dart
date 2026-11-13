// Copyright 2024 Google LLC
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

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';

/// In-memory cache of global values (port of the Android `MemoryGlobalsCache`).
class MemoryGlobalsCache implements GlobalsCache {
  Uint8List _sessionToken = Uint8List(0);

  @override
  Future<Uint8List> getSessionToken() async => _sessionToken;

  @override
  Future<void> setSessionToken(Uint8List value) async {
    _sessionToken = value;
  }
}
