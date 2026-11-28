import 'dart:convert';

import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:firebase_error_reporting_dart/src/format.dart';
import 'package:test/test.dart';

import 'fakes.dart';

FormattedError _format(
  StackTrace? stack, {
  MessageFormat format = MessageFormat.v8,
  String type = 'StateError',
  String description = 'Bad state: no element',
  String? reason,
  bool fatal = false,
  int maxBytes = 32 * 1024,
}) => formatError(
  typeName: type,
  description: description,
  stack: stack,
  format: format,
  reason: reason,
  fatal: fatal,
  maxBytes: maxBytes,
);

void main() {
  group('V8 format', () {
    test('rewrites each frame as V8 prints error.stack', () {
      final FormattedError result = _format(appStack);
      expect(
        result.message,
        'StateError: Bad state: no element\n'
        '    at ListBase.first (dart:collection/list.dart:79:5)\n'
        '    at NoteRepository.load (package:notes/src/repository.dart:42:7)\n'
        '    at NoteListModel.refresh (package:notes/src/model.dart:88:12)\n'
        '    at main (package:notes/main.dart:12:3)',
      );
    });

    test(
      'the location is the first frame outside dart: and package:flutter',
      () {
        expect(
          _format(appStack).reportLocation,
          const SourceLocation(
            filePath: 'package:notes/src/repository.dart',
            lineNumber: 42,
            functionName: 'NoteRepository.load',
          ),
        );
        final StackTrace flutter = StackTrace.fromString('''
#0      State.setState (package:flutter/src/widgets/framework.dart:1192:30)
#1      Page.tap (package:notes/page.dart:9:3)
''');
        expect(_format(flutter).reportLocation!.functionName, 'Page.tap');
      },
    );

    test('the reporter\'s own leading frames are skipped', () {
      final StackTrace own = StackTrace.fromString('''
#0      ErrorReporter._record (package:firebase_error_reporting_dart/src/reporter.dart:300:7)
#1      ErrorReporter.recordError (package:firebase_error_reporting_dart/src/reporter.dart:200:12)
#2      main (package:notes/main.dart:5:3)
''');
      final FormattedError result = _format(own);
      expect(result.message.split('\n').skip(1), <String>[
        '    at main (package:notes/main.dart:5:3)',
      ]);
      expect(result.fingerprint, 'StateError|package:notes/main.dart:5');
    });

    test('a browser stack trace is rewritten too', () {
      final StackTrace chrome = StackTrace.fromString('''
Error: boom
    at Object.load (http://localhost:8080/main.dart.js:120:15)
    at main (http://localhost:8080/main.dart.js:9:3)
''');
      final FormattedError result = _format(chrome);
      expect(
        result.message,
        contains(
          '    at Object.load (http://localhost:8080/main.dart.js:120:15)',
        ),
      );
    });
  });

  group('Dart format', () {
    test('keeps the trace as Dart printed it, with the location', () {
      final FormattedError result = _format(
        appStack,
        format: MessageFormat.dart,
      );
      expect(
        result.message,
        'StateError: Bad state: no element\n${appStack.toString().trimRight()}',
      );
      expect(result.reportLocation!.lineNumber, 42);
    });
  });

  group('header', () {
    test('a description that starts with its type is not repeated', () {
      expect(
        _format(
          appStack,
          type: 'FormatException',
          description: 'FormatException: bad input',
        ).message.split('\n').first,
        'FormatException: bad input',
      );
    });

    test(
      'fatal goes after the colon, the first line of the reason at the end',
      () {
        expect(
          _format(
            appStack,
            fatal: true,
            reason: 'while syncing\nmore detail',
          ).message.split('\n').first,
          'StateError: [fatal] Bad state: no element (while syncing)',
        );
      },
    );

    test('a long reason and a long description are cut', () {
      final String header = _format(
        appStack,
        description: 'x' * 10000,
        reason: 'r' * 1000,
      ).message.split('\n').first;
      expect(header.length, lessThanOrEqualTo(maxHeaderLength + 1));
      final String withReason = _format(
        appStack,
        reason: 'r' * 1000,
      ).message.split('\n').first;
      expect(withReason, endsWith('${'r' * 200}…)'));
    });
  });

  test('the message is cut to the size, dropping frames from the bottom', () {
    final String frames = List<String>.generate(
      400,
      (int i) => '#$i      f$i (package:notes/f.dart:${i + 1}:1)',
    ).join('\n');
    final FormattedError result = _format(
      StackTrace.fromString(frames),
      maxBytes: 4096,
    );
    expect(utf8.encode(result.message).length, lessThanOrEqualTo(4096));
    final List<String> lines = result.message.split('\n');
    expect(
      lines.first,
      matches(
        RegExp(r'^StateError: Bad state: no element \[\d+ frames dropped\]$'),
      ),
    );
    final int dropped = int.parse(
      RegExp(r'\[(\d+) frames').firstMatch(lines.first)!.group(1)!,
    );
    expect(lines.length - 1 + dropped, 400);
    expect(lines[1], '    at f0 (package:notes/f.dart:1:1)');
  });

  test('an obfuscated trace is sent as printed, with the build id', () {
    final StackTrace obfuscated = StackTrace.fromString('''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
build_id: '8deece9b0e5bf1aa541b5a91e171282e'
#00 abs 00007f1c2b0d1e2f virt 000000000002de2f _kDartIsolateSnapshotInstructions+0x28e2f
#01 abs 00007f1c2b0c0a11 virt 000000000001ca11 _kDartIsolateSnapshotInstructions+0x17a11
''');
    final FormattedError result = _format(obfuscated);
    expect(
      result.message,
      contains("build_id: '8deece9b0e5bf1aa541b5a91e171282e'"),
    );
    expect(result.message, contains('#00 abs 00007f1c2b0d1e2f'));
    expect(result.reportLocation!.functionName, '<obfuscated>');
  });

  test('no stack: the header alone and no location', () {
    final FormattedError result = _format(null);
    expect(result.message, 'StateError: Bad state: no element');
    expect(result.reportLocation, isNull);
  });

  test('the fingerprint is the type and the top frame', () {
    expect(
      _format(appStack).fingerprint,
      'StateError|dart:collection/list.dart:79',
    );
  });
}
