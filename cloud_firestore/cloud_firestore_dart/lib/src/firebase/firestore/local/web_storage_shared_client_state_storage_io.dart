import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';

/// Whether this platform has `window.localStorage`: only the web.
const bool webStorageSharedClientStateSupported = false;

/// The storage shared by the tabs of this origin, or null where there is none (here: always).
SharedClientStateStorage? createWebStorageSharedClientStateStorage() => null;
