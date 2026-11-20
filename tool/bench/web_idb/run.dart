// Runs the pages of web/ in headless Chrome and prints what they measured.
// Part of docs/spikes/indexeddb_cache.md.
//
//   cd tool/bench/web_idb && dart pub get
//   dart run.dart build                  # compiles web/*.dart, copies the assets
//   dart run.dart [txtest] [engine] [startup] [--runs=N]   # default: all three
//       [--engines=idb,sqlite-idb,sqlite-opfs] [--compilers=js,wasm] [--browser=chrome|firefox|safari]
//   dart run.dart read [--kinds=engine,sqlite-idb,sqlite-opfs] [--docs=20000] [--port=8397] [--runs=N]
//       # web/read.dart: the read cases of docs/spikes/cache_read_profile.md on acknowledged documents (needs a
//       # Firestore emulator on --port; it writes the documents there once, then a seed and a measure load per run)
//   dart run.dart cache [--kinds=engine,sqlite-idb,sqlite-opfs] [--sizes=2000,20000] [--runs=N]
//       # web/cache.dart: reads over a large cache through the SDK, a seed load then a measure load per run
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

Future<void> build(List<String> pages) async {
  for (final String page in pages) {
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
  // Kept when the assets were put into web/ by hand.
  if (File('$assets/sqlite3.wasm').existsSync()) {
    File('$assets/sqlite3.wasm').copySync('$here/web/sqlite3.wasm');
    File(
      '$assets/opfs/sqlite_opfs_worker.js',
    ).copySync('$here/web/sqlite_opfs_worker.js');
  }
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
List<String> kinds = <String>['engine', 'sqlite-idb', 'sqlite-opfs'];
List<int> sizes = <int>[2000, 20000];
int docs = 20000;
int port = 8397;
final String tag = DateTime.now().millisecondsSinceEpoch.toString();

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
  // The documents are written to the emulator once; each run reads them into a new cache, then measures it.
  if (parts.contains('read')) ...<Step>[
    Step(
      'index.html?p=read&c=${compilers.first}&n=$docs&port=$port&phase=load',
      cache: 'cold',
      count: false,
    ),
    for (final String c in compilers)
      for (final String kind in kinds)
        for (int i = 0; i < runs; i++)
          for (final String phase in <String>['seed', 'measure'])
            Step(
              'index.html?p=read&c=$c&kind=$kind&n=$docs&port=$port&phase=$phase&tag=$tag-$c-$kind-$i',
              cache: 'cold',
              count: phase == 'measure',
            ),
  ],
  // Each run seeds a new database (its own name) and measures it on the next page load.
  if (parts.contains('cache'))
    for (final String c in compilers)
      for (final int n in sizes)
        for (final String kind in kinds)
          for (int i = 0; i < runs; i++)
            for (final String phase in <String>['seed', 'measure'])
              Step(
                'index.html?p=cache&c=$c&kind=$kind&n=$n&phase=$phase&tag=$tag-$c-$kind-$n-$i',
              ),
];

double median(List<double> values) {
  final List<double> sorted = List<double>.of(values)..sort();
  final int n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

String ms(double v) => v.toStringAsFixed(v < 10 ? 2 : 0);

Future<void> main(List<String> arguments) async {
  if (arguments.contains('build')) {
    final List<String> pages = arguments.where((a) => a != 'build').toList();
    await build(
      pages.isEmpty ? <String>['engine', 'startup', 'cache', 'read'] : pages,
    );
    return;
  }
  int runs = 5;
  String browserName = 'chrome';
  final Set<String> parts = <String>{};
  for (final String a in arguments) {
    if (a.startsWith('--engines=')) {
      engines = a.substring(10).split(',');
    } else if (a.startsWith('--compilers=')) {
      compilers = a.substring(12).split(',');
    } else if (a.startsWith('--browser=')) {
      browserName = a.substring(10);
    } else if (a.startsWith('--kinds=')) {
      kinds = a.substring(8).split(',');
    } else if (a.startsWith('--sizes=')) {
      sizes = a.substring(8).split(',').map(int.parse).toList();
    } else if (a.startsWith('--docs=')) {
      docs = int.parse(a.substring(7));
    } else if (a.startsWith('--port=')) {
      port = int.parse(a.substring(7));
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
      result['browser'] = browserName;
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
  // Chrome and Firefox run headless on a fresh profile. Safari has no headless mode and no profile option: the
  // page opens in the Safari of the logged-in user (a new database name per run, see the pages).
  final String first = '$origin/${steps.first.url}';
  final Process browser = switch (browserName) {
    'firefox' => await Process.start(
      '/Applications/Firefox.app/Contents/MacOS/firefox',
      <String>['--headless', '--no-remote', '--profile', profile.path, first],
    ),
    'safari' => await Process.start('/usr/bin/open', <String>[
      '-a',
      'Safari',
      first,
    ]),
    _ => await Process.start(chrome, <String>[
      '--headless=new',
      '--user-data-dir=${profile.path}',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      first,
    ]),
  };
  unawaited(browser.stdout.drain<void>());
  unawaited(browser.stderr.drain<void>());
  await finished.future;
  watchdog?.cancel();
  if (browserName == 'safari') {
    // Close the tab this run opened in the user's Safari. Needs the Automation permission for Safari; without it
    // (over ssh, for example) osascript can wait on a prompt, hence the timeout: the tab then stays open.
    final Process close = await Process.start('osascript', <String>[
      '-e',
      'tell application "Safari" to close (every tab of every window whose URL starts with "$origin")',
    ]);
    await close.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        close.kill();
        stderr.writeln('Could not close the Safari tab at $origin');
        return -1;
      },
    );
  }
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
  reportCache(results.where((r) => r['page'] == 'cache').toList());
  reportRead(results.where((r) => r['page'] == 'read').toList());
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

const List<String> cacheOps = <String>[
  'seed',
  'open_first_read',
  'doc_reads_100',
  'query_all',
  'query_group_1pct',
  'query_orderBy_limit20',
  'query_collection_group',
  'write_then_limit_query',
];

void reportCache(List<Map<String, Object?>> results) {
  if (results.isEmpty) return;
  final Map<String, Map<String, List<double>>> byKey =
      <String, Map<String, List<double>>>{};
  final Map<String, Map<String, Set<Object?>>> counts =
      <String, Map<String, Set<Object?>>>{};
  for (final Map<String, Object?> r in results) {
    if (r['error'] != null) continue;
    final String key =
        '${r['browser']} ${r['compiler']} n=${r['n']} ${r['kind']}';
    final Map<String, List<double>> ops = byKey.putIfAbsent(
      key,
      () => <String, List<double>>{},
    );
    for (final String op in cacheOps) {
      if (r[op] is num) {
        ops.putIfAbsent(op, () => <double>[]).add((r[op]! as num).toDouble());
      }
    }
    final Map<String, Set<Object?>> c = counts.putIfAbsent(
      key,
      () => <String, Set<Object?>>{},
    );
    ((r['sizes'] as Map<String, Object?>?) ?? <String, Object?>{}).forEach(
      (String op, Object? v) => c.putIfAbsent(op, () => <Object?>{}).add(v),
    );
    for (final String f in <String>[
      'lastFound',
      'pendingWrites',
      'writeSeen',
    ]) {
      if (r.containsKey(f)) c.putIfAbsent(f, () => <Object?>{}).add(r[f]);
    }
  }
  stdout.writeln('\nCache medians (ms) [min-max] {result sizes}:');
  byKey.forEach((String key, Map<String, List<double>> ops) {
    stdout.writeln('  $key');
    for (final String op in cacheOps) {
      final List<double>? v = ops[op];
      if (v == null) continue;
      final List<double> sorted = List<double>.of(v)..sort();
      stdout.writeln(
        '    $op: ${ms(median(v))} [${ms(sorted.first)}-${ms(sorted.last)}] '
        '(${v.length}) ${counts[key]![op] ?? ''}',
      );
    }
    stdout.writeln(
      '    checks: ${{
        for (final f in <String>['lastFound', 'pendingWrites', 'writeSeen']) f: counts[key]![f],
      }}',
    );
  });
}

const List<String> readCases = <String>['point', 'whole', 'eq', 'ord'];

/// Per compiler and kind, the median over the measure loads of each case (the median of its timed reads, in ms; the
/// point read per document), and the median of the first read.
void reportRead(List<Map<String, Object?>> results) {
  if (results.isEmpty) return;
  final Map<String, List<Map<String, Object?>>> byKey =
      <String, List<Map<String, Object?>>>{};
  for (final Map<String, Object?> r in results) {
    if (r['error'] != null) continue;
    byKey
        .putIfAbsent(
          '${r['compiler']} ${r['kind']} n=${r['n']}',
          () => <Map<String, Object?>>[],
        )
        .add(r);
  }
  stdout.writeln(
    '\nRead medians (ms) over the loads [min-max] (loads) {sizes}; first = first read after open:',
  );
  byKey.forEach((String key, List<Map<String, Object?>> list) {
    stdout.writeln(
      '  $key (${list.length} loads), user agent ${list.first['userAgent']}',
    );
    String three(double v) => v.toStringAsFixed(v < 10 ? 3 : 1);
    for (final String c in readCases) {
      final List<double> v = <double>[
        for (final r in list) (r['read_$c']! as num).toDouble(),
      ];
      final List<double> f = <double>[
        for (final r in list) (r['first_$c']! as num).toDouble(),
      ];
      final List<double> sorted = List<double>.of(v)..sort();
      stdout.writeln(
        '    $c: ${three(median(v))} [${three(sorted.first)}-${three(sorted.last)}] first ${three(median(f))} '
        '{${<Object?>{for (final r in list) (r['sizes'] as Map<String, Object?>)[c]}}}',
      );
    }
    stdout.writeln(
      '    open_first_read: ${three(median(<double>[for (final r in list) (r['open_first_read']! as num).toDouble()]))}',
    );
  });
}
