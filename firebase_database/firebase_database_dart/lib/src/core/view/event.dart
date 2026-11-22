/// Events raised by views. JS: `core/view/Event.ts` (`Event`, `EventType`); Android:
/// `core/view/Event.java`.
///
/// [DataEvent] and [CancelEvent] live in the part files `data_event.dart` and
/// `cancel_event.dart`. These are internal objects; the public stream API wraps them later.
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

part 'cancel_event.dart';
part 'data_event.dart';

/// The kinds of data events, in the order they are raised for one change set.
enum EventType {
  /// A child was removed.
  childRemoved,

  /// A child was added.
  childAdded,

  /// A child moved.
  childMoved,

  /// A child changed.
  childChanged,

  /// The value changed.
  value,
}

/// An event ready to be raised: a [DataEvent] or a [CancelEvent].
sealed class Event {
  const Event();

  /// The path events are grouped and ordered by in the event queue.
  Path get path;

  /// Delivers the event to its registration.
  void fire();
}
