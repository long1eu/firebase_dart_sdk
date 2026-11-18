// Runs the pages of web/ in headless Chrome and prints what they measured.
// Part of docs/spikes/indexeddb_cache.md.
//
//   cd tool/bench/web_idb && dart pub get
//   dart run.dart build                  # compiles web/*.dart, copies the assets
//   dart run.dart [txtest] [engine] [startup] [--runs=N]   # default: all three
//       [--engines=idb,sqlite-idb,sqlite-opfs] [--compilers=js,wasm]
//
// build compiles engine.dart and startup.dart with dart2js -O2 and dart2wasm
// -O2, and copies sqlite3.wasm and sqlite_opfs_worker.js from
// cloud_firestore_dart/test/browser (run tool/build_web_test_assets.sh first).
//
// A local HTTP server on 127.0.0.1 serves web/ and receives each page's
// result (POST /result); its answer is the URL the page goes to next, so one
// headless Chrome (a fresh profile in a temp dir) walks the whole plan.
// Pages of a "cold" step are loaded from /cold/..., where everything is served
// with `Cache-Control: no-store`; those of a "warm" step from /warm/..., with
// `max-age=3600` (the first warm load, which fills the HTTP cache, is not
// counted). IndexedDB and OPFS belong to the origin, so both see the same
// stored cache. Raw results go to
// out/results.jsonl, the medians to stdout.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

final String here = File.fromUri(Platform.script).parent.path;
const String chrome =
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

Future<void> build() async {
  for (final String page in <String>['engine', 'startup']) {
    for (final List<String> args in <List<String>>[
      <String>['compile', 'js', '-O2', '-o', 'web/$page.js', 'web/$page.dart'],
      <String>[
        'compile',
        'wasm',
        '-O2',
        '-o',
        'web/$page.wasm',
        'web/$page.dart',
      ],
    ]) {
      stdout.writeln('dart ${args.join(' ')}');
      final ProcessResult r = await Process.run(
        Platform.resolvedExecutable,
        args,
        workingDirectory: here,
      );
      if (r.exitCode != 0) {
        stderr.writeln('${r.stdout}${r.stderr}');
        exit(2);
      }
    }
  }
  final String assets =
      '$here/../../../cloud_firestore/cloud_firestore_dart/test/browser';
  File('$assets/sqlite3.wasm').copySync('$here/web/sqlite3.wasm');
  File(
    '$assets/opfs/sqlite_opfs_worker.js',
  ).copySync('$here/web/sqlite_opfs_worker.js');
}

class Step {
  Step(String page, {this.cache = 'warm', this.count = true})
    : url = '$cache/$page';
  final String url;
  final String cache;
  final bool count;
}

List<String> engines = <String>['idb', 'sqlite-idb', 'sqlite-opfs'];
List<String> compilers = <String>['js', 'wasm'];

List<Step> plan(Set<String> parts, int runs) => <Step>[
  if (parts.contains('txtest'))
    for (final String c in <String>['js', 'wasm'])
      Step('index.html?p=engine&c=$c&engine=txtest'),
  if (parts.contains('engine'))
    for (final String c in compilers)
      for (final String engine in engines)
        Step('index.html?p=engine&c=$c&engine=$engine&runs=$runs'),
  if (parts.contains('startup'))
    for (final String c in compilers)
      for (final String storage in <String>['memory', 'idb', 'opfs']) ...<Step>[
        if (storage != 'memory')
          Step(
            'index.html?p=startup&c=$c&storage=$storage&phase=seed',
            cache: 'cold',
            count: false,
          ),
        for (int i = 0; i < runs; i++)
          Step(
            'index.html?p=startup&c=$c&storage=$storage&phase=measure&cache=cold',
            cache: 'cold',
          ),
        Step(
          'index.html?p=startup&c=$c&storage=$storage&phase=measure&cache=warm',
          count: false,
        ),
        for (int i = 0; i < runs; i++)
          Step(
            'index.html?p=startup&c=$c&storage=$storage&phase=measure&cache=warm',
          ),
      ],
];

double median(List<double> values) {
  final List<double> sorted = List<double>.of(values)..sort();
  final int n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

String ms(double v) => v.toStringAsFixed(v < 10 ? 2 : 0);

Future<void> main(List<String> arguments) async {
  if (arguments.contains('build')) {
    await build();
    return;
  }
  int runs = 5;
  final Set<String> parts = <String>{};
  for (final String a in arguments) {
    if (a.startsWith('--engines=')) {
      engines = a.substring(10).split(',');
    } else if (a.startsWith('--compilers=')) {
      compilers = a.substring(12).split(',');
    } else if (a.startsWith('--runs=')) {
      runs = int.parse(a.substring(7));
    } else {
      parts.add(a);
    }
  }
  if (parts.isEmpty) parts.addAll(<String>['txtest', 'engine', 'startup']);
  final List<Step> steps = plan(parts, runs);
  final Directory out = Directory('$here/out')..createSync();
  final IOSink raw = File(
    '${out.path}/results.jsonl',
  ).openWrite(mode: FileMode.append);

  int index = 0;
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  final Completer<void> finished = Completer<void>();
  Timer? watchdog;
  void arm() {
    watchdog?.cancel();
    watchdog = Timer(const Duration(minutes: 15), () {
      stderr.writeln('No result for 15 minutes at ${steps[index].url}');
      if (!finished.isCompleted) finished.complete();
    });
  }

  final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
  final String origin = 'http://127.0.0.1:${server.port}';
  server.listen((HttpRequest request) async {
    final HttpResponse response = request.response;
    if (request.method == 'POST' && request.uri.path == '/result') {
      final Map<String, Object?> result =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      result['step'] = steps[index].url;
      result['counted'] = steps[index].count;
      raw.writeln(jsonEncode(result));
      stdout.writeln(
        '${index + 1}/${steps.length} ${steps[index].url}'
        '${result['error'] != null ? '  ERROR ${result['error']}' : ''}',
      );
      results.add(result);
      index++;
      if (index < steps.length) {
        arm();
        response.write('$origin/${steps[index].url}');
      } else if (!finished.isCompleted) {
        finished.complete();
      }
      await response.close();
      return;
    }
    // /cold/... is always served with no-store, /warm/... with max-age: the
    // two never share an HTTP cache entry.
    final List<String> segments = request.uri.pathSegments;
    final String cacheMode = segments.isEmpty ? 'cold' : segments.first;
    final String path = '/${segments.skip(1).join('/')}';
    final File file = File('$here/web$path');
    if (path.contains('..') || path == '/' || !file.existsSync()) {
      response.statusCode = 404;
      await response.close();
      return;
    }
    response.headers
      ..set('Cache-Control', cacheMode == 'cold' ? 'no-store' : 'max-age=3600')
      ..contentType = switch (path.split('.').last) {
        'html' => ContentType.html,
        'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
        'wasm' => ContentType('application', 'wasm'),
        _ => ContentType.binary,
      };
    await response.addStream(file.openRead());
    await response.close();
  });

  final Directory profile = Directory.systemTemp.createTempSync(
    'web_idb_chrome',
  );
  arm();
  final Process browser = await Process.start(chrome, <String>[
    '--headless=new',
    '--user-data-dir=${profile.path}',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--disable-background-timer-throttling',
    '--disable-renderer-backgrounding',
    '$origin/${steps.first.url}',
  ]);
  unawaited(browser.stdout.drain<void>());
  unawaited(browser.stderr.drain<void>());
  await finished.future;
  watchdog?.cancel();
  browser.kill();
  await browser.exitCode;
  await raw.close();
  await server.close(force: true);
  profile.deleteSync(recursive: true);
  report(
    results.where((Map<String, Object?> r) => r['counted'] == true).toList(),
  );
}

void report(List<Map<String, Object?>> results) {
  for (final Map<String, Object?> r in results) {
    if (r['error'] != null)
      stdout.writeln('ERROR in ${r['step']}: ${r['error']}');
  }
  // Point 4.
  for (final Map<String, Object?> r in results.where((r) => r['tx'] != null)) {
    stdout.writeln('\nTransaction lifetime, ${r['compiler']}:');
    (r['tx']! as Map<String, Object?>).forEach((String k, Object? v) {
      stdout.writeln('  $k: $v');
    });
  }
  // Point 3.
  final List<Map<String, Object?>> engines = results
      .where((r) => r['runs'] != null)
      .toList();
  if (engines.isNotEmpty) {
    stdout.writeln('\nEngine medians (ms):');
    for (final Map<String, Object?> r in engines) {
      final List<Map<String, Object?>> runs = (r['runs']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final List<String> ops = runs.first.keys.toList();
      stdout.writeln(
        '  ${r['compiler']} ${r['engine']} (${runs.length} runs): ' +
            ops
                .map(
                  (String op) =>
                      '$op ${ms(median(<double>[for (final Map<String, Object?> run in runs) (run[op]! as num).toDouble()]))}',
                )
                .join(', '),
      );
    }
  }
  // Point 2.
  final Map<String, List<Map<String, Object?>>> startup =
      <String, List<Map<String, Object?>>>{};
  for (final Map<String, Object?> r in results.where(
    (r) => r['page'] == 'startup' && r['phase'] == 'measure',
  )) {
    startup
        .putIfAbsent(
          '${r['compiler']} ${r['storage']} ${r['cache']}',
          () => <Map<String, Object?>>[],
        )
        .add(r);
  }
  if (startup.isNotEmpty) {
    stdout.writeln(
      '\nStart-up medians (ms from timeOrigin): main starts / first read done / read - main',
    );
    startup.forEach((String k, List<Map<String, Object?>> list) {
      final List<double> main = <double>[
        for (final r in list) (r['mainStart']! as num).toDouble(),
      ];
      final List<double> read = <double>[
        for (final r in list) ((r['read'] ?? double.nan) as num).toDouble(),
      ];
      final List<double> diff = <double>[
        for (int i = 0; i < list.length; i++) read[i] - main[i],
      ];
      final Set<Object?> found = <Object?>{for (final r in list) r['found']};
      stdout.writeln(
        '  $k (${list.length}): ${ms(median(main))} / ${ms(median(read))} / ${ms(median(diff))}  found=$found',
      );
    });
  }
}
