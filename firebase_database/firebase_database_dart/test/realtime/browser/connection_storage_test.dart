// Owner P. Threat model T27 for the connection layer in the browser: a whole PersistentConnection
// session (connect, credentials, a listen, writes, pushes, a token change, a drop, a reconnect,
// a shutdown) leaves localStorage and sessionStorage exactly as it found them. Compares before
// and after, so a browser profile that already holds data does not fail it (threat coverage note
// 21). Run with `dart test -p chrome -c dart2js` and `-c dart2wasm`.
@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../../util/persistent_connection_harness.dart';

Map<String, String?> _snapshot(web.Storage storage) => <String, String?>{
  for (int i = 0; i < storage.length; i++)
    storage.key(i)!: storage.getItem(storage.key(i)!),
};

void main() {
  test(
    'a connection session writes nothing to localStorage or sessionStorage',
    () async {
      final Map<String, String?> local = _snapshot(web.window.localStorage);
      final Map<String, String?> session = _snapshot(web.window.sessionStorage);

      final PRig rig = PRig(hold: false);
      await rig.start();
      rig.connection.listen(
        defaultListen('/a'),
        hashProvider: CountingHash(''),
        onComplete: (_, _) {},
      );
      rig.connection.put('/a', <String, Object?>{'k': 'v'});
      rig.connection.onDisconnectPut('/b', 1);
      rig.server.pushData('/a', <String, Object?>{'k': 'w'});
      rig.tokens.emitAuth(
        'eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1MiIsImlhdCI6MX0.sig2',
      );
      await rig.settle();
      await rig.drop();
      await until(() => rig.connects == 2);
      await rig.settle();
      await rig.connection.shutdown();

      expect(rig.server.log, isNotEmpty);
      expect(_snapshot(web.window.localStorage), local);
      expect(_snapshot(web.window.sessionStorage), session);
    },
  );
}
