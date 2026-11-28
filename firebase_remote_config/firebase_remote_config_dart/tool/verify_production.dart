// The production verification kit of firebase_installations_dart and firebase_remote_config_dart: a command line
// program that runs the clients against a real Firebase project and reports what the unit tests cannot know.
//
//     dart run tool/verify_production.dart --yes --project-id=my-project --app-id=1:123:web:abc --api-key=...
//
// See tool/verify_production_remote_config/README.md (repository root) for what it needs and how to read its
// report.
//
// It runs seven checks in order: create an installation, force a token refresh, fetch, activate and read, a second
// fetch that must answer NO_CHANGE, a realtime invalidation, delete the installation. It prints PASS, FAIL,
// INCONCLUSIVE or SKIPPED for each. It stores its installation in a private temporary directory, never prints the
// API key, a token or the installation id, and deletes the installation it created when it ends, also after a
// failure and on Ctrl-C.

// ignore_for_file: avoid_print, public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

/// The parameter the project's template must hold; the README tells the operator to publish it first.
const String probeKey = 'rc_probe_flag';

/// The outcome of a check.
enum Status {
  /// The behaviour was observed and is what the clients rely on.
  pass('PASS'),

  /// A client misbehaved, or the backend did something the client does not handle.
  fail('FAIL'),

  /// The check could not come to a result; the line says what to do.
  inconclusive('INCONCLUSIVE'),

  /// The check was not run: it was switched off, or an earlier check it needs did not pass.
  skipped('SKIPPED');

  const Status(this.label);

  final String label;
}

/// The result of one check: a status and a line of explanation.
class CheckResult {
  const CheckResult(this.status, this.summary);

  final Status status;
  final String summary;
}

/// Thrown into a running check when the operator presses Ctrl-C.
class _Interrupted implements Exception {
  const _Interrupted();
}

/// What the checks share: the clients, and the facts one check hands to the next.
class _Kit {
  _Kit({
    required this.options,
    required this.realtimeWindow,
    required this.skipRealtime,
  });

  final FirebaseOptions options;
  final Duration realtimeWindow;
  final bool skipRealtime;

  Directory? directory;
  FirebaseApp? app;
  FileKeyValueStore? store;
  FirebaseInstallations? installations;
  FirebaseRemoteConfig? config;

  bool registered = false;
  bool deleted = false;
  int? firstFetchVersion;
  final Completer<void> interrupted = Completer<void>();

  /// Runs [action], and throws [_Interrupted] instead if Ctrl-C is pressed first.
  Future<T> guard<T>(Future<T> action) {
    return Future.any<T>(<Future<T>>[
      action,
      interrupted.future.then((_) => throw const _Interrupted()),
    ]);
  }
}

Future<void> main(List<String> arguments) async {
  final ArgParser parser = _parser();
  final ArgResults flags;
  try {
    flags = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n${parser.usage}');
    exitCode = 64;
    return;
  }
  if (flags['help'] as bool) {
    print(
      'Usage: dart run tool/verify_production.dart --yes [options]\n\n${parser.usage}',
    );
    return;
  }
  final _Kit? kit = _configure(flags);
  if (kit == null) {
    return;
  }
  if (!(flags['yes'] as bool)) {
    _printPlan(kit);
    stderr.writeln(
      '\nNothing was done. Run it again with --yes to run the checks.',
    );
    exitCode = 2;
    return;
  }
  exitCode = await _run(kit);
}

ArgParser _parser() {
  return ArgParser()
    ..addOption(
      'project-id',
      help: 'The project id (or FIREBASE_TEST_PROJECT_ID).',
    )
    ..addOption(
      'app-id',
      help:
          'The app id, 1:<project number>:<platform>:<hash> (or FIREBASE_TEST_APP_ID).',
    )
    ..addOption(
      'api-key',
      help: 'The API key of the app (or FIREBASE_API_KEY).',
    )
    ..addOption(
      'realtime-window',
      defaultsTo: '300',
      help: 'Seconds to wait for a realtime update while you publish a change.',
    )
    ..addFlag(
      'skip-realtime',
      negatable: false,
      help: 'Do not run the realtime check (it is SKIPPED).',
    )
    ..addFlag(
      'yes',
      negatable: false,
      help: 'Confirm that the kit may use the project.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');
}

/// The kit for [flags], or null (after printing the problem and setting the exit code to 2).
_Kit? _configure(ArgResults flags) {
  String? value(String option, String variable) {
    final String text =
        (flags[option] as String?) ?? Platform.environment[variable] ?? '';
    return text.isEmpty ? null : text;
  }

  final String? projectId = value('project-id', 'FIREBASE_TEST_PROJECT_ID');
  final String? appId = value('app-id', 'FIREBASE_TEST_APP_ID');
  final String? apiKey = value('api-key', 'FIREBASE_API_KEY');
  final int? window = int.tryParse(flags['realtime-window'] as String);
  final List<String> missing = <String>[
    if (projectId == null) '--project-id (FIREBASE_TEST_PROJECT_ID)',
    if (appId == null) '--app-id (FIREBASE_TEST_APP_ID)',
    if (apiKey == null) '--api-key (FIREBASE_API_KEY)',
  ];
  if (missing.isNotEmpty || window == null || window < 1 || window > 3600) {
    stderr.writeln(
      missing.isNotEmpty
          ? 'Missing: ${missing.join(', ')}'
          : '--realtime-window must be a whole number of seconds from 1 to 3600',
    );
    exitCode = 2;
    return null;
  }
  return _Kit(
    options: FirebaseOptions(
      apiKey: apiKey!,
      appId: appId!,
      projectId: projectId,
    ),
    realtimeWindow: Duration(seconds: window),
    skipRealtime: flags['skip-realtime'] as bool,
  );
}

void _printPlan(_Kit kit) {
  print('Remote Config production verification kit');
  print('  project id:  ${kit.options.projectId}');
  print('  app id:      ${kit.options.appId}');
  print('  API key:     given (never printed)');
  print(
    '  it will:     register one installation, fetch the template, and delete the installation at the end',
  );
  print(
    '  realtime:    ${kit.skipRealtime ? 'skipped' : 'waits up to ${kit.realtimeWindow.inSeconds} s for you to publish'}',
  );
}

Future<int> _run(_Kit kit) async {
  _printPlan(kit);
  final StreamSubscription<ProcessSignal> sigint = ProcessSignal.sigint
      .watch()
      .listen((_) {
        if (!kit.interrupted.isCompleted) {
          print('\nInterrupted: cleaning up.');
          kit.interrupted.complete();
        }
      });
  final List<(String, CheckResult)> results = <(String, CheckResult)>[];
  bool interrupted = false;
  try {
    await _setUp(kit);
    for (final (String, Future<CheckResult> Function(_Kit)) check in _checks) {
      final CheckResult result = await _runOne(kit, check.$2);
      results.add((check.$1, result));
      print(
        '${results.length}. ${result.status.label.padRight(12)} ${check.$1}: ${result.summary}',
      );
    }
  } on _Interrupted {
    interrupted = true;
  } on Object catch (error) {
    stderr.writeln('The kit stopped: ${_describe(error)}');
    results.add(('kit', CheckResult(Status.fail, _describe(error))));
  } finally {
    await _cleanUp(kit);
    await sigint.cancel();
  }
  if (interrupted) {
    return 130;
  }
  return results.any(((String, CheckResult) r) => r.$2.status == Status.fail)
      ? 1
      : 0;
}

Future<CheckResult> _runOne(
  _Kit kit,
  Future<CheckResult> Function(_Kit) check,
) async {
  try {
    return await kit.guard(check(kit).timeout(const Duration(minutes: 10)));
  } on _Interrupted {
    rethrow;
  } on FirebaseInstallationsException catch (error) {
    return CheckResult(
      Status.fail,
      'installations error ${error.code} (status ${error.httpStatus})',
    );
  } on FirebaseRemoteConfigException catch (error) {
    return CheckResult(
      Status.fail,
      'remote config error ${error.code} (status ${error.httpStatus}, ${error.serverStatus})',
    );
  } on TimeoutException {
    return const CheckResult(Status.fail, 'timed out');
  }
}

/// The text of [error] that is safe to print: the code of a Firebase exception, else its type.
String _describe(Object error) {
  if (error is FirebaseInstallationsException) {
    return error.code;
  }
  if (error is FirebaseRemoteConfigException) {
    return error.code;
  }
  return error.runtimeType.toString();
}

Future<void> _setUp(_Kit kit) async {
  final Directory directory = Directory.systemTemp.createTempSync('rc_kit_');
  kit.directory = directory;
  final FirebaseApp app = FirebaseApp.withOptions(kit.options, name: 'rc-kit');
  final FileKeyValueStore store = FileKeyValueStore(directory.path);
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: store,
  );
  kit
    ..app = app
    ..store = store
    ..installations = installations
    ..config = FirebaseRemoteConfig(app, installations: installations);
}

/// Deletes the installation if one is registered and not deleted yet, then closes everything and removes the
/// temporary directory. It never throws: a failure is printed with what to remove by hand.
Future<void> _cleanUp(_Kit kit) async {
  final FirebaseInstallations? installations = kit.installations;
  if (installations != null && kit.registered && !kit.deleted) {
    try {
      await installations.delete().timeout(const Duration(seconds: 30));
      kit.deleted = true;
    } on Object catch (error) {
      print(
        'Clean-up failed: the installation was not deleted (${_describe(error)}). '
        'Delete it in the Firebase console or leave it: unused installations expire.',
      );
    }
  }
  try {
    await kit.config?.close();
    await installations?.close();
    await kit.store?.close();
    await kit.app?.delete();
    kit.directory?.deleteSync(recursive: true);
  } on Object catch (error) {
    print(
      'Clean-up of local files failed (${_describe(error)}): remove ${kit.directory?.path} by hand.',
    );
  }
}

final List<(String, Future<CheckResult> Function(_Kit))> _checks =
    <(String, Future<CheckResult> Function(_Kit))>[
      ('create installation', _createInstallation),
      ('forced token refresh', _forcedRefresh),
      ('fetch', _fetch),
      ('activate and read', _activateAndRead),
      ('NO_CHANGE with the stored ETag', _noChange),
      ('realtime invalidation', _realtime),
      ('delete installation', _deleteInstallation),
    ];

CheckResult _skipped(String why) => CheckResult(Status.skipped, why);

Future<CheckResult> _createInstallation(_Kit kit) async {
  final FirebaseInstallations installations = kit.installations!;
  final ({String id, String token}) pair = await installations.getIdAndToken();
  kit.registered = true;
  if (pair.id.length != 22 || pair.token.isEmpty) {
    return const CheckResult(
      Status.fail,
      'the server accepted the installation but the id or token is malformed',
    );
  }
  return const CheckResult(
    Status.pass,
    'registered; got a 22-character id and an auth token',
  );
}

Future<CheckResult> _forcedRefresh(_Kit kit) async {
  if (!kit.registered) {
    return _skipped('no installation');
  }
  final FirebaseInstallations installations = kit.installations!;
  final String before = await installations.getId();
  final ({String id, String token}) pair = await installations.getIdAndToken(
    forceRefresh: true,
  );
  if (pair.token.isEmpty) {
    return const CheckResult(Status.fail, 'the refreshed token is empty');
  }
  if (pair.id != before) {
    return const CheckResult(
      Status.fail,
      'the id changed during a token refresh',
    );
  }
  return const CheckResult(Status.pass, 'a new token for the same id');
}

Future<CheckResult> _fetch(_Kit kit) async {
  if (!kit.registered) {
    return _skipped('no installation');
  }
  final FirebaseRemoteConfig config = kit.config!;
  final FetchResult result = await config.fetch(
    minimumFetchInterval: Duration.zero,
  );
  final int? version = config.info.fetchedTemplateVersion;
  kit.firstFetchVersion = version;
  if (version == null) {
    return CheckResult(
      Status.inconclusive,
      'the fetch answered ${result.name} but the project has no published template: '
      'publish a template with the parameter $probeKey',
    );
  }
  return CheckResult(Status.pass, '${result.name}; template version $version');
}

Future<CheckResult> _activateAndRead(_Kit kit) async {
  if (kit.firstFetchVersion == null) {
    return _skipped('no fetched template');
  }
  final FirebaseRemoteConfig config = kit.config!;
  final bool activated = await config.activate();
  final RemoteConfigValue value = config.getValue(probeKey);
  if (!activated) {
    return const CheckResult(
      Status.fail,
      'activate() returned false after a successful fetch',
    );
  }
  if (value.source != ValueSource.valueRemote) {
    return CheckResult(
      Status.inconclusive,
      'activated, but the template has no parameter $probeKey: publish it (any value) and run the kit again',
    );
  }
  return CheckResult(
    Status.pass,
    'activated; $probeKey came from the server (${value.text.length} characters)',
  );
}

Future<CheckResult> _noChange(_Kit kit) async {
  final int? first = kit.firstFetchVersion;
  if (first == null) {
    return _skipped('no fetched template');
  }
  final FirebaseRemoteConfig config = kit.config!;
  final FetchResult result = await config.fetch(
    minimumFetchInterval: Duration.zero,
  );
  final int? second = config.info.fetchedTemplateVersion;
  if (second != first) {
    return const CheckResult(
      Status.inconclusive,
      'the template changed between the two fetches: run the kit again',
    );
  }
  if (result == FetchResult.unchanged) {
    return const CheckResult(
      Status.pass,
      'the server answered NO_CHANGE to the stored ETag',
    );
  }
  return CheckResult(
    Status.fail,
    'the second fetch of the same template version was ${result.name}, not unchanged: '
    'the ETag was not stored or not accepted',
  );
}

Future<CheckResult> _realtime(_Kit kit) async {
  if (kit.skipRealtime) {
    return _skipped('switched off with --skip-realtime');
  }
  if (kit.firstFetchVersion == null) {
    return _skipped('no fetched template');
  }
  final FirebaseRemoteConfig config = kit.config!;
  final Completer<CheckResult> done = Completer<CheckResult>();
  final Stopwatch watch = Stopwatch()..start();
  print(
    '   Publish a change to a parameter in the Firebase console now; '
    'waiting up to ${kit.realtimeWindow.inSeconds} s.',
  );
  final StreamSubscription<RemoteConfigUpdate>
  subscription = config.onConfigUpdated.listen(
    (RemoteConfigUpdate update) {
      if (done.isCompleted) {
        return;
      }
      done.complete(
        CheckResult(
          Status.pass,
          'an update after ${watch.elapsed.inSeconds} s; ${update.updatedKeys.length} key(s) changed',
        ),
      );
    },
    onError: (Object error) {
      if (done.isCompleted) {
        return;
      }
      done.complete(
        CheckResult(Status.fail, 'the stream reported ${_describe(error)}'),
      );
    },
  );
  try {
    return await done.future.timeout(
      kit.realtimeWindow,
      onTimeout: () => CheckResult(
        Status.inconclusive,
        'no change was published within ${kit.realtimeWindow.inSeconds} s; the stream may still be fine',
      ),
    );
  } finally {
    await subscription.cancel();
  }
}

Future<CheckResult> _deleteInstallation(_Kit kit) async {
  if (!kit.registered) {
    return _skipped('no installation');
  }
  await kit.installations!.delete();
  kit.deleted = true;
  return const CheckResult(
    Status.pass,
    'deleted on the server and removed from the store',
  );
}
