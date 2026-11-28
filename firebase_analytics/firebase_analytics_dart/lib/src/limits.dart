// The limits and reserved names of the GA4 Measurement Protocol, with their sources in
// docs/analytics_protocol.md (section numbers below). Change a value here only with a source.

/// The Measurement Protocol limits the client enforces before an event is queued.
///
/// Each value comes from Google's documentation of the protocol; `docs/analytics_protocol.md` in the
/// repository names the page and date of each one. Where two pages disagree, the stricter value is used.
abstract final class AnalyticsLimits {
  /// Events in one request (protocol §4).
  static const int maxEventsPerRequest = 25;

  /// Bytes of UTF-8 JSON in one request body: the smaller reading of "less than 130kB" (protocol §3).
  static const int maxBodyBytes = 130000;

  /// Parameters of one event, the two session parameters the client adds included (protocol §4).
  static const int maxParametersPerEvent = 25;

  /// User properties of one request (protocol §4).
  static const int maxUserProperties = 25;

  /// Characters of an event name (protocol §4).
  static const int maxEventNameLength = 40;

  /// Characters of a parameter name, item parameters included (protocol §4).
  static const int maxParameterNameLength = 40;

  /// Characters of a string parameter value, item parameter values included (protocol §4).
  static const int maxParameterValueLength = 100;

  /// Characters of a user property name (protocol §4).
  static const int maxUserPropertyNameLength = 24;

  /// Characters of a user property value (protocol §4).
  static const int maxUserPropertyValueLength = 36;

  /// Custom parameters of one item, beyond the documented item parameters (protocol §4).
  static const int maxCustomItemParameters = 10;

  /// Characters of a user id (protocol §4).
  static const int maxUserIdLength = 256;

  /// How far back an event can be dated (protocol §3).
  static const Duration maxEventAge = Duration(hours: 72);
}

/// Event names the Measurement Protocol reserves (protocol §4), plus `ad_impression`, `in_app_purchase` and
/// `screen_view`, which it allows only for app streams.
const Set<String> reservedEventNames = <String>{
  'ad_activeview',
  'ad_click',
  'ad_exposure',
  'ad_query',
  'ad_reward',
  'adunit_exposure',
  'app_clear_data',
  'app_exception',
  'app_install',
  'app_remove',
  'app_store_refund',
  'app_update',
  'app_upgrade',
  'dynamic_link_app_open',
  'dynamic_link_app_update',
  'dynamic_link_first_open',
  'error',
  'firebase_campaign',
  'firebase_in_app_message_action',
  'firebase_in_app_message_dismiss',
  'firebase_in_app_message_impression',
  'first_open',
  'first_visit',
  'notification_dismiss',
  'notification_foreground',
  'notification_open',
  'notification_receive',
  'notification_send',
  'os_update',
  'session_start',
  'user_engagement',
  // Allowed for app streams only; the client sends to a web stream.
  'ad_impression',
  'in_app_purchase',
  'screen_view',
};

/// Prefixes an event name cannot start with: those of parameter names that an event name can contain, as
/// the Android SDK documents for event names (protocol §4).
const List<String> reservedEventPrefixes = <String>[
  '_',
  'firebase_',
  'google_',
  'ga_',
];

/// Parameter names the protocol reserves (protocol §4).
const Set<String> reservedParameterNames = <String>{'firebase_conversion'};

/// Parameters the client sets on every event itself; an event or a default parameter cannot set them.
const Set<String> clientParameterNames = <String>{
  'session_id',
  'engagement_time_msec',
};

/// Prefixes a parameter name cannot start with (protocol §4).
const List<String> reservedParameterPrefixes = <String>[
  '_',
  'firebase_',
  'ga_',
  'google_',
  'gtag.',
];

/// User property names the protocol reserves (protocol §4).
const Set<String> reservedUserPropertyNames = <String>{
  'first_open_time',
  'first_visit_time',
  'last_deep_link_referrer',
  'user_id',
  'first_open_after_install',
};

/// Prefixes a user property name cannot start with (protocol §4).
const List<String> reservedUserPropertyPrefixes = <String>[
  '_',
  'firebase_',
  'ga_',
  'google_',
];

/// The item parameters of GA4's recommended events. Any other item key is a custom parameter, of which an
/// item may carry [AnalyticsLimits.maxCustomItemParameters].
const Set<String> documentedItemParameters = <String>{
  'item_id',
  'item_name',
  'affiliation',
  'coupon',
  'discount',
  'index',
  'item_brand',
  'item_category',
  'item_category2',
  'item_category3',
  'item_category4',
  'item_category5',
  'item_list_id',
  'item_list_name',
  'item_variant',
  'location_id',
  'price',
  'quantity',
  'creative_name',
  'creative_slot',
  'promotion_id',
  'promotion_name',
};
