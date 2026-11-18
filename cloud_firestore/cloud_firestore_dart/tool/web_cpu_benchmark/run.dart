// Compares dart2js and dart2wasm on the client work of cloud_firestore_dart in
// headless Chrome: serialization, queries on a memory cache, a batch of writes
// with its listeners, a remote event, memory, the same queries on a SQLite
// cache (IndexedDB and OPFS), and start-up. See README.md for what each case
// measures.
//
// From cloud_firestore/cloud_firestore_dart, after tool/build_web_test_assets.sh
// (repository root) fetched sqlite3.wasm and compiled the OPFS worker:
//
//   dart run tool/web_cpu_benchmark/run.dart [--runs 7] [--reps 5]
//       [--suites cpu,sqlite,startup] [--storages indexeddb,opfs]
//       [--sqlite-docs 10000] [--compilers dart2js,dart2wasm]
//       [--out results.jsonl] [--chrome-flags "--flag1 --flag2"]
//
// Every run starts a new Chrome with an empty profile. The compilers alternate
// from one run to the next (dart2js first in even runs, dart2wasm first in odd
// ones). Each case reports the median of `--reps` repetitions in the page after
// one warm-up; the table gives, for each compiler, the median, minimum and
// maximum of those per-run values over `--runs` runs. Set CHROME to the Chrome
// binary if it is not in the default place of macOS.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final int at = args.indexOf('--$name');
    return at >= 0 ? args[at + 1] : fallback;
  }

  final int runs = int.parse(option('runs', '7'));
  final int reps = int.parse(option('reps', '5'));
  final List<String> suites = option('suites', 'cpu,sqlite,startup').split(',');
  final List<String> storages = option('storages', 'indexeddb,opfs').split(',');
  final int sqliteDocs = int.parse(option('sqlite-docs', '10000'));
  final List<String> compilers = option(
    'compilers',
    'dart2js,dart2wasm',
  ).split(',');
  final String? out = args.contains('--out') ? option('out', '') : null;
  final List<String> extraFlags = option(
    'chrome-flags',
    '',
  ).split(' ').where((String f) => f.isNotEmpty).toList();
  final String chrome =
      Platform.environment['CHROME'] ??
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

  final Directory build = await Directory.systemTemp.createTemp('web_cpu');
  final IOSink? log = out == null ? null : File(out).openWrite();
  try {
    final Map<String, int> sizes = await prepare(build, compilers);
    final ProcessResult version = await Process.run(chrome, <String>[
      '--version',
    ]);
    final Map<String, Object?> header = <String, Object?>{
      'chrome': '${version.stdout}'.trim(),
      'dart': Platform.version,
      'os': Platform.operatingSystemVersion,
      'cpus': Platform.numberOfProcessors,
      'sizes': sizes,
      'flags': extraFlags,
    };
    stdout.writeln(jsonEncode(header));
    log?.writeln(jsonEncode(header));

    final List<Map<String, Object?>> results = <Map<String, Object?>>[];
    for (int run = 0; run < runs; run++) {
      final List<String> order = run.isEven
          ? compilers
          : compilers.reversed.toList();
      for (final String compiler in order) {
        final List<(String, String)> pages = <(String, String)>[
          if (suites.contains('cpu')) ('page', 'suite=cpu&reps=$reps'),
          if (suites.contains('sqlite'))
            for (final String storage in storages)
              (
                'page',
                'suite=sqlite&storage=$storage&docs=$sqliteDocs&reps=$reps',
              ),
          if (suites.contains('startup')) ('startup', 'load=1'),
        ];
        for (final (String page, String query) in pages) {
          final Map<String, Object?> result = await runOnce(
            build: build,
            chrome: chrome,
            page: '${page}_$compiler.html',
            query: query,
            extraFlags: extraFlags,
            expected: page == 'startup' ? 3 : 1,
          );
          result['run'] = run;
          result['compiler'] = compiler;
          stdout.writeln(jsonEncode(result));
          log?.writeln(jsonEncode(result));
          results.add(result);
        }
      }
    }
    printTable(results, compilers);
  } finally {
    await log?.close();
    await build.delete(recursive: true);
  }
}

Future<void> run(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}

/// Compiles both pages with each compiler and writes their HTML. Returns the
/// sizes of the start-up program files, raw and gzipped.
Future<Map<String, int>> prepare(
  Directory build,
  List<String> compilers,
) async {
  for (final String asset in <String>[
    'test/browser/sqlite3.wasm',
    'test/browser/opfs/sqlite_opfs_worker.js',
  ]) {
    final File file = File(asset);
    if (!file.existsSync()) {
      throw StateError('$asset is missing: run tool/build_web_test_assets.sh');
    }
    await file.copy('${build.path}/${asset.split('/').last}');
  }
  final Map<String, int> sizes = <String, int>{};
  void size(String name) {
    final List<int> bytes = File('${build.path}/$name').readAsBytesSync();
    sizes[name] = bytes.length;
    sizes['$name.gz'] = gzip.encode(bytes).length;
  }

  for (final String page in <String>['page', 'startup']) {
    if (compilers.contains('dart2js')) {
      stdout.writeln('Compiling $page with dart2js -O2');
      await run(Platform.resolvedExecutable, <String>[
        'compile',
        'js',
        '-O2',
        '--no-source-maps',
        '-o',
        '${build.path}/$page.dart.js',
        'tool/web_cpu_benchmark/$page.dart',
      ]);
      File('${build.path}/${page}_dart2js.html').writeAsStringSync(
        '<!DOCTYPE html>\n'
        '<script>window.benchMarks = {bootStart: performance.now()};</script>\n'
        '<script src="$page.dart.js"></script>\n',
      );
      if (page == 'startup') {
        size('startup.dart.js');
      }
    }
    if (compilers.contains('dart2wasm')) {
      stdout.writeln('Compiling $page with dart2wasm -O2');
      await run(Platform.resolvedExecutable, <String>[
        'compile',
        'wasm',
        '-O2',
        '--no-source-maps',
        '-o',
        '${build.path}/$page.wasm',
        'tool/web_cpu_benchmark/$page.dart',
      ]);
      // The same loading code as the playground's bootstrap.js, with marks.
      File('${build.path}/${page}_dart2wasm.html').writeAsStringSync('''
<!DOCTYPE html>
<script type="module">
const marks = window.benchMarks = {bootStart: performance.now()};
const {compileStreaming} = await import('./$page.mjs');
marks.moduleImported = performance.now();
const app = await compileStreaming(fetch('$page.wasm'));
marks.compiled = performance.now();
const instance = await app.instantiate({});
marks.instantiated = performance.now();
instance.invokeMain();
</script>
''');
      if (page == 'startup') {
        size('startup.wasm');
        size('startup.mjs');
      }
    }
  }
  return sizes;
}

const Map<String, String> contentTypes = <String, String>{
  'html': 'text/html',
  'js': 'text/javascript',
  'mjs': 'text/javascript',
  'wasm': 'application/wasm',
};

/// Opens [page] in a new headless Chrome and waits for [expected] reports.
Future<Map<String, Object?>> runOnce({
  required Directory build,
  required String chrome,
  required String page,
  required String query,
  required List<String> extraFlags,
  required int expected,
}) async {
  final List<Map<String, Object?>> reports = <Map<String, Object?>>[];
  final Completer<Map<String, Object?>> done =
      Completer<Map<String, Object?>>();
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final HttpResponse response = request.response;
    final String path = request.uri.path;
    // Cross-origin isolation: `measureUserAgentSpecificMemory` needs it, and
    // it gives `performance.now()` its finest resolution.
    response.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      // The program files may come from the HTTP cache on a second load.
      ..set(
        'Cache-Control',
        path.endsWith('.html') ? 'no-store' : 'max-age=3600',
      );
    if (request.method == 'POST') {
      final Map<String, Object?> body =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      await response.close();
      if (path == '/error') {
        if (!done.isCompleted) {
          done.complete(<String, Object?>{...body, 'failed': true});
        }
        return;
      }
      reports.add(body);
      if (reports.length == expected && !done.isCompleted) {
        done.complete(
          expected == 1
              ? body
              : <String, Object?>{
                  'startup': <Map<String, Object?>>[...reports],
                },
        );
      }
      return;
    }
    final File file = File('${build.path}$path');
    if (path.contains('..') || !file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.headers.set(
      'Content-Type',
      contentTypes[path.split('.').last] ?? 'application/octet-stream',
    );
    await response.addStream(file.openRead());
    await response.close();
  });

  final Directory profile = await Directory.systemTemp.createTemp('web_cpu');
  final Process browser = await Process.start(chrome, <String>[
    '--headless=new',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--user-data-dir=${profile.path}',
    // Measures at once instead of at the next garbage collection.
    '--enable-blink-features=ForceEagerMeasureMemory',
    ...extraFlags,
    'http://127.0.0.1:${server.port}/$page?$query',
  ]);
  unawaited(browser.stdout.drain<void>());
  unawaited(browser.stderr.drain<void>());
  try {
    return await done.future.timeout(const Duration(minutes: 20));
  } on TimeoutException {
    return <String, Object?>{
      'page': page,
      'query': query,
      'failed': true,
      'error': 'timed out',
      'reports': reports,
    };
  } finally {
    browser.kill();
    await browser.exitCode;
    await server.close(force: true);
    // Chrome's helper processes may still write to the profile for a moment.
    for (int attempt = 0; profile.existsSync(); attempt++) {
      try {
        await profile.delete(recursive: true);
      } on FileSystemException {
        if (attempt == 20) {
          stderr.writeln('Could not delete ${profile.path}');
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}

/// The per-run values of every metric: the numbers a page reported, and for
/// start-up the times derived from its marks.
Map<String, double> metrics(Map<String, Object?> result) {
  final Map<String, double> values = <String, double>{};
  if (result['failed'] == true) {
    return values;
  }
  final Object? startup = result['startup'];
  if (startup is List) {
    const List<String> loads = <String>['cold', 'warm', 'hot'];
    for (final Map<String, Object?> load in startup.cast()) {
      final String name = 'startup_${loads[(load['load']! as int) - 1]}';
      final double mainStart = (load['mainStart']! as num).toDouble();
      values['${name}_main'] = mainStart;
      values['${name}_ready'] = (load['ready']! as num).toDouble();
      values['${name}_first_snapshot'] = (load['firstSnapshot']! as num)
          .toDouble();
      // From the first script of the page to the first snapshot: without the
      // navigation and the HTML, which do not depend on the compiler.
      values['${name}_boot_to_snapshot'] =
          values['${name}_first_snapshot']! -
          (load['bootStart']! as num).toDouble();
      final Map<String, Object?> program = (load['program']! as Map)
          .cast<String, Object?>();
      if (load['compiled'] != null) {
        // dart2wasm: streaming compilation (it overlaps the download), then
        // instantiation, then the start of main.
        final double imported = (load['moduleImported']! as num).toDouble();
        final double compiled = (load['compiled']! as num).toDouble();
        final double instantiated = (load['instantiated']! as num).toDouble();
        values['${name}_load_compile'] = compiled - imported;
        values['${name}_instantiate'] = instantiated - compiled;
        values['${name}_to_main'] = mainStart - instantiated;
      } else if (program['responseEnd'] != null) {
        // dart2js: from the end of the download to the start of main: parse,
        // compile and run the top level of the script.
        values['${name}_parse_to_main'] =
            mainStart - (program['responseEnd']! as num).toDouble();
      }
    }
    return values;
  }
  for (final MapEntry<String, Object?> entry in result.entries) {
    if (entry.value is num && entry.key != 'run') {
      values[entry.key] = (entry.value! as num).toDouble();
    }
  }
  return values;
}

void printTable(List<Map<String, Object?>> results, List<String> compilers) {
  final Map<String, Map<String, List<double>>> byMetric =
      <String, Map<String, List<double>>>{};
  for (final Map<String, Object?> result in results) {
    if (result['failed'] == true) {
      stdout.writeln('FAILED: ${jsonEncode(result)}');
    }
    metrics(result).forEach((String name, double value) {
      byMetric
          .putIfAbsent(name, () => <String, List<double>>{})
          .putIfAbsent(result['compiler']! as String, () => <double>[])
          .add(value);
    });
  }
  String fmt(double v) => v >= 100
      ? v.toStringAsFixed(0)
      : v >= 10
      ? v.toStringAsFixed(1)
      : v.toStringAsFixed(2);
  stdout
    ..writeln()
    ..writeln(
      '| Case | ${compilers.map((String c) => '$c median (min-max), n').join(' | ')} '
      '| wasm / js | Verdict |',
    )
    ..writeln('|---|${compilers.map((_) => '---:|').join()}---:|---|');
  for (final MapEntry<String, Map<String, List<double>>> metric
      in byMetric.entries) {
    final List<String> cells = <String>[];
    final Map<String, (double, double, double)> stats =
        <String, (double, double, double)>{};
    for (final String compiler in compilers) {
      final List<double> values = (metric.value[compiler] ?? <double>[])
        ..sort();
      if (values.isEmpty) {
        cells.add('-');
        continue;
      }
      final (double, double, double) s = (
        values[values.length ~/ 2],
        values.first,
        values.last,
      );
      stats[compiler] = s;
      cells.add('${fmt(s.$1)} (${fmt(s.$2)}-${fmt(s.$3)}), ${values.length}');
    }
    String ratio = '-';
    String verdict = '-';
    final (double, double, double)? js = stats['dart2js'];
    final (double, double, double)? wasm = stats['dart2wasm'];
    if (js != null && wasm != null && js.$1 > 0) {
      ratio = (wasm.$1 / js.$1).toStringAsFixed(2);
      // Every metric is a time or a size: lower is better. A difference
      // counts only when the ranges of the runs do not overlap.
      if (wasm.$3 < js.$2) {
        verdict = 'wasm lower';
      } else if (wasm.$2 > js.$3) {
        verdict = 'js lower';
      } else {
        verdict = 'within spread';
      }
    }
    stdout.writeln(
      '| ${metric.key} | ${cells.join(' | ')} | $ratio | $verdict |',
    );
  }
}
