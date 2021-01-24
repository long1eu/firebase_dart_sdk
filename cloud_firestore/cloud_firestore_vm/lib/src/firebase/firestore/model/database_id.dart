// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

class DatabaseId implements Comparable<DatabaseId> {
  const DatabaseId._(this.projectId, this.databaseId);

  factory DatabaseId.forProject(String projectId) {
    return DatabaseId.forDatabase(projectId, defaultDatabaseId);
  }

  factory DatabaseId.forDatabase(String projectId, String databaseId) {
    return DatabaseId._(projectId, databaseId);
  }

  /// Returns a DatabaseId from a fully qualified resource name.
  factory DatabaseId.fromName(String name) {
    final ResourcePath resourceName = ResourcePath.fromString(name);
    hardAssert(
      resourceName.length >= 3 && resourceName[0] == 'projects' && resourceName[2] == 'databases',
      'Tried to parse an invalid resource name: $resourceName',
    );
    return DatabaseId._(resourceName[1], resourceName[3]);
  }

  static const String defaultDatabaseId = '(default)';

  final String projectId;
  final String databaseId;

  @override
  int compareTo(DatabaseId other) {
    final int cmp = projectId.compareTo(other.projectId);
    return cmp != 0 ? cmp : databaseId.compareTo(other.databaseId);
  }

  @override
  String toString() => 'DatabaseId($projectId, $databaseId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatabaseId &&
          runtimeType == other.runtimeType &&
          projectId == other.projectId &&
          databaseId == other.databaseId;

  @override
  int get hashCode => projectId.hashCode ^ databaseId.hashCode;
}
