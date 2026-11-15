// A static file server for this example, on the loopback interface only.
//
//     dart run bin/serve.dart [port]      (default 8000)
//
// Serves build/web (the compiled programs and sqlite3.wasm) and web (the
// pages), in that order. Not for production: no caching headers, no
// compression, no HTTPS.

import 'dart:io';

import 'package:path/path.dart' as p;

const Map<String, String> _types = <String, String>{
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  // WebAssembly.compileStreaming refuses any other type.
  '.wasm': 'application/wasm',
  '.map': 'application/json',
};

Future<void> main(List<String> args) async {
  final int port = args.isEmpty ? 8000 : int.parse(args.first);
  final List<String> roots = <String>[
    p.absolute('build', 'web'),
    p.absolute('web'),
  ];
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port,
  );
  print('Serving http://localhost:${server.port}/ (Ctrl-C to stop)');
  await for (final HttpRequest request in server) {
    final String path = request.uri.path == '/'
        ? 'index.html'
        : p.normalize(request.uri.path.substring(1));
    File? file;
    for (final String root in roots) {
      final String candidate = p.join(root, path);
      // No path outside the roots (`..`).
      if (p.isWithin(root, candidate) && File(candidate).existsSync()) {
        file = File(candidate);
        break;
      }
    }
    final HttpResponse response = request.response;
    if (file == null) {
      response.statusCode = HttpStatus.notFound;
      response.write('Not found: ${request.uri.path}');
    } else {
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        _types[p.extension(file.path)] ?? 'application/octet-stream',
      );
      await response.addStream(file.openRead());
    }
    await response.close();
  }
}
