import 'package:firebase_remote_config_dart/src/bounded.dart';
import 'package:firebase_remote_config_dart/src/json_guard.dart';

/// The longest text after a `{` without its `}`, in characters (5.11 rule 7).
const int maxRealtimeMessage = 16 * 1024;

/// The cap on `retryIntervalSeconds` (5.9 step 3; iOS clamps to 24 h).
const int maxRetryIntervalSeconds = 86400;

/// One message of the realtime stream, with its known fields checked.
final class RealtimeMessage {
  /// Creates a message.
  const RealtimeMessage({
    this.featureDisabled = false,
    this.latestTemplateVersion,
    this.retryIntervalSeconds,
  });

  /// `featureDisabled == true`.
  final bool featureDisabled;

  /// `latestTemplateVersionNumber`, when present.
  final int? latestTemplateVersion;

  /// `retryIntervalSeconds` when it is a positive integer, capped at [maxRetryIntervalSeconds]; a
  /// malformed or non-positive value is null.
  final int? retryIntervalSeconds;
}

/// What the framer found in the text it was given.
sealed class FramerEvent {
  const FramerEvent();
}

/// A valid message.
final class FramedMessage extends FramerEvent {
  /// Creates the event for [message].
  const FramedMessage(this.message);

  /// The message.
  final RealtimeMessage message;
}

/// A slice that is not a JSON object, or has a known field of the wrong type.
final class FramedInvalid extends FramerEvent {
  /// Creates the event.
  const FramedInvalid();
}

/// More than [maxRealtimeMessage] characters after a `{` without a `}`: the connection must end as a
/// failure. The framer accepts no more text.
final class FramedOverflow extends FramerEvent {
  /// Creates the event.
  const FramedOverflow();
}

/// Splits the decoded text of the realtime body into messages (5.9 Framing).
///
/// Text before a `{` is dropped as it arrives; a message is the text from `{` to the next `}` (messages
/// are flat); every complete message of a chunk is returned; a partial one waits for more text.
final class RealtimeFramer {
  final StringBuffer _pending = StringBuffer();
  bool _inMessage = false;
  bool _overflowed = false;

  /// Adds a chunk of decoded text and returns the events it completes, in order.
  List<FramerEvent> add(String chunk) {
    final List<FramerEvent> events = <FramerEvent>[];
    if (_overflowed) {
      return events;
    }
    int index = 0;
    while (index < chunk.length) {
      if (!_inMessage) {
        final int open = chunk.indexOf('{', index);
        if (open < 0) {
          break;
        }
        _inMessage = true;
        _pending.clear();
        index = open;
      }
      final int close = chunk.indexOf('}', index);
      final int end = close < 0 ? chunk.length : close + 1;
      // The text between the braces, so far.
      final int content =
          _pending.length + (end - index) - 1 - (close < 0 ? 0 : 1);
      if (content > maxRealtimeMessage) {
        _overflowed = true;
        _pending.clear();
        events.add(const FramedOverflow());
        return events;
      }
      _pending.write(chunk.substring(index, end));
      index = end;
      if (close >= 0) {
        _inMessage = false;
        events.add(parseRealtimeMessage(_pending.toString()));
        _pending.clear();
      }
    }
    return events;
  }
}

/// Reads one `{...}` slice: a [FramedMessage], or [FramedInvalid] when it is not a JSON object or a known
/// field has the wrong type. A malformed `retryIntervalSeconds` is ignored, not invalid.
FramerEvent parseRealtimeMessage(String slice) {
  final Object? decoded;
  try {
    decoded = decodeGuardedText(slice);
  } on FormatException {
    return const FramedInvalid();
  }
  final Map<String, Object?>? json = asObject(decoded);
  if (json == null) {
    return const FramedInvalid();
  }
  final Object? disabled = json['featureDisabled'];
  // Present means typed: `"featureDisabled": null` is the wrong type, like any other non-bool.
  if (json.containsKey('featureDisabled') && disabled is! bool) {
    return const FramedInvalid();
  }
  if (disabled == true) {
    // Step 1 of 5.9: the rest of the message is ignored, so a malformed field cannot hide it.
    return const FramedMessage(RealtimeMessage(featureDisabled: true));
  }
  int? version;
  if (json.containsKey('latestTemplateVersionNumber')) {
    version = parseBoundedInt(
      json['latestTemplateVersionNumber'],
      min: 0,
      max: maxSafeInteger,
    );
    if (version == null) {
      return const FramedInvalid();
    }
  }
  return FramedMessage(
    RealtimeMessage(
      latestTemplateVersion: version,
      retryIntervalSeconds: _retryInterval(json['retryIntervalSeconds']),
    ),
  );
}

/// `retryIntervalSeconds` (5.9 step 3): a positive integer, at most [maxRetryIntervalSeconds]; a larger
/// one, even past 2^53 − 1, becomes [maxRetryIntervalSeconds]. Anything else is null. Leading zeros of
/// a digit string are dropped first, so `"00000000000000000600"` is 600.
int? _retryInterval(Object? raw) {
  final Object? value = raw is String ? _withoutLeadingZeros(raw) : raw;
  final int? seconds = parseBoundedInt(value, min: 1, max: maxSafeInteger);
  if (seconds != null) {
    return seconds > maxRetryIntervalSeconds
        ? maxRetryIntervalSeconds
        : seconds;
  }
  return _isHugeInteger(value) ? maxRetryIntervalSeconds : null;
}

/// [text] without its leading `0`s; all zeros become `"0"`.
String _withoutLeadingZeros(String text) {
  int start = 0;
  while (start < text.length - 1 && text.codeUnitAt(start) == 0x30) {
    start++;
  }
  return text.substring(start);
}

/// True for a whole number above 2^53 − 1: a finite JSON number, or a digit string (without leading
/// zeros) too long for [parseBoundedInt].
bool _isHugeInteger(Object? value) {
  if (value is num) {
    return value.isFinite &&
        value == value.truncateToDouble() &&
        value > maxSafeInteger;
  }
  if (value is String && value.length > 16) {
    for (final int unit in value.codeUnits) {
      if (unit < 0x30 || unit > 0x39) {
        return false;
      }
    }
    return true;
  }
  return false;
}
