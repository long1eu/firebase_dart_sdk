import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';

/// Options of [DocumentReference.get] and [Query.get]: where the data comes from.
///
/// FlutterFire's `GetOptions` also has a `serverTimestampBehavior`; here it is an argument of
/// `DocumentSnapshot.data` and `DocumentSnapshot.get` instead.
///
/// ```dart
/// final DocumentSnapshot<Map<String, Object?>> cached = await firestore
///     .doc('cities/SF')
///     .get(const GetOptions(source: Source.cache));
/// ```
class GetOptions {
  /// Options that read from [source], by default the server with a fallback to the cache.
  const GetOptions({this.source = Source.serverAndCache});

  /// Where to read from.
  final Source source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GetOptions && source == other.source;

  @override
  int get hashCode => source.hashCode;

  @override
  String toString() => 'GetOptions(source: ${source.name})';
}
