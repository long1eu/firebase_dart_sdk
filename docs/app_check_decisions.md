# App Check: decisions and departures

This document records the design decisions of `firebase_app_check_dart` with the alternatives that were considered,
and every place where the package departs from the official SDKs, with the test that pins it. The comparison with
the official SDKs feature by feature is [app_check_parity.md](app_check_parity.md); the user guide is
[guides/app_check.md](guides/app_check.md).

Paths such as `lib/src/gate.dart` are in `firebase_app_check/firebase_app_check_dart/`. `D1` to `D41` are the
decisions below; "SHARED" is the specification shared by the packages of this round that talk to Firebase over HTTP
(Functions, App Check, AI Logic, Data Connect), whose numbered rules (S1 to S8, L1 to L3, C1 to C3) say what a
token provider owes the services that use it. `C<n>` and `M<n>` are claim numbers of the fact-check of the upstream
code that the design was reviewed against; each names one statement about an official SDK. `CHECK` is that
fact-check and `MATRIX` the feature comparison behind [app_check_parity.md](app_check_parity.md). Bare numbers such
as 5.7, 11.2 or "§7 question 6" are sections of the design specification, which is not part of this repository; the
four paragraphs below and the guide carry what a reader needs from them.

## How the design works, in five paragraphs

Each decision below belongs to one of four mechanisms. They are described here so that a row of the tables can be
read without the specification.

**The token manager** (`lib/src/token_manager.dart`) holds the session token and answers every call. A token is
*usable* while it has at least `min(5 min, lifetime / 2)` left; a call that finds a usable token sends nothing. At
most one session exchange is in flight, and a forced call joins it. A forced call that arrives less than 30 seconds
after the token's issue gets that token back: this floor is the only forced-refresh limit for App Check, because a
backend that rejects every token would otherwise turn each request of each service into an exchange. Limited-use
tokens skip all of it: they are not cached, not shared and not announced. Waits and deadlines read a monotonic
clock; a token's age reads the wall clock and the monotonic clock and takes the larger.

**The refresher** (`lib/src/refresher.dart`) replaces the session token before it stops being usable: half its life
plus 5 minutes after issue (35 minutes for a one-hour token), earlier for short lifetimes, never sooner than 30
seconds after issue, minus a random lead of at most two minutes (or a tenth of the lifetime) so that browser tabs on
one stored record do not all exchange at the same moment. It has no retry ladder of its own: after a failure it runs
again when the gate opens. It starts with the first token, not at construction.

**The gates** (`lib/src/gate.dart`) are the only rate control for failures. There are two per instance, one for
session tokens and one for limited-use tokens. Every failed exchange of either provider, a refused one, a timeout or
a callback that throws, closes its gate for `min(1 s x 2^(n-1) x (0.5 + random), cap)`, where the cap is 4 hours
when the server refused the exchange and 5 minutes when it could not be reached. A call inside the window fails with
`throttled` and sends nothing. A generation number on each gate makes fifteen concurrent failures count once.

**Rate control** is these three rules and nothing else: the usable margin, the forced floor and the gates. With
auto-refresh on, a healthy instance exchanges once per refresh period. A backend that rejects every token while the
services keep forcing a refresh costs one exchange per 30 seconds, 2 880 a day. A server that refuses every exchange
costs one per window, 6 to 12 a day once the windows reach 4 hours. Limited-use tokens cost one exchange per call,
by design. The gates are not stored, so every process start and page load begins open and a restart loop is not
bounded by this package.

**The seam object** (`lib/src/app_check_seam.dart`) is the implementation of `AppCheckTokenProvider` that the other
clients of this repository read from `FirebaseApp.appCheckProvider`. It never throws: a token comes back as a
result, a failure as the placeholder token plus the error. It survives `close()` and is bound again by the next
`FirebaseAppCheck`, because Firestore, Auth and Database keep the provider they read when they were created.

## Decisions and alternatives considered

This table is the alternatives evaluation: each row names the options, the one chosen, and why each other one was
rejected. D6, D8 and D18 were decided by the repository's owner on 2026-11-28. The rest are the design's own and may
be overruled; D7 is among those and is the one to revisit first.

| # | Question | Chosen | Rejected, and why |
|---|---|---|---|
| D1 | Transport | REST | gRPC on a hand-written proto: no published contract, no SDK uses it, no web (3.1) |
| D2 | Host | `firebaseappcheck.googleapis.com` everywhere | JS's `content-` host: only JS uses it; two hosts mean two request shapes to test. Decided by P1 and P2 before the build |
| D3 | API key | Header | `?key=`: the key lands in every recorded URL |
| D4 | Body casing | snake_case | camelCase: `limitedUse` is sent by no shipping client. Android's mix: two conventions in one body |
| D5 | Day-long block on some statuses | None; every status backs off to a 4 h cap | 400/404 (Android, iOS) or 403/404 (JS): no exit without a restart, and no evidence those statuses never clear on the server |
| D6 | Debug token in release builds (owner) | The Dart package has no guard; the adapter refuses unless opted in | Refusing on `dart.vm.product` in the Dart package: breaks servers and tools that use a debug token on purpose. Doing nothing in the adapter: a Flutter release build is almost always distributed |
| D7 | Debug token sources | Constructor, plus one explicit environment helper | Constructor only: every server would write the same three lines. The CLI's configstore file, a page global, generate-and-store: hidden sources of a secret |
| D8 | Persistence (owner, 2026-11-28) | In 0.1.0: an optional `store`; null means memory; the adapter has a default store | Memory only: one exchange per start and per tab, and it was a goal of the owner's brief. A required store (as Installations): the token is an optimization, not an identity, so memory is a valid choice |
| D9 | Usable margin | `min(5 min, ttl/2)` | 0 (JS): a token can expire on the way. A flat 5 min: a token living under 5 minutes would never be usable |
| D10 | Auto-refresh | On by default; starts after the first token | Off (JS's code): every token is then fetched inside a request. Eager at construction (JS, Android): a constructor that uses the network, and an exchange spent by a tool that never needs a token |
| D11 | Failure on the seam | Placeholder and error | An empty token (C++): callers then send no header, and SHARED requires the placeholder of this repository's providers |
| D12 | What feeds a gate | Every failed exchange, both providers | Statuses only (JS, Android, iOS): a fast transport error or a throwing callback repeats at the app's request rate. Not the debug path (JS, iOS): the same for a refused debug token |
| D13 | Forced-refresh floor | 30 s, the only forced-refresh limit for App Check (SHARED S8) | None: one exchange per request against a backend that rejects everything. A limit in each caller instead: Firestore and Database have none, and several callers would each spend their own |
| D14 | `ttl` bounds | Under 60 s refused; over 7 days clamped | Accepting any positive value: a 1 s lifetime means an exchange per request. Rejecting over 7 days: clients would fail if Google raised the maximum |
| D15 | JWT `iat` of custom tokens | Not parsed | Trusting it within bounds (JS): a claim nobody verified, and JS's own comparison is wrong (MATRIX §3 item 23) |
| D16 | How the client meets the seam | A separate seam object that survives `close()` and is bound again | `FirebaseAppCheck` extending the seam class: the public `getToken` throws and returns `AppCheckToken`, the seam's never throws and returns a result. A seam object removed at `close()`: services that captured it never reach a later instance |
| D17 | Provider type | `abstract final`, a closed set in one library | `sealed`: a new provider breaks exhaustive switches. An open interface: that is the attestor seam, published before anything needs it |
| D18 | Native attestation (owner) | Not planned; no attestor seam | A seam now: six more endpoints, three of them the stateful App Attest calls, with no plugin to use them (11.2) |
| D19 | reCAPTCHA on the web | Later, through `secure_flow` | In 0.1.0: needs a v3 path that does not exist and a site-key probe. An own script loader: a second place that injects Google scripts |
| D20 | Adapter | Registers itself on Linux only; the provider comes from `providerFor` only | Also Windows automatically: replaces a working native implementation silently. Mapping FlutterFire's provider classes and reading environment variables: rules for platforms where the app opts in anyway, and an implicit secret source |
| D21 | Clocks | One per purpose: waits (gate windows, the forced floor, deadlines, timers) on the monotonic source only; a token's age on both, the larger winning | Both clocks for everything (v2): a wall clock moved forward ended every gate window and the floor at once. Wall only (Installations, Remote Config): a clock set back stretches a cached token and holds a window closed. Monotonic only for tokens: a suspended machine can stop a `Stopwatch`, and a stored record has no monotonic age |
| D22 | Gate persistence | Memory; storing them is deferred (11.3) | Stored next to the token now: no upstream SDK does; it needs a configuration fingerprint so that a fixed configuration starts open, and a planted gate record could delay exchanges |
| D23 | Provider deadline | 7 s for the answer, exchange and custom callback alike; a late session answer of the callback is kept | None (every official SDK): a hung request holds every caller of the shared exchange. 7 s with the late answer dropped (v2): a callback that always needs longer could never deliver. A longer limit for the callback (30 s) with the seam answering early: the same outcome as keeping the late answer, with a second number to tune. 10 s or more: the caller's own 10 s wait ends first and the request goes out with no header instead of the placeholder. Source of 7 s: SHARED 5.6 (8 s answer limit minus a second) |
| D24 | Refresh moment | issued + ttl/2 + 5 min, clamped | Expiry − 5 min (iOS in effect): 5 minutes to survive a failing server. Never (C++ desktop): every expiry is paid inside a request |
| D25 | Token stream | New tokens only; no replay; no errors | Replay (JS, Android, C++) and error events (JS): SHARED's contract forbids both; an error event is an unhandled stream error for a listener without `onError` |
| D26 | Backoff formula | `min(1 s × 2^(n−1) × (0.5 + random), cap)` in this package, with two caps | One cap: the 5-minute class would wait up to 4 h after a network outage. A cap before the jitter (v2): waits of up to 6 h, longer than any upstream SDK. A shared calculator: SHARED builds none in 0.1.0 |
| D27 | Stopping an idle refresher | Not done; documented (2.3) | Stop after a period with no `getToken`: Database follows `onTokenChanged` on an open socket without calling `getToken`, so it would lose its tokens. Arm the refresher only while the stream has a listener (proposed in the second review): deferred, because Storage, Auth and the `TokenSource` products never listen and would then pay an exchange inside a request each period, and Firestore listens anyway, so few programs would gain the clean exit |
| D28 | Refresher retry | When the gate opens, not sooner than 30 s | Its own 30 s to 16 min ladder (JS, Android, iOS): a second backoff next to the gate's, with different numbers |
| D29 | What the custom callback is told | `limitedUse` and `forceRefresh` | Neither (JS): a limited-use request would get a session token, and a forced request the token just rejected |
| D30 | Expiry counted from | Before the request (iOS) | After the response (JS, Android): the token is believed to live longer by the request's duration |
| D31 | Identity headers for restricted keys | None | Caller-supplied values: an unchecked claim (§7 question 6) |
| D32 | Concurrent session calls | One exchange; forced calls join it | Forced calls starting their own (iOS): two services reacting to one revocation spend two exchanges |
| D33 | Accepted status | Exactly 200 (JS) | Any 2xx (Android): a 204 or 202 has no token to read |
| D34 | `close()` and a request in flight | Cancelled through `sendCapped`'s `cancel` future; pending calls answered at once; a late result dropped | Not cancelling: an owned client could be closed only after up to 7 s. Waiting for the request before answering callers: `close()` and app deletion would block on the network |
| D35 | Default logger | None | `print` or `stderr` for the debug notice: an output channel the library opens unasked, in programs whose output is piped or collected |
| D36 | Gates | Two: session and limited-use | One: a burst of limited-use failures stops session tokens for every service |
| D37 | Order of stored records | By issue time; own exchange always overwrites; adopt only a later-issued record | By expiry (v1): discards a forced exchange whenever an older or planted record expires later. A write counter: a second number to keep consistent across tabs, when the issue time already orders exchanges |
| D38 | Load and write timing | Lazy load at the first call, at most 500 ms; writes not awaited; every store failure caught, `Error`s included | Load in the constructor: a constructor that does I/O, and an unhandled failure with no caller. No deadline: a blocked store stops every token request and breaks the seam's 8 s. Awaited writes: a slow store delays every caller for an optimization |
| D39 | Instances on one store at refresh time | Adoption by issue time, plus a random lead per instance on the due time (`random × min(2 min, ttl/10)`) | No lead (v2): instances holding one record are due at the same millisecond and each exchanges. Dropping live adoption (load once, write always): each tab then exchanges every period, which the store was meant to save on the web. A Web Lock around the refresh: browser-only code and frozen-tab cases. Installations' marker-and-wait pattern: built for a one-time registration, not a recurring refresh; a second protocol on the same store |
| D40 | Services that keep the provider they read at creation (Firestore, Auth, Database) | A seam object that survives `close()` and is bound again; the creation order stated (2.3) | Those services reading `app.appCheckProvider` per request, as Storage, Analytics and Error Reporting do: the right fix, but it changes three released packages and is not this package's to make (§16 idea 2). A forwarding slot created with every `FirebaseApp`: a change to `firebase_app_dart` beyond SHARED's seam change, and one more async call per request for apps without App Check. A warning from those services when they capture no provider: it would fire in every app that does not use App Check |
| D41 | The constants | 7 s: SHARED 5.6. 30 s (forced floor, refresher minimum): the first retry delay of the refresh in JS, Android and iOS (C64). 4 h: the upstream backoff cap (5.7). 5 min margin: Android, iOS, SHARED S1. 60 s `ttl` floor, 500 ms store read, 5 min unreachable cap, the 2 min lead: this design's own, not measured | For each of the four own values the alternative considered was "none" (no floor, no read limit, one cap, no lead); the sections that introduce them give the failure "none" allows |

## Departures from upstream

Reference per area: protocol JS; token validity Android and iOS; expiry origin iOS; gating scope Android. Each row is
checked with a revert of the code and a test that must then fail.

| # | Area | Departure | Failure it fixes | Pinning test |
|---|---|---|---|---|
| 1 | Secrets | the debug token is never logged, printed or stored | JS, Android and C++ log it (C107, C109, C110) | `security/sentinel_test.dart` |
| 2 | Secrets | explicit sources only | a production page enters debug mode from a global (C89) | `debug_provider_test.dart` "no implicit source" |
| 3 | Gate | every failure counts, for both providers | JS and iOS do not throttle debug exchanges (C50, C54); no SDK counts transport errors (C49, C55) | `gate_test.dart` "every failure class" |
| 4 | Gate | no day-long block | a 400 or 404 blocks Android and iOS for a day with no exit (C51, C54) | `gate_test.dart` "404 backs off" |
| 5 | Gate | a generation per gate; separate gates | none upstream; one burst of failures would otherwise count many times | `gate_test.dart` "fifteen concurrent failures count once" |
| 6 | Gate | the failing call keeps its own code | JS replaces it with `initial-throttle` (C56) | `gate_test.dart` "first failure keeps its code" |
| 7 | Manager | usable margin `min(5 min, ttl/2)` | JS hands out a token that expires on the way (C59) | `manager_test.dart` "margin" |
| 8 | Manager | forced floor of 30 s | none upstream; one exchange per request against a rejecting backend | `manager_test.dart` "forced floor" |
| 9 | Manager | no request from the constructor | JS exchanges at `initializeAppCheck` (C66) | `manager_test.dart` "constructor sends nothing" |
| 10 | Manager | expiry counted from before the request (iOS) | JS and Android count from after the response (C37) | `exchange_test.dart` "expiry from send time" |
| 11 | Manager | waits on a monotonic source; a token's age on two clocks | Installations and Remote Config of this repository use the wall clock alone; upstream guards only its backoff | `clock_test.dart` "a forward jump ends no window", "a clock set back does not extend a cached token" |
| 12 | Request | a 7 s deadline | no official SDK sets one (CHECK M12) | `exchange_test.dart` "deadline" |
| 13 | Request | API key in a header, one host | JS and Android put the key in the URL (C6, C7) | `request_shape_test.dart` |
| 14 | Parsing | strict `ttl` grammar, 60 s floor, 7-day clamp | JS passes `1.2.3s` to `Number()` (C36); C++ truncates (C46) | `ttl_test.dart` |
| 15 | Custom | told `limitedUse` and `forceRefresh`; JWT not parsed; expiry bounded | JS tells it neither and trusts `iat` (C50, C114) | `custom_provider_test.dart` |
| 16 | Seam | a limited-use failure is the placeholder and an error (Android, iOS) | JS rejects (CHECK M3); the seam's contract is "no throw" | `seam_test.dart` "limited-use failure" |
| 17 | Seam | the seam object survives `close()` | none upstream; services here capture the provider once | `seam_test.dart` "re-bound after close" |
| 18 | Stream | no error events, no replay | JS sends errors to listeners and replays (C85) | `manager_test.dart` "no error events", "no replay" |
| 19 | Refresher | no retry ladder of its own | a second backoff beside the gate (C64) | `refresher_test.dart` "retries when the gate opens" |
| 20 | Errors | fixed messages; server text only in a field | Android and C++ put the body in the message (C42, C110) | `security/sentinel_test.dart` |
| 21 | Storage | opt-in; the debug token never stored | JS always writes IndexedDB, the debug token included (C74) | `store_test.dart` "no store, no writes"; `web_storage_test.dart` |
| 22 | Security | caps, refused redirects, constructor-only origin | JS reads the body with no cap (`JS/client.ts:80-90`, not re-pinned) | `security/limits_test.dart` |
| 23 | Storage | records ordered by issue time; a deadline on the load; failures survived | none upstream to compare for the order; JS swallows storage failures without a deadline (C75) | `store_test.dart` "a forced refresh replaces a record that expires later" |
| 24 | Refresher | a random lead on the due time | none upstream; instances on one stored record would refresh together | `refresher_test.dart` "two instances with different leads make one exchange" |
| 25 | Custom | a late answer to a session request is kept | none upstream (no deadline exists there) | `custom_provider_test.dart` "a late session result is kept" |

