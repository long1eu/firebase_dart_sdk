// Owner U. The connection half alone against the Database emulator through the chaos proxy and
// its WebSocket frame tap: framing on the wire, replay after a cut, the dead-link probe, the
// keep-alive, and requests that are never answered. Expectations are what
// rtdb_emulator_probe.md measured; the section is named in each test.
@Tags(<String>['emulator'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:test/test.dart';

import '../util/chaos_proxy.dart';
import '../util/ws_tap.dart';
import 'emulator_rig.dart';

/// The `d` of a data envelope, or null.
Map<String, Object?>? dataOf(TapMessage m) {
  final Object? d = m.envelope['d'];
  return m.envelope['t'] == 'd' && d is Map<String, Object?> ? d : null;
}

/// Whether [d] is a client request with [action] at [path] (sent with or without the slash).
bool isRequest(Map<String, Object?> d, String action, String path) {
  final Object? body = d['b'];
  if (d['a'] != action || body is! Map<String, Object?>) {
    return false;
  }
  final Object? p = body['p'];
  return p is String && p.replaceFirst(RegExp('^/'), '') == path;
}

void main() {
  group('connection through the chaos proxy', skip: emulatorSkipReason, () {
    test(
      'a message just over one frame goes as a count frame and two pieces '
      '(probe "Frame and message limits": count frame first, 16384 per frame)',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        final ChaosProxy proxy = await rig.proxy();
        final WsFrameTap tap = WsFrameTap(proxy);
        final List<String> upTexts = <String>[];
        final StreamSubscription<TapFrame> frames = tap.frames.listen((
          TapFrame f,
        ) {
          if (f.direction == ChaosDirection.up && f.text != null) {
            upTexts.add(f.text!);
          }
        });
        addTearDown(frames.cancel);
        final RigClient client = await rig.open(proxy: proxy);
        final String value = 'y' * 16400;
        upTexts.clear();
        expect((await client.put('/f', value)).status, statusOk);
        final int count = upTexts.indexOf('2');
        expect(count, isNot(-1), reason: 'a count frame "2"');
        expect(upTexts[count + 1].length, 16384);
        expect(
          (upTexts[count + 1] + upTexts[count + 2]).contains(value),
          isTrue,
        );
        expect(await rig.read('/f'), value);
      },
    );

    test('a cut after the put is sent and before its ack: the put is re-sent '
        'after the reconnect and applied twice, an increment gives 2 (probe '
        'addendum 2 item 12, measured 2)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final ChaosProxy proxy = await rig.proxy();
      final WsFrameTap tap = WsFrameTap(proxy);
      final RigClient client = await rig.open(proxy: proxy);
      int? putRequest;
      int puts = 0;
      tap.cutBeforeFrame((TapMessage m) {
        final Map<String, Object?>? d = dataOf(m);
        if (d == null) {
          return false;
        }
        if (m.direction == ChaosDirection.up && isRequest(d, 'p', 'cnt')) {
          putRequest = d['r'] as int?;
          return false;
        }
        return m.direction == ChaosDirection.down &&
            putRequest != null &&
            d['r'] == putRequest;
      });
      final StreamSubscription<TapMessage> sent = tap.messages.listen((
        TapMessage m,
      ) {
        final Map<String, Object?>? d = dataOf(m);
        if (m.direction == ChaosDirection.up &&
            d != null &&
            isRequest(d, 'p', 'cnt')) {
          puts++;
        }
      });
      addTearDown(sent.cancel);

      final (RequestResultCallback callback, List<Ack> acks) = client
          .recorder();
      client.connection.put('/cnt', <String, Object?>{
        '.sv': <String, Object?>{'increment': 1},
      }, onComplete: callback);
      final Ack ack = await client.first(acks);
      expect(ack.status, statusOk);
      expect(proxy.cuts, 1);
      expect(client.disconnectReasons, isNotEmpty);
      await client.waitConnects(2);
      expect(puts, 2, reason: 'sent, cut before the ack, re-sent once');
      expect(await rig.read('/cnt'), 2);
      expect(acks, hasLength(1), reason: 'completed once');
    });

    test('a silent cut (black hole) is detected by the dead-link probe, and '
        'the client reconnects when the link comes back (probe addendum 2 '
        'item 9: the server answers a ping at any time)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final ChaosProxy proxy = await rig.proxy();
      final RigClient client = await rig.open(
        proxy: proxy,
        timings: const ConnectionTimings(
          reconnectMin: Duration(milliseconds: 50),
          reconnectMax: Duration(milliseconds: 500),
          connectTimeout: Duration(seconds: 2),
          idleProbeAfter: Duration(seconds: 1),
          idleProbeTimeout: Duration(seconds: 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(
        client.disconnectReasons,
        isEmpty,
        reason: 'a live link answers the probe pings',
      );
      proxy.mode = ChaosMode.blackHole;
      await eventually(
        () => client.disconnectReasons.contains(DisconnectReason.deadLink)
            ? true
            : null,
        what: 'a deadLink close',
      );
      expect(client.delegate.callsOf('disconnect'), isNotEmpty);
      proxy.mode = ChaosMode.forward;
      await client.waitConnects(2, timeout: const Duration(seconds: 4));
    });

    test('an idle connection sends the keep-alive 0 and stays open (probe '
        '"Keep-alive and idle behaviour"; shrunk to 1 s)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final ChaosProxy proxy = await rig.proxy();
      final WsFrameTap tap = WsFrameTap(proxy);
      int keepAlives = 0;
      final StreamSubscription<TapFrame> frames = tap.frames.listen((
        TapFrame f,
      ) {
        if (f.direction == ChaosDirection.up && f.text == '0') {
          keepAlives++;
        }
      });
      addTearDown(frames.cancel);
      final RigClient client = await rig.open(
        proxy: proxy,
        timings: const ConnectionTimings(
          reconnectMin: Duration(milliseconds: 50),
          keepAlive: Duration(seconds: 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      expect(keepAlives, greaterThanOrEqualTo(2));
      expect(client.disconnectReasons, isEmpty);
      expect(proxy.cuts, 0);
      expect(await client.connection.get(defaultSpec('/k')), isNull);
    });

    test(
      'with the production keep-alive (45 s) the emulator\'s 120 s idle '
      'close does not happen (probe "Keep-alive and idle behaviour": '
      'exactly 120 s without a frame)',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        final RigClient client = await rig.open(
          timings: const ConnectionTimings(
            // The dead-link probe would also keep the link busy; leave only the keep-alive.
            idleProbeAfter: Duration(minutes: 10),
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 130));
        expect(client.disconnectReasons, isEmpty);
        expect(client.delegate.callsOf('disconnect'), isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 160)),
      // 130 s: excluded by default with the emulator-slow tag.
      tags: 'emulator-slow',
    );

    test('a put the server never answers (unknown server value) is never '
        'failed: each silence closes the connection and the same put is sent '
        'again on the next one (timeout rule of the review rulings, H1; probe '
        '"Server values": control error, no answer)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final ChaosProxy proxy = await rig.proxy();
      final WsFrameTap tap = WsFrameTap(proxy);
      final List<Object?> sentBodies = <Object?>[];
      final StreamSubscription<TapMessage> sent = tap.messages.listen((
        TapMessage m,
      ) {
        final Map<String, Object?>? d = dataOf(m);
        if (m.direction == ChaosDirection.up &&
            d != null &&
            isRequest(d, 'p', 'nx')) {
          sentBodies.add((d['b']! as Map<String, Object?>)['d']);
        }
      });
      addTearDown(sent.cancel);
      final RigClient client = await rig.open(
        proxy: proxy,
        timings: const ConnectionTimings(
          reconnectMin: Duration(milliseconds: 50),
          reconnectMax: Duration(milliseconds: 500),
          requestTimeout: Duration(seconds: 1),
        ),
      );
      final (RequestResultCallback callback, List<Ack> acks) = client
          .recorder();
      client.connection.put('/nx', <String, Object?>{
        '.sv': 'bogus',
      }, onComplete: callback);
      // Two rounds: sent, silence, closed, re-sent; silence, closed, re-sent.
      await eventually(
        () => sentBodies.length >= 3 && client.disconnectReasons.length >= 2
            ? true
            : null,
        what: 'two closes after silence and two re-sends',
        timeout: const Duration(seconds: 8),
      );
      expect(acks, isEmpty, reason: 'a write is never failed by a timeout');
      expect(
        sentBodies,
        everyElement(<String, Object?>{'.sv': 'bogus'}),
        reason: 'the same put each time',
      );
      expect(
        client.delegate.callsOf('connect').length,
        greaterThanOrEqualTo(3),
      );
      expect(await rig.read('/nx'), isNull);
      client.connection.purgeOutstandingWrites();
      final Ack purged = await client.first(acks);
      expect(purged.status, 'write_canceled');
    });

    test('a get whose answers are lost times out twice and fails with '
        'network_error (tap drops the answers)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final ChaosProxy proxy = await rig.proxy();
      final WsFrameTap tap = WsFrameTap(proxy);
      final Set<Object?> gets = <Object?>{};
      tap.dropFrames((TapMessage m) {
        final Map<String, Object?>? d = dataOf(m);
        if (d == null) {
          return false;
        }
        if (m.direction == ChaosDirection.up && isRequest(d, 'g', 'gx')) {
          gets.add(d['r']);
          return false;
        }
        return m.direction == ChaosDirection.down &&
            d['a'] == null &&
            gets.contains(d['r']);
      });
      final RigClient client = await rig.open(
        proxy: proxy,
        timings: const ConnectionTimings(
          reconnectMin: Duration(milliseconds: 50),
          reconnectMax: Duration(milliseconds: 500),
          requestTimeout: Duration(seconds: 1),
        ),
      );
      await expectLater(
        client.connection
            .get(defaultSpec('/gx'))
            .timeout(const Duration(seconds: 8)),
        throwsA(
          isA<ServerActionsException>().having(
            (ServerActionsException e) => e.status,
            'status',
            statusNetworkError,
          ),
        ),
      );
      expect(gets, hasLength(2), reason: 'sent, timed out, re-sent once');
    });
  });
}
