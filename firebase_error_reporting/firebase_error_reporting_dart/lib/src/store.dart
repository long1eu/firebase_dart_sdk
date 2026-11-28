import 'dart:convert';

import 'package:meta/meta.dart';

import 'local_storage_stub.dart'
    if (dart.library.js_interop) 'local_storage_web.dart'
    as local_storage;
import 'model.dart';

/// What an `ErrorReporter` keeps between runs: the user, the collection switch and the queue of events not
/// sent yet.
@immutable
final class ErrorReportingState {
  /// Creates a state.
  const ErrorReportingState({
    this.user,
    this.collectionEnabled,
    this.queue = const <ErrorEvent>[],
  });

  /// The state of a reporter that never ran.
  static const ErrorReportingState empty = ErrorReportingState();

  /// Decodes the JSON of [toJson]. Events that cannot be decoded are skipped; anything that is not a state
  /// throws a [FormatException].
  factory ErrorReportingState.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Not an error reporting state.');
    }
    final Object? queue = json['queue'];
    final Object? enabled = json['collectionEnabled'];
    return ErrorReportingState(
      user: json['user'] as String?,
      collectionEnabled: enabled is bool ? enabled : null,
      queue: <ErrorEvent>[
        if (queue is List)
          for (final Object? item in queue)
            if (_decode(item) case final ErrorEvent event) event,
      ],
    );
  }

  /// The user of `ErrorReporter.setUser`, or null.
  final String? user;

  /// The value of the last `ErrorReporter.setCollectionEnabled`, or null when it was never called.
  final bool? collectionEnabled;

  /// The events not sent yet, oldest first.
  final List<ErrorEvent> queue;

  /// The JSON the stores keep.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'user': ?user,
    'collectionEnabled': ?collectionEnabled,
    'queue': <Object?>[
      for (final ErrorEvent event in queue) event.toStoreJson(),
    ],
  };

  static ErrorEvent? _decode(Object? item) {
    if (item is! Map<String, Object?>) {
      return null;
    }
    try {
      return ErrorEvent.fromStoreJson(item);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

/// Where an `ErrorReporter` keeps its [ErrorReportingState].
///
/// Three stores ship: [ErrorReportingStore.memory], [ErrorReportingStore.localStorage] in a browser, and
/// `FileErrorReportingStore` in `package:firebase_error_reporting_dart/io.dart`. A store of your own
/// implements [load] and [save].
abstract interface class ErrorReportingStore {
  /// A store that keeps the state in memory: the queue is lost when the program ends.
  factory ErrorReportingStore.memory() = _MemoryStore;

  /// A store in the browser's `localStorage` under [key]. Throws an [UnsupportedError] outside a browser.
  factory ErrorReportingStore.localStorage({
    String key = 'firebase_error_reporting',
  }) => local_storage.LocalStorageStore(key);

  /// Loads the saved state; [ErrorReportingState.empty] when nothing was saved. May throw; the reporter then
  /// starts empty.
  Future<ErrorReportingState> load();

  /// Saves [state] in place of the saved one.
  Future<void> save(ErrorReportingState state);
}

final class _MemoryStore implements ErrorReportingStore {
  ErrorReportingState _state = ErrorReportingState.empty;

  @override
  Future<ErrorReportingState> load() async => _state;

  @override
  Future<void> save(ErrorReportingState state) async {
    _state = state;
  }
}

/// Encodes [state] for a store that keeps text.
@internal
String encodeState(ErrorReportingState state) => jsonEncode(state.toJson());

/// Decodes the text of [encodeState].
@internal
ErrorReportingState decodeState(String text) =>
    ErrorReportingState.fromJson(jsonDecode(text));
