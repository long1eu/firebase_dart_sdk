// Measures the two storages of example/sqlite_database_web.dart (IndexedDB
// and OPFS) in headless Chrome: memory and read latency of a cache of N
// documents of about 1 KB, compiled with dart2js and with dart2wasm.
//
// From cloud_firestore/cloud_firestore_dart, after
// tool/build_web_test_assets.sh (repository root) fetched sqlite3.wasm and
// compiled the OPFS worker:
//
//   dart run tool/web_storage_benchmark/run.dart [--docs 10000,100000]
//       [--storages indexeddb,opfs] [--compilers dart2js,dart2wasm]
//
// No emulator is needed: the cache is filled from a bundle, offline. Each
// measurement runs in a new Chrome with an empty profile; the page is served
// with cross-origin isolation, which `performance.measureUserAgentSpecificMemory`
// needs (the storages themselves do not). Prints one JSON line per run and a
// table at the end. Set CHROME to the Chrome binary if it is not in the
// default place of macOS.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  List<String> option(String name, String fallback) {
    final int at = args.indexOf('--$name');
    return (at >= 0 ? args[at + 1] : fallback).split(',');
  }

  final List<int> docCounts = option(
    'docs',
    '10000,100000',
  ).map(int.parse).toList();
  final List<String> storages = option('storages', 'indexeddb,opfs');
  final List<String> compilers = option('compilers', 'dart2js,dart2wasm');
  final String chrome =
      Platform.environment['CHROME'] ??
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

  final Directory build = await Directory.systemTemp.createTemp('web_bench');
  try {
    await prepare(build, compilers);
    final List<Map<String, Object?>> results = <Map<String, Object?>>[];
    for (final int docs in docCounts) {
      for (final String compiler in compilers) {
        for (final String storage in storages) {
          final Map<String, Object?> result = await runOnce(
            build: build,
            chrome: chrome,
            compiler: compiler,
            storage: storage,
            docs: docs,
          );
          stdout.writeln(jsonEncode(result));
          results.add(result);
        }
      }
    }
    printTable(results);
  } finally {
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

Future<void> prepare(Directory build, List<String> compilers) async {
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
  if (compilers.contains('dart2js')) {
    stdout.writeln('Compiling with dart2js');
    await run(Platform.resolvedExecutable, <String>[
      'compile',
      'js',
      '-O2',
      '-o',
      '${build.path}/page.dart.js',
      'tool/web_storage_benchmark/page.dart',
    ]);
    File('${build.path}/dart2js.html').writeAsStringSync(
      '<!DOCTYPE html><script defer src="page.dart.js"></script>',
    );
  }
  if (compilers.contains('dart2wasm')) {
    stdout.writeln('Compiling with dart2wasm');
    await run(Platform.resolvedExecutable, <String>[
      'compile',
      'wasm',
      '-O2',
      '-o',
      '${build.path}/page.wasm',
      'tool/web_storage_benchmark/page.dart',
    ]);
    File('${build.path}/dart2wasm.html').writeAsStringSync('''
<!DOCTYPE html>
<script type="module">
import {compileStreaming} from './page.mjs';
const app = await compileStreaming(fetch('page.wasm'));
const instance = await app.instantiate({});
instance.invokeMain();
</script>''');
  }
}

const Map<String, String> contentTypes = <String, String>{
  'html': 'text/html',
  'js': 'text/javascript',
  'mjs': 'text/javascript',
  'wasm': 'application/wasm',
};

Future<Map<String, Object?>> runOnce({
  required Directory build,
  required String chrome,
  required String compiler,
  required String storage,
  required int docs,
}) async {
  final Completer<Map<String, Object?>> done =
      Completer<Map<String, Object?>>();
  Map<String, Object?> filled = <String, Object?>{};
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final HttpResponse response = request.response;
    response.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set('Cache-Control', 'no-store');
    final String path = request.uri.path;
    if (request.method == 'POST') {
      final Map<String, Object?> body =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      await response.close();
      if (path == '/filled') {
        filled = body;
      } else if (!done.isCompleted) {
        done.complete(<String, Object?>{
          ...body,
          ...filled,
          if (path == '/error') 'failed': true,
        });
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

  final Directory profile = await Directory.systemTemp.createTemp('web_bench');
  final String query = 'storage=$storage&docs=$docs&phase=fill';
  final Process browser = await Process.start(chrome, <String>[
    '--headless=new',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--user-data-dir=${profile.path}',
    // Measures at once instead of at the next garbage collection.
    '--enable-blink-features=ForceEagerMeasureMemory',
    'http://127.0.0.1:${server.port}/$compiler.html?$query',
  ]);
  unawaited(browser.stdout.drain<void>());
  unawaited(browser.stderr.drain<void>());
  try {
    return await done.future.timeout(const Duration(minutes: 20));
  } on TimeoutException {
    return <String, Object?>{
      'storage': storage,
      'docs': docs,
      'compiler': compiler,
      'failed': true,
      'error': 'timed out',
      ...filled,
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

String mb(Object? memory, String key) {
  if (memory is! Map) {
    return '?';
  }
  return ((memory[key]! as num) / (1 << 20)).toStringAsFixed(0);
}

void printTable(List<Map<String, Object?>> results) {
  stdout
    ..writeln()
    ..writeln(
      '| Documents | Compiler | Storage | Open | First read | Read by id '
      '(median; max) | Filtered query (scan) | Full scan | Memory open '
      '(workers) | Memory after scan | Fill |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final Map<String, Object?> r in results) {
    if (r['failed'] == true) {
      stdout.writeln(
        '| ${r['docs']} | ${r['compiler']} | ${r['storage']} | '
        'failed: ${r['error']} |',
      );
      continue;
    }
    stdout.writeln(
      '| ${r['docs']} | ${r['compiler']} | ${r['storage']} | '
      '${r['openMs']} ms | ${r['firstReadMs']} ms | '
      '${(r['pointMedianMs']! as num).toStringAsFixed(2)} ms; '
      '${(r['pointMaxMs']! as num).toStringAsFixed(1)} ms | '
      '${r['filteredMs']} ms | ${r['scanMs']} ms | '
      '${mb(r['memoryOpen'], 'total')} MB (${mb(r['memoryOpen'], 'workers')}) | '
      '${mb(r['memoryAfterScan'], 'total')} MB | '
      '${((r['fillMs']! as num) / 1000).toStringAsFixed(0)} s |',
    );
  }
}
