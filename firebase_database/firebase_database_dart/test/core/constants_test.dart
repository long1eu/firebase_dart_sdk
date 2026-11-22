// Pins the named timing constants of Repo and the event dispatcher.
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/view/event_dispatcher.dart';
import 'package:test/test.dart';

void main() {
  test(
    'get falls back to the persisted cache after 3 s (Android Repo.java:64)',
    () {
      expect(getPersistedFallbackDelay, const Duration(seconds: 3));
    },
  );

  test('the drain yields after a fixed number of events', () {
    expect(eventsPerDrainSlice, 1000);
  });
}
