// The SharedClientStateStorage over window.localStorage, in a browser. A `storage` event is not delivered to the window
// that wrote, so the second participant is the window of a frame of the same origin.
//
//   dart test -p chrome -c dart2wasm test/browser/web_storage_shared_client_state_storage_test.dart

@TestOn('browser')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/web_storage_shared_client_state_storage.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

int _keys = 0;
String newKey() =>
    'firestore_test_${DateTime.now().microsecondsSinceEpoch}_${_keys++}';

void main() {
  late web.HTMLIFrameElement frame;
  late WebStorageSharedClientStateStorage page;
  late WebStorageSharedClientStateStorage other;
  final List<String> keys = <String>[];

  setUp(() {
    frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
    web.document.body!.append(frame);
    page = WebStorageSharedClientStateStorage();
    other = WebStorageSharedClientStateStorage(frame.contentWindow);
  });

  tearDown(() {
    for (final String key in keys) {
      web.window.localStorage.removeItem(key);
    }
    keys.clear();
    frame.remove();
  });

  String key() {
    final String key = newKey();
    keys.add(key);
    return key;
  }

  test('creates the storage of this window', () {
    expect(webStorageSharedClientStateSupported, isTrue);
    final SharedClientStateStorage? storage =
        createWebStorageSharedClientStateStorage();
    expect(storage, isA<WebStorageSharedClientStateStorage>());
    final String k = key();
    storage!.setItem(k, 'v');
    expect(web.window.localStorage.getItem(k), 'v');
  });

  test('reads and writes the localStorage shared by the windows', () {
    final String k = key();
    expect(page.getItem(k), isNull);
    page.setItem(k, 'a');
    expect(other.getItem(k), 'a');
    other.setItem(k, 'b');
    expect(page.getItem(k), 'b');
    page.removeItem(k);
    expect(other.getItem(k), isNull);
  });

  test('tells the other window of a change, not the one that wrote', () async {
    final String k = key();
    final List<SharedClientStateStorageEvent> pageEvents =
        <SharedClientStateStorageEvent>[];
    final StreamController<SharedClientStateStorageEvent> otherEvents =
        StreamController<SharedClientStateStorageEvent>();
    page.addListener(pageEvents.add);
    other.addListener(otherEvents.add);
    final StreamIterator<SharedClientStateStorageEvent> events =
        StreamIterator<SharedClientStateStorageEvent>(otherEvents.stream);

    page.setItem(k, 'a');
    expect(await events.moveNext(), isTrue);
    expect(events.current.key, k);
    expect(events.current.oldValue, isNull);
    expect(events.current.newValue, 'a');
    expect(identical(events.current.storageArea, other), isTrue);

    page.removeItem(k);
    expect(await events.moveNext(), isTrue);
    expect(events.current.key, k);
    expect(events.current.oldValue, 'a');
    expect(events.current.newValue, isNull);

    // The page hears the writes of the frame, and not its own.
    final Completer<SharedClientStateStorageEvent> fromFrame =
        Completer<SharedClientStateStorageEvent>();
    page.addListener((SharedClientStateStorageEvent event) {
      if (!fromFrame.isCompleted) {
        fromFrame.complete(event);
      }
    });
    other.setItem(k, 'b');
    final SharedClientStateStorageEvent event = await fromFrame.future;
    expect(event.key, k);
    expect(event.newValue, 'b');
    expect(identical(event.storageArea, page), isTrue);
    expect(
      pageEvents.map((SharedClientStateStorageEvent e) => e.newValue),
      <String?>['b'],
    );

    other.removeListener(otherEvents.add);
    await events.cancel();
    await otherEvents.close();
  });

  test('stops telling a listener once it is removed', () async {
    final String k = key();
    final List<String?> heard = <String?>[];
    void listener(SharedClientStateStorageEvent event) =>
        heard.add(event.newValue);
    final Completer<void> second = Completer<void>();
    void witness(SharedClientStateStorageEvent event) {
      if (event.newValue == '2' && !second.isCompleted) {
        second.complete();
      }
    }

    other.addListener(listener);
    other.addListener(witness);
    page.setItem(k, '1');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    other.removeListener(listener);
    page.setItem(k, '2');
    await second.future;
    expect(heard, <String?>['1']);
    other.removeListener(witness);
  });

  test('ignores sessionStorage', () async {
    final String k = key();
    final List<String> heard = <String>[];
    other.addListener((SharedClientStateStorageEvent event) {
      heard.add(event.key);
    });
    web.window.sessionStorage.setItem(k, 'session');
    page.setItem(k, 'local');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    web.window.sessionStorage.removeItem(k);
    expect(heard, <String>[k]);
  });
}
