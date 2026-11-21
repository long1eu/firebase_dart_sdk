// The commands of storage_cli. Each one opens a FirebaseStorage from the
// global flags and the environment, runs, and closes it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';
import 'package:storage_cli/storage_from_env.dart';

/// The runner with every command. Results go to [out], progress and notes to
/// [err]; [environment] stands in for the process environment (for tests).
CommandRunner<void> buildRunner({
  required IOSink out,
  required IOSink err,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final CommandRunner<void> runner = CommandRunner<void>(
    'storage_cli',
    'Lists, uploads, downloads and deletes Cloud Storage for Firebase objects.',
  );
  runner.argParser
    ..addOption(
      'project',
      help: 'Project id (FIREBASE_PROJECT_ID); demo-example with an emulator.',
      defaultsTo: firstEnvironment(<String>['FIREBASE_PROJECT_ID'], env),
    )
    ..addOption(
      'bucket',
      help: 'Bucket (STORAGE_BUCKET); <project>.appspot.com when not given.',
      defaultsTo: firstEnvironment(<String>['STORAGE_BUCKET'], env),
    )
    ..addOption(
      'emulator-host',
      help:
          'host:port of the Storage emulator (FIREBASE_STORAGE_EMULATOR_HOST).',
      defaultsTo: firstEnvironment(<String>[
        'FIREBASE_STORAGE_EMULATOR_HOST',
      ], env),
    )
    ..addOption(
      'auth-emulator-host',
      help: 'host:port of the Auth emulator (FIREBASE_AUTH_EMULATOR_HOST).',
      defaultsTo: firstEnvironment(<String>[
        'FIREBASE_AUTH_EMULATOR_HOST',
      ], env),
    )
    ..addOption(
      'api-key',
      help: 'Web API key, to sign in to a real project (FIREBASE_API_KEY).',
      defaultsTo: firstEnvironment(<String>['FIREBASE_API_KEY'], env),
    )
    ..addOption(
      'email',
      help: 'Sign in with this email first (STORAGE_EMAIL).',
      defaultsTo: firstEnvironment(<String>['STORAGE_EMAIL'], env),
    )
    ..addOption(
      'password',
      help: 'Password for --email (STORAGE_PASSWORD).',
      defaultsTo: firstEnvironment(<String>['STORAGE_PASSWORD'], env),
    )
    ..addFlag(
      'create-account',
      negatable: false,
      help: 'Create the --email user first (Auth emulator).',
    );
  for (final _StorageCommand command in <_StorageCommand>[
    ListCommand(out),
    PutCommand(out, err),
    GetCommand(out),
    CatCommand(out),
    StatCommand(out),
    RemoveCommand(out),
    UrlCommand(out),
  ]) {
    runner.addCommand(command);
  }
  return runner;
}

abstract class _StorageCommand extends Command<void> {
  _StorageCommand(this.out);

  final IOSink out;

  /// Runs the command; [arguments] are its positional arguments.
  Future<void> execute(FirebaseStorage storage, List<String> arguments);

  /// How many positional arguments the command takes.
  int get arity;

  String get usageArguments;

  @override
  String get invocation => '${runner!.executableName} $name $usageArguments';

  @override
  Future<void> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length != arity) {
      usageException('Expected: $usageArguments');
    }
    final ArgResults global = globalResults!;
    final StorageSession session = await openStorage(
      StorageConfig(
        projectId: global.option('project'),
        bucket: global.option('bucket'),
        emulatorHost: global.option('emulator-host'),
        authEmulatorHost: global.option('auth-emulator-host'),
        apiKey: global.option('api-key'),
        email: global.option('email'),
        password: global.option('password'),
        createAccount: global.flag('create-account'),
      ),
    );
    try {
      await execute(session.storage, rest);
    } finally {
      await session.close();
    }
  }
}

/// `ls [path]`: the prefixes (with a trailing `/`) and objects under a path,
/// one per line, a page at a time.
class ListCommand extends _StorageCommand {
  ListCommand(super.out) {
    argParser.addOption(
      'page-size',
      help: 'Entries per request (1 to 1000).',
      defaultsTo: '100',
    );
  }

  @override
  String get name => 'ls';

  @override
  String get description => 'Lists the prefixes and objects under a path.';

  @override
  int get arity => argResults!.rest.isEmpty ? 0 : 1;

  @override
  String get usageArguments => '[path]';

  @override
  Future<void> execute(FirebaseStorage storage, List<String> arguments) async {
    final int? pageSize = int.tryParse(argResults!.option('page-size')!);
    if (pageSize == null || pageSize < 1 || pageSize > 1000) {
      usageException('--page-size is a number from 1 to 1000.');
    }
    final Reference ref = storage.ref(arguments.isEmpty ? '' : arguments[0]);
    await for (final ListResult page in ref.listPages(pageSize: pageSize)) {
      for (final Reference prefix in page.prefixes) {
        out.writeln('${prefix.fullPath}/');
      }
      for (final Reference item in page.items) {
        out.writeln(item.fullPath);
      }
    }
  }
}

/// `put <file> <path>`: a resumable upload streamed from disk, with a
/// progress line on stderr.
class PutCommand extends _StorageCommand {
  PutCommand(super.out, this.err) {
    argParser
      ..addOption('content-type', help: 'Content type of the object.')
      ..addMultiOption(
        'meta',
        help: 'Custom metadata, key=value (repeatable).',
        valueHelp: 'key=value',
      );
  }

  final IOSink err;

  @override
  String get name => 'put';

  @override
  String get description => 'Uploads a file with a resumable upload.';

  @override
  int get arity => 2;

  @override
  String get usageArguments => '<file> <path>';

  @override
  Future<void> execute(FirebaseStorage storage, List<String> arguments) async {
    final File file = File(arguments[0]);
    if (!file.existsSync()) {
      throw FileSystemException('No such file', file.path);
    }
    final Map<String, String> custom = <String, String>{};
    for (final String pair in argResults!.multiOption('meta')) {
      final int eq = pair.indexOf('=');
      if (eq < 1) {
        usageException('--meta takes key=value, not "$pair".');
      }
      custom[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    final UploadTask task = storage
        .ref(arguments[1])
        .putFile(
          file,
          metadata: SettableMetadata(
            contentType: argResults!.option('content-type'),
            customMetadata: custom.isEmpty ? null : custom,
          ),
        );
    final bool tty = err is Stdout && (err as Stdout).hasTerminal;
    final StreamSubscription<UploadProgress> progress = task.progress.listen((
      UploadProgress p,
    ) {
      if (tty) {
        err.write('\r${_progressLine(p.bytesTransferred, p.totalBytes)}');
      }
    });
    final FullMetadata metadata;
    try {
      metadata = await task.result;
    } finally {
      await progress.cancel();
    }
    err.writeln(
      '${tty ? '\r' : ''}${_progressLine(task.bytesTransferred, task.totalBytes)}',
    );
    out.writeln(metadata.fullPath);
  }

  static String _progressLine(int done, int total) {
    final int percent = total == 0 ? 100 : done * 100 ~/ total;
    return 'uploaded $done of $total bytes ($percent%)';
  }
}

/// `get <path> <file>`: a download streamed to a file.
class GetCommand extends _StorageCommand {
  GetCommand(super.out);

  @override
  String get name => 'get';

  @override
  String get description => 'Downloads an object to a file.';

  @override
  int get arity => 2;

  @override
  String get usageArguments => '<path> <file>';

  @override
  Future<void> execute(FirebaseStorage storage, List<String> arguments) async {
    final int bytes = await storage
        .ref(arguments[0])
        .writeToFile(File(arguments[1]));
    out.writeln('${arguments[1]}: $bytes bytes');
  }
}

/// `cat <path>`: the bytes of an object on stdout.
class CatCommand extends _StorageCommand {
  CatCommand(super.out);

  @override
  String get name => 'cat';

  @override
  String get description => 'Writes an object to standard output.';

  @override
  int get arity => 1;

  @override
  String get usageArguments => '<path>';

  @override
  Future<void> execute(FirebaseStorage storage, List<String> arguments) =>
      out.addStream(storage.ref(arguments[0]).openRead());
}

/// `stat <path>`: the metadata of an object as JSON.
class StatCommand extends _StorageCommand {
  StatCommand(super.out);

  @override
  String get name => 'stat';

  @override
  String get description => 'Prints the metadata of an object as JSON.';

  @override
  int get arity => 1;

  @override
  String get usageArguments => '<path>';

  @override
  Future<void> execute(FirebaseStorage storage, List<String> arguments) async {
    final FullMetadata metadata = await storage.ref(arguments[0]).metadata();
    out.writeln(const JsonEncoder.withIndent('  ').convert(metadata.toJson()));
  }
}

/// `rm <path>`: deletes an object.
class RemoveCommand extends _StorageCommand {
  RemoveCommand(super.out);

  @override
  String get name => 'rm';

  @override
  String get description => 'Deletes an object.';

  @override
  int get arity => 1;

  @override
  String get usageArguments => '<path>';

  @override
  Future<void> execute(FirebaseStorage storage, List<String> arguments) async {
    await storage.ref(arguments[0]).delete();
    out.writeln('deleted ${arguments[0]}');
  }
}

/// `url <path>`: the download URL of an object.
class UrlCommand extends _StorageCommand {
  UrlCommand(super.out);

  @override
  String get name => 'url';

  @override
  String get description => 'Prints the download URL of an object.';

  @override
  int get arity => 1;

  @override
  String get usageArguments => '<path>';

  @override
  Future<void> execute(FirebaseStorage storage, List<String> arguments) async {
    out.writeln(await storage.ref(arguments[0]).downloadUrl());
  }
}
