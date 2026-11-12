import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// Upstream (25.1.4) had to guard `halfClose()` on an already cancelled RPC.
/// This checks that tearing down a bidirectional call the way
/// `BaseStream._close` does (close the request controller, cancel the
/// subscription, cancel the response) does not throw or leak an uncaught error
/// when the call was already cancelled or failed.
class _EchoService extends Service {
  _EchoService() {
    $addMethod(ServiceMethod<int, int>(
      'Echo',
      (ServiceCall call, Stream<int> requests) async* {
        await for (final int r in requests) {
          yield r;
        }
      },
      true,
      true,
      (List<int> b) => b.first,
      (int v) => <int>[v],
    ));
  }

  @override
  String get $name => 'test.Echo';
}

class _EchoClient extends Client {
  _EchoClient(super.channel);

  static final ClientMethod<int, int> _method = ClientMethod<int, int>(
    '/test.Echo/Echo',
    (int v) => <int>[v],
    (List<int> b) => b.first,
  );

  ResponseStream<int> echo(Stream<int> requests) =>
      $createStreamingCall(_method, requests);
}

void main() {
  for (final String how in <String>['cancelled by client', 'server gone']) {
    test('teardown after the call was $how does not throw', () async {
      final List<Object> uncaught = <Object>[];
      await runZonedGuarded(() async {
        final Server server =
            Server.create(services: <Service>[_EchoService()]);
        await server.serve(address: '127.0.0.1', port: 0);
        final ClientChannel channel = ClientChannel('127.0.0.1',
            port: server.port!,
            options: const ChannelOptions(
                credentials: ChannelCredentials.insecure()));
        final StreamController<int> requests =
            StreamController<int>.broadcast();
        final ResponseStream<int> response =
            _EchoClient(channel).echo(requests.stream);
        final Completer<void> first = Completer<void>();
        final StreamSubscription<int> sub = response.listen(
            (int _) => first.isCompleted ? null : first.complete(),
            onError: (Object _) {});
        await Future<void>.delayed(const Duration(milliseconds: 200));
        requests.add(1);
        await first.future.timeout(const Duration(seconds: 5));

        if (how == 'server gone') {
          // Drop the connection from the server side (a graceful shutdown would
          // wait for the open call).
          unawaited(server.shutdown());
        } else {
          await response.cancel();
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Same sequence as BaseStream._close.
        await requests.close();
        await sub.cancel();
        await response.cancel();
        await channel.shutdown();
        await server
            .shutdown()
            .timeout(const Duration(seconds: 5), onTimeout: () {});
      }, (Object e, StackTrace s) => uncaught.add(e));
      expect(uncaught, isEmpty);
    });
  }
}
