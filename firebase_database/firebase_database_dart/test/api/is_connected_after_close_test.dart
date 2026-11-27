// isConnected after close and after the app is deleted: always false, whatever it was before,
// from the call on. onConnected listeners get done, with no error and no final false event.

import 'dart:async';

import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// Runs [body] on a harness that is online; time is fake.
void _connected(String name, void Function(Harness h) body) {
  test(name, () => fakeTime((FakeTime time) => body(Harness(time))));
}

/// Listens to onConnected, logging `C:true`, `C:false`, `C:E(code)` and `C:done`.
void _listenConnected(Harness h) {
  h.db.onConnected.listen(
    (bool connected) => h.log.add('C:$connected'),
    onError: (Object e) => h.log.add('C:${errorText(e)}'),
    onDone: () => h.log.add('C:done'),
  );
  h.settle();
}

void main() {
  _connected(
    'close while connected: isConnected is false at once and stays false',
    (Harness h) {
      _listenConnected(h);
      expect(h.db.isConnected, isTrue);
      expect(h.log, <String>['C:true']);

      unawaited(h.db.close());
      expect(h.db.isConnected, isFalse);
      h.settle();
      expect(h.db.isConnected, isFalse);
      h.elapse(const Duration(minutes: 5));
      expect(h.db.isConnected, isFalse);
      expect(h.log, <String>['C:true', 'C:done']);
    },
  );

  _connected('app deleted while connected: isConnected is false', (Harness h) {
    _listenConnected(h);
    expect(h.db.isConnected, isTrue);

    unawaited(h.app.delete());
    // The close that the deletion starts runs one event later; isConnected is false already.
    expect(h.db.isConnected, isFalse);
    h.settle();
    expect(h.db.isConnected, isFalse);
    expect(h.log, <String>['C:true', 'C:done']);
  });

  _connected('close while offline: isConnected stays false', (Harness h) {
    h.db.goOffline();
    h.settle();
    expect(h.db.isConnected, isFalse);

    unawaited(h.db.close());
    h.settle();
    expect(h.db.isConnected, isFalse);
  });
}
