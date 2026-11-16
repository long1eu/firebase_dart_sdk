import 'dart:math';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'document_reference.dart';
import 'firestore.dart';
import 'query.dart';

/// A [CollectionReferencePlatform] backed by `cloud_firestore_dart`.
///
/// It is a [DartQuery] over the collection, as the method channel
/// implementation's collection is a query of its own.
class DartCollectionReference extends DartQuery
    implements
        // ignore: avoid_implementing_value_types
        CollectionReferencePlatform {
  /// The collection at [path] of [firestore].
  DartCollectionReference(super.firestore, super.path);

  DartFirebaseFirestore get _firestore => firestore as DartFirebaseFirestore;

  @override
  String get id => path.substring(path.lastIndexOf('/') + 1);

  @override
  DocumentReferencePlatform? get parent {
    final int slash = path.lastIndexOf('/');
    return slash < 0
        ? null
        : DartDocumentReference(_firestore, path.substring(0, slash));
  }

  @override
  DocumentReferencePlatform doc([String? path]) {
    return DartDocumentReference(
      _firestore,
      '${this.path}/${path ?? _autoId()}',
    );
  }

  static const String _autoIdChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _random = Random.secure();

  /// A random document id of 20 characters, as the SDKs make them. Made here
  /// rather than by `cloud_firestore_dart`, so that `doc()` does not start the
  /// instance (which fixes its settings).
  static String _autoId() {
    return String.fromCharCodes(<int>[
      for (int i = 0; i < 20; i++)
        _autoIdChars.codeUnitAt(_random.nextInt(_autoIdChars.length)),
    ]);
  }
}
