import 'package:meta/meta.dart';

/// A place in the source code: the `reportLocation` of an Error Reporting event.
@immutable
final class SourceLocation {
  /// Creates a location. [lineNumber] is 1-based; 0 means unknown.
  const SourceLocation({
    required this.filePath,
    required this.lineNumber,
    required this.functionName,
  });

  /// Decodes the JSON of [toJson].
  factory SourceLocation.fromJson(Map<String, Object?> json) => SourceLocation(
    filePath: json['filePath'] as String? ?? '',
    lineNumber: _int(json['lineNumber']),
    functionName: json['functionName'] as String? ?? '',
  );

  /// The file, as the stack trace names it (`package:app/src/x.dart`).
  final String filePath;

  /// The 1-based line; 0 when unknown.
  final int lineNumber;

  /// The function or method.
  final String functionName;

  /// The JSON of the API's `SourceLocation`.
  Map<String, Object?> toJson() => <String, Object?>{
    'filePath': filePath,
    'lineNumber': lineNumber,
    'functionName': functionName,
  };

  @override
  bool operator ==(Object other) =>
      other is SourceLocation &&
      other.filePath == filePath &&
      other.lineNumber == lineNumber &&
      other.functionName == functionName;

  @override
  int get hashCode => Object.hash(filePath, lineNumber, functionName);

  @override
  String toString() => '$functionName ($filePath:$lineNumber)';
}

/// The HTTP request a server was handling when the error happened: the `httpRequest` of an Error Reporting
/// event.
@immutable
final class HttpRequestContext {
  /// Creates a request context. Every field is optional.
  const HttpRequestContext({
    this.method,
    this.url,
    this.userAgent,
    this.referrer,
    this.responseStatusCode,
    this.remoteIp,
  });

  /// Decodes the JSON of [toJson].
  factory HttpRequestContext.fromJson(Map<String, Object?> json) =>
      HttpRequestContext(
        method: json['method'] as String?,
        url: json['url'] as String?,
        userAgent: json['userAgent'] as String?,
        referrer: json['referrer'] as String?,
        responseStatusCode: json['responseStatusCode'] == null
            ? null
            : _int(json['responseStatusCode']),
        remoteIp: json['remoteIp'] as String?,
      );

  /// The method, such as `GET`.
  final String? method;

  /// The URL of the request. Leave out query parameters that hold secrets.
  final String? url;

  /// The `User-Agent` of the request.
  final String? userAgent;

  /// The `Referer` of the request.
  final String? referrer;

  /// The status the server answered with.
  final int? responseStatusCode;

  /// The IP address of the client. It is personal data in many places: send it only when you may.
  final String? remoteIp;

  /// The JSON of the API's `HttpRequestContext`, without the fields that are null.
  Map<String, Object?> toJson() => <String, Object?>{
    'method': ?method,
    'url': ?url,
    'userAgent': ?userAgent,
    'referrer': ?referrer,
    'responseStatusCode': ?responseStatusCode,
    'remoteIp': ?remoteIp,
  };

  @override
  bool operator ==(Object other) =>
      other is HttpRequestContext &&
      other.method == method &&
      other.url == url &&
      other.userAgent == userAgent &&
      other.referrer == referrer &&
      other.responseStatusCode == responseStatusCode &&
      other.remoteIp == remoteIp;

  @override
  int get hashCode => Object.hash(
    method,
    url,
    userAgent,
    referrer,
    responseStatusCode,
    remoteIp,
  );
}

/// An error, formatted and ready to be queued and sent.
///
/// `beforeSend` (see `ErrorReporter`) receives it and may return a changed copy made with [copyWith], or null to
/// drop it.
@immutable
final class ErrorEvent {
  /// Creates an event. The reporter creates them; you need this only in tests and in `beforeSend`.
  const ErrorEvent({
    required this.eventTime,
    required this.message,
    required this.fingerprint,
    this.reportLocation,
    this.user,
    this.httpRequest,
    this.fatal = false,
  });

  /// Decodes the JSON of [toStoreJson]. Throws a [FormatException] for anything else.
  factory ErrorEvent.fromStoreJson(Map<String, Object?> json) {
    final Object? time = json['eventTime'];
    final Object? message = json['message'];
    if (time is! String || message is! String) {
      throw const FormatException('Not a stored error event.');
    }
    final Object? location = json['reportLocation'];
    final Object? request = json['httpRequest'];
    return ErrorEvent(
      eventTime: DateTime.parse(time).toUtc(),
      message: message,
      fingerprint: json['fingerprint'] as String? ?? '',
      reportLocation: location is Map<String, Object?>
          ? SourceLocation.fromJson(location)
          : null,
      user: json['user'] as String?,
      httpRequest: request is Map<String, Object?>
          ? HttpRequestContext.fromJson(request)
          : null,
      fatal: json['fatal'] == true,
    );
  }

  /// When the error was recorded, in UTC.
  final DateTime eventTime;

  /// The `message` sent to Error Reporting: the header line and the stack trace, in the reporter's
  /// `MessageFormat`.
  final String message;

  /// The `reportLocation`: the first frame of the program's own code, when one is known.
  final SourceLocation? reportLocation;

  /// The `context.user`, set by `ErrorReporter.setUser`.
  final String? user;

  /// The `context.httpRequest`, given to `ErrorReporter.recordError`.
  final HttpRequestContext? httpRequest;

  /// Whether the error was recorded as fatal.
  final bool fatal;

  /// The error type and the top frame, which the reporter's rate limit counts by. Not sent.
  final String fingerprint;

  /// A copy with the given fields replaced. Pass [clearUser], [clearHttpRequest] or [clearReportLocation] to
  /// remove a field.
  ErrorEvent copyWith({
    String? message,
    SourceLocation? reportLocation,
    String? user,
    HttpRequestContext? httpRequest,
    bool clearUser = false,
    bool clearHttpRequest = false,
    bool clearReportLocation = false,
  }) => ErrorEvent(
    eventTime: eventTime,
    message: message ?? this.message,
    fingerprint: fingerprint,
    reportLocation: clearReportLocation
        ? null
        : reportLocation ?? this.reportLocation,
    user: clearUser ? null : user ?? this.user,
    httpRequest: clearHttpRequest ? null : httpRequest ?? this.httpRequest,
    fatal: fatal,
  );

  /// The `ReportedErrorEvent` JSON for [service] and [version].
  Map<String, Object?> toReportJson({
    required String service,
    String? version,
  }) {
    final Map<String, Object?> context = <String, Object?>{
      'user': ?user,
      'httpRequest': ?httpRequest?.toJson(),
      'reportLocation': ?reportLocation?.toJson(),
    };
    return <String, Object?>{
      'eventTime': eventTime.toUtc().toIso8601String(),
      'serviceContext': <String, Object?>{
        'service': service,
        'version': ?version,
      },
      'message': message,
      if (context.isNotEmpty) 'context': context,
    };
  }

  /// The JSON the stores keep.
  Map<String, Object?> toStoreJson() => <String, Object?>{
    'eventTime': eventTime.toUtc().toIso8601String(),
    'message': message,
    'fingerprint': fingerprint,
    'reportLocation': ?reportLocation?.toJson(),
    'user': ?user,
    'httpRequest': ?httpRequest?.toJson(),
    if (fatal) 'fatal': true,
  };

  @override
  bool operator ==(Object other) =>
      other is ErrorEvent &&
      other.eventTime == eventTime &&
      other.message == message &&
      other.fingerprint == fingerprint &&
      other.reportLocation == reportLocation &&
      other.user == user &&
      other.httpRequest == httpRequest &&
      other.fatal == fatal;

  @override
  int get hashCode => Object.hash(
    eventTime,
    message,
    fingerprint,
    reportLocation,
    user,
    httpRequest,
    fatal,
  );

  @override
  String toString() {
    final int end = message.indexOf('\n');
    return 'ErrorEvent(${end < 0 ? message : message.substring(0, end)})';
  }
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
