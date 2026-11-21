// Benchmark of the uploads of firebase_storage_dart: object sizes, chunked against single-request uploads,
// round-trip latency and bandwidth (a local proxy between the client and the emulator) and many uploads at once.
//
//     dart run benchmark/upload_benchmark.dart --backend=emulator          # FIREBASE_STORAGE_EMULATOR_HOST
//     dart run benchmark/upload_benchmark.dart --help
//
// See benchmark/README.md. In production nothing runs without --yes; the kit writes only below one prefix,
// uploads at most --max-bytes in total, and deletes every object it wrote.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';
import 'package:http/http.dart' as http;

import 'delay_proxy.dart';

const String projectVariable = 'FIREBASE_TEST_PROJECT_ID';
const String bucketVariable = 'FIREBASE_TEST_STORAGE_BUCKET';
const String webApiKeyVariable = 'FIREBASE_API_KEY';
const String emulatorHostVariable = 'FIREBASE_STORAGE_EMULATOR_HOST';
const String authEmulatorHostVariable = 'FIREBASE_AUTH_EMULATOR_HOST';

const int mib = 1024 * 1024;

final ArgParser parser = ArgParser(usageLineLength: 110)
  ..addOption(
    'backend',
    help:
        'emulator: the Storage emulator at $emulatorHostVariable, through a local proxy that adds latency.\n'
        'production: Cloud Storage for Firebase ($projectVariable and $bucketVariable); the network is the real one, '
        'so --rtt and --bandwidth-mbit are refused. Does nothing without --yes.',
    valueHelp: 'emulator|production',
  )
  ..addFlag('yes', negatable: false, help: 'Confirms a run against production.')
  ..addOption(
    'bucket',
    help:
        'The bucket (default: $bucketVariable, or on the emulator demo-test.appspot.com).',
    valueHelp: 'name',
  )
  ..addOption(
    'api-key',
    help: 'The Web API key of the project (default: $webApiKeyVariable).',
    valueHelp: 'key',
  )
  ..addFlag(
    'create-user',
    negatable: false,
    help:
        'Signs up a throwaway user bench-<run>@example.com with a random password kept in memory, uploads as that '
        'user and deletes the user at the end. Needs the API key (on the emulator also $authEmulatorHostVariable).',
  )
  ..addOption(
    'suite',
    help: 'Which tables to measure.',
    allowed: <String>['all', 'size', 'concurrency'],
    defaultsTo: 'all',
  )
  ..addOption(
    'sizes',
    help: 'Object sizes in MiB for the size table.',
    valueHelp: 'mib,mib',
    defaultsTo: '1,16,64,256',
  )
  ..addOption(
    'modes',
    help:
        'chunked: maxUploadChunkSize = --chunk-max-mib (chunks start at 256 KiB and grow); single: one streamed request.',
    valueHelp: 'chunked,single',
    defaultsTo: 'chunked,single',
  )
  ..addOption(
    'chunk-max-mib',
    help: 'maxUploadChunkSize of the chunked mode.',
    valueHelp: 'mib',
    defaultsTo: '16',
  )
  ..addOption(
    'rtt',
    help: 'Added round-trip times in ms (emulator only).',
    valueHelp: 'ms,ms',
    defaultsTo: '0,50,150',
  )
  ..addOption(
    'bandwidth-mbit',
    help: 'Cap of each direction in Mbit/s, 0 for none (emulator only).',
    valueHelp: 'mbit',
    defaultsTo: '0',
  )
  ..addOption(
    'files',
    help: 'Files of the concurrency table.',
    valueHelp: 'n',
    defaultsTo: '20',
  )
  ..addOption(
    'file-mib',
    help: 'Size of each file of the concurrency table in MiB.',
    valueHelp: 'mib',
    defaultsTo: '2',
  )
  ..addOption(
    'concurrency',
    help: 'maxConcurrentUploads values of the concurrency table.',
    valueHelp: 'n,n',
    defaultsTo: '1,4,8',
  )
  ..addOption(
    'source',
    help: 'Upload from memory (startUpload) or from a file (putFile).',
    allowed: <String>['bytes', 'file'],
    defaultsTo: 'bytes',
  )
  ..addOption(
    'repeats',
    help: 'Runs of each cell; the table shows the median.',
    valueHelp: 'n',
    defaultsTo: '3',
  )
  ..addOption(
    'max-bytes',
    help: 'Refuses to start when the whole plan uploads more (default 1 GiB).',
    valueHelp: 'n',
    defaultsTo: '${1024 * mib}',
  )
  ..addOption(
    'out',
    help: 'Directory of the JSON result.',
    valueHelp: 'dir',
    defaultsTo: 'benchmark/results',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Prints this text.');

String get usage =>
    'Usage: dart run benchmark/upload_benchmark.dart --backend=emulator|production [options]\n\n${parser.usage}';

/// One cell of a table: what is uploaded and how.
class Cell {
  Cell({
    required this.table,
    required this.files,
    required this.sizeMib,
    required this.mode,
    required this.rttMs,
    required this.concurrency,
  });

  /// `size` or `concurrency`.
  final String table;
  final int files;
  final int sizeMib;

  /// `chunked` or `single`.
  final String mode;
  final int rttMs;
  final int concurrency;

  int get bytes => files * sizeMib * mib;

  String get label =>
      '$table ${files}x$sizeMib MiB $mode rtt=${rttMs}ms concurrency=$concurrency';

  Map<String, Object?> toJson() => <String, Object?>{
    'table': table,
    'files': files,
    'sizeMib': sizeMib,
    'mode': mode,
    'rttMs': rttMs,
    'concurrency': concurrency,
  };
}

/// What one run of a cell measured.
class Run {
  Run({
    required this.wallSeconds,
    required this.requests,
    required this.events,
    required this.maxGapMs,
    required this.peakRssDeltaBytes,
    required this.bytes,
  });

  final double wallSeconds;
  final int requests;
  final int events;
  final double maxGapMs;
  final int peakRssDeltaBytes;
  final int bytes;

  double get mibPerSecond => bytes / mib / wallSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'wallSeconds': wallSeconds,
    'mibPerSecond': mibPerSecond,
    'requests': requests,
    'progressEvents': events,
    'maxGapMs': maxGapMs,
    'peakRssDeltaMib': peakRssDeltaBytes / mib,
  };
}

double median(List<double> values) {
  final List<double> sorted = List<double>.of(values)..sort();
  final int middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Counts every request that goes out, retries included.
class CountingClient extends http.BaseClient {
  CountingClient(this._inner);

  final http.Client _inner;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// The target and the identity of a run.
class Target {
  Target({
    required this.production,
    required this.projectId,
    required this.bucket,
    required this.emulatorHost,
    required this.apiKey,
    required this.userAuth,
  });

  final bool production;
  final String projectId;
  final String bucket;
  final String? emulatorHost;
  final String apiKey;
  FirebaseUserAuth? userAuth;
}

class Bench {
  Bench(this.target, this.args, this.runId) : prefix = 'bench_storage/$runId';

  final Target target;
  final ArgResults args;
  final String runId;
  final String prefix;
  int _apps = 0;
  final List<String> written = <String>[];

  bool get fromFile => args.option('source') == 'file';

  FirebaseStorage storage({
    String? emulatorHost,
    int maxConcurrentUploads = 4,
    int? maxUploadChunkSize,
    http.Client? httpClient,
  }) {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: target.apiKey,
        appId: '1:0:dart:storage-bench',
        projectId: target.projectId,
        storageBucket: target.bucket,
      ),
      name: 'storage-bench-$runId-${_apps++}',
    );
    final FirebaseUserAuth? auth = target.userAuth;
    if (auth != null) {
      app.authProvider = auth;
    }
    return FirebaseStorage(
      app,
      emulatorHost: emulatorHost,
      httpClient: httpClient,
      maxConcurrentUploads: maxConcurrentUploads,
      maxUploadChunkSize: maxUploadChunkSize,
    );
  }

  /// Runs [cell] once and returns what it measured; deletes what it uploaded.
  Future<Run> runOnce(Cell cell, int index, Uint8List? data, File? file) async {
    DelayProxy? proxy;
    String? host = target.emulatorHost;
    if (!target.production) {
      final Uri emulator = Uri.parse('http://${target.emulatorHost}');
      proxy = await DelayProxy.start(
        targetHost: emulator.host,
        targetPort: emulator.port,
        rtt: Duration(milliseconds: cell.rttMs),
        bandwidthMbit: double.parse(args.option('bandwidth-mbit')!),
      );
      host = proxy.address;
    }
    final CountingClient client = CountingClient(http.Client());
    final FirebaseStorage uploader = storage(
      emulatorHost: host,
      maxConcurrentUploads: cell.concurrency,
      maxUploadChunkSize: cell.mode == 'chunked'
          ? int.parse(args.option('chunk-max-mib')!) * mib
          : null,
      httpClient: client,
    );
    final FirebaseStorage cleaner = storage(emulatorHost: target.emulatorHost);
    final List<Reference> refs = <Reference>[
      for (int i = 0; i < cell.files; i++)
        uploader.ref(
          '$prefix/${cell.table}_${cell.sizeMib}_${cell.mode}_${cell.rttMs}_${cell.concurrency}_$index/$i.bin',
        ),
    ];
    written.addAll(<String>[for (final Reference ref in refs) ref.fullPath]);

    final int baseline = ProcessInfo.currentRss;
    int peak = baseline;
    final Timer sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
      peak = math.max(peak, ProcessInfo.currentRss);
    });
    final Stopwatch clock = Stopwatch()..start();
    final List<int> stamps = <int>[];
    final List<StreamSubscription<UploadProgress>> subscriptions =
        <StreamSubscription<UploadProgress>>[];
    try {
      final List<UploadTask> tasks = <UploadTask>[
        for (final Reference ref in refs)
          if (fromFile) ref.putFile(file!) else ref.startUpload(data!),
      ];
      for (final UploadTask task in tasks) {
        subscriptions.add(
          task.progress.listen(
            (UploadProgress _) => stamps.add(clock.elapsedMicroseconds),
          ),
        );
      }
      final List<FullMetadata> done = await Future.wait(<Future<FullMetadata>>[
        for (final UploadTask t in tasks) t.result,
      ]);
      clock.stop();
      for (final FullMetadata metadata in done) {
        if (metadata.size != cell.sizeMib * mib) {
          throw StateError(
            'an object has ${metadata.size} bytes, expected ${cell.sizeMib * mib}',
          );
        }
      }
      stamps.sort();
      int gap = 0;
      for (int i = 1; i < stamps.length; i++) {
        gap = math.max(gap, stamps[i] - stamps[i - 1]);
      }
      if (stamps.isNotEmpty) {
        gap = math.max(gap, clock.elapsedMicroseconds - stamps.last);
      }
      peak = math.max(peak, ProcessInfo.currentRss);
      return Run(
        wallSeconds: clock.elapsedMicroseconds / 1e6,
        requests: client.requests,
        events: stamps.length,
        maxGapMs: gap / 1000,
        peakRssDeltaBytes: peak - baseline,
        bytes: cell.bytes,
      );
    } finally {
      sampler.cancel();
      for (final StreamSubscription<UploadProgress> s in subscriptions) {
        await s.cancel();
      }
      uploader.close();
      await proxy?.close();
      for (final Reference ref in refs) {
        try {
          await cleaner.ref(ref.fullPath).delete();
        } on FirebaseStorageException catch (e) {
          if (e.code != 'object-not-found') {
            stderr.writeln('could not delete ${ref.fullPath}: ${e.code}');
          }
        }
      }
      cleaner.close();
    }
  }
}

List<int> _ints(String text) => <int>[
  for (final String part in text.split(','))
    if (part.trim().isNotEmpty) int.parse(part.trim()),
];

List<Cell> plan(ArgResults args, bool production) {
  final String suite = args.option('suite')!;
  final List<int> rtts = production ? <int>[0] : _ints(args.option('rtt')!);
  final List<Cell> cells = <Cell>[];
  if (suite == 'all' || suite == 'size') {
    for (final int size in _ints(args.option('sizes')!)) {
      for (final String mode in args.option('modes')!.split(',')) {
        for (final int rtt in rtts) {
          cells.add(
            Cell(
              table: 'size',
              files: 1,
              sizeMib: size,
              mode: mode.trim(),
              rttMs: rtt,
              concurrency: 4,
            ),
          );
        }
      }
    }
  }
  if (suite == 'all' || suite == 'concurrency') {
    for (final int concurrency in _ints(args.option('concurrency')!)) {
      for (final int rtt in rtts) {
        cells.add(
          Cell(
            table: 'concurrency',
            files: int.parse(args.option('files')!),
            sizeMib: int.parse(args.option('file-mib')!),
            mode: 'single',
            rttMs: rtt,
            concurrency: concurrency,
          ),
        );
      }
    }
  }
  return cells;
}

String _fmt(double value, [int digits = 2]) => value.toStringAsFixed(digits);

String markdown(
  List<(Cell, List<Run>)> results,
  ArgResults args,
  Target target,
) {
  final StringBuffer out = StringBuffer()
    ..writeln('# Storage upload benchmark')
    ..writeln()
    ..writeln(
      '- target: ${target.production ? 'production, bucket ${target.bucket}' : 'emulator behind a delay proxy'}; '
      'source: ${args.option('source')}; repeats: ${args.option('repeats')} (median shown)',
    )
    ..writeln(
      '- bandwidth cap: ${target.production ? 'none (real network)' : '${args.option('bandwidth-mbit')} Mbit/s per direction (0 = none)'}',
    )
    ..writeln(
      '- chunked = maxUploadChunkSize ${args.option('chunk-max-mib')} MiB (chunks start at 256 KiB and grow); single = one streamed request',
    )
    ..writeln(
      '- "gap" is the longest time without a progress event; RSS is the growth of the resident set during the run',
    )
    ..writeln();
  for (final String table in <String>['size', 'concurrency']) {
    final List<(Cell, List<Run>)> rows = <(Cell, List<Run>)>[
      for (final (Cell, List<Run>) r in results)
        if (r.$1.table == table) r,
    ];
    if (rows.isEmpty) {
      continue;
    }
    if (table == 'size') {
      out
        ..writeln('## One object')
        ..writeln()
        ..writeln(
          '| size MiB | mode | RTT ms | wall s | MiB/s | requests | events | max gap ms | RSS +MiB |',
        )
        ..writeln(
          '| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
        );
    } else {
      out
        ..writeln(
          '## Many objects (${rows.first.$1.files} x ${rows.first.$1.sizeMib} MiB)',
        )
        ..writeln()
        ..writeln(
          '| concurrent | RTT ms | wall s | MiB/s | requests | events | max gap ms | RSS +MiB |',
        )
        ..writeln('| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    }
    for (final (Cell cell, List<Run> runs) in rows) {
      final String metrics =
          '${_fmt(median(<double>[for (final Run r in runs) r.wallSeconds]))} | '
          '${_fmt(median(<double>[for (final Run r in runs) r.mibPerSecond]))} | '
          '${median(<double>[for (final Run r in runs) r.requests.toDouble()]).round()} | '
          '${median(<double>[for (final Run r in runs) r.events.toDouble()]).round()} | '
          '${_fmt(median(<double>[for (final Run r in runs) r.maxGapMs]), 0)} | '
          '${_fmt(median(<double>[for (final Run r in runs) r.peakRssDeltaBytes / mib]), 1)}';
      out.writeln(
        table == 'size'
            ? '| ${cell.sizeMib} | ${cell.mode} | ${cell.rttMs} | $metrics |'
            : '| ${cell.concurrency} | ${cell.rttMs} | $metrics |',
      );
    }
    out.writeln();
  }
  return out.toString();
}

Future<File> writeJson(
  List<(Cell, List<Run>)> results,
  ArgResults args,
  Target target,
  String runId,
) async {
  final Directory dir = Directory(args.option('out')!)
    ..createSync(recursive: true);
  final File file = File('${dir.path}/upload_$runId.json');
  final Map<String, Object?> json = <String, Object?>{
    'runId': runId,
    'backend': target.production ? 'production' : 'emulator',
    'source': args.option('source'),
    'repeats': int.parse(args.option('repeats')!),
    'bandwidthMbit': target.production
        ? null
        : double.parse(args.option('bandwidth-mbit')!),
    'chunkMaxMib': int.parse(args.option('chunk-max-mib')!),
    'dart': Platform.version,
    'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'cells': <Object?>[
      for (final (Cell cell, List<Run> runs) in results)
        <String, Object?>{
          ...cell.toJson(),
          'runs': <Object?>[for (final Run r in runs) r.toJson()],
          'median': <String, Object?>{
            'wallSeconds': median(<double>[
              for (final Run r in runs) r.wallSeconds,
            ]),
            'mibPerSecond': median(<double>[
              for (final Run r in runs) r.mibPerSecond,
            ]),
            'requests': median(<double>[
              for (final Run r in runs) r.requests.toDouble(),
            ]),
            'progressEvents': median(<double>[
              for (final Run r in runs) r.events.toDouble(),
            ]),
            'maxGapMs': median(<double>[for (final Run r in runs) r.maxGapMs]),
            'peakRssDeltaMib': median(<double>[
              for (final Run r in runs) r.peakRssDeltaBytes / mib,
            ]),
          },
        },
    ],
  };
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  return file;
}

/// A file of [size] bytes in [dir]; the content is zeros (nothing compresses on the way).
Future<File> _tempFile(Directory dir, int size) async {
  final File file = File('${dir.path}/object_$size.bin');
  final RandomAccessFile handle = await file.open(mode: FileMode.write);
  final Uint8List block = Uint8List(mib);
  for (int written = 0; written < size; written += mib) {
    await handle.writeFrom(block, 0, math.min(mib, size - written));
  }
  await handle.close();
  return file;
}

Future<int> run(List<String> arguments) async {
  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args.rest.isNotEmpty) {
      throw FormatException('Unexpected argument: ${args.rest.first}');
    }
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(usage);
    return 64;
  }
  if (args.flag('help')) {
    print(usage);
    return 0;
  }
  String? setting(String name) {
    final String? value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  int fail(String message) {
    stderr
      ..writeln(message)
      ..writeln(usage);
    return 2;
  }

  final String? backend = args.option('backend');
  final String? emulatorHost = setting(emulatorHostVariable);
  final bool production = backend == 'production';
  if (backend != 'production' && backend != 'emulator') {
    return fail('--backend=emulator or --backend=production is required.');
  }
  if (production && emulatorHost != null) {
    return fail(
      '$emulatorHostVariable is set. Unset it for --backend=production, so that it is unambiguous where the benchmark writes.',
    );
  }
  if (!production && emulatorHost == null) {
    return fail(
      '$emulatorHostVariable is not set: it is the host:port of the Storage emulator.',
    );
  }
  if (production &&
      (args.wasParsed('rtt') || args.option('bandwidth-mbit') != '0')) {
    return fail(
      '--rtt and --bandwidth-mbit need the emulator: against production the network is the real one.',
    );
  }
  final String? project = production ? setting(projectVariable) : 'demo-test';
  final String? bucket =
      args.option('bucket') ??
      (production ? setting(bucketVariable) : 'demo-test.appspot.com');
  if (project == null || bucket == null) {
    return fail(
      '$projectVariable and $bucketVariable (or --bucket) name the project and the bucket.',
    );
  }
  final String? apiKey = args.option('api-key') ?? setting(webApiKeyVariable);
  final bool createUser = args.flag('create-user');
  if (createUser && apiKey == null) {
    return fail(
      '--create-user needs the Web API key: $webApiKeyVariable or --api-key.',
    );
  }
  if (createUser && !production && setting(authEmulatorHostVariable) == null) {
    return fail(
      '--create-user on the emulator needs $authEmulatorHostVariable.',
    );
  }

  final List<Cell> cells = plan(args, production);
  final int repeats = int.parse(args.option('repeats')!);
  final int maxBytes = int.parse(args.option('max-bytes')!);
  final int planned = cells.fold(
    0,
    (int sum, Cell c) => sum + c.bytes * repeats,
  );
  final DateTime now = DateTime.now().toUtc();
  final String runId =
      'run_${now.toIso8601String().replaceAll(RegExp('[^0-9]'), '').substring(0, 14)}_${now.microsecond.toRadixString(36)}';
  print('Storage upload benchmark');
  print(
    '  backend:  ${production ? 'production' : 'emulator at $emulatorHost (through a local delay proxy)'}',
  );
  print('  project:  $project');
  print('  bucket:   $bucket');
  print(
    '  prefix:   bench_storage/$runId/ (the only place written; every object is deleted after its run)',
  );
  print(
    '  user:     ${createUser ? 'a throwaway user bench-$runId@example.com, deleted at the end' : 'none'}',
  );
  print(
    '  plan:     ${cells.length} cells x $repeats runs, ${_fmt(planned / mib, 0)} MiB uploaded in total (cap ${_fmt(maxBytes / mib, 0)} MiB)',
  );
  if (planned > maxBytes) {
    return fail(
      'The plan uploads more than --max-bytes: choose fewer --sizes, --repeats or --rtt, or raise --max-bytes.',
    );
  }
  if (production && !args.flag('yes')) {
    print('');
    print(
      'Nothing was done. Pass --yes to run this against the real project and bucket above.',
    );
    return 2;
  }
  print('');

  FirebaseUserAuth? auth;
  String? uid;
  final Target target = Target(
    production: production,
    projectId: project,
    bucket: bucket,
    emulatorHost: emulatorHost,
    apiKey: apiKey ?? 'storage-bench-no-key',
    userAuth: null,
  );
  final Bench bench = Bench(target, args, runId);
  Directory? tempDir;
  final List<(Cell, List<Run>)> results = <(Cell, List<Run>)>[];
  try {
    if (createUser) {
      final FirebaseApp authApp = FirebaseApp.withOptions(
        FirebaseOptions(
          apiKey: apiKey!,
          appId: '1:0:dart:storage-bench',
          projectId: project,
          storageBucket: bucket,
        ),
        name: 'storage-bench-auth-$runId',
      );
      auth = await FirebaseUserAuth.forApp(
        authApp,
        emulatorHost: production ? null : setting(authEmulatorHostVariable),
      );
      final math.Random secure = math.Random.secure();
      const String alphabet =
          'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final String password = <String>[
        for (int i = 0; i < 32; i++) alphabet[secure.nextInt(alphabet.length)],
      ].join();
      try {
        final UserCredential created = await auth
            .createUserWithEmailAndPassword(
              email: 'bench-$runId@example.com',
              password: password,
            );
        uid = created.user?.uid;
      } on FirebaseAuthException catch (e) {
        stderr.writeln(
          'Signing up the throwaway user failed: ${e.code}. Nothing was written.',
        );
        return 2;
      }
      target.userAuth = auth;
    }
    if (bench.fromFile) {
      tempDir = await Directory.systemTemp.createTemp('storage_bench');
    }
    final Map<int, Uint8List> memory = <int, Uint8List>{};
    final Map<int, File> files = <int, File>{};
    for (final Cell cell in cells) {
      stderr.writeln(cell.label);
      final int size = cell.sizeMib * mib;
      final Uint8List? data = bench.fromFile
          ? null
          : memory.putIfAbsent(size, () => Uint8List(size));
      final File? file = bench.fromFile
          ? (files[size] ??= await _tempFile(tempDir!, size))
          : null;
      final List<Run> runs = <Run>[];
      for (int i = 0; i < repeats; i++) {
        final Run result = await bench.runOnce(cell, i, data, file);
        runs.add(result);
        stderr.writeln(
          '  run ${i + 1}/$repeats: ${_fmt(result.wallSeconds)} s, ${_fmt(result.mibPerSecond)} MiB/s, ${result.requests} requests',
        );
      }
      results.add((cell, runs));
    }
    print(markdown(results, args, target));
    final File json = await writeJson(results, args, target, runId);
    print('JSON: ${json.path}');
    return 0;
  } finally {
    if (tempDir != null) {
      await tempDir.delete(recursive: true);
    }
    if (auth != null) {
      try {
        await auth.deleteCurrentUser();
        print('The throwaway user was deleted.');
      } on Object catch (e) {
        print(
          'Deleting the throwaway user FAILED (${e.runtimeType}). Delete the user with uid $uid by hand.',
        );
      }
    }
  }
}

Future<void> main(List<String> arguments) async {
  final int code = await run(arguments);
  await stdout.flush();
  exit(code);
}
