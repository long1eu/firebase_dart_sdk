/// The kinds of events a query raises. JS: `api/Reference_impl.ts` (`EventType`); Android:
/// `core/view/Event.java` (`EventType`).
library;

/// The kind of a `DatabaseEvent`.
///
/// Inside one change the events come in this order: [childRemoved], [childAdded], [childMoved],
/// [childChanged], then [value]. Within one kind they come in the query's index order.
enum DatabaseEventType {
  /// The whole value of the query's location, raised once with the initial data and after every change.
  value,

  /// A child appeared in the query's results. `previousChildKey` names the child before it, or null when it
  /// is the first.
  childAdded,

  /// A child in the results changed value. `previousChildKey` names the child before it.
  childChanged,

  /// A child moved to another place in the query's order. `previousChildKey` names its new predecessor.
  childMoved,

  /// A child left the query's results. `previousChildKey` is null.
  childRemoved,
}
