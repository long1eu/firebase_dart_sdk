// Runs the task API in this process against the Firestore emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
//
// Skipped without FIRESTORE_EMULATOR_HOST.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_shelf/firestore_from_env.dart';
import 'package:server_shelf/task_api.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];

  group(
    'task API',
    () {
      late TaskApi api;
      late HttpServer server;
      late HttpClient client;

      setUp(() async {
        api = TaskApi(
          firestoreFromEnvironment(
            appName: 'server-test-${DateTime.now().microsecondsSinceEpoch}',
          ),
          'server-test-${DateTime.now().microsecondsSinceEpoch}',
        );
        await api.ready;
        server = await shelf_io.serve(
          api.handler,
          InternetAddress.loopbackIPv4,
          0,
        );
        client = HttpClient();
      });

      tearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await api.close();
      });

      Future<(int, Object?)> send(
        String method,
        String path, [
        Object? body,
      ]) async {
        final HttpClientRequest request = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        if (body != null) {
          request.write(jsonEncode(body));
        }
        final HttpClientResponse response = await request.close();
        final String text = await utf8.decodeStream(response);
        return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
      }

      test('creates, reads, lists, updates and deletes tasks', () async {
        final (int created, Object? body) = await send(
          'POST',
          '/tasks',
          <String, Object?>{'title': 'Write the docs'},
        );
        expect(created, 201);
        final String id = (body! as Map<String, Object?>)['id']! as String;

        final (int status, Object? task) = await send('GET', '/tasks/$id');
        expect(status, 200);
        expect(task, containsPair('title', 'Write the docs'));
        expect(task, containsPair('done', false));
        expect((task! as Map<String, Object?>)['createdAt'], isA<String>());

        expect(
          (await send('PATCH', '/tasks/$id', <String, Object?>{
            'done': true,
          })).$1,
          200,
        );
        final (_, Object? open) = await send('GET', '/tasks?done=false');
        expect(open, isEmpty);
        final (_, Object? all) = await send('GET', '/tasks');
        expect(all, hasLength(1));

        expect((await send('DELETE', '/tasks/$id')).$1, 204);
        expect((await send('GET', '/tasks/$id')).$1, 404);
      });

      test('answers bad requests and missing tasks with 400 and 404', () async {
        expect((await send('POST', '/tasks', <String, Object?>{})).$1, 400);
        expect(
          (await send('PATCH', '/tasks/missing', <String, Object?>{
            'done': 1,
          })).$1,
          400,
        );
        expect(
          (await send('PATCH', '/tasks/missing', <String, Object?>{
            'done': true,
          })).$1,
          404,
        );
      });

      test(
        'sends the changes to every subscriber as server-sent events',
        () async {
          final List<StreamIterator<String>> subscribers =
              <StreamIterator<String>>[];
          for (int i = 0; i < 2; i++) {
            final HttpClientRequest request = await client.getUrl(
              Uri.http('127.0.0.1:${server.port}', '/events'),
            );
            final HttpClientResponse response = await request.close();
            expect(response.headers.contentType?.mimeType, 'text/event-stream');
            subscribers.add(
              StreamIterator<String>(
                response
                    .transform(utf8.decoder)
                    .transform(const LineSplitter()),
              ),
            );
          }

          /// The next event of [events] whose name is [name], with its data.
          Future<Map<String, Object?>> next(
            StreamIterator<String> events,
            String name,
          ) async {
            String? current;
            while (await events.moveNext().timeout(
              const Duration(seconds: 20),
            )) {
              final String line = events.current;
              if (line.startsWith('event: ')) {
                current = line.substring('event: '.length);
              } else if (line.startsWith('data: ') && current == name) {
                return jsonDecode(line.substring('data: '.length))
                    as Map<String, Object?>;
              }
            }
            throw StateError('The event stream ended before a $name event.');
          }

          for (final StreamIterator<String> events in subscribers) {
            expect(await next(events, 'snapshot'), <String, Object?>{
              'documents': <Object?>[],
            });
          }
          expect(api.subscribers, 2);

          final (_, Object? body) = await send(
            'POST',
            '/tasks',
            <String, Object?>{'title': 'Ship it'},
          );
          final String id = (body! as Map<String, Object?>)['id']! as String;
          await send('PATCH', '/tasks/$id', <String, Object?>{'done': true});
          await send('DELETE', '/tasks/$id');

          for (final StreamIterator<String> events in subscribers) {
            expect(await next(events, 'added'), containsPair('id', id));
            Map<String, Object?> modified;
            do {
              modified = await next(events, 'modified');
            } while (modified['done'] != true);
            expect(await next(events, 'removed'), containsPair('id', id));
          }

          for (final StreamIterator<String> events in subscribers) {
            await events.cancel();
          }
        },
      );
    },
    skip: emulator == null || emulator.isEmpty
        ? 'Set FIRESTORE_EMULATOR_HOST to run these tests against the emulator.'
        : false,
  );
}
