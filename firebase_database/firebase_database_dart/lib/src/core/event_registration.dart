/// A listener registered on a query. JS: `core/view/EventRegistration.ts` (`EventRegistration`);
/// Android: `core/EventRegistration.java`, `core/EventRegistrationZombieListener.java`.
///
/// The public layer uses one concrete subclass for value and child listeners,
/// `CallbackEventRegistration` (`core/callback_event_registration.dart`); the sync tree has its
/// own `KeepSyncedEventRegistration`.
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';

/// Called once when a registration is zombified (removed while events for it may be queued).
typedef ZombieListener = void Function(EventRegistration registration);

/// A listener on [querySpec] that turns changes into events and delivers them.
abstract class EventRegistration {
  /// Constructor for subclasses.
  EventRegistration();

  /// The query listened to.
  QuerySpec get querySpec;

  /// Whether this registration wants events of [type].
  bool respondsTo(EventType type);

  /// The event for [change] on [query].
  DataEvent createEvent(Change change, QuerySpec query);

  /// Delivers [event] to the listener (skipped once zombified).
  void fireEvent(DataEvent event);

  /// Delivers the cancellation [error] to the listener.
  void fireCancelEvent(DatabaseError error);

  /// The same listener on [newQuery].
  EventRegistration clone(QuerySpec newQuery);

  /// Whether [other] is the same listener (the same callback); used to remove listeners.
  bool isSameListener(EventRegistration other);

  bool _zombied = false;
  ZombieListener? _zombieListener;
  bool _isUserInitiated = false;

  /// Marks the registration removed; queued events for it are dropped. Calls the [onZombied]
  /// listener once (Android `EventRegistration.zombify`).
  void zombify() {
    if (_zombied) {
      return;
    }
    _zombied = true;
    final ZombieListener? listener = _zombieListener;
    if (listener != null) {
      _zombieListener = null;
      listener(this);
    }
  }

  /// Whether [zombify] was called (Android `EventRegistration.isZombied`).
  bool get isZombied => _zombied;

  /// Sets the listener called on [zombify]; only once, before it (Android
  /// `EventRegistration.setOnZombied`).
  set onZombied(ZombieListener? listener) {
    assert(!_zombied, 'The registration is already zombied');
    assert(_zombieListener == null, 'A zombie listener is already set');
    _zombieListener = listener;
  }

  /// Whether the user added it (false for internal ones such as keepSynced; Android
  /// `EventRegistration.isUserInitiated`).
  // The getter and setter pair is the skeleton's signature.
  // ignore: unnecessary_getters_setters
  bool get isUserInitiated => _isUserInitiated;

  /// Sets [isUserInitiated] (Android `EventRegistration.setIsUserInitiated`).
  set isUserInitiated(bool value) => _isUserInitiated = value;
}
