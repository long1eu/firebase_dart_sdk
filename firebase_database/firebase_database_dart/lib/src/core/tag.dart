/// Query tag. JS: `core/SyncTree.ts` (`number` tags); Android: `core/Tag.java`.
library;

/// The number that marks the server data of one filtered (tagged) listen.
///
/// Tags are allocated by each SyncTree instance from its own counter starting at 1, only for
/// queries that do not load all data. They travel on the wire as `t`.
extension type const Tag(int number) {}
