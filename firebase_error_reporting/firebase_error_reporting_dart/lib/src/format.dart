import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';

import 'model.dart';

/// How a Dart error becomes the `message` of an Error Reporting event.
///
/// Error Reporting parses stack traces of Java, Python, JavaScript (V8), Ruby, C#, PHP, Go and Rust, not of
/// Dart, so the reporter either rewrites the frames or sends them as Dart prints them. Both formats set the
/// `reportLocation` to the first frame of the program's own code. Which one the console handles better is
/// what `tool/error_reporting_probe.dart` finds out; until it has run, [v8] is the default
/// (docs/error_reporting_spec.md, section 7).
enum MessageFormat {
  /// The frames rewritten as V8 prints `error.stack`: `    at member (uri:line:column)`.
  v8,

  /// The stack trace as Dart prints it.
  dart,
}

/// The parts of an event that come from the error: the message, the location and the fingerprint.
@internal
@immutable
final class FormattedError {
  /// Creates the result of [formatError].
  const FormattedError(this.message, this.reportLocation, this.fingerprint);

  /// The `message`.
  final String message;

  /// The `reportLocation`, or null when no frame is known.
  final SourceLocation? reportLocation;

  /// The error type and the top frame, for the rate limit.
  final String fingerprint;
}

/// The longest header line kept, in characters.
@internal
const int maxHeaderLength = 4096;

/// The longest reason kept in the header, in characters.
const int _maxReasonLength = 200;

/// Packages whose frames are never the program's own code.
const Set<String> _libraryPackages = <String>{
  'flutter',
  'stack_trace',
  'firebase_error_reporting_dart',
};

final RegExp _obfuscatedFrame = RegExp(
  r'^\s*#\d+\s+abs\s+[0-9a-f]+',
  multiLine: true,
);

/// Formats an error of the type [typeName] whose description is [description] (its `toString()`), with the
/// [stack] where it was thrown, as [format] says.
///
/// The header is `<type>: <description>`, with `[fatal] ` after the colon when [fatal] is set and the first
/// line of [reason] in parentheses at the end. The whole message is cut to [maxBytes] bytes of UTF-8 by
/// dropping frames from the bottom; the header then says how many were dropped. An obfuscated stack trace
/// (`#00 abs … virt …` frames) is always sent as Dart printed it, with the build id it carries.
@internal
FormattedError formatError({
  required String typeName,
  required String description,
  required StackTrace? stack,
  required MessageFormat format,
  String? reason,
  bool fatal = false,
  int maxBytes = 32 * 1024,
}) {
  final String raw = stack?.toString().trimRight() ?? '';
  final bool obfuscated = _obfuscatedFrame.hasMatch(raw);
  final List<Frame> frames = obfuscated ? const <Frame>[] : _frames(stack);
  final Frame? own = _ownFrame(frames);
  final SourceLocation? location = own == null
      ? (obfuscated
            ? const SourceLocation(
                filePath: 'unknown',
                lineNumber: 0,
                functionName: '<obfuscated>',
              )
            : null)
      : SourceLocation(
          filePath: own.uri.toString(),
          lineNumber: own.line ?? 0,
          functionName: own.member ?? '<fn>',
        );
  final Frame? top = frames.isEmpty ? null : frames.first;
  final String fingerprint = top == null
      ? '$typeName|${_firstLine(raw)}'
      : '$typeName|${top.uri}:${top.line ?? 0}';

  final String header = _header(typeName, description, reason, fatal);
  final List<String> lines = obfuscated || format == MessageFormat.dart
      ? (raw.isEmpty ? const <String>[] : raw.split('\n'))
      : <String>[for (final Frame frame in frames) _v8Frame(frame)];
  return FormattedError(_fit(header, lines, maxBytes), location, fingerprint);
}

String _header(String type, String description, String? reason, bool fatal) {
  // `FormatException: bad input` already starts with its type.
  final String text = description.startsWith('$type:')
      ? description.substring(type.length + 1).trimLeft()
      : description;
  final StringBuffer out = StringBuffer('$type: ');
  if (fatal) {
    out.write('[fatal] ');
  }
  out.write(text);
  final String? firstLine = reason == null ? null : _firstLine(reason).trim();
  if (firstLine != null && firstLine.isNotEmpty) {
    out.write(
      ' (${firstLine.length <= _maxReasonLength ? firstLine : '${firstLine.substring(0, _maxReasonLength)}…'})',
    );
  }
  final String header = out.toString();
  return header.length <= maxHeaderLength
      ? header
      : '${header.substring(0, maxHeaderLength)}…';
}

/// The header and as many [lines] as fit in [maxBytes].
String _fit(String header, List<String> lines, int maxBytes) {
  int size = utf8.encode(header).length;
  int kept = 0;
  for (final String line in lines) {
    final int next = size + 1 + utf8.encode(line).length;
    // Room for the note in the header.
    if (next > maxBytes - 32) {
      break;
    }
    size = next;
    kept++;
  }
  final int dropped = lines.length - kept;
  final String first = dropped == 0
      ? header
      : '$header [$dropped frames dropped]';
  return <String>[first, ...lines.take(kept)].join('\n');
}

List<Frame> _frames(StackTrace? stack) {
  if (stack == null || stack.toString().trim().isEmpty) {
    return const <Frame>[];
  }
  try {
    final List<Frame> frames = <Frame>[
      for (final Frame frame in Trace.from(stack).frames)
        if (frame is! UnparsedFrame) frame,
    ];
    // A stack taken inside the reporter (`StackTrace.current` for an error
    // recorded without one) starts with the reporter's own frames.
    int start = 0;
    while (start < frames.length &&
        frames[start].package == 'firebase_error_reporting_dart') {
      start++;
    }
    return frames.sublist(start);
  } on Object {
    return const <Frame>[];
  }
}

Frame? _ownFrame(List<Frame> frames) {
  for (final Frame frame in frames) {
    if (!frame.isCore && !_libraryPackages.contains(frame.package)) {
      return frame;
    }
  }
  return frames.isEmpty ? null : frames.first;
}

String _v8Frame(Frame frame) {
  final String member = frame.member ?? '<fn>';
  final int? line = frame.line;
  if (line == null) {
    return '    at $member (${frame.uri})';
  }
  return '    at $member (${frame.uri}:$line:${frame.column ?? 0})';
}

String _firstLine(String text) {
  final int end = text.indexOf('\n');
  return end < 0 ? text : text.substring(0, end);
}
