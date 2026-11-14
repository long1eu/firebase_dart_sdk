import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'firestore_from_env.dart';
import 'json_values.dart';

/// The command runner of `firestore_cli`: `import`, `export` and `watch`.
CommandRunner<void> buildRunner() {
  return CommandRunner<void>(
      'firestore_cli',
      'Imports, exports and watches Firestore collections. The backend comes '
          'from the environment: FIRESTORE_EMULATOR_HOST for the emulator, '
          'FIREBASE_PROJECT_ID for a real project (see README.md).',
    )
    ..addCommand(ImportCommand())
    ..addCommand(ExportCommand())
    ..addCommand(WatchCommand());
}

/// A command that needs a Firestore instance; it is created when the command
/// runs (so that `--help` works without any configuration) and terminated
/// when it ends, so that the process can exit.
abstract class FirestoreCommand extends Command<void> {
  FirestoreCommand() {
    argParser
      ..addOption(
        'collection',
        abbr: 'c',
        help:
            'The collection (path), for example "users" or "users/ada/posts". '
            'Required.',
      )
      ..addOption(
        'id-field',
        help: 'The JSON field that holds the document id.',
        defaultsTo: 'id',
      );
  }

  String get collection => argResults!.option('collection')!;

  String get idField => argResults!.option('id-field')!;

  @override
  Future<void> run() async {
    if (argResults!.option('collection') == null) {
      usageException('--collection (-c) is required.');
    }
    final Firestore firestore = firestoreFromEnvironment();
    try {
      await runWith(firestore);
    } finally {
      await firestore.terminate();
    }
  }

  Future<void> runWith(Firestore firestore);
}

/// `import`: writes the objects of a JSON array as documents, in batches.
class ImportCommand extends FirestoreCommand {
  ImportCommand() {
    argParser.addOption(
      'batch-size',
      help:
          'Writes per batch. A batch is committed atomically; 500 is the '
          'limit of a commit.',
      defaultsTo: '500',
    );
  }

  @override
  String get name => 'import';

  @override
  String get description =>
      'Writes the objects of a JSON array file (or - for stdin) as documents. '
      'An object with the --id-field gets that id (the field is not stored), '
      'the others a generated one. Values written by `export` (timestamps, '
      'references, ...) are read back as their types.';

  @override
  String get invocation =>
      '${runner!.executableName} import <file> -c <collection>';

  @override
  Future<void> runWith(Firestore firestore) async {
    final List<String> rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Give one JSON file (or - for stdin).');
    }
    final int? batchSize = int.tryParse(argResults!.option('batch-size')!);
    if (batchSize == null || batchSize < 1 || batchSize > 500) {
      usageException('--batch-size must be between 1 and 500.');
    }
    final String text = rest.single == '-'
        ? await utf8.decodeStream(stdin)
        : await File(rest.single).readAsString();
    final Object? decoded = jsonDecode(text);
    if (decoded is! List<Object?>) {
      usageException('The file must hold a JSON array of objects.');
    }

    final CollectionReference<Map<String, Object?>> target = firestore
        .collection(collection);
    int written = 0;
    for (int start = 0; start < decoded.length; start += batchSize) {
      final int end = start + batchSize < decoded.length
          ? start + batchSize
          : decoded.length;
      final WriteBatch batch = firestore.batch();
      for (int i = start; i < end; i++) {
        final Object? item = decoded[i];
        if (item is! Map<String, Object?>) {
          usageException('Element $i of the array is not an object.');
        }
        final Map<String, Object?> data = Map<String, Object?>.of(item);
        final Object? id = data.remove(idField);
        if (id != null && id is! String) {
          usageException('Element $i: "$idField" must be a string.');
        }
        batch.set(
          id == null ? target.doc() : target.doc(id as String),
          fromJsonValue(firestore, data)! as Map<String, Object?>,
        );
      }
      // Awaited one after the other: if a batch fails, the batches before it
      // are written and the ones after it are not, and the count says how far
      // it got.
      await batch.commit();
      written = end;
      print('committed $written/${decoded.length}');
    }
    print('imported $written documents into $collection');
  }
}

/// The query options shared by `export` and `watch`.
mixin QueryOptions on FirestoreCommand {
  void addQueryOptions() {
    argParser
      ..addMultiOption(
        'where',
        abbr: 'w',
        help:
            'A filter, repeatable: "age>=18", "city==Paris", "tags '
            'array-contains red", "role in [\\"admin\\",\\"owner\\"]". The value '
            'is read as JSON when it is valid JSON, else as a string. '
            'Operators: == != < <= > >= array-contains array-contains-any in '
            'not-in.',
        splitCommas: false,
      )
      ..addOption(
        'order-by',
        help: 'A field to order by; "field:desc" for descending.',
      )
      ..addOption('limit', help: 'The maximum number of documents.');
  }

  Query<Map<String, Object?>> buildQuery(Firestore firestore) {
    Query<Map<String, Object?>> query = firestore.collection(collection);
    for (final String where in argResults!.multiOption('where')) {
      query = query.where(parseFilter(where));
    }
    final String? orderBy = argResults!.option('order-by');
    if (orderBy != null) {
      final bool descending = orderBy.endsWith(':desc');
      query = query.orderBy(
        descending ? orderBy.substring(0, orderBy.length - 5) : orderBy,
        descending ? Direction.descending : Direction.ascending,
      );
    }
    final String? limit = argResults!.option('limit');
    if (limit != null) {
      final int? value = int.tryParse(limit);
      if (value == null || value < 1) {
        usageException('--limit must be a positive number.');
      }
      query = query.limit(value);
    }
    return query;
  }

  static final RegExp _wordOperator = RegExp(
    r'^(\S+)\s+(array-contains-any|array-contains|not-in|in)\s+(.+)$',
  );
  static final RegExp _symbolOperator = RegExp(
    r'^([^=!<>]+?)\s*(==|!=|<=|>=|<|>)\s*(.*)$',
  );

  Filter parseFilter(String text) {
    final RegExpMatch? match =
        _wordOperator.firstMatch(text) ?? _symbolOperator.firstMatch(text);
    if (match == null) {
      usageException('Can not read the filter "$text".');
    }
    final String field = match[1]!;
    final Object? value = _value(match[3]!);
    List<Object?> list() => value is List<Object?>
        ? value
        : usageException('"$text": the value must be a JSON array.');
    return switch (match[2]) {
      '==' => Filter.equalTo(field, value),
      '!=' => Filter.notEqualTo(field, value),
      '<' => Filter.lessThan(field, value),
      '<=' => Filter.lessThanOrEqualTo(field, value),
      '>' => Filter.greaterThan(field, value),
      '>=' => Filter.greaterThanOrEqualTo(field, value),
      'array-contains' => Filter.arrayContains(field, value),
      'array-contains-any' => Filter.arrayContainsAny(field, list()),
      'in' => Filter.inArray(field, list()),
      _ => Filter.notInArray(field, list()),
    };
  }

  static Object? _value(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// A document as one JSON object: the id under [FirestoreCommand.idField],
  /// then its fields.
  Map<String, Object?> documentJson(
    DocumentSnapshot<Map<String, Object?>> document,
  ) => <String, Object?>{
    idField: document.id,
    ...toJsonValue(document.data)! as Map<String, Object?>,
  };
}

/// `export`: runs a query on the backend and writes the documents as a JSON
/// array, in the format `import` reads.
class ExportCommand extends FirestoreCommand with QueryOptions {
  ExportCommand() {
    addQueryOptions();
    argParser.addOption(
      'out',
      abbr: 'o',
      help: 'The file to write (default: stdout).',
    );
  }

  @override
  String get name => 'export';

  @override
  String get description =>
      'Writes the documents of a query as a JSON array, in the format '
      '`import` reads.';

  @override
  Future<void> runWith(Firestore firestore) async {
    // Source.server: an export never comes from a stale cache; without a
    // connection it fails instead.
    final QuerySnapshot<Map<String, Object?>> snapshot = await buildQuery(
      firestore,
    ).get(Source.server);
    final String json = const JsonEncoder.withIndent('  ')
        .convert(<Map<String, Object?>>[
          for (final QueryDocumentSnapshot<Map<String, Object?>> doc
              in snapshot.docs)
            documentJson(doc),
        ]);
    final String? out = argResults!.option('out');
    if (out == null) {
      print(json);
    } else {
      await File(out).writeAsString('$json\n');
      print('exported ${snapshot.docs.length} documents to $out');
    }
  }
}

/// `watch`: listens to a query and prints a line per change until Ctrl-C.
class WatchCommand extends FirestoreCommand with QueryOptions {
  WatchCommand() {
    addQueryOptions();
    argParser.addOption(
      'exit-after',
      help: 'Stop after this many changes (for scripts and tests).',
    );
  }

  @override
  String get name => 'watch';

  @override
  String get description =>
      'Prints the documents of a query, then a line per change: "added", '
      '"modified" or "removed", the id and the fields as JSON. Runs until '
      'Ctrl-C.';

  @override
  Future<void> runWith(Firestore firestore) async {
    final String? exitAfterText = argResults!.option('exit-after');
    final int? exitAfter = exitAfterText == null
        ? null
        : int.tryParse(exitAfterText);
    if (exitAfterText != null && (exitAfter == null || exitAfter < 1)) {
      usageException('--exit-after must be a positive number.');
    }

    final Completer<void> done = Completer<void>();
    void finish([Object? error]) {
      if (!done.isCompleted) {
        error == null ? done.complete() : done.completeError(error);
      }
    }

    int changes = 0;
    final StreamSubscription<QuerySnapshot<Map<String, Object?>>> listener =
        buildQuery(firestore).snapshots.listen((
          QuerySnapshot<Map<String, Object?>> snapshot,
        ) {
          for (final DocumentChange<Map<String, Object?>> change
              in snapshot.docChanges) {
            print(
              '${change.type.name} ${change.document.id} '
              '${jsonEncode(toJsonValue(change.document.data))}',
            );
            changes++;
            if (exitAfter != null && changes >= exitAfter) {
              finish();
              return;
            }
          }
        }, onError: finish);
    final StreamSubscription<ProcessSignal> interrupt = ProcessSignal.sigint
        .watch()
        .listen((_) => finish());
    try {
      await done.future;
    } finally {
      await interrupt.cancel();
      await listener.cancel();
    }
  }
}
