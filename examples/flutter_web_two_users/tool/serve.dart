// A static file server for build/web on the loopback interface, for run.sh.
// It sends .wasm as application/wasm (which WebAssembly.instantiateStreaming
// needs) and .mjs as JavaScript. Not for anything but trying the example.
//
//   dart run tool/serve.dart <port> [directory]

import 'dart:io';

Future<void> main(List<String> args) async {
  final int port = int.parse(args.isEmpty ? '8203' : args[0]);
  final Directory root = Directory(args.length > 1 ? args[1] : 'build/web');
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port,
  );
  stdout.writeln('Serving ${root.path} on http://127.0.0.1:$port/');
  await for (final HttpRequest request in server) {
    String path = request.uri.path;
    if (path.endsWith('/')) {
      path = '${path}index.html';
    }
    final File file = File('${root.path}$path');
    if (path.contains('..') || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    request.response.headers
      ..contentType = _type(path)
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }
}

ContentType _type(String path) {
  final String extension = path.substring(path.lastIndexOf('.') + 1);
  return switch (extension) {
    'html' => ContentType.html,
    'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
    'wasm' => ContentType('application', 'wasm'),
    'json' => ContentType.json,
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    'png' => ContentType('image', 'png'),
    'otf' => ContentType('font', 'otf'),
    'ttf' => ContentType('font', 'ttf'),
    _ => ContentType.binary,
  };
}
