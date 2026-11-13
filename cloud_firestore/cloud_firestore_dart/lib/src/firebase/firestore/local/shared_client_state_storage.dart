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

/// A change of an entry of a [SharedClientStateStorage] made by another participant (the shape of a WebStorage
/// `StorageEvent`). [newValue] is null when the entry was removed.
class SharedClientStateStorageEvent {
  const SharedClientStateStorageEvent(
    this.key,
    this.oldValue,
    this.newValue,
    this.storageArea,
  );

  final String key;
  final String? oldValue;
  final String? newValue;

  /// The storage the change is reported to.
  final SharedClientStateStorage storageArea;

  @override
  String toString() => 'SharedClientStateStorageEvent($key: $newValue)';
}

/// A string key-value store shared by the clients of one persistence, with change notifications: the part of
/// `window.localStorage` that the JS SDK's `WebStorageSharedClientState` uses.
///
/// Like WebStorage, a participant is not notified of its own writes, and notifications are delivered synchronously
/// (the listener is expected to queue the work).
abstract class SharedClientStateStorage {
  String? getItem(String key);

  void setItem(String key, String value);

  void removeItem(String key);

  /// Starts delivering the changes made by the other participants to [listener].
  void addListener(void Function(SharedClientStateStorageEvent event) listener);

  /// Stops delivering changes to [listener].
  void removeListener(
    void Function(SharedClientStateStorageEvent event) listener,
  );
}

/// A [SharedClientStateStorage] bus for the clients of one process (the port of the JS `SharedFakeWebStorage`): one
/// map, and one [SharedClientStateStorage] per participant ([connect]) that notifies the other participants of its
/// writes.
class InMemorySharedClientStateStorage {
  final Map<String, String> _data = <String, String>{};
  final List<_InMemoryStorageArea> _areas = <_InMemoryStorageArea>[];

  /// The entries, for tests.
  Map<String, String> get entries => Map<String, String>.unmodifiable(_data);

  /// Returns the storage of a new participant.
  SharedClientStateStorage connect() {
    final _InMemoryStorageArea area = _InMemoryStorageArea(this);
    _areas.add(area);
    return area;
  }

  void _raise(
    _InMemoryStorageArea source,
    String key,
    String? oldValue,
    String? newValue,
  ) {
    for (final _InMemoryStorageArea area in _areas.toList()) {
      // WebStorage doesn't raise events for writes from the originating client.
      if (identical(area, source)) {
        continue;
      }
      for (final void Function(SharedClientStateStorageEvent) listener
          in area._listeners.toList()) {
        listener(SharedClientStateStorageEvent(key, oldValue, newValue, area));
      }
    }
  }
}

class _InMemoryStorageArea implements SharedClientStateStorage {
  _InMemoryStorageArea(this._bus);

  final InMemorySharedClientStateStorage _bus;
  final List<void Function(SharedClientStateStorageEvent)> _listeners =
      <void Function(SharedClientStateStorageEvent)>[];

  @override
  String? getItem(String key) => _bus._data[key];

  @override
  void setItem(String key, String value) {
    final String? oldValue = _bus._data[key];
    _bus._data[key] = value;
    _bus._raise(this, key, oldValue, value);
  }

  @override
  void removeItem(String key) {
    final String? oldValue = _bus._data.remove(key);
    _bus._raise(this, key, oldValue, null);
  }

  @override
  void addListener(
    void Function(SharedClientStateStorageEvent event) listener,
  ) {
    _listeners.add(listener);
  }

  @override
  void removeListener(
    void Function(SharedClientStateStorageEvent event) listener,
  ) {
    _listeners.remove(listener);
  }
}
