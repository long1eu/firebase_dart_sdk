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

import 'dart:js_interop';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:web/web.dart' as web;

/// Whether this platform has `window.localStorage`: the web.
const bool webStorageSharedClientStateSupported = true;

/// The storage shared by the tabs of this origin ([WebStorageSharedClientStateStorage] over `window.localStorage`),
/// or null when there is none: not in a window (a worker), or LocalStorage is blocked (`WebStorageSharedClientState`'s
/// `isAvailable` of the JS SDK).
SharedClientStateStorage? createWebStorageSharedClientStateStorage() {
  try {
    final web.Window window = web.window;
    // Throws a SecurityError when the storage of the page is blocked.
    window.localStorage.length;
    return WebStorageSharedClientStateStorage(window);
  } catch (e) {
    Log.d(
      WebStorageSharedClientStateStorage._tag,
      'LocalStorage is not available: $e',
    );
    return null;
  }
}

/// A [SharedClientStateStorage] over the `localStorage` of a window, with its `storage` event as the notification: the
/// storage of `WebStorageSharedClientState` of the JS SDK, shared by all the tabs (and frames) of an origin.
///
/// The browser fires the `storage` event in the other windows of the origin, not in the window that wrote, which is
/// the contract of [SharedClientStateStorage]. Changes of `sessionStorage`, and a `clear()` of the storage (an event
/// without a key), are not passed on.
class WebStorageSharedClientStateStorage implements SharedClientStateStorage {
  /// The storage of [window] (the window of this page by default; a test passes the window of a frame).
  WebStorageSharedClientStateStorage([web.Window? window])
    : _window = window ?? web.window;

  static const String _tag = 'WebStorageSharedClientStateStorage';

  final web.Window _window;

  web.Storage get _storage => _window.localStorage;

  final List<void Function(SharedClientStateStorageEvent)> _listeners =
      <void Function(SharedClientStateStorageEvent)>[];

  JSFunction? _handler;

  @override
  String? getItem(String key) => _storage.getItem(key);

  @override
  void setItem(String key, String value) => _storage.setItem(key, value);

  @override
  void removeItem(String key) => _storage.removeItem(key);

  @override
  void addListener(
    void Function(SharedClientStateStorageEvent event) listener,
  ) {
    _listeners.add(listener);
    if (_handler == null) {
      final JSFunction handler = _handler = _onStorage.toJS;
      _window.addEventListener('storage', handler);
    }
  }

  @override
  void removeListener(
    void Function(SharedClientStateStorageEvent event) listener,
  ) {
    _listeners.remove(listener);
    final JSFunction? handler = _handler;
    if (_listeners.isEmpty && handler != null) {
      _window.removeEventListener('storage', handler);
      _handler = null;
    }
  }

  void _onStorage(web.StorageEvent event) {
    final String? key = event.key;
    final web.Storage? area = event.storageArea;
    if (key == null || area == null || !area.strictEquals(_storage).toDart) {
      return;
    }
    final SharedClientStateStorageEvent change = SharedClientStateStorageEvent(
      key,
      event.oldValue,
      event.newValue,
      this,
    );
    for (final void Function(SharedClientStateStorageEvent) listener
        in _listeners.toList()) {
      try {
        listener(change);
      } catch (e, s) {
        Log.e(_tag, 'A listener of $key failed: $e\n$s');
      }
    }
  }
}
