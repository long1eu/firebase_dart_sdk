import 'dart:js_interop';

import 'store.dart';

@JS('localStorage')
external _Storage get _localStorage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

/// A store in the browser's `localStorage`.
final class LocalStorageStore implements ErrorReportingStore {
  /// A store under the key given.
  LocalStorageStore(this._key);

  final String _key;

  @override
  Future<ErrorReportingState> load() async {
    final String? text = _localStorage.getItem(_key);
    return text == null ? ErrorReportingState.empty : decodeState(text);
  }

  @override
  Future<void> save(ErrorReportingState state) async {
    _localStorage.setItem(_key, encodeState(state));
  }
}
