// A client in a process of its own, for sqlite_shared_processes_test.dart.
//
// Usage: dart run <this file> <database name> <writer>
//
// Opens the cache (DatabaseMock.pathForName, relative to the working directory), prints `ready`, then for every line
// `round <i>` read from stdin allocates a target of its own and a shared one, writes a batch and prints
// `done <i> <target id> <batch id> <sequence number>`. On `close` it shuts the persistence down and prints `closed`.
// Every line it prints starts with `writer: `, so that the logs of the client (also on stdout) can be told apart.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';

import 'sqlite_shared_clients_test.dart' as shared;

void say(String line) => stdout.writeln('writer: $line');

Future<void> main(List<String> args) async {
  final String name = args[0];
  final int writer = int.parse(args[1]);
  final shared.Client client = await shared.Client.open(name);
  say('ready');

  await for (final String line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final List<String> parts = line.split(' ');
    if (parts.first == 'close') {
      await client.persistence.shutdown();
      say('closed');
      break;
    }
    final int round = int.parse(parts[1]);
    final QueryData own = await client.listen('process$writer-$round');
    await client.listen('shared-$round');
    final int batchId = await client.write('writes/process$writer-$round');
    say('done $round ${own.targetId} $batchId ${own.sequenceNumber}');
  }
  await stdout.flush();
  exit(0);
}
