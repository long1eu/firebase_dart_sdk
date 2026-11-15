// Logging: turning the logs of the SDK on and sending them to your own
// logger instead of standard output.
//
// The SDK writes each log line with `print`, as
//
//     D:WatchStream                 ||(548683807) Stream sending: {...}
//
// that is the level (`D` debug, `W` warning, `E` error), a colon, the tag
// (the class that logged it), padding, `||` and the message. A zone that
// overrides `print` receives these lines; this example parses them and hands
// them to a logger of its own. The format is not a stable API: match it
// loosely and keep a fallback for lines it does not recognise.
//
// See docs/guides/troubleshooting.md in the repository for the tags.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/logging.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

/// One log line of the SDK.
class SdkLogRecord {
  SdkLogRecord(this.level, this.tag, this.message);

  /// `D` (debug), `W` (warning), `E` (error), or `I` (verbose).
  final String level;

  /// The class that logged the line, for example `WatchStream`.
  final String tag;

  final String message;
}

/// `D:Tag   ||message`: level, tag, padding, separator, message (which can
/// span several lines).
final RegExp _sdkLine = RegExp(r'^([IDWE]):(\S+)\s*\|\|(.*)$', dotAll: true);

/// Runs [body] in a zone that passes every log line of the SDK to [onRecord]
/// and every other `print` on to the normal output. Everything the SDK does
/// for an instance created inside [body] (timers, network callbacks) runs in
/// this zone too, so create your instances in it.
R runWithSdkLogger<R>(
  R Function() body,
  void Function(SdkLogRecord record) onRecord,
) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        final RegExpMatch? match = _sdkLine.firstMatch(line);
        if (match == null) {
          parent.print(zone, line);
        } else {
          onRecord(SdkLogRecord(match[1]!, match[2]!, match[3]!));
        }
      },
    ),
  );
}

/// A stand-in for your own logger: counts the debug lines per tag and prints
/// warnings and errors with a prefix of its own. In an app, forward to
/// `package:logging`, a crash reporter or a file instead.
class AppLogger {
  final Map<String, int> debugLinesPerTag = <String, int>{};

  void call(SdkLogRecord record) {
    if (record.level == 'W' || record.level == 'E') {
      print(
        '[firestore ${record.level == 'W' ? 'warning' : 'error'}] '
        '${record.tag}: ${record.message}',
      );
    } else {
      debugLinesPerTag.update(
        record.tag,
        (int count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }
}

Future<void> main() async {
  final AppLogger logger = AppLogger();

  await runWithSdkLogger(() async {
    // The level is global (every instance, every package of this SDK) and per
    // isolate: set it again in a background isolate. The default is
    // LogLevel.warn: warnings and errors only.
    Firestore.setLogLevel(LogLevel.debug);

    final Firestore firestore = connect();
    final DocumentReference<Map<String, Object?>> doc = firestore.doc(
      '${scratch('logs')}/hello',
    );
    await doc.set(<String, Object?>{'greeting': 'hello'});
    await doc.get();
    print('wrote and read ${doc.path}'); // the app's own print goes through

    // A warning of the SDK: loading a bundle that cannot be parsed.
    try {
      await firestore.loadBundle(<int>[1, 2, 3]).future;
    } on FirestoreError {
      // Handled; the warning reached the logger.
    }

    // Back to the default.
    Firestore.setLogLevel(LogLevel.warn);
    await firestore.terminate();
  }, logger.call);

  final List<String> tags = logger.debugLinesPerTag.keys.toList()..sort();
  print('debug lines came from ${tags.length} tags, among them:');
  for (final String tag in <String>[
    'FirestoreClient',
    'WatchStream',
    'WriteStream',
  ]) {
    print('  $tag: ${tags.contains(tag) ? 'yes' : 'no'}');
  }
}
