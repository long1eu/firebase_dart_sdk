import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'document_reference.dart';
import 'errors.dart';
import 'firestore.dart';
import 'snapshots.dart';
import 'value_codec.dart';

/// A [TransactionPlatform] backed by a `cloud_firestore_dart` transaction.
///
/// The reads and writes go to the `cloud_firestore_dart` transaction at once;
/// it checks that every read comes before the first write and commits when the
/// handler of `runTransaction` completes.
class DartTransaction extends TransactionPlatform {
  /// The platform view of [_transaction], a transaction of [_firestore].
  DartTransaction(this._firestore, this._transaction);

  final DartFirebaseFirestore _firestore;
  final fs.Transaction _transaction;

  fs.DocumentReference<Map<String, Object?>> _ref(String path) =>
      _firestore.delegate.doc(path);

  /// Not used by this implementation: the writes are applied to the
  /// transaction as they are made, not collected as commands.
  @override
  List<InternalTransactionCommand> get commands {
    throw UnimplementedError(
      'cloud_firestore_dart_platform applies the writes of a transaction '
      'directly and has no command list.',
    );
  }

  @override
  Future<DocumentSnapshotPlatform> get(String documentPath) {
    return guard(() async {
      final fs.DocumentSnapshot<Map<String, Object?>> snapshot =
          await _transaction.get(_ref(documentPath));
      return documentSnapshotOf(_firestore, snapshot);
    });
  }

  @override
  TransactionPlatform delete(String documentPath) {
    guardSync(() => _transaction.delete(_ref(documentPath)));
    return this;
  }

  @override
  TransactionPlatform update(
    String documentPath,
    Map<FieldPath, dynamic> data,
  ) {
    guardSync(
      () => data.isEmpty
          ? _transaction.update(_ref(documentPath), <String, Object?>{})
          : _transaction.updateFromList(
              _ref(documentPath),
              ValueCodec.encodeUpdate(data),
            ),
    );
    return this;
  }

  @override
  TransactionPlatform set(
    String documentPath,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    guardSync(() {
      final Map<String, Object?> encoded = ValueCodec.encodeMap(data);
      final fs.SetOptions? setOptions = setOptionsOf(options);
      return setOptions == null
          ? _transaction.set(_ref(documentPath), encoded)
          : _transaction.set(_ref(documentPath), encoded, setOptions);
    });
    return this;
  }
}
