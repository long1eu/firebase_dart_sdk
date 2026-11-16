import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'errors.dart';

/// A [PersistentCacheIndexManagerPlatform] backed by `cloud_firestore_dart`.
class DartPersistentCacheIndexManager
    extends PersistentCacheIndexManagerPlatform {
  /// The platform view of [_manager].
  DartPersistentCacheIndexManager(this._manager);

  final fs.PersistentCacheIndexManager _manager;

  @override
  Future<void> enableIndexAutoCreation() =>
      guard(_manager.enableIndexAutoCreation);

  @override
  Future<void> disableIndexAutoCreation() =>
      guard(_manager.disableIndexAutoCreation);

  @override
  Future<void> deleteAllIndexes() => guard(_manager.deleteAllIndexes);
}
