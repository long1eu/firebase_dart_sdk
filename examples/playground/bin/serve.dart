// A static file server for the built playground, on the loopback interface
// only.
//
//     dart run bin/serve.dart [port] [prefix]
//
// Serves build/web (run ./build.sh first) at http://localhost:<port><prefix>.
// The default port is 8000 and the default prefix is `/`; pass a prefix such
// as `/firebase_dart_sdk/` to try the page under a sub-path, as GitHub Pages
// serves a project site. Not for production: no caching headers, no
// compression, no HTTPS.

import 'dart:io';

const Map<String, String> _types = <String, String>{
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  // WebAssembly.compileStreaming refuses any other type.
  '.wasm': 'application/wasm',
};

Future<void> main(List<String> args) async {
  final int port = args.isEmpty ? 8000 : int.parse(args[0]);
  final String prefix = args.length < 2 ? '/' : args[1];
  final Directory root = Directory('build/web').absolute;
  if (!root.existsSync()) {
    stderr.writeln('No build/web: run ./build.sh first.');
    exit(1);
  }
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port,
  );
  print('Serving http://localhost:${server.port}$prefix (Ctrl-C to stop)');
  await for (final HttpRequest request in server) {
    final HttpResponse response = request.response;
    final String path = request.uri.path;
    File? file;
    if (path.startsWith(prefix)) {
      String relative = path.substring(prefix.length);
      if (relative.isEmpty || relative.endsWith('/')) {
        relative = '${relative}index.html';
      }
      // No path outside the root.
      if (!relative.split('/').contains('..')) {
        final File candidate = File('${root.path}/$relative');
        if (candidate.existsSync()) {
          file = candidate;
        }
      }
    }
    if (file == null) {
      response.statusCode = HttpStatus.notFound;
      response.write('Not found: $path');
    } else {
      final int dot = file.path.lastIndexOf('.');
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        _types[file.path.substring(dot)] ?? 'application/octet-stream',
      );
      await response.addStream(file.openRead());
    }
    await response.close();
  }
}
