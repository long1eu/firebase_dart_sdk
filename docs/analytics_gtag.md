# Analytics: a gtag transport (plan)

A third, optional transport for `firebase_analytics_dart`, next to `relay` and `direct`. It sends events the
way gtag.js does from a web page: to `/g/collect`, with the public measurement id and no API secret. An app
can then report to Google Analytics without a relay and without shipping a secret.

**Status: planned, not built.** The protocol of gtag.js is not documented. Nothing below is implemented until a
capture of real gtag.js traffic confirms it (section 4). This page says what is expected, what must be
measured, and how the transport will be built.

## 1. Why

- The Measurement Protocol needs an `api_secret` on every request. A secret in an app is not a secret:
  compiling it into a binary hides nothing, since it can be read from the binary or from the traffic. So the
  client offers a relay ([analytics_spec.md](analytics_spec.md), section 5), which some users do not want to run.
- gtag.js reports from every web page with only the measurement id, which is public. A Dart client that speaks
  the same protocol needs no secret and no relay.
- The emulation of the Android SDK's own protocol was considered and rejected. It is binary and tied to the
  Firebase installation and the app instance id, it is likely to break with each SDK release, and it means
  emulating a closed SDK rather than a browser.

## 2. What it costs

- **Not documented.** Google can change `/g/collect` at any time and without notice. The transport is opt-in,
  marked experimental, and a change shows as missing data, not as an error: the endpoint answers 2xx to
  almost anything.
- **Web traffic.** As with the Measurement Protocol, the data lands in a web stream and shows as web traffic,
  not as an app.
- **Terms.** Whether a non-browser client may send this traffic under the Google Analytics terms is for each
  user to judge. The README of the transport says so.
- **No validation server.** `/debug/mp/collect` checks Measurement Protocol bodies only. The client keeps its
  own validation (protocol §9) and the limits of protocol §4 until a capture shows different ones.

## 3. What is expected, to confirm

These are expectations from what gtag.js is generally seen to send. None is a fact for this project until the
capture of section 4 shows it.

| Expected | To confirm |
|---|---|
| `POST https://www.google-analytics.com/g/collect`, and a regional host for the EU | the host for each region, and whether GET is also used |
| Request-level parameters in the query string: `v=2`, `tid` (measurement id), `cid` (client id), `sid` (session id), `sct` (session count), `seg` (engaged session), `ul` (language), `sr` (screen), `dl`, `dt` (page location and title), `_p`, `_s` (hit counter) | each name, which are required, and their order |
| One event per line of the body when several are batched, each with `en` (name), `ep.<name>` (text parameters), `epn.<name>` (numeric parameters), `_et` (engagement time) | the line format, the batch size, the body limit |
| User properties as `up.<name>` and `upn.<name>`, and the user id as `uid` | whether they are sent on every request or once |
| Flags `_fv` (first visit), `_ss` (session start), `_nsi` (new session id), `_dbg` (debug mode) | which flags make Google Analytics derive `first_visit` and `session_start` |
| Consent as `gcs` and `gcd` | the encoding of each consent state |
| A 204 answer | the answers to a malformed request |

If gtag.js lets Google Analytics derive `first_visit`, `session_start` and `user_engagement` from these
flags, the transport would report sessions and new users the way a web page does, which the Measurement
Protocol cannot do (protocol §6).

## 4. The capture

The owner of the project captures the traffic. This repository sends nothing to Google Analytics endpoints.
The steps are in [tool/gtag_capture.md](../tool/gtag_capture.md): a local test page,
[tool/gtag_capture.html](../tool/gtag_capture.html), runs gtag.js against a test stream, with one button for
each scenario, and the browser's developer tools record the requests. The capture is saved outside the
repository, since it holds the measurement id and the client id.

From the capture, this page gets a section "What gtag.js sends", with the date of the capture and the version
of gtag.js. Section 3 is then replaced by facts.

## 5. Design, once the capture is in

- `AnalyticsTransport.gtag()`: no secret and no relay; the measurement id as for `direct`.
- The queue, the batching, the retries and the stores stay as they are. Only the encoding of a batch and the
  endpoint change, so the transport is a new encoder behind the existing sender.
- One class owns the wire format, as `ClientIdentity` owns the identifier today. The rest of the package
  does not know which transport is used.
- Tests compare the encoder's output with requests from the capture, with the identifiers replaced.
- The web build keeps working: on the web, the transport is still a plain `package:http` request.
- The README of the package lists the transport under "experimental", with section 2 of this page.

## 6. Order of work

1. This plan, the capture guide and the test page (this PR).
2. The capture, by the owner. Its results are written into this page.
3. The encoder and the transport, with tests from the capture, in one PR.
