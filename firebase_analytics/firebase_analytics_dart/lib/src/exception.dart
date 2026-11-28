import 'package:firebase_app_dart/firebase_app_dart.dart';

/// Thrown when an event, a parameter, a user property or a user id breaks a rule of the Measurement Protocol.
///
/// It extends [FirebaseException] with the [plugin] `firebase_analytics`, so `on FirebaseException catch (e)`
/// catches it too. Branch on [code]; [message] is for people.
///
/// The native SDKs drop such an event and log it. This client throws instead, before anything is queued:
/// the Measurement Protocol accepts invalid data with a 2xx answer and never reports it, so a mistake would
/// otherwise stay hidden until someone looks at a report.
///
/// | Code | Meaning |
/// | --- | --- |
/// | `invalid-event-name` | the name is empty, too long, or has characters other than letters, digits and `_`, or does not start with a letter |
/// | `reserved-name` | the event, parameter or user property name, or its prefix, is reserved by the protocol or set by the client itself |
/// | `invalid-parameter` | a parameter name or value breaks a rule: its length, its type, a number that is not finite, an `items` entry |
/// | `too-many-parameters` | more parameters than an event may carry, default parameters and the two session parameters included |
/// | `invalid-user-property` | the user property name or value breaks a rule |
/// | `too-many-user-properties` | setting the property would pass the limit of user properties |
/// | `invalid-user-id` | the user id is empty or too long |
/// | `event-too-large` | the event alone would not fit in one request body |
///
/// Delivery problems (no network, an answer of 5xx) are not thrown: events stay queued and are sent later.
class FirebaseAnalyticsException extends FirebaseException {
  /// Creates an exception with the [code] (for example `invalid-event-name`) and a [message]. The package
  /// creates them; you need this only in tests.
  const FirebaseAnalyticsException({
    required String code,
    required String message,
    super.stackTrace,
  }) : super(plugin: 'firebase_analytics', code: code, message: message);

  @override
  String toString() => '[$plugin/$code] $message';
}
