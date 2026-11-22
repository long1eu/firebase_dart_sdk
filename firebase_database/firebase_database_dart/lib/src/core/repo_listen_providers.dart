// The listen providers of Repo's two sync trees. JS: `core/Repo.ts` (`repoStart`, the
// `infoSyncTree_` and `serverSyncTree_` providers); Android: `core/Repo.java` (the anonymous
// `SyncTree.ListenProvider`s of the constructor).
part of 'repo.dart';

/// The server tree's [ListenProvider]: turns [QuerySpec] into a `ListenSpec` and [Tag] into an
/// int, calls [connection], and posts the events of the completion through [postEvents].
/// [startListening] returns no events.
final class RepoListenProvider implements ListenProvider {
  /// Creates the provider; the `no_index` warning goes to [logger] (null: dropped).
  const RepoListenProvider(this.connection, this.postEvents, {this.logger});

  /// The connection.
  final ServerActions connection;

  /// Raises events produced by a listen completion.
  final void Function(List<Event> events) postEvents;

  /// Receives the `no_index` warning of a listen response.
  final DatabaseLogger? logger;

  /// Sends the listen; its answer completes the sync tree's listen and the resulting events are
  /// posted (Android `Repo` server provider `startListening`; JS `repoStart` `startListening`).
  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    connection.listen(
      query.toListenSpec(),
      hashProvider: hash,
      tag: tag?.number,
      onComplete: (String status, Object? data) {
        if (status == statusOk) {
          _warnOnIndexWarnings(query, data);
        }
        postEvents(onComplete(Repo._errorFor(status, data)));
      },
    );
    return const <Event>[];
  }

  /// JS `PersistentConnection.warnOnListenWarnings_`: the server filters nothing for an
  /// unindexed `orderByChild`, so the data is downloaded and filtered here.
  void _warnOnIndexWarnings(QuerySpec query, Object? payload) {
    if (payload is! Map) {
      return;
    }
    final Object? warnings = payload['w'];
    if (warnings is List && warnings.contains('no_index')) {
      final String indexSpec =
          '".indexOn": "${query.params.index.queryDefinition}"';
      logger?.call(
        DatabaseLogLevel.warning,
        'Using an unspecified index. Your data will be downloaded and filtered on the '
        'client. Consider adding $indexSpec at ${query.path} to your security rules for '
        'better performance.',
      );
    }
  }

  /// Sends the unlisten with the same tag (Android `Repo` server provider `stopListening`).
  @override
  void stopListening(QuerySpec query, Tag? tag) =>
      connection.unlisten(query.toListenSpec(), tag: tag?.number);
}

/// The `.info` tree's [ListenProvider]: never touches the network. [startListening] applies the
/// current [infoData] at the query's path to [syncTree] as a server overwrite and returns those
/// events (none for an absent value), then completes the listen asynchronously (JS
/// `Repo.ts` `repoStart`, `infoSyncTree_` provider).
final class InfoListenProvider implements ListenProvider {
  /// Creates the provider; Repo sets [syncTree] right after building the `.info` tree.
  InfoListenProvider(this.infoData, this.postEvents);

  /// The `.info` data.
  final SnapshotHolder infoData;

  /// The `.info` tree this provider serves.
  late final SyncTreeApi syncTree;

  /// Raises events.
  final void Function(List<Event> events) postEvents;

  /// JS `repoStart` info provider `startListening`; Android `Repo` info provider
  /// `startListening` (which completes synchronously).
  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    final Node node = infoData.getNode(query.path);
    if (node.isEmpty) {
      return const <Event>[];
    }
    final List<Event> events = syncTree.applyServerOverwrite(query.path, node);
    scheduleMicrotask(() => postEvents(onComplete(null)));
    return events;
  }

  /// Nothing to stop (JS and Android: a no-op).
  @override
  void stopListening(QuerySpec query, Tag? tag) {}
}
