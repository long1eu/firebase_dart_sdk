import 'dart:convert';

import 'package:meta/meta.dart';

import 'client_identity.dart';
import 'validation.dart';

/// The consent the user gave, as set through `FirebaseAnalytics.setConsent`. Null means never set.
@internal
@immutable
class ConsentState {
  const ConsentState({
    this.adUserData,
    this.adPersonalization,
    this.analyticsStorage,
    this.adStorage,
  });

  final bool? adUserData;
  final bool? adPersonalization;
  final bool? analyticsStorage;
  final bool? adStorage;

  ConsentState merge({
    bool? adUserData,
    bool? adPersonalization,
    bool? analyticsStorage,
    bool? adStorage,
  }) => ConsentState(
    adUserData: adUserData ?? this.adUserData,
    adPersonalization: adPersonalization ?? this.adPersonalization,
    analyticsStorage: analyticsStorage ?? this.analyticsStorage,
    adStorage: adStorage ?? this.adStorage,
  );

  /// The `consent` field of a request, or null when neither advertising consent was set: without the field,
  /// Google Analytics keeps the consent it already has for the client (protocol §6).
  Map<String, String>? toRequest() {
    if (adUserData == null && adPersonalization == null) {
      return null;
    }
    return <String, String>{
      if (adUserData != null)
        'ad_user_data': adUserData! ? 'GRANTED' : 'DENIED',
      if (adPersonalization != null)
        'ad_personalization': adPersonalization! ? 'GRANTED' : 'DENIED',
    };
  }

  Map<String, Object> toJson() => <String, Object>{
    'adUserData': ?adUserData,
    'adPersonalization': ?adPersonalization,
    'analyticsStorage': ?analyticsStorage,
    'adStorage': ?adStorage,
  };

  static ConsentState fromJson(Object? json) {
    if (json is! Map) {
      return const ConsentState();
    }
    bool? flag(String key) => json[key] is bool ? json[key] as bool : null;
    return ConsentState(
      adUserData: flag('adUserData'),
      adPersonalization: flag('adPersonalization'),
      analyticsStorage: flag('analyticsStorage'),
      adStorage: flag('adStorage'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConsentState &&
      other.adUserData == adUserData &&
      other.adPersonalization == adPersonalization &&
      other.analyticsStorage == analyticsStorage &&
      other.adStorage == adStorage;

  @override
  int get hashCode =>
      Object.hash(adUserData, adPersonalization, analyticsStorage, adStorage);
}

/// The state that survives a restart, except the queue.
@internal
class AnalyticsState {
  AnalyticsState({
    this.clientId,
    this.userId,
    Map<String, String>? userProperties,
    Map<String, Object>? defaultParameters,
    this.consent = const ConsentState(),
    this.collectionEnabled,
    this.sessionId,
    this.lastEventMicros,
  }) : userProperties = userProperties ?? <String, String>{},
       defaultParameters = defaultParameters ?? <String, Object>{};

  String? clientId;
  String? userId;
  Map<String, String> userProperties;
  Map<String, Object> defaultParameters;
  ConsentState consent;

  /// The persisted collection switch; null means the constructor's default applies.
  bool? collectionEnabled;

  /// The id of the current session: its start time in Unix seconds.
  int? sessionId;

  /// The time of the last event logged, in Unix microseconds.
  int? lastEventMicros;

  String encode() => jsonEncode(<String, Object>{
    'v': 1,
    'clientId': ?clientId,
    'userId': ?userId,
    if (userProperties.isNotEmpty) 'userProperties': userProperties,
    if (defaultParameters.isNotEmpty) 'defaultParameters': defaultParameters,
    'consent': consent.toJson(),
    'collectionEnabled': ?collectionEnabled,
    'sessionId': ?sessionId,
    'lastEventMicros': ?lastEventMicros,
  });

  /// Reads a stored state. The store is untrusted: each field that does not pass the checks the public
  /// methods apply is dropped, and [warn] is told.
  static AnalyticsState decode(String? text, void Function(String) warn) {
    if (text == null) {
      return AnalyticsState();
    }
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      warn('The stored analytics state could not be read; starting empty.');
      return AnalyticsState();
    }
    if (json is! Map) {
      warn('The stored analytics state could not be read; starting empty.');
      return AnalyticsState();
    }
    final AnalyticsState state = AnalyticsState();
    final Object? clientId = json['clientId'];
    if (clientId is String && ClientIdentity.isValid(clientId)) {
      state.clientId = clientId;
    } else if (clientId != null) {
      warn('The stored client id is not valid; a new one is made.');
    }
    final Object? userId = json['userId'];
    if (userId is String) {
      try {
        checkUserId(userId);
        state.userId = userId;
      } on Object {
        warn('The stored user id is not valid; it was dropped.');
      }
    }
    final Object? properties = json['userProperties'];
    if (properties is Map) {
      properties.forEach((Object? name, Object? value) {
        if (name is String && value is String) {
          try {
            checkUserProperty(name, value);
            state.userProperties[name] = value;
            return;
          } on Object {
            // Reported below.
          }
        }
        warn('A stored user property is not valid; it was dropped.');
      });
    }
    final Object? defaults = json['defaultParameters'];
    if (defaults is Map) {
      try {
        state.defaultParameters = normalizeParameters(
          defaults.cast<String, Object?>(),
        );
      } on Object {
        warn('The stored default parameters are not valid; they were dropped.');
      }
    }
    state.consent = ConsentState.fromJson(json['consent']);
    final Object? enabled = json['collectionEnabled'];
    if (enabled is bool) {
      state.collectionEnabled = enabled;
    }
    final Object? sessionId = json['sessionId'];
    final Object? last = json['lastEventMicros'];
    if (sessionId is int && sessionId > 0 && last is int && last > 0) {
      state.sessionId = sessionId;
      state.lastEventMicros = last;
    }
    return state;
  }
}

/// What a request says about the user: the same for every event in it.
@internal
@immutable
class EventContext {
  const EventContext({
    this.userId,
    this.userProperties = const <String, String>{},
    this.consent,
  });

  final String? userId;
  final Map<String, String> userProperties;
  final Map<String, String>? consent;

  Map<String, Object> toJson() => <String, Object>{
    'u': ?userId,
    if (userProperties.isNotEmpty) 'p': userProperties,
    'c': ?consent,
  };

  static EventContext? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? userId = json['u'];
    final Object? properties = json['p'] ?? const <String, String>{};
    final Object? consent = json['c'];
    if (userId != null && userId is! String) {
      return null;
    }
    if (properties is! Map || (consent != null && consent is! Map)) {
      return null;
    }
    try {
      checkUserId(userId as String?);
      final Map<String, String> checked = <String, String>{};
      for (final MapEntry<Object?, Object?> entry in properties.entries) {
        final Object? name = entry.key;
        final Object? value = entry.value;
        if (name is! String || value is! String) {
          return null;
        }
        checkUserProperty(name, value);
        checked[name] = value;
      }
      Map<String, String>? checkedConsent;
      if (consent is Map) {
        checkedConsent = <String, String>{};
        for (final MapEntry<Object?, Object?> entry in consent.entries) {
          if ((entry.key != 'ad_user_data' &&
                  entry.key != 'ad_personalization') ||
              (entry.value != 'GRANTED' && entry.value != 'DENIED')) {
            return null;
          }
          checkedConsent[entry.key as String] = entry.value as String;
        }
      }
      return EventContext(
        userId: userId,
        userProperties: checked,
        consent: checkedConsent,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is EventContext &&
      other.userId == userId &&
      _mapEquals(other.userProperties, userProperties) &&
      _mapEquals(other.consent, consent);

  @override
  int get hashCode => Object.hash(
    userId,
    Object.hashAllUnordered(
      userProperties.entries.map(
        (MapEntry<String, String> e) => '${e.key}=${e.value}',
      ),
    ),
    consent == null
        ? null
        : Object.hashAllUnordered(
            consent!.entries.map(
              (MapEntry<String, String> e) => '${e.key}=${e.value}',
            ),
          ),
  );
}

bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
  if (a == null || b == null) {
    return a == b;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<String, String> entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// An event waiting to be sent, with everything its request needs.
@internal
@immutable
class QueuedEvent {
  const QueuedEvent({
    required this.name,
    required this.parameters,
    required this.timestampMicros,
    required this.context,
  });

  final String name;

  /// The parameters as sent: default parameters merged in and the session parameters added.
  final Map<String, Object> parameters;

  /// When the event was logged, in Unix microseconds.
  final int timestampMicros;
  final EventContext context;

  /// The event as it appears in the `events` array of a request.
  Map<String, Object> toRequest() => <String, Object>{
    'name': name,
    'params': parameters,
    'timestamp_micros': timestampMicros,
  };

  Map<String, Object> toJson() => <String, Object>{
    'n': name,
    'p': parameters,
    't': timestampMicros,
    'x': context.toJson(),
  };

  /// Reads a stored event, or returns null when it does not pass the checks of `logEvent`.
  static QueuedEvent? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? name = json['n'];
    final Object? parameters = json['p'];
    final Object? timestamp = json['t'];
    final EventContext? context = EventContext.fromJson(json['x']);
    if (name is! String ||
        parameters is! Map ||
        timestamp is! int ||
        timestamp <= 0 ||
        context == null) {
      return null;
    }
    try {
      checkEventName(name);
      final Map<String, Object?> user = <String, Object?>{};
      final Map<String, Object> session = <String, Object>{};
      for (final MapEntry<Object?, Object?> entry in parameters.entries) {
        final Object? key = entry.key;
        if (key is! String) {
          return null;
        }
        if (key == 'session_id' || key == 'engagement_time_msec') {
          final Object? value = entry.value;
          if (value is! int || value <= 0) {
            return null;
          }
          session[key] = value;
        } else {
          user[key] = entry.value;
        }
      }
      final Map<String, Object> checked = normalizeParameters(user);
      checkParameterCount(checked.length);
      return QueuedEvent(
        name: name,
        parameters: <String, Object>{...checked, ...session},
        timestampMicros: timestamp,
        context: context,
      );
    } on Object {
      return null;
    }
  }
}
