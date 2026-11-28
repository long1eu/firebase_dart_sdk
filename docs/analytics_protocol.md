# Analytics: the Measurement Protocol, as documented

The wire facts that `firebase_analytics_dart` relies on, taken from Google's documentation of the GA4
Measurement Protocol. [analytics_spec.md](analytics_spec.md) marks each fact it needs with **(measure)**, and
this document answers each one with a source and the date the source was last updated. No request was sent to
any Google Analytics endpoint to write it. Where the documentation leaves a question open, this document
says so, and the production verification kit (spec section 10, step 6) is where it gets answered.

## Sources

All pages were read on 2026-11-28, in both the "gtag.js" (web stream) and "Firebase" (app stream) variants
where the page has the switch (`?client_type=gtag` and `?client_type=firebase`).

| Short name | Page | Last updated |
|---|---|---|
| [REF] | [Measurement Protocol reference](https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference?client_type=gtag) | 2026-11-10 |
| [SEND] | [Send Measurement Protocol events](https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events?client_type=gtag) | 2026-11-10 |
| [VALIDATE] | [Validate events](https://developers.google.com/analytics/devguides/collection/protocol/ga4/validating-events?client_type=gtag) | 2026-11-10 |
| [VERIFY] | [Verify implementation](https://developers.google.com/analytics/devguides/collection/protocol/ga4/verify-implementation?client_type=gtag) | 2026-06-15 |
| [LIMITS] | [Event collection limits](https://support.google.com/analytics/answer/9267744) (Analytics Help) | no date shown |
| [AUTO] | [Automatically collected events](https://support.google.com/analytics/answer/9234069) (Analytics Help) | no date shown |
| [EVENTS] | [Recommended events reference](https://developers.google.com/analytics/devguides/collection/ga4/reference/events) | not recorded |
| [ANDROID] | [`FirebaseAnalytics` Android reference](https://firebase.google.com/docs/reference/android/com/google/firebase/analytics/FirebaseAnalytics) | 2026-07-08 |

The Analytics Help pages do not show a last-updated date; for those the read date is the only date.

## 1. Endpoints

| Use | URL | Source |
|---|---|---|
| Collect | `https://www.google-analytics.com/mp/collect` | [REF] |
| Collect, EU | `https://region1.google-analytics.com/mp/collect` ("if you want your data to be collected in the EU") | [REF] |
| Validation | the same hosts with the path `/debug/mp/collect`; "all other request fields are the same" | [VALIDATE] |

- Method `POST` only, over HTTPS, with `Content-Type: application/json` [REF], [SEND].
- Query parameters, web stream: `api_secret` (required; "private to your organization", created under
  Admin > Data Streams > the stream > Measurement Protocol) and `measurement_id` (the `G-…` id of the
  stream) [REF].
- Query parameters, app stream: `api_secret` and `firebase_app_id` [REF, Firebase variant].
- **Responses.** "The Measurement Protocol returns a 2xx status code if the HTTP request is received. The
  Measurement Protocol doesn't return an error code if the payload is malformed, or if the data is incorrect
  or not processed by Google Analytics." The page adds: "If you don't get a 2xx status code, correct any
  errors in your HTTP request. Don't retry the same request." [REF]
- **Rate.** At most 100 million non-conversion requests per hour per property; past that, the protocol
  "silently ignores" non-conversion requests for the rest of the hour [SEND].

**Decision (transport).** 2xx means delivered. Other 4xx responses are not retried: they are the case the
documentation describes, and the batch is dropped with a logged warning. Network errors, 5xx and 429 are
retried with backoff, as the spec says: the documentation's "don't retry" is about a request the server
refused, and a dropped connection or an overloaded server says nothing about the request.

## 2. Validation server

From [VALIDATE]:

- Events sent there "don't show up in reports".
- It does **not** check `api_secret` or `measurement_id` (or `firebase_app_id`). A green validation run
  proves the body, not the credentials.
- Response: `{"validationMessages": [{"fieldPath": …, "description": …, "validationCode": …}]}`, an empty
  array when the body is valid.
- `validationCode` is one of `VALUE_INVALID`, `VALUE_REQUIRED`, `NAME_INVALID`, `NAME_RESERVED`,
  `VALUE_OUT_OF_BOUNDS`, `EXCEEDED_MAX_ENTITIES`, `NAME_DUPLICATED`.
- The page's examples send `validation_behavior: "ENFORCE_RECOMMENDATIONS"`.

DebugView is not fed by the validation server. To see events there, send them to `/mp/collect` with
`"debug_mode": true` (or `1`) and a positive `engagement_time_msec` in the event's `params` [VERIFY]. The
production kit does both: the validation server first, then DebugView.

## 3. Request body

"The size of the JSON POST body must be less than 130kB" [REF]; "the post body must be smaller than 130kB"
[SEND]. The documentation does not say whether kB means 1,000 or 1,024 bytes.

| Field | Type | What the documentation says | Source |
|---|---|---|---|
| `client_id` | string | Required for a web stream. "Identifier for a user instance of a web client." Accepted formats: **recommended**, "two positive numbers, joined by a period"; or the full value of the client ID cookie. | [REF] |
| `app_instance_id` | string | Required for an app stream instead of `client_id`. "Must be retrieved using the Firebase SDK" (`getAppInstanceId()`, `appInstanceID()`, `GetAnalyticsInstanceId()`). No format is documented. | [REF, Firebase] |
| `user_id` | string | Optional. "Can include only utf-8 characters." | [REF] |
| `timestamp_micros` | number | Optional. Unix time in microseconds; set only for events in the past. Overridden by a user property's or an event's own timestamp. | [REF] |
| `user_properties` | object | Optional. Up to 25 per request; each is `{"value": …}`, with an optional `timestamp_micros`. | [REF], [SEND] |
| `user_data` | object | Optional. User-provided data (hashed email and phone). | [REF] |
| `consent` | object | Optional. Section 6. | [REF] |
| `non_personalized_ads` | boolean | Deprecated in favour of `consent.ad_personalization`. | [REF] |
| `user_location` | object | Optional. Section 7. | [REF] |
| `ip_override` | string | Optional. An IP address to derive geography from. Ignored when `user_location` is present. | [REF] |
| `device` | object | Optional. Section 7. | [REF] |
| `user_agent` | string | Optional, **web variant only**. Used to derive device data; ignored when `device` is present. | [REF, gtag] |
| `validation_behavior` | string | `RELAXED` (default) or `ENFORCE_RECOMMENDATIONS`. | [REF] |
| `events[]` | array | Required. Up to 25 per request. | [REF] |
| `events[].name` | string | Required. 40 characters or fewer. | [REF] |
| `events[].params` | object | Optional. Up to 25 per event. | [REF] |
| `events[].timestamp_micros` | number | The event's own time; also listed as a common event parameter. | [SEND], [REF] |

**Timestamps** [SEND]. Precedence: the event's or user property's `timestamp_micros`, then the request's,
then the time the server receives the request. Events and user properties "can be backdated up to 72 hours".
An older timestamp is clamped to 72 hours ago under `RELAXED` and rejected under
`ENFORCE_RECOMMENDATIONS`. Events meant to be joined with events from the SDK or gtag.js "should be received
by Google Analytics within 48 hours".

**`validation_behavior`** [REF]. `RELAXED` "only rejects requests that are malformed … but it ignores
parameters that exceed limits". `ENFORCE_RECOMMENDATIONS` rejects event and item parameters of the wrong type
or over the limits. Google recommends the strict mode for validation and no `validation_behavior` field in
production.

**Decisions (body).**

- Each event carries its own `timestamp_micros`, the time `logEvent` was called. The request-level field is
  not sent. This replaces the spec's "for each request": one batch holds events logged at different times.
- Queued events older than 72 hours are dropped instead of being sent and silently re-dated.
- The client sends no `validation_behavior` in production. The kit sends `ENFORCE_RECOMMENDATIONS` to the
  validation server.
- A batch is cut at 25 events or at 130,000 bytes of UTF-8 JSON, whichever comes first. 130,000 is the
  smaller reading of "130kB".
- `user_data`, `ip_override` and `non_personalized_ads` are not sent.

## 4. Names and limits

From [SEND] "Limitations" and [REF], unless marked otherwise.

| Limit | Value | Constant |
|---|---|---|
| Events per request | 25 | `maxEventsPerRequest` |
| Body size | under 130 kB | `maxBodyBytes = 130000` |
| Parameters per event | 25 | `maxParametersPerEvent` |
| User properties per request | 25 ([SEND] says "per event", [REF] "per request"; the body carries them per request) | `maxUserProperties` |
| Event name | 40 characters; letters, digits and underscores; starts with a letter | `maxEventNameLength` |
| Parameter name, item parameters included | 40 characters; same character rule | `maxParameterNameLength` |
| Parameter value, item parameter values included | 100 characters (500 on a GA4 360 property) | `maxParameterValueLength` |
| User property name | 24 characters | `maxUserPropertyNameLength` |
| User property value | 36 characters | `maxUserPropertyValueLength` |
| Custom parameters per item | 10 | `maxCustomItemParameters` |
| User ID | 256 characters [LIMITS] | `maxUserIdLength` |
| Backdating | 72 hours | `maxEventAge` |

The documentation does not state the character rule for user property names. The client applies the
event-name rule to them as well: the Android SDK documents "1 to 24 alphanumeric characters or underscores"
that "must start with an alphabetic character" [ANDROID].

**Where the pages disagree.**

1. **Custom item parameters:** 10 in [SEND], "up to 27 item-level custom parameters" in [LIMITS]. The client
   enforces 10, the Measurement Protocol's own figure.
2. **Long page parameters:** [LIMITS] allows `page_title` 300, `page_referrer` 420 and `page_location` 1,000
   characters, for tag and SDK collection. [SEND] gives 100 for every parameter value and does not list
   exceptions. The client enforces 100 everywhere. The kit checks whether the validation server, in strict
   mode, accepts a longer `page_location`; if it does, the exception goes in.
3. **How characters are counted:** [LIMITS] says "the encoded URL character length is used when counting
   character limits", and the limits are the same for single-width and double-width scripts. Whether that
   applies to the JSON body of the Measurement Protocol is not said. The client counts the length of
   `Uri.encodeComponent(value)`, the stricter reading: an ASCII name counts the same either way, and a
   non-ASCII value is never sent longer than either reading allows.

**Items per event.** No page gives a maximum number of `items`. The body limit bounds it.

**Values.** [REF] types `session_id` as "number or string" and `engagement_time_msec` as number. Parameter
value types in general are not specified beyond the recommended events, whose tables use string and number.
The client sends strings and numbers and maps `bool` to `0` or `1`, as the spec says.

### Reserved names

Event names that "are reserved and can't be used" [REF], the same list in both variants:

```
ad_activeview ad_click ad_exposure ad_query ad_reward adunit_exposure app_clear_data
app_exception app_install app_remove app_store_refund app_update app_upgrade
dynamic_link_app_open dynamic_link_app_update dynamic_link_first_open error firebase_campaign
firebase_in_app_message_action firebase_in_app_message_dismiss firebase_in_app_message_impression
first_open first_visit notification_dismiss notification_foreground notification_open
notification_receive notification_send os_update session_start user_engagement
```

"In addition, `ad_impression`, `in_app_purchase` and `screen_view` events are only allowed for App streams"
[REF]. The client targets a web stream (section 5), so for it these three are reserved too.

- Reserved parameter name: `firebase_conversion`. Parameter names cannot begin with `_`, `firebase_`, `ga_`,
  `google_` or `gtag.` [REF].
- Reserved user property names: `first_open_time`, `first_visit_time`, `last_deep_link_referrer`, `user_id`,
  `first_open_after_install`. User property names cannot begin with `_`, `firebase_`, `ga_` or `google_`
  [REF].
- `session_start` is reserved, but "creating a new `session_id` creates a new session without the need to
  send `session_start`" [SEND].

The spec listed `firebase_`, `google_` and `ga_` as reserved event prefixes. The Measurement Protocol pages
document those prefixes for parameter and user property names only. The client refuses them for event names
as well, because the Android SDK reserves them there ("the `firebase_`, `google_` and `ga_` prefixes are
reserved" [ANDROID]); the parity document records it.

## 5. The kind of stream

- An app stream needs an `app_instance_id` that "must be retrieved using the Firebase SDK", with no
  documented format [REF, Firebase]. [VERIFY] says an event is valid only with an `app_instance_id` "that has
  been previously used by the Google Analytics for Firebase SDK".
- A web stream takes a `client_id` in the recommended form "two positive numbers, joined by a period" [REF].
  [VERIFY] says, for the web: "In order for an event to be valid, it must have a `client_id` that has already
  been used to send an event from gtag.js."

**Decision.** The client targets a **web stream** only. A self-generated `app_instance_id` contradicts the
documentation, so the app-stream path is not built. The spec's open question about a 32-hex id is closed by
the documentation, not by measurement.

**Open risk.** The client generates its own `client_id`, as `<random 31-bit positive integer>.<Unix seconds
of first use>`, which matches the documented format. The same sentence in [VERIFY] says a valid event needs
a `client_id` that gtag.js has used. Read literally, events from a client that never ran gtag.js may be
accepted (2xx) and validated (the validation server checks the body only) but not reported. The
documentation does not say what happens to them. This is the first thing the production kit checks:
events with a fresh `client_id` must appear in Realtime and in DebugView. If they do not, the package cannot
work as designed, and the spec goes back for a decision before step 3 ships.

## 6. Sessions, engagement and consent

- `session_id` [REF]: "a positive numeric value representing a timestamp, provided as a number or a string",
  in the web variant. The app variant says it "must match the regular expression `^\d+$`" and comes from the
  SDK. The client sends the session's start time in Unix seconds, as a number.
- `engagement_time_msec` [REF]: "the amount of user engagement time since the preceding event".
- Both go in each event's `params`. Without them, events "may still appear in some reports" but do not count
  towards engaged sessions or average engagement time, and "may not be fully reflected in Realtime user
  counts" [REF]. DebugView needs a positive `engagement_time_msec` [VERIFY].
- `consent` [REF]: `ad_user_data` and `ad_personalization`, each `"GRANTED"` or `"DENIED"`. When the field is
  omitted, Google Analytics uses "the consent settings from corresponding online interactions for the client".
  The client sends `consent` only after `setConsent` was called; it sends neither value as a default.

## 7. Device and geography

`device` [REF]: `category` (recommended at a minimum; `desktop`, `tablet`, `mobile`, `smart TV`),
`language` (ISO 639-1, `en` or `en-US`), `screen_resolution` (`WIDTHxHEIGHT`), `operating_system`,
`operating_system_version`, `model`, `brand`, `browser`, `browser_version`. Every sub-field is an optional
string. Both variants document it.

`user_location` [REF]: `city`, `region_id` (ISO 3166-2, `US-CA`), `country_id` (ISO 3166-1 alpha-2),
`subcontinent_id` and `continent_id` (UN M49). `country_id` and `region_id` are recommended at a minimum.

Without `device` or `user_agent`, Google Analytics derives device data "from tagging events using
`client_id`"; without `user_location` or `ip_override`, geography likewise [REF]. A client that never ran
gtag.js has no tagging events, so anything it does not send is not reported. The property's granular
location and device settings apply in every case.

**Decision.** The client sends `device` with `category`, `language`, `operating_system`,
`operating_system_version` and `screen_resolution` where the platform exposes them. It sends no `user_agent`
(the structured field wins anyway) and no `ip_override`. It sends `user_location` only if the developer
supplies it: guessing a country from the locale would report the wrong country for travellers and
expatriates. Without it, geography is reported from the IP address of the request if the protocol does
that at all, which the documentation does not say; the kit records what appears.

## 8. Screen views

`screen_view` is allowed only for app streams, and [SEND] says "for web streams, use `page_view`
instead". `page_view` is not reserved. [AUTO] lists `page_location`, `page_referrer` and
`engagement_time_msec` as the parameters of the automatic `page_view`, and `page_title` as a default web
parameter. This confirms the spec's proposal: `logScreenView(screenName:, screenClass:)` sends `page_view`
with `page_title` set to the screen name and `page_location` set to `app://<app id>/<screen name>`, the
screen class in a `screen_class` parameter, all within the 100-character value limit of section 4.

## 9. Validation in the client: throw

Under the default `RELAXED` behaviour the server drops parameters that exceed limits and accepts the rest,
and it never answers with an error (sections 1 and 3). A mistake in an event name is invisible until someone
looks at a report. The client therefore **throws** `FirebaseAnalyticsException` for an invalid event,
parameter or user property, before anything is queued. The native SDKs drop and log instead; the parity
document lists the difference.

## 10. What the production kit must answer

The documentation leaves these open. The kit (spec section 10, step 6) records each answer with the date and
the property's settings:

1. Do events with a `client_id` that gtag.js never used appear in Realtime and DebugView? (Section 5. This
   decides whether the package works at all.) `tool/analytics_probe.dart` asks it, with a `client_id` from
   gtag.js as a control: without the control, a negative answer could also mean a wrong secret or stream,
   which neither endpoint reports.
2. Is geography reported for such a client without `user_location`? (Section 7.)
3. Does the validation server, in strict mode, accept a `page_location` longer than 100 characters?
   (Section 4.)
4. Does it count a non-ASCII value by code points or by its percent-encoded length? (Section 4.)
5. Is a body of 130,000 bytes accepted, and one of 133,120? (Section 3.)
