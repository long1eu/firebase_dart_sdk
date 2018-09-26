// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

class DatabaseId implements Comparable<DatabaseId> {
  static const String defaultDatabaseId = '(default)';

  final String projectId;
  final String databaseId;

  const DatabaseId._(this.projectId, this.databaseId);

  factory DatabaseId.forProject(String projectId) {
    return DatabaseId.forDatabase(projectId, defaultDatabaseId);
  }

  factory DatabaseId.forDatabase(String projectId, String databaseId) {
    return DatabaseId._(projectId, databaseId);
  }

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
