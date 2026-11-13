import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/write_send_ahead.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

const String docs = 'projects/p/databases/(default)/documents';

proto.WriteRequest request(List<proto.Write> writes) =>
    proto.WriteRequest()..writes.addAll(writes);

proto.Write set(String path) =>
    proto.Write()..update = (proto.Document()..name = '$docs/$path');

proto.Write update(String path) => set(path)
  ..updateMask = proto.DocumentMask()
  ..currentDocument = (proto.Precondition()..exists = true);

proto.Write delete(String path) => proto.Write()..delete = '$docs/$path';

proto.Write increment(String path) => set(path)
  ..updateMask = proto.DocumentMask()
  ..updateTransforms.add(proto.DocumentTransform_FieldTransform()
    ..fieldPath = 'n'
    ..increment = (proto.Value()..integerValue = Int64(1)));

proto.Write serverTimestamp(String path) => set(path)
  ..updateTransforms.add(proto.DocumentTransform_FieldTransform()
    ..fieldPath = 't'
    ..setToServerValue =
        proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME);

void main() {
  late WriteSendAheadGate gate;

  setUp(() => gate = WriteSendAheadGate());

  void inFlight(List<proto.Write> writes) => gate.sent(request(writes));

  bool canSend(List<proto.Write> writes) => gate.canSend(request(writes));

  test('anything is sent when nothing is in flight', () {
    expect(canSend(<proto.Write>[increment('c/a')]), isTrue);
    expect(canSend(<proto.Write>[update('c/a')]), isTrue);
    expect(gate.canSend(proto.WriteRequest()..database = 'db'), isTrue);
  });

  test('sets, deletes and idempotent transforms are sent ahead', () {
    inFlight(<proto.Write>[set('c/a')]);
    expect(canSend(<proto.Write>[set('c/a')]), isTrue);
    expect(canSend(<proto.Write>[delete('c/a')]), isTrue);
    expect(canSend(<proto.Write>[serverTimestamp('c/a')]), isTrue);
    expect(canSend(<proto.Write>[set('c/b'), delete('c/c')]), isTrue);
    // The empty write that announces the end of the stream.
    expect(canSend(<proto.Write>[]), isTrue);
  });

  test('an increment waits until nothing is in flight', () {
    inFlight(<proto.Write>[set('c/other')]);
    expect(canSend(<proto.Write>[increment('c/a')]), isFalse);
    expect(canSend(<proto.Write>[set('c/b'), increment('c/a')]), isFalse);

    gate.responseReceived();
    expect(gate.inFlight, 0);
    expect(canSend(<proto.Write>[increment('c/a')]), isTrue);
  });

  test('repeatable writes are sent ahead of an increment in flight', () {
    inFlight(<proto.Write>[increment('c/a')]);
    expect(canSend(<proto.Write>[set('c/a')]), isTrue);
    expect(canSend(<proto.Write>[increment('c/b')]), isFalse);
  });

  test('updates of distinct documents are sent ahead', () {
    inFlight(<proto.Write>[update('c/a')]);
    expect(canSend(<proto.Write>[update('c/b')]), isTrue);
    expect(canSend(<proto.Write>[set('c/c')]), isTrue);
  });

  test(
      'a write does not share a document with a write in flight when one of '
      'them has a precondition on it', () {
    inFlight(<proto.Write>[update('c/a')]);
    // Replayed after this delete, the update would fail with NOT_FOUND.
    expect(canSend(<proto.Write>[delete('c/a')]), isFalse);
    expect(canSend(<proto.Write>[set('c/a')]), isFalse);
    expect(canSend(<proto.Write>[update('c/a')]), isFalse);

    gate.responseReceived();
    inFlight(<proto.Write>[delete('c/a')]);
    expect(canSend(<proto.Write>[update('c/a')]), isFalse);
    expect(canSend(<proto.Write>[update('c/b')]), isTrue);
  });

  test('responses release the requests in order', () {
    inFlight(<proto.Write>[update('c/a')]);
    inFlight(<proto.Write>[set('c/b')]);
    expect(gate.inFlight, 2);
    gate.responseReceived();
    // The update is answered: its document is free again.
    expect(canSend(<proto.Write>[delete('c/a')]), isTrue);
    gate.responseReceived();
    gate.responseReceived();
    expect(gate.inFlight, 0);
  });
}
