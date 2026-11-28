# Analytics parity with the official SDKs

This document compares the public API of the official Analytics SDKs with the planned Dart packages:

- **The Dart client**: `firebase_analytics/firebase_analytics_dart`, specified in
  [analytics_spec.md](analytics_spec.md) and in development (not released). Each row says what the first
  release does.
- **The FlutterFire adapter**: `firebase_analytics/firebase_analytics_dart_platform`, in development too.
  The last section maps every method of FlutterFire's `FirebaseAnalytics`.

Unlike the other parity documents, this one cannot compare behaviour. The Android and iOS SDKs are closed
binaries, the JS SDK forwards to `gtag.js`, and the Windows part of the C++ SDK is a closed DLL. What can be
compared is the public API, and the wire facts in [analytics_protocol.md](analytics_protocol.md).

## Sources

Read on 2026-11-28.

| Short name | Source | Version |
|---|---|---|
| `J:` | firebase-js-sdk, `packages/analytics/src` (`api.ts`, `public-types.ts`, `factory.ts`) | `main` at 6e8b0eb (2026-11-24) |
| Android | [`FirebaseAnalytics` reference](https://firebase.google.com/docs/reference/android/com/google/firebase/analytics/FirebaseAnalytics) | page last updated 2026-07-08 |
| iOS | firebase-ios-sdk, `FirebaseAnalytics/Tests/SwiftUnit/AnalyticsAPITests.swift` (the API surface test of the closed binary) and `FirebaseAnalytics/Sources/Analytics+SwiftUI.swift` | `main` at f267458 (2026-11-26) |
| `C:` | firebase-cpp-sdk, `analytics/src/include/firebase/analytics.h` and `analytics/src/analytics_desktop.cc` | `main` at 0c31588 (2026-11-26) |
| `FF:` | flutterfire, `packages/firebase_analytics` (`firebase_analytics` 13.1.0 and its platform interface) | `main` at bbdc38e (2026-11-27) |

References to the JS SDK carry line numbers of `api.ts` at 6e8b0eb.

## The C++ SDK on desktop

The C++ SDK has a desktop implementation that matters for the question of who this package is for
(spec section 1):

- **Windows:** `Initialize` verifies a closed `google_analytics.dll` against a list of known hashes and loads
  it, passing the Firebase app id and package name (`C:analytics_desktop.cc`, `Initialize`). Event logging,
  user properties, user id, the collection switch and reset go to that DLL. `SetConsent`,
  `SetDefaultEventParameters`, `SetSessionTimeoutDuration`, the on-device conversion calls and
  `GetAnalyticsInstanceId` are not supported there: they log a warning, and the instance id is the fixed
  string `FakeAnalyticsInstanceId0`. Vector parameters are skipped; a map parameter becomes `items`.
  Four functions exist for the desktop only: `SetLogCallback`, `NotifyAppLifecycleChange(kTermination)`
  (blocks until pending data is uploaded), `IsDesktopInitialized` and `SetDesktopDebugMode`.
- **Linux and macOS desktop:** stubs. Calls do nothing.
- **FlutterFire** declares Android, iOS, macOS and the web for `firebase_analytics`. It has generated
  Windows message files but no Windows plugin (`FF:firebase_analytics/pubspec.yaml`).

So on Windows a native path exists for C++ programs, through a closed DLL with no consent and no instance id.
On Linux, from Dart, and from a Flutter app on Windows there is still none. The spec's statement that
FlutterFire has no implementation on Windows and Linux holds. The Windows DLL is a reason to keep this
package's claims modest, not a reason to stop: it is not reachable from Dart without FFI against a closed
binary, and it reports to an app stream through a channel this package cannot use.

## Ranks

- **first release**: in the first published version of the client (step 3) or the adapter (step 4).
- **later**: possible over the Measurement Protocol, not planned for the first release.
- **n/a**: cannot be done by a Measurement Protocol client, or has no meaning outside its platform.

## Instance and configuration

| Feature | JS | Android | iOS | C++ | Dart client | Rank | Notes |
|---|---|---|---|---|---|---|---|
| Get an instance | `getAnalytics(app)` J:73 | `getInstance(context)` | class methods on `Analytics` | `Initialize(app)` | `FirebaseAnalytics(app, measurementId:, transport:, …)` | first release | One object per constructor call, no global cache (design rule 4). |
| Options at start | `initializeAnalytics(app, {config})` J:95 | none | none | none | constructor arguments | first release | `config` is gtag configuration (`send_page_view`, cookie settings); the parts with a meaning here (`page_title`, `page_location`) are parameters of `logScreenView`. |
| Global script names | `settings({gtagName, dataLayerName})` J:58 | none | none | none | none | n/a | Names of the page's gtag globals. |
| Is supported | `isSupported()` J:127: not a browser extension, cookies enabled, IndexedDB present | none | none | none | none in the client; the adapter answers `true` | first release (adapter) | The client works wherever `package:http` works. |
| Measurement target | Firebase config's `measurementId` | `google-services.json` | `GoogleService-Info.plist` | app options | `measurementId:` (a web stream, `G-…`) | first release | Web streams only (protocol §5). |
| API secret | none | none | none | none | `AnalyticsTransport.direct(apiSecret:)` or a relay | first release | A Measurement Protocol requirement with no SDK counterpart (spec section 2). |
| EU collection | gtag setting | none | none | none | `region: AnalyticsRegion.eu` | first release | `region1.google-analytics.com` (protocol §1). |
| Shut down | `deleteApp` | none | none | `Terminate()`; `NotifyAppLifecycleChange(kTermination)` on Windows | `close()`, which flushes | first release | `close()` is the counterpart of the Windows termination call. |
| Upload now | none | none | none | Windows termination only | `flush()` | first release | |
| Log callback | none | none | none | `SetLogCallback` (Windows) | `package:logging` logger | first release | The same logger as the other packages. |
| Debug mode | `debug_mode` parameter | adb property | launch argument | `SetDesktopDebugMode` (Windows) | `debug_mode` parameter on events, documented | first release | Puts events in DebugView (protocol §2). No separate switch. |
| Is initialized | none | none | none | `IsDesktopInitialized()` | none | n/a | A constructed client is ready. |

## Events

| Feature | JS | Android | iOS | C++ | Dart client | Rank | Notes |
|---|---|---|---|---|---|---|---|
| Log an event | `logEvent(analytics, name, params, options)` J:275–736, typed overloads per event | `logEvent(name, Bundle)` | `logEvent(_:parameters:)` | `LogEvent` with 0, 1 or many `Parameter`s | `logEvent(name:, parameters:)` | first release | One untyped method. The typed helpers live in the adapter (spec section 4). |
| Invalid event | logged by gtag | dropped and logged | dropped and logged | dropped and logged | throws `FirebaseAnalyticsException` | first release | **Deliberate difference** (protocol §9). |
| Reserved event names | not checked by the JS SDK | checked | checked | checked | checked against the protocol list, plus `ad_impression`, `in_app_purchase`, `screen_view` | first release | Protocol §4. |
| `firebase_`, `google_`, `ga_` event prefixes | not checked | reserved | reserved | reserved | refused | first release | The protocol pages reserve them for parameters and user properties only; the Android SDK for event names too. |
| Parameter types | string, number, `items` arrays | string, long, double, `Bundle[]` items | string, number, item arrays | int64, double, string, map (items) | `String`, `int`, `double`, `bool` (as `0`/`1`), `items` as `List<Map<String, Object>>` | first release | Numbers checked with `isFinite` (design rule 9). |
| Recommended event and parameter names | `EventNameString` union, `EventParams`, `Item` | `Event` and `Param` constants | `AnalyticsEvent…`, `AnalyticsParameter…` constants | `kEvent…`, `kParameter…` constants | constants for the names the protocol accepts on a web stream | first release | Constants only; the adapter has the typed helpers. |
| Default parameters | `setDefaultEventParameters(params)` J:257 | `setDefaultEventParameters(Bundle?)` | `setDefaultEventParameters(_:)` | `SetDefaultEventParameters` (no-op on Windows) | `setDefaultEventParameters(Map?)`, persisted | first release | Merged into each event when it is logged; the event's own value wins. |
| Screen view | `setCurrentScreen` J:157, deprecated; `logEvent('screen_view')` | `logEvent(SCREEN_VIEW)`; `setCurrentScreen` deprecated | `logEvent(AnalyticsEventScreenView)`; SwiftUI `.analyticsScreen(name:class:)` | `LogEvent(kEventScreenView)` | `logScreenView(screenName:, screenClass:)` sends `page_view` | first release | **Deliberate difference**: `screen_view` is for app streams only (protocol §8). |
| Automatic events (`first_open`, `session_start`, `user_engagement`, `app_update`, `os_update`, …) | by gtag (web events) | yes | yes | Windows: by the DLL | none | n/a | Reserved in the protocol. Sessions come from `session_id` (below). |
| Enhanced measurement (scroll, outbound clicks, file downloads) | by gtag | none | none | none | none | n/a | Page events. |
| Call options `{global: true}` | `AnalyticsCallOptions` | none | none | none | none | n/a | Applies a call to every gtag property of the page. |
| Store transactions | none | automatic `in_app_purchase` | `logTransaction(_:)` (StoreKit 2) | `LogAppleTransaction` | none | n/a | Needs the store's receipt and an app stream. |

## Identity and properties

| Feature | JS | Android | iOS | C++ | Dart client | Rank | Notes |
|---|---|---|---|---|---|---|---|
| User id | `setUserId(id \| null)` J:197 | `setUserId(String?)` | `setUserID(_:)` | `SetUserId` | `setUserId(String?)`, persisted | first release | Up to 256 characters (protocol §4). |
| User property | `setUserProperties(props)` J:216, several at once | `setUserProperty(name, value?)` | `setUserProperty(_:forName:)` | `SetUserProperty` | `setUserProperty(name:, value:)`, persisted; `null` removes | first release | Up to 25, names up to 24 characters, values up to 36. |
| Instance id | `getGoogleAnalyticsClientId()` J:179 (gtag's `client_id`) | `getAppInstanceId()`, null if `ANALYTICS_STORAGE` is denied | `appInstanceID()` | `GetAnalyticsInstanceId()` (fake on Windows) | `appInstanceId`, the persisted `client_id`; null while analytics storage is denied | first release | Closest to the JS `getGoogleAnalyticsClientId`; the FlutterFire name is kept. |
| Session id | none | `getSessionId()` | `sessionID()` | `GetSessionId()` | `sessionId` | first release | Start time of the session in seconds (protocol §6). |
| Session timeout | none | `setSessionTimeoutDuration(ms)` | `setSessionTimeoutInterval(_:)` | `SetSessionTimeoutDuration` (no-op on Windows) | `sessionTimeout:` constructor argument | first release | Configuration, not a setter (design rule 4). The adapter's setter is allowed before the first event and throws after it (adapter table). |
| Engagement time | by gtag | automatic | automatic | Windows: by the DLL | `engagement_time_msec` from `setAppActive` | first release | Spec section 6. |
| Reset | none | `resetAnalyticsData()` | `resetAnalyticsData()` | `ResetAnalyticsData()` | `resetAnalyticsData()`: new client id, clears user id, properties, session and the queue; default parameters, consent and the collection switch stay | first release | Default parameters are app configuration (an app version), not user data. |
| Device and geography | from the browser | automatic | automatic | Windows: by the DLL | `device` from the platform; `user_location` only if supplied | first release | Protocol §7. No IP address. |

## Consent and collection

| Feature | JS | Android | iOS | C++ | Dart client | Rank | Notes |
|---|---|---|---|---|---|---|---|
| Collection switch | `setAnalyticsCollectionEnabled(analytics, enabled)` J:239 | `setAnalyticsCollectionEnabled` | `setAnalyticsCollectionEnabled(_:)` | `SetAnalyticsCollectionEnabled` | `setAnalyticsCollectionEnabled(bool)`, persisted; disabling drops the queue | first release | |
| Collection off by default | none (the switch sets `window['ga-disable-<id>']`, J:232) | manifest flag | plist flag | at first launch (Windows) | `collectionEnabledByDefault:` | first release | |
| `ad_user_data`, `ad_personalization` | `setConsent` J:768 | `setConsent(Map)` | `setConsent(_:)` | `SetConsent` (no-op on Windows) | `setConsent(adUserData:, adPersonalization:)`, sent as `consent` | first release | Sent only after a call (protocol §6). |
| `analytics_storage` | `setConsent` | `setConsent` | `setConsent` | `SetConsent` | `setConsent(analyticsStorage:)`: while denied, nothing is queued or sent and `appInstanceId` is null | first release | The protocol has no field for it, and a client that cannot send cookieless pings must not send at all. **Deliberate difference** from gtag, which still sends cookieless pings. |
| `ad_storage` | `setConsent` | `setConsent` | `setConsent` | `SetConsent` | accepted and stored, no effect | first release | The client collects no advertising identifiers. |
| `functionality_storage`, `personalization_storage`, `security_storage` | `setConsent` | none | none | none | accepted by the adapter, no effect | first release (adapter) | Web consent types with no meaning here. |
| On-device conversion (email, phone, hashed) | none | none | `initiateOnDeviceConversionMeasurement(…)` | four `InitiateOnDeviceConversionMeasurementWith…` (no-op on Windows) | none | n/a | iOS ads attribution. The protocol's `user_data` is a different feature (later). |
| User-provided data (`user_data`) | gtag `user_data` | none | none | none | none | later | Hashed email and phone for ads; needs a clear privacy story first. |

## Platform hooks

| Feature | JS | Android | iOS | C++ | Dart client | Rank | Notes |
|---|---|---|---|---|---|---|---|
| App active or in background | page visibility | automatic | automatic | none | `setAppActive(bool)`; the adapter hooks `AppLifecycleListener` | first release | |
| Deep links and attribution | gtag campaign parameters | automatic | `handleOpen(_:)`, `handleUserActivity(_:)` | none | none | n/a | Install attribution needs the native SDK. |
| Background URL sessions | none | none | `handleEvents(forBackgroundURLSession:)` | none | none | n/a | iOS only. |
| Audiences for Remote Config, AdMob linking | none | yes | yes | none | none | n/a | Spec section 2. |

## The FlutterFire adapter

Every public method of FlutterFire's `FirebaseAnalytics` (`FF:firebase_analytics/lib/src/firebase_analytics.dart`)
and what `firebase_analytics_dart_platform` does with it. The adapter reports every error of the client as `firebase_core`'s `FirebaseException` with plugin `firebase_analytics` and the client's code, like the other adapters of the repository. All of it is rank **first release (adapter)**
unless the row says otherwise.

| FlutterFire method | Adapter |
|---|---|
| `FirebaseAnalytics.instance`, `instanceFor(app:)` | The client built from `FirebaseAnalyticsDart.configure(...)` for that app. |
| `isSupported()` | `true`. |
| `appInstanceId` / `getAppInstanceId()` | `appInstanceId`. |
| `getSessionId()` | `sessionId`. |
| `logEvent(name:, parameters:, callOptions:)` | `logEvent`; `callOptions` ignored. |
| `setUserId`, `setUserProperty` | Mapped; `callOptions` ignored. |
| `setAnalyticsCollectionEnabled`, `resetAnalyticsData`, `setDefaultEventParameters` | Mapped. |
| `setConsent(...)`, seven flags | `adUserData`, `adPersonalizationSignals`, `analyticsStorage` and `adStorage` mapped as in the consent table; the three web storage flags accepted and ignored. |
| `setSessionTimeoutDuration(Duration)` | Allowed before the first event of the process (it reconfigures the client); throws `StateError` with a clear message after it. |
| `logScreenView(screenName:, screenClass:, parameters:)` | `logScreenView` (sends `page_view`). |
| Typed helpers: `logAddPaymentInfo`, `logAddShippingInfo`, `logAddToCart`, `logAddToWishlist`, `logBeginCheckout`, `logPurchase`, `logRefund`, `logRemoveFromCart`, `logSelectItem`, `logSelectPromotion`, `logViewCart`, `logViewItem`, `logViewItemList`, `logViewPromotion`, `logEarnVirtualCurrency`, `logSpendVirtualCurrency`, `logGenerateLead`, `logJoinGroup`, `logLevelStart`, `logLevelEnd`, `logLevelUp`, `logPostScore`, `logUnlockAchievement`, `logLogin`, `logSignUp`, `logSearch`, `logViewSearchResults`, `logSelectContent`, `logShare`, `logTutorialBegin`, `logTutorialComplete`, `logAppOpen`, `logCampaignDetails` | Nothing to do: FlutterFire's `FirebaseAnalytics` builds the recommended name and parameters itself and calls the platform's `logEvent`. |
| `logAdImpression` | Reaches the adapter as `logEvent('ad_impression')`, which the client refuses: a `FirebaseException` with plugin `firebase_analytics` and code `reserved-name`, since the event is for app streams only (protocol §4). |
| `logInAppPurchase` | FlutterFire calls the platform only on iOS and throws `UnimplementedError` itself on Windows and Linux. Where the adapter is chosen on iOS, it reaches the adapter as `logEvent('in_app_purchase')` and gets `reserved-name`, as above. |
| `logTransaction(transactionId)` (platform `logTransaction`) | FlutterFire calls the platform only on iOS and macOS. The adapter throws `UnimplementedError`: StoreKit only. |
| `initiateOnDeviceConversionMeasurementWithEmailAddress`, `…PhoneNumber`, `…HashedEmailAddress`, `…HashedPhoneNumber` (platform `initiateOnDeviceConversionMeasurement`) | FlutterFire calls the platform only on iOS. The adapter throws `UnimplementedError`. |

## Deliberate differences, in one list

1. Invalid events throw instead of being dropped (protocol §9).
2. `logScreenView` sends `page_view`; `screen_view`, `ad_impression` and `in_app_purchase` are refused
   (protocol §4, §8).
3. The data goes to a web stream and shows as web traffic, not as an app (protocol §5).
4. No automatic events: `first_open`, `session_start` and the rest are reserved. Sessions are carried by
   `session_id` and `engagement_time_msec` on every event.
5. While `analytics_storage` is denied, nothing is sent; gtag would send cookieless pings.
6. The session timeout is configuration; the adapter's setter works only before the first event.
7. The `firebase_`, `google_` and `ga_` prefixes are refused for event names too, as the Android SDK
   documents, although the protocol pages list them for parameters and user properties only.
