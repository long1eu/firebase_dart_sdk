@TestOn('vm')
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/rc_fetch_harness.dart';

const Duration _zero = Duration.zero;

FakeAnswer _template(Map<String, String> entries, {Object? version}) =>
    FakeAnswer.fetch(entries: entries, templateVersion: version);

void main() {
  fakeTest('5.5 activate without a fetched record returns false', (
    FakeAsync async,
    Harness h,
  ) {
    final RcEnv env = h.env(defaults: <String, Object>{'a': 'default'});

    expect(h.settle(env.remoteConfig.activate()), isFalse);
    expect(env.remoteConfig.getString('a'), 'default');
    expect(h.settle(env.readRecord('active')), isNull);
  });

  fakeTest(
    '5.5 activate makes the fetched record active; reads go remote, then default, then static',
    (FakeAsync async, Harness h) {
      final RcEnv env = h.env(
        defaults: <String, Object>{'a': 'default', 'b': 'default-b'},
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{
          'a': 'remote',
          'c': 'only-remote',
        }, version: '5'),
      );
      h.settle(env.remoteConfig.fetch());

      expect(h.settle(env.remoteConfig.activate()), isTrue);

      expect(env.remoteConfig.getValue('a').source, ValueSource.valueRemote);
      expect(env.remoteConfig.getString('a'), 'remote');
      expect(env.remoteConfig.getValue('b').source, ValueSource.valueDefault);
      expect(env.remoteConfig.getString('b'), 'default-b');
      expect(env.remoteConfig.getValue('z').source, ValueSource.valueStatic);
      expect(
        env.remoteConfig.getAll().keys,
        unorderedEquals(<String>['a', 'b', 'c']),
      );
      expect(env.remoteConfig.info.activeTemplateVersion, 5);
      final Map<String, Object?> active = h.settle(env.readRecord('active'))!;
      expect(active['entries'], <String, Object?>{
        'a': 'remote',
        'c': 'only-remote',
      });
      // The fetched record is not removed.
      expect(h.settle(env.readRecord('fetched')), active);
    },
  );

  fakeTest('5.5 a repeated activate returns false', (
    FakeAsync async,
    Harness h,
  ) {
    final RcEnv env = h.env();
    env.backend.enqueue(
      FakeRoute.fetch,
      _template(<String, String>{'a': '1'}, version: '1'),
    );
    h.settle(env.remoteConfig.fetch());

    expect(h.settle(env.remoteConfig.activate()), isTrue);
    expect(h.settle(env.remoteConfig.activate()), isFalse);
    expect(env.remoteConfig.getString('a'), '1');
  });

  fakeTest(
    '5.5 fetchAndActivate returns activate\'s result after cached and unchanged fetches',
    (FakeAsync async, Harness h) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': '1'}, version: '1'),
      );
      expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);

      // Cached: no request; the fetched record is already active.
      expect(h.settle(env.remoteConfig.fetchAndActivate()), isFalse);
      expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

      // Unchanged.
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
      );
      expect(
        h.settle(
          env.remoteConfig.fetchAndActivate(minimumFetchInterval: _zero),
        ),
        isFalse,
      );

      // A fetch stored earlier but not activated is activated after a cached fetch. A minute passes
      // first: activate tells two fetches apart by their fetch time.
      async.elapse(const Duration(minutes: 1));
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': '2'}, version: '2'),
      );
      h.settle(env.remoteConfig.fetch(minimumFetchInterval: _zero));
      expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);
      expect(env.remoteConfig.getString('a'), '2');
    },
  );

  fakeTest('5.5 fetchAndActivate does not activate after a failed fetch', (
    FakeAsync async,
    Harness h,
  ) {
    final RcEnv env = h.env();
    env.backend.enqueue(
      FakeRoute.fetch,
      _template(<String, String>{'a': '1'}, version: '1'),
    );
    h.settle(env.remoteConfig.fetch());
    env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(500));

    expect(
      h
          .rcError(
            env.remoteConfig.fetchAndActivate(minimumFetchInterval: _zero),
          )
          .code,
      'fetch-status',
    );
    expect(env.remoteConfig.info.activeTemplateVersion, isNull);
  });

  group('NO_TEMPLATE', () {
    fakeTest('5.5 NO_TEMPLATE clears values: activate leaves only defaults', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(
        defaults: <String, Object>{'a': 'default'},
        minimumFetchInterval: _zero,
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': 'remote', 'b': 'x'}),
      );
      expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);
      expect(env.remoteConfig.getString('a'), 'remote');

      async.elapse(const Duration(minutes: 1));
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_TEMPLATE'),
      );
      expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
      expect(h.settle(env.remoteConfig.activate()), isTrue);

      expect(env.remoteConfig.getString('a'), 'default');
      expect(env.remoteConfig.getValue('b').source, ValueSource.valueStatic);
      expect(env.remoteConfig.getAll().keys, <String>['a']);
    });

    fakeTest('5.5 EMPTY_CONFIG with a newer template version clears values', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(minimumFetchInterval: _zero);
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': 'remote'}, version: '3'),
      );
      h.settle(env.remoteConfig.fetchAndActivate());

      async.elapse(const Duration(minutes: 1));
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'EMPTY_CONFIG', templateVersion: '4'),
      );
      h.settle(env.remoteConfig.fetch());
      expect(h.settle(env.remoteConfig.activate()), isTrue);

      expect(env.remoteConfig.getAll(), isEmpty);
      expect(env.remoteConfig.info.activeTemplateVersion, 4);
    });

    fakeTest(
      '5.5 NO_TEMPLATE without a version replaces a versioned active record and clears values',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(
          defaults: <String, Object>{'b': 'default'},
          minimumFetchInterval: _zero,
        );
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '2'),
        );
        h.settle(env.remoteConfig.fetchAndActivate());

        async.elapse(const Duration(minutes: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_TEMPLATE'),
        );
        h.settle(env.remoteConfig.fetch());
        expect(env.remoteConfig.info.fetchedTemplateVersion, isNull);

        // "Refuse a lower version" needs a version on both records.
        expect(h.settle(env.remoteConfig.activate()), isTrue);
        expect(env.remoteConfig.getValue('a').source, ValueSource.valueStatic);
        expect(env.remoteConfig.getString('b'), 'default');
        expect(env.remoteConfig.getAll().keys, <String>['b']);
        expect(env.remoteConfig.info.activeTemplateVersion, isNull);
        final Map<String, Object?> active = h.settle(env.readRecord('active'))!;
        expect(active['entries'], isEmpty);
        expect(active.containsKey('templateVersion'), isFalse);
      },
    );
  });

  group('two instances on one store', () {
    fakeTest(
      '5.5 a lower version is refused and memory loads the stored active record',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(minimumFetchInterval: _zero);
        final FirebaseRemoteConfig other = env.newRemoteConfig(
          minimumFetchInterval: _zero,
        );
        h.settle(other.ensureInitialized());

        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'v5'}, version: '5'),
        );
        expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);

        // The other instance fetches an older version afterwards (a lagging server).
        async.elapse(const Duration(minutes: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'v3'}, version: '3'),
        );
        expect(h.settle(other.fetch()), FetchResult.updated);
        expect(other.getString('a'), '');

        expect(h.settle(other.activate()), isFalse);
        expect(other.getString('a'), 'v5');
        expect(other.info.activeTemplateVersion, 5);
        expect(h.settle(env.readRecord('active'))!['templateVersion'], 5);
      },
    );

    fakeTest(
      '5.5 activate of a record another instance already activated returns false and loads it',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig other = env.newRemoteConfig();
        h.settle(other.ensureInitialized());

        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '7'),
        );
        expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);

        expect(h.settle(other.activate()), isFalse);
        expect(other.getString('a'), 'remote');
        expect(other.info.activeTemplateVersion, 7);
      },
    );

    fakeTest(
      '5.5 (A21) a higher version another instance stores while this request is in flight is kept',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(minimumFetchInterval: _zero);
        final FirebaseRemoteConfig other = env.newRemoteConfig(
          minimumFetchInterval: _zero,
        );
        h.settle(other.ensureInitialized());

        final Gate gate = Gate();
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{
            'a': 'lower',
          }, version: '8').after(gate.future),
        );
        final Future<FetchResult> slow = env.remoteConfig.fetch();
        async.flushMicrotasks();
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

        // Sent <= stored fetch time <= now, and a higher version: the other instance's record stays,
        // although its fetch time is earlier than that of the slow answer.
        async.elapse(const Duration(seconds: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'higher'}, version: '9'),
        );
        expect(h.settle(other.fetch()), FetchResult.updated);
        async.elapse(const Duration(seconds: 1));
        gate.open();
        h.settle(slow);

        final Map<String, Object?> fetched = h.settle(
          env.readRecord('fetched'),
        )!;
        expect(fetched['entries'], <String, Object?>{'a': 'higher'});
        expect(fetched['templateVersion'], 9);
        expect(env.remoteConfig.info.fetchedTemplateVersion, 9);

        expect(h.settle(env.remoteConfig.activate()), isTrue);
        expect(env.remoteConfig.getString('a'), 'higher');
      },
    );

    fakeTest(
      '5.5 (A21) a higher version stored before this request was sent is replaced by its answer',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(minimumFetchInterval: _zero);
        final FirebaseRemoteConfig other = env.newRemoteConfig(
          minimumFetchInterval: _zero,
        );
        h.settle(other.ensureInitialized());

        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'higher'}, version: '9'),
        );
        expect(h.settle(other.fetch()), FetchResult.updated);

        async.elapse(const Duration(minutes: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'lower'}, version: '8'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);

        final Map<String, Object?> fetched = h.settle(
          env.readRecord('fetched'),
        )!;
        expect(fetched['entries'], <String, Object?>{'a': 'lower'});
        expect(fetched['templateVersion'], 8);
        expect(env.remoteConfig.info.fetchedTemplateVersion, 8);

        expect(h.settle(env.remoteConfig.activate()), isTrue);
        expect(env.remoteConfig.getString('a'), 'lower');
      },
    );

    fakeTest(
      '5.5 (A21) a write of fetched with a higher version replaces a stored record with a later '
      'fetch time',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(minimumFetchInterval: _zero);
        // The other instance's clock runs one minute ahead: its fetch of the lower version has a
        // fetch time after this request's now (impossible under A21) and a lower version; it is
        // replaced either way.
        final FirebaseRemoteConfig ahead = env.newRemoteConfig(
          minimumFetchInterval: _zero,
          clock: () => h.now().add(const Duration(minutes: 1)),
        );
        h.settle(ahead.ensureInitialized());

        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'lower'}, version: '8'),
        );
        expect(h.settle(ahead.fetch()), FetchResult.updated);

        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'higher'}, version: '9'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);

        final Map<String, Object?> fetched = h.settle(
          env.readRecord('fetched'),
        )!;
        expect(fetched['entries'], <String, Object?>{'a': 'higher'});
        expect(env.remoteConfig.info.fetchedTemplateVersion, 9);
      },
    );

    fakeTest('5.5 activate picks up a fetch stored by another instance', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      final FirebaseRemoteConfig other = env.newRemoteConfig();
      h.settle(other.ensureInitialized());

      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': 'remote'}, version: '2'),
      );
      h.settle(env.remoteConfig.fetch());

      expect(h.settle(other.activate()), isTrue);
      expect(other.getString('a'), 'remote');
    });
  });

  group('store failures (5.10)', () {
    fakeTest(
      '5.5 a failed write of active is storage-error and leaves memory unchanged',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(store: store, minimumFetchInterval: _zero);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'v1'}, version: '1'),
        );
        h.settle(env.remoteConfig.fetchAndActivate());
        async.elapse(const Duration(minutes: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'v2'}, version: '2'),
        );
        h.settle(env.remoteConfig.fetch());

        store.before = (StoreOp op, String key) {
          if (op == StoreOp.update && key == env.recordKey('active')) {
            throw StateError('disk full');
          }
        };
        final FirebaseRemoteConfigException error = h.rcError(
          env.remoteConfig.activate(),
        );
        expect(error.code, 'storage-error');
        expect(error.cause, isA<StateError>());
        expect(env.remoteConfig.getString('a'), 'v1');
        expect(env.remoteConfig.info.activeTemplateVersion, 1);
        expect(h.settle(env.readRecord('active'))!['templateVersion'], 1);

        // The store recovers: the next activate writes.
        store.before = null;
        expect(h.settle(env.remoteConfig.activate()), isTrue);
        expect(env.remoteConfig.getString('a'), 'v2');
      },
    );

    fakeTest(
      '5.5 a failed read of fetched is storage-error and leaves memory unchanged',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(store: store);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'v1'}, version: '1'),
        );
        h.settle(env.remoteConfig.fetch());

        store.before = (StoreOp op, String key) {
          if (op == StoreOp.read && key == env.recordKey('fetched')) {
            throw StateError('io error');
          }
        };
        expect(h.rcError(env.remoteConfig.activate()).code, 'storage-error');
        expect(env.remoteConfig.getString('a'), '');
        expect(env.remoteConfig.info.activeTemplateVersion, isNull);
      },
    );

    fakeTest('5.5 activate waits for the records to load', (
      FakeAsync async,
      Harness h,
    ) {
      final ScriptedStore store = ScriptedStore();
      final RcEnv env = h.env(store: store);
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': 'v1'}, version: '1'),
      );
      h.settle(env.remoteConfig.fetch());

      final Completer<void> loaded = Completer<void>();
      store.before = (StoreOp op, String key) =>
          op == StoreOp.read && key.startsWith('remote_config/')
          ? loaded.future
          : null;
      final FirebaseRemoteConfig other = env.newRemoteConfig();
      bool done = false;
      final Future<bool> activated = other.activate()
        ..whenComplete(() => done = true).ignore();
      async.flushMicrotasks();
      expect(other.isInitialized, isFalse);
      expect(done, isFalse);

      loaded.complete();
      expect(h.settle(activated), isTrue);
      expect(other.getString('a'), 'v1');
    });
  });

  group('closed (5.4)', () {
    fakeTest(
      '5.4 activate after close is remote-config-closed; reads keep answering',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(defaults: <String, Object>{'b': 'default'});
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '1'),
        );
        h.settle(env.remoteConfig.fetchAndActivate());
        h.settle(env.remoteConfig.close());
        h.settle(env.remoteConfig.close());

        expect(
          h.rcError(env.remoteConfig.activate()).code,
          'remote-config-closed',
        );
        expect(env.remoteConfig.getString('a'), 'remote');
        expect(env.remoteConfig.getString('b'), 'default');
      },
    );

    fakeTest(
      '5.4 close while activate waits for the store fails it with remote-config-closed',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(store: store);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '1'),
        );
        h.settle(env.remoteConfig.fetch());

        final Completer<void> slow = Completer<void>();
        store.before = (StoreOp op, String key) =>
            op == StoreOp.update && key == env.recordKey('active')
            ? slow.future
            : null;
        final Future<bool> activated = env.remoteConfig.activate()..ignore();
        async.flushMicrotasks();

        h.settle(env.remoteConfig.close());
        slow.complete();
        expect(h.rcError(activated).code, 'remote-config-closed');
        expect(env.remoteConfig.getString('a'), '');
      },
    );

    fakeTest('5.4 deleting the app closes the instance', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      h.settle(env.app.delete());

      expect(
        h.rcError(env.remoteConfig.activate()).code,
        'remote-config-closed',
      );
    });
  });
}
