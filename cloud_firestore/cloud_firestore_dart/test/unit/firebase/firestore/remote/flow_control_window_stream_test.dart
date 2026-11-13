// The stream plumbing of FlowControlWindow: back pressure of package:http2 on the incoming side reaches the socket, and
// errors on the outgoing side reach the socket unchanged.

// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/flow_control_window.dart';
import 'package:test/test.dart';

Uint8List _settingsAck() =>
    Uint8List.fromList(<int>[0, 0, 0, 0x4, 0x1, 0, 0, 0, 0]);

void main() {
  test(
    'pausing the incoming stream pauses the socket, resuming resumes it',
    () async {
      final StreamController<List<int>> socket = StreamController<List<int>>();
      final FlowControlWindow window = FlowControlWindow(1 << 18);
      final List<List<int>> received = <List<int>>[];
      final StreamSubscription<List<int>> subscription = window
          .bindIncoming(socket.stream)
          .listen(received.add);
      await pumpEventQueue();

      subscription.pause();
      await pumpEventQueue();
      expect(socket.isPaused, isTrue);

      socket.add(_settingsAck());
      await pumpEventQueue();
      expect(received, isEmpty);

      subscription.resume();
      await pumpEventQueue();
      expect(socket.isPaused, isFalse);
      expect(received, hasLength(1));
      await expectLater(window.settingsAcknowledged, completes);

      await subscription.cancel();
      expect(socket.hasListener, isFalse);
    },
  );

  test('an error added to the outgoing sink reaches the socket', () async {
    final StreamController<List<int>> socket = StreamController<List<int>>();
    final List<Object> errors = <Object>[];
    socket.stream.listen((_) {}, onError: errors.add);
    final StreamSink<List<int>> sink = FlowControlWindow(
      1 << 18,
    ).bindOutgoing(socket.sink);

    final StateError error = StateError('write failed');
    sink.addError(error);
    await pumpEventQueue();
    expect(errors, <Object>[error]);
    await sink.close();
  });
}
