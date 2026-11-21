// Checks that libraries meant for the web reach neither dart:io nor dart:ffi. Neither dart2js nor dart2wasm
// rejects those imports (the code fails at run time), so a web compile does not catch them.
//
// It follows the import and export directives from each entry library through the package and its
// dependencies (resolved with the package's .dart_tool/package_config.json, so run `dart pub get` first). For
// a conditional import it takes the branch the web uses: the first `if (dart.library.js_interop)`,
// `if (dart.library.html)` or `if (dart.library.js)` branch, else the default URI.
//
// Usage, from the repository root:
//   dart tool/check_web_imports.dart <package dir> [entry library...]
//
// Entry libraries are paths relative to the package directory; the default is lib/<package name>.dart.
// Exits 1 and prints the chain of imports when a forbidden library is reached, 2 on a usage error.
import 'dart:convert';
import 'dart:io';

const Set<String> _forbidden = <String>{'dart:io', 'dart:ffi'};
const Set<String> _webConditions = <String>{
  'dart.library.js_interop',
  'dart.library.html',
  'dart.library.js',
};

final RegExp _directive = RegExp(
  r'''^[ \t]*(?:import|export)\s+(['"])(.+?)\1((?:\s+if\s*\([^)]*\)\s*(['"]).+?\4)*)''',
  multiLine: true,
);
final RegExp _branch = RegExp(r'''if\s*\(\s*([\w.]+)[^)]*\)\s*(['"])(.+?)\2''');

/// The URIs that [source] imports or exports when compiled for the web.
List<String> webDirectives(String source) {
  final List<String> uris = <String>[];
  for (final RegExpMatch match in _directive.allMatches(source)) {
    String uri = match.group(2)!;
    for (final RegExpMatch branch in _branch.allMatches(match.group(3) ?? '')) {
      if (_webConditions.contains(branch.group(1))) {
        uri = branch.group(3)!;
        break;
      }
    }
    uris.add(uri);
  }
  return uris;
}

/// Maps the package names of [packageDir] to the directories their `package:` URIs resolve to.
Map<String, Uri> packageRoots(Directory packageDir) {
  final File config = File('${packageDir.path}/.dart_tool/package_config.json');
  if (!config.existsSync()) {
    throw StateError(
      '${config.path} not found: run `dart pub get` in ${packageDir.path} first.',
    );
  }
  final Map<String, Object?> json =
      jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  final Uri base = config.absolute.uri;
  final Map<String, Uri> roots = <String, Uri>{};
  for (final Object? entry in json['packages']! as List<Object?>) {
    final Map<String, Object?> package = entry! as Map<String, Object?>;
    Uri root = base.resolve(package['rootUri']! as String);
    if (!root.path.endsWith('/')) {
      root = root.replace(path: '${root.path}/');
    }
    final String packageUri = (package['packageUri'] as String?) ?? 'lib/';
    roots[package['name']! as String] = root.resolve(packageUri);
  }
  return roots;
}

/// For each forbidden library reached from [entries], the chain of files that leads to it (empty when the
/// libraries are clean).
Map<String, List<String>> forbiddenFrom(
  List<Uri> entries,
  Map<String, Uri> roots,
) {
  final Map<Uri, Uri?> parents = <Uri, Uri?>{
    for (final Uri entry in entries) entry: null,
  };
  final List<Uri> pending = List<Uri>.of(entries);
  final Map<String, List<String>> found = <String, List<String>>{};
  while (pending.isNotEmpty) {
    final Uri file = pending.removeLast();
    for (final String uri in webDirectives(
      File.fromUri(file).readAsStringSync(),
    )) {
      if (uri.startsWith('dart:')) {
        if (_forbidden.contains(uri) && !found.containsKey(uri)) {
          found[uri] = _chain(file, parents)..add(uri);
        }
        continue;
      }
      final Uri? target = _resolve(file, uri, roots);
      if (target != null && !parents.containsKey(target)) {
        parents[target] = file;
        pending.add(target);
      }
    }
  }
  return found;
}

Uri? _resolve(Uri from, String uri, Map<String, Uri> roots) {
  if (!uri.startsWith('package:')) {
    return from.resolve(uri);
  }
  final String path = uri.substring('package:'.length);
  final int slash = path.indexOf('/');
  final Uri? root = roots[path.substring(0, slash)];
  if (root == null) {
    throw StateError(
      '$from imports $uri, which the package config does not know.',
    );
  }
  return root.resolve(path.substring(slash + 1));
}

List<String> _chain(Uri file, Map<Uri, Uri?> parents) {
  final List<String> chain = <String>[];
  for (Uri? at = file; at != null; at = parents[at]) {
    chain.insert(0, at.toFilePath());
  }
  return chain;
}

void main(List<String> args) {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln(
      'Usage: dart tool/check_web_imports.dart <package dir> [entry library...]',
    );
    exit(2);
  }
  final Directory packageDir = Directory(args.first).absolute;
  final File pubspec = File('${packageDir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('${packageDir.path} has no pubspec.yaml.');
    exit(2);
  }
  final String name = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync())!.group(1)!;
  final List<String> entryPaths = args.length > 1
      ? args.sublist(1)
      : <String>['lib/$name.dart'];
  final List<Uri> entries = <Uri>[];
  for (final String path in entryPaths) {
    final File file = File('${packageDir.path}/$path');
    if (!file.existsSync()) {
      stderr.writeln('${file.path} does not exist.');
      exit(2);
    }
    entries.add(file.uri);
  }

  final Map<String, List<String>> found = forbiddenFrom(
    entries,
    packageRoots(packageDir),
  );
  if (found.isEmpty) {
    stdout.writeln(
      'OK: ${entryPaths.join(', ')} of $name reach neither dart:io nor dart:ffi on the web.',
    );
    return;
  }
  for (final MapEntry<String, List<String>> entry in found.entries) {
    stdout.writeln('${entry.key} is reached on the web through:');
    for (final String step in entry.value) {
      stdout.writeln('  $step');
    }
  }
  exit(1);
}
