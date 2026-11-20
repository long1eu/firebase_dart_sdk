/// The [SharedClientStateStorage] over `window.localStorage`, without importing `dart:js_interop` where it does not
/// exist.
library;

export 'web_storage_shared_client_state_storage_web.dart'
    if (dart.library.io) 'web_storage_shared_client_state_storage_io.dart';
