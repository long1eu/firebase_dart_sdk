import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_auth_providers_dart/src/auth_storage.dart';
import 'package:web/web.dart' as web;

/// An [AuthStorage] in the browser's `sessionStorage` or `localStorage` (the JS SDK's `browserSessionPersistence`
/// and `browserLocalPersistence`).
///
/// * [WebAuthStorage.session]: the session lasts as long as the tab (it survives reloads, not closing the tab);
///   other tabs do not share it.
/// * [WebAuthStorage.local]: the session survives closing the browser and is shared by the tabs of the origin.
///
/// **What the storage exposes.** It holds the refresh token of the signed-in user, which does not expire. Every
/// script that runs on the origin can read both storages: a cross-site scripting flaw, or a compromised
/// third-party script, gives the session away, and with `localStorage` the token stays on the device until the user
/// signs out. Use a strict Content Security Policy, load no script you do not trust, and prefer
/// [WebAuthStorage.session] (or `InMemoryAuthStorage`, signing in again on every visit) unless users expect to stay
/// signed in.
///
/// A storage that the browser refuses (for example with cookies blocked) throws from [read] and [write], so
/// `FirebaseUserAuth.forApp` fails: catch that and fall back to `InMemoryAuthStorage` if you want.
///
/// **Other tabs.** [changes] emits when another tab or window of the origin changes the key or
/// clears the storage (the browser's `storage` event). The browser sends that event to the other
/// pages only, so the writes of this page, through this object or another, never emit. With
/// `sessionStorage` the other page can only be another frame of the same tab.
///
/// On the Dart VM the constructors throw an [UnsupportedError]: use `FileAuthStorage` there.
///
/// ```dart
/// final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
///   app,
///   storage: WebAuthStorage.session(),
/// );
/// ```
class WebAuthStorage implements ObservableAuthStorage {
  /// The `sessionStorage` of the page. [prefix] goes before every key.
  WebAuthStorage.session({this.prefix = ''}) : _local = false;

  /// The `localStorage` of the origin. [prefix] goes before every key.
  WebAuthStorage.local({this.prefix = ''}) : _local = true;

  /// What goes before every key in the browser storage.
  final String prefix;

  final bool _local;

  web.Storage get _storage =>
      _local ? web.window.localStorage : web.window.sessionStorage;

  @override
  String? read(String key) => _storage.getItem('$prefix$key');

  @override
  void write(String key, String? value) {
    if (value == null) {
      _storage.removeItem('$prefix$key');
    } else {
      _storage.setItem('$prefix$key', value);
    }
  }

  /// Emits when another tab or window changes [key] (under [prefix]) or clears the storage: the
  /// browser's `storage` event of this storage. The listener on `window` is added while the stream
  /// is listened to.
  @override
  Stream<void> changes(String key) {
    final String storageKey = '$prefix$key';
    return Stream<void>.multi((MultiStreamController<void> controller) {
      final JSFunction listener = ((web.StorageEvent event) {
        final String? changed = event.key;
        if ((changed == null || changed == storageKey) && _isMine(event)) {
          controller.add(null);
        }
      }).toJS;
      web.window.addEventListener('storage', listener);
      controller.onCancel = () {
        web.window.removeEventListener('storage', listener);
      };
    });
  }

  bool _isMine(web.StorageEvent event) {
    try {
      return event.storageArea.strictEquals(_storage).toDart;
    } on Object {
      // The browser refuses this storage now (site data blocked): there is nothing to follow.
      return false;
    }
  }
}
