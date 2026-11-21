/// Requests for the bytes of an object ask for the identity encoding on the VM, so that offsets and sizes of an
/// object stored gzip-compressed are in unzipped bytes (see lib/src/media_headers_io.dart).
@TestOn('vm')
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'streaming_client.dart';

void main() {
  late FirebaseApp app;

  setUp(() => app = newApp());
  tearDown(() => app.delete());

  FirebaseStorage storageOn(StreamingClient client) {
    final FirebaseStorage storage = FirebaseStorage(app, httpClient: client);
    addTearDown(storage.close);
    return storage;
  }

  String? encodingOf(http.BaseRequest request) =>
      request.headers['Accept-Encoding'];

  test(
    'openRead asks for the identity encoding, with or without a range',
    () async {
      final StreamingClient client = StreamingClient.chunks(<String>['hello']);
      final Reference ref = storageOn(client).ref('f');
      await ref.openRead().drain<void>();
      await ref.openRead(1).drain<void>();
      expect(client.requests.map(encodingOf), <String>['identity', 'identity']);
    },
  );

  test(
    'getBytes asks for the identity encoding, with or without maxSize',
    () async {
      final StreamingClient client = StreamingClient.chunks(<String>['hello']);
      final Reference ref = storageOn(client).ref('f');
      await ref.getBytes();
      await ref.getBytes(maxSize: 10);
      expect(client.requests.map(encodingOf), <String>['identity', 'identity']);
    },
  );

  test(
    'a 200 with the whole object answered to a range is cut to the range',
    () async {
      // What the server does for an object stored gzip-compressed when the identity encoding is asked for: it
      // unzips the object and ignores the Range header.
      final StreamingClient client = StreamingClient.chunks(<String>[
        'hello world',
      ]);
      final List<int> bytes = await storageOn(
        client,
      ).ref('f').openRead(6).expand((List<int> c) => c).toList();
      expect(String.fromCharCodes(bytes), 'world');
    },
  );

  test('metadata requests leave the encoding to the client', () async {
    final StreamingClient client = StreamingClient.chunks(<String>[
      '{"name":"f","bucket":"b","generation":"1","metageneration":"1","size":"5"}',
    ]);
    await storageOn(client).ref('f').metadata();
    expect(encodingOf(client.requests.single), isNull);
  });
}
