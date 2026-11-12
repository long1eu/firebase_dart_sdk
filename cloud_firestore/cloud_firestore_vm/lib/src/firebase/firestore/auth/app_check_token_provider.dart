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

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:rxdart/rxdart.dart';

/// Uses an [InternalAppCheckTokenProvider] to get App Check tokens for the
/// `x-firebase-appcheck` header.
///
/// When constructed without an interop provider, [token] fails with
/// [FirebaseApiNotAvailableError] (which callers ignore).
class AppCheckTokenProvider {
  AppCheckTokenProvider(this._interop) {
    // Like upstream, keep listening to token changes for as long as the
    // provider lives. The new token is picked up by the next request; streams
    // are deliberately not restarted (upstream reverted that, 62d868a).
    _subscription = _interop?.onTokenChanged.listen(_onTokenChanged);
  }

  static const String _tag = 'AppCheckTokenProvider';

  final InternalAppCheckTokenProvider? _interop;
  final PublishSubject<String> _onChange = PublishSubject<String>();
  StreamSubscription<AppCheckTokenResult>? _subscription;
  bool _forceRefresh = false;

  /// Emits the new token whenever the App Check token changes.
  Stream<String> get onChange => _onChange;

  void _onTokenChanged(AppCheckTokenResult result) {
    if (result.error != null) {
      Log.w(_tag,
          'Error getting App Check token; using placeholder token instead. Error: ${result.error}');
    }
    _onChange.add(result.token);
  }

  /// The current token. Throws [FirebaseApiNotAvailableError] when there is no
  /// App Check source, and rethrows failures of the source.
  Future<String> get token async {
    final InternalAppCheckTokenProvider? interop = _interop;
    if (interop == null) {
      throw const FirebaseApiNotAvailableError('AppCheck is not available');
    }
    final bool forceRefresh = _forceRefresh;
    _forceRefresh = false;
    final AppCheckTokenResult result =
        await interop.getToken(forceRefresh: forceRefresh);
    if (result.error != null) {
      Log.w(_tag,
          'Error getting App Check token; using placeholder token instead. Error: ${result.error}');
    }
    return result.token;
  }

  /// The next [token] request will force-refresh.
  void invalidateToken() => _forceRefresh = true;

  /// Stops listening for token changes.
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _onChange.close();
  }
}
