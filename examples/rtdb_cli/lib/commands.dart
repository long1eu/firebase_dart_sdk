// The commands of rtdb_cli. Each one opens a FirebaseDatabase from the global
// flags and the environment, runs, and closes it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:rtdb_cli/parsing.dart';

/// The runner with every command. Results go to [out]; [environment] stands in
/// for the process environment (for tests).
CommandRunner<void> buildRunner({
  required IOSink out,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final CommandRunner<void> runner = CommandRunner<void>(
    'rtdb_cli',
    'Reads and writes the Firebase Realtime Database. Needs --emulator or an '
        'explicit --database-url.',
  );
  runner.argParser
    ..addOption(
      'emulator',
      help:
          'host:port of the Database emulator '
          '(FIREBASE_DATABASE_EMULATOR_HOST).',
    )
    ..addOption('project', help: 'Project id; demo-example with an emulator.')
    ..addOption(
      'database-url',
      help: 'URL of a real database; required without an emulator.',
    )
    ..addOption('api-key', help: 'Web API key (FIREBASE_API_KEY).');
  for (final _DbCommand command in <_DbCommand>[
    GetCommand(out, env),
    SetCommand(out, env),
    UpdateCommand(out, env),
    PushCommand(out, env),
    RemoveCommand(out, env),
    WatchCommand(out, env),
    ExportCommand(out, env),
    ImportCommand(out, env),
  ]) {
    runner.addCommand(command);
  }
  return runner;
}

void _addQueryFlags(ArgParser parser) {
  parser
    ..addOption('order-by-child', help: 'Order by this child path.')
    ..addFlag('order-by-key', negatable: false, help: 'Order by key.')
    ..addFlag('order-by-value', negatable: false, help: 'Order by value.')
    ..addOption('limit-to-first', help: 'Keep the first N children.')
    ..addOption('limit-to-last', help: 'Keep the last N children.')
    ..addOption('start-at', help: 'Lower bound (JSON, or a plain string).')
    ..addOption('end-at', help: 'Upper bound (JSON, or a plain string).')
    ..addOption('equal-to', help: 'Exact match (JSON, or a plain string).');
}

QuerySpec _querySpec(ArgResults r) => parseQuerySpec(
  orderByChild: r['order-by-child'] as String?,
  orderByKey: r['order-by-key'] as bool,
  orderByValue: r['order-by-value'] as bool,
  limitToFirst: r['limit-to-first'] as String?,
  limitToLast: r['limit-to-last'] as String?,
  startAt: r['start-at'] as String?,
  endAt: r['end-at'] as String?,
  equalTo: r['equal-to'] as String?,
);

Query _applyQuery(DatabaseReference ref, QuerySpec spec) {
  Query q = ref;
  switch (spec.orderBy) {
    case OrderBy.key:
      q = q.orderByKey();
    case OrderBy.value:
      q = q.orderByValue();
    case OrderBy.child:
      q = q.orderByChild(spec.orderByChild!);
    case null:
      break;
  }
  if (spec.hasStartAt) {
    q = q.startAt(spec.startAt);
  }
  if (spec.hasEndAt) {
    q = q.endAt(spec.endAt);
  }
  if (spec.hasEqualTo) {
    q = q.equalTo(spec.equalTo);
  }
  if (spec.limitToFirst != null) {
    q = q.limitToFirst(spec.limitToFirst!);
  }
  if (spec.limitToLast != null) {
    q = q.limitToLast(spec.limitToLast!);
  }
  return q;
}

abstract class _DbCommand extends Command<void> {
  _DbCommand(this.out, this.env);

  final IOSink out;
  final Map<String, String> env;

  /// The positional arguments, between [min] and [max] of them.
  List<String> positionals(int min, int max) {
    final List<String> rest = argResults!.rest;
    if (rest.length < min || rest.length > max) {
      usageException('Usage: rtdb_cli $invocation');
    }
    return rest;
  }

  Future<void> withDatabase(
    Future<void> Function(FirebaseDatabase db) body,
  ) async {
    final ArgResults global = globalResults!;
    final DatabaseTarget target = resolveTarget(
      emulator: global['emulator'] as String?,
      databaseUrl: global['database-url'] as String?,
      project: global['project'] as String?,
      environment: env,
    );
    final String? apiKey =
        (global['api-key'] as String?) ?? env['FIREBASE_API_KEY'];
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: apiKey ?? (target.emulatorHost != null ? 'fake-api-key' : ''),
        // Any non-empty id works outside of Android and iOS.
        appId: '1:1234567890:dart:example',
        projectId: target.projectId,
      ),
      name: 'rtdb_cli',
    );
    final FirebaseDatabase db = FirebaseDatabase(
      app,
      emulatorHost: target.emulatorHost,
      databaseUrl: target.databaseUrl,
    );
    try {
      await body(db);
    } finally {
      await db.close();
    }
  }
}

class GetCommand extends _DbCommand {
  GetCommand(super.out, super.env) {
    _addQueryFlags(argParser);
  }

  @override
  final String name = 'get';
  @override
  final String description = 'Prints the value at a path as JSON.';
  @override
  final String invocation = 'get <path> [query flags]';

  @override
  Future<void> run() async {
    final String path = normalizePath(positionals(1, 1).single);
    final QuerySpec spec = _querySpec(argResults!);
    await withDatabase((FirebaseDatabase db) async {
      final DataSnapshot snapshot = await _applyQuery(db.ref(path), spec).get();
      out.writeln(encodeJson(snapshot.value));
    });
  }
}

class SetCommand extends _DbCommand {
  SetCommand(super.out, super.env);

  @override
  final String name = 'set';
  @override
  final String description = 'Replaces the value at a path with a JSON value.';
  @override
  final String invocation = 'set <path> <json>';

  @override
  Future<void> run() async {
    final List<String> args = positionals(2, 2);
    final String path = normalizePath(args[0]);
    final Object? value = parseJsonValue(args[1]);
    await withDatabase((FirebaseDatabase db) => db.ref(path).set(value));
  }
}

class UpdateCommand extends _DbCommand {
  UpdateCommand(super.out, super.env);

  @override
  final String name = 'update';
  @override
  final String description = 'Merges the keys of a JSON object into a path.';
  @override
  final String invocation = 'update <path> <json-object>';

  @override
  Future<void> run() async {
    final List<String> args = positionals(2, 2);
    final String path = normalizePath(args[0]);
    final Map<String, Object?> values = parseJsonObject(args[1]);
    await withDatabase((FirebaseDatabase db) => db.ref(path).update(values));
  }
}

class PushCommand extends _DbCommand {
  PushCommand(super.out, super.env);

  @override
  final String name = 'push';
  @override
  final String description =
      'Writes a JSON value under a new child key and prints the key.';
  @override
  final String invocation = 'push <path> <json>';

  @override
  Future<void> run() async {
    final List<String> args = positionals(2, 2);
    final String path = normalizePath(args[0]);
    final Object? value = parseJsonValue(args[1]);
    await withDatabase((FirebaseDatabase db) async {
      final DatabaseReference child = db.ref(path).push();
      await child.set(value);
      out.writeln(child.key);
    });
  }
}

class RemoveCommand extends _DbCommand {
  RemoveCommand(super.out, super.env);

  @override
  final String name = 'remove';
  @override
  final String description = 'Deletes the data at a path.';
  @override
  final String invocation = 'remove <path>';

  @override
  Future<void> run() async {
    final String path = normalizePath(positionals(1, 1).single);
    await withDatabase((FirebaseDatabase db) => db.ref(path).remove());
  }
}

class WatchCommand extends _DbCommand {
  WatchCommand(super.out, super.env) {
    _addQueryFlags(argParser);
  }

  @override
  final String name = 'watch';
  @override
  final String description =
      'Prints the value at a path now and after each change, until Ctrl-C.';
  @override
  final String invocation = 'watch <path> [query flags]';

  @override
  Future<void> run() async {
    final String path = normalizePath(positionals(1, 1).single);
    final QuerySpec spec = _querySpec(argResults!);
    await withDatabase((FirebaseDatabase db) async {
      final Completer<void> stop = Completer<void>();
      final StreamSubscription<ProcessSignal> sigint = ProcessSignal.sigint
          .watch()
          .listen((_) {
            if (!stop.isCompleted) {
              stop.complete();
            }
          });
      final StreamSubscription<DatabaseEvent> events =
          _applyQuery(db.ref(path), spec).onValue.listen(
            (DatabaseEvent event) =>
                out.writeln(encodeJson(event.snapshot.value, compact: true)),
            onError: (Object error, StackTrace stackTrace) {
              if (!stop.isCompleted) {
                stop.completeError(error, stackTrace);
              }
            },
          );
      try {
        await stop.future;
      } finally {
        await events.cancel();
        await sigint.cancel();
      }
    });
  }
}

class ExportCommand extends _DbCommand {
  ExportCommand(super.out, super.env);

  @override
  final String name = 'export';
  @override
  final String description =
      'Writes the JSON at a path to a file, or to standard output.';
  @override
  final String invocation = 'export <path> [file]';

  @override
  Future<void> run() async {
    final List<String> args = positionals(1, 2);
    final String path = normalizePath(args[0]);
    await withDatabase((FirebaseDatabase db) async {
      final DataSnapshot snapshot = await db.ref(path).get();
      final String json = encodeJson(snapshot.value);
      if (args.length == 2) {
        await File(args[1]).writeAsString('$json\n');
      } else {
        out.writeln(json);
      }
    });
  }
}

class ImportCommand extends _DbCommand {
  ImportCommand(super.out, super.env);

  @override
  final String name = 'import';
  @override
  final String description =
      'Replaces the data at a path with the JSON of a file (- for stdin).';
  @override
  final String invocation = 'import <path> <file>';

  @override
  Future<void> run() async {
    final List<String> args = positionals(2, 2);
    final String path = normalizePath(args[0]);
    final String text = args[1] == '-'
        ? await utf8.decodeStream(stdin)
        : await File(args[1]).readAsString();
    final Object? value = parseJson(text, what: 'file ${args[1]}');
    await withDatabase((FirebaseDatabase db) => db.ref(path).set(value));
  }
}
