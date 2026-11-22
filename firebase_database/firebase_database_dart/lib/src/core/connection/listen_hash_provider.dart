/// The hash a listen sends. JS: the `currentHashFn` argument of `ServerActions.listen`
/// (`core/ServerActions.ts`); Android: `connection/ListenHashProvider.java`,
/// `connection/CompoundHash.java`.
///
/// Cross-team seam: JSON only.
library;

/// A compound hash in wire form (`ch`: `ps` and `hs`).
final class WireCompoundHash {
  /// Creates a hash; [posts] must have one element fewer than [hashes].
  const WireCompoundHash({required this.posts, required this.hashes});

  /// The range end paths in wire form (`/a/b`), sent as `ps`.
  final List<String> posts;

  /// The base64 SHA-1 of each range, sent as `hs`; the last is `''`.
  final List<String> hashes;
}

/// Gives the hash of the client's cached data for a listen, computed when the listen is sent
/// (also again when it is replayed after a reconnect).
abstract interface class ListenHashProvider {
  /// The base64 SHA-1 hash of the cached server data, or `''` when nothing is cached. Every listen
  /// carries it as `h`.
  String simpleHash();

  /// Whether to send [compoundHash] as `ch` too (Android: cached data larger than 1024 bytes).
  /// The JS SDK never does; when false the server never answers with `rm`.
  bool shouldIncludeCompoundHash();

  /// The compound hash of the cached server data.
  WireCompoundHash compoundHash();
}
