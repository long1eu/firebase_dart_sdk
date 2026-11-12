// Copyright 2018 Google LLC / Lung Razvan. Licensed under the Apache License,
// Version 2.0.

import 'dart:async';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// Checks that a channel configured like the one in `Datastore` can receive
/// messages larger than the 4 MiB gRPC default. Upstream raised the inbound
/// limit to 17 MiB to support 16 MiB documents; this test shows whether the
/// Dart channel needs the same treatment. (The emulator cannot be used for
/// this: it does not support documents above 1 MiB.)
class _BigService extends Service {
  _BigService(this.size) {
    $addMethod(ServiceMethod<int, Uint8List>(
      'Big',
      (ServiceCall call, Future<int> request) async =>
          Uint8List(size)..fillRange(0, size, 7),
      false,
      false,
      (List<int> bytes) => bytes.length,
      (Uint8List value) => value,
    ));
  }

  final int size;

  @override
  String get $name => 'test.Big';
}

class _BigClient extends Client {
  _BigClient(super.channel);

  static final ClientMethod<int, Uint8List> _method =
      ClientMethod<int, Uint8List>(
    '/test.Big/Big',
    (int value) => <int>[1],
    Uint8List.fromList,
  );

  ResponseFuture<Uint8List> big() => $createUnaryCall(_method, 0);
}

void main() {
  const int sixteenMiB = 16 * 1024 * 1024;

  for (final int size in <int>[5 * 1024 * 1024, sixteenMiB + 1024]) {
    test('receives a ${size ~/ 1024} KiB response', () async {
      final Server server =
          Server.create(services: <Service>[_BigService(size)]);
      await server.serve(address: '127.0.0.1', port: 0);
      final ClientChannel channel = ClientChannel(
        '127.0.0.1',
        port: server.port!,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      );
      try {
        final Uint8List result = await _BigClient(channel).big();
        expect(result.length, size);
      } finally {
        await channel.shutdown();
        await server.shutdown();
      }
    });
  }
}
