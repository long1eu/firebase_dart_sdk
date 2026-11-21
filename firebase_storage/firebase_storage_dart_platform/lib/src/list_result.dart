import 'package:firebase_storage_dart/firebase_storage_dart.dart' as fs;
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';

import 'firebase_storage.dart';
import 'reference.dart';

/// A page of `list` or the result of `listAll`.
class DartListResult extends ListResultPlatform {
  DartListResult._(
    DartFirebaseStorage super.storage,
    super.nextPageToken,
    this.items,
    this.prefixes,
  );

  /// The FlutterFire result of the client's [result], with references of
  /// [storage].
  factory DartListResult.of(DartFirebaseStorage storage, fs.ListResult result) {
    List<ReferencePlatform> refs(List<fs.Reference> of) => List.unmodifiable(
      of.map((fs.Reference ref) => DartReference(storage, ref.fullPath)),
    );
    return DartListResult._(
      storage,
      result.nextPageToken,
      refs(result.items),
      refs(result.prefixes),
    );
  }

  @override
  final List<ReferencePlatform> items;

  @override
  final List<ReferencePlatform> prefixes;
}
