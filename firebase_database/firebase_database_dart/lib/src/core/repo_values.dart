// Number normalisation of the values users write through Repo. JS: `JSON.stringify` (which sends
// -0 as 0); Android: none (Java keeps longs and doubles apart).
part of 'repo.dart';

/// [node] with every number (values and priorities) in `normalizeUserNumber` form: a negative
/// zero becomes `0` and an integral double within 2^53 an `int`, so the local value and the sent
/// JSON match what JS sends (contract C12). Unchanged subtrees are returned as they are.
Node _normalizeUserNode(Node node) {
  if (node is LeafNode) {
    final Node priority = node.priority;
    final Node normalizedPriority = priority.isEmpty
        ? priority
        : _normalizeUserNode(priority);
    final Object? raw = _rawLeafValue(node);
    if (raw is num) {
      final num normalized = normalizeUserNumber(raw);
      if (!_sameNumber(raw, normalized) ||
          !identical(priority, normalizedPriority)) {
        return LeafNode(normalized, normalizedPriority);
      }
      return node;
    }
    return identical(priority, normalizedPriority)
        ? node
        : node.updatePriority(normalizedPriority);
  }
  if (node.isEmpty) {
    return node;
  }
  Node result = node;
  node.forEachChild(priorityIndex, (ChildKey key, Node child) {
    final Node normalized = _normalizeUserNode(child);
    if (!identical(normalized, child)) {
      result = result.updateImmediateChild(key, normalized);
    }
    return false;
  });
  final Node priority = node.priority;
  if (!priority.isEmpty) {
    final Node normalizedPriority = _normalizeUserNode(priority);
    if (!identical(normalizedPriority, priority)) {
      result = result.updatePriority(normalizedPriority);
    }
  }
  return result;
}

/// The value of [leaf] as stored (its export form without the priority wrapper).
Object? _rawLeafValue(LeafNode leaf) {
  final Object? json = leaf.toJson(exportFormat: true);
  if (json is Map && json.containsKey('.value')) {
    return json['.value'];
  }
  return json;
}

/// Whether [a] and [b] are the same number of the same type (an `int` and a `double` differ on
/// the VM, so `5.0` is replaced by `5`).
///
/// A negative zero is never the same as `0`: on the web `identical(-0.0, 0)` is true.
bool _sameNumber(num a, num b) {
  if (a == 0 && b == 0) {
    return a.isNegative == b.isNegative;
  }
  return identical(a, b) || (a is int && b is int && a == b);
}

/// A copy of the JSON [json] with every number in `normalizeUserNumber` form (keys kept as
/// given, so multi-segment update keys survive).
Object? _normalizeUserJson(Object? json) => switch (json) {
  final num n => normalizeUserNumber(n),
  final Map<Object?, Object?> m => <String, Object?>{
    for (final MapEntry<Object?, Object?> e in m.entries)
      '${e.key}': _normalizeUserJson(e.value),
  },
  final List<Object?> l => <Object?>[
    for (final Object? e in l) _normalizeUserJson(e),
  ],
  _ => json,
};
