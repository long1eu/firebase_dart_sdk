# Analytics reporting probe

`firebase_analytics_dart` will send events over the GA4 Measurement Protocol with a `client_id` it generates
itself. Google's documentation says a valid web event needs a `client_id` "that has already been used to send an
event from gtag.js" ([analytics_protocol.md](../docs/analytics_protocol.md), section 5). If Google Analytics does
not report events from a generated id, the package cannot work as designed. This probe checks that before any of
the client is built, and step 3 of [analytics_spec.md](../docs/analytics_spec.md) waits for its result.

The code is `tool/analytics_probe.dart`. It needs only the Dart SDK: no `pub get`, no packages from this
repository.

## What it does

1. It generates a `client_id` in the documented form (two positive numbers joined by a period), a `session_id`
   (the time of the first event, in seconds) and a six-character run tag.
2. It sends six events and the user property `probe_kind` to the **validation server**
   (`/debug/mp/collect`) in strict mode (`ENFORCE_RECOMMENDATIONS`), and the control body too when there is one.
   That server records nothing. Unless it answers 200 with no validation messages, the probe prints what it got
   and stops.
3. It sends three events with `debug_mode` to `/mp/collect`, for DebugView: `probe_start`, `page_view` and
   `level_up`.
4. It sends three events without `debug_mode` to `/mp/collect`, for Realtime and the standard reports:
   `probe_report`, `page_view` and `select_content`.
5. With `--control-client-id`, it sends the events of step 4 again under that client id (see below).
6. It prints what to look for in DebugView, Realtime and, 24 to 48 hours later, the standard reports. It also
   prints this after a failed step, whenever `/mp/collect` may already have recorded something.

Every event carries `session_id`, `engagement_time_msec`, `probe_run` (the run tag) and `probe_arm` (`generated`
or `control`). Each request carries a `device` block with category `desktop`, the operating system, and the
two-letter language of the locale without its region. There is no `user_location`, no `ip_override` and no
`user_id`. Event timestamps lie within the two minutes before the run, so a clock that runs a little fast still
dates them in the past.

## The control

The validation server checks neither the secret nor the stream, and `/mp/collect` answers 2xx either way. A
mistyped secret, or one from another stream, therefore looks like a clean run, and nothing appears in Google
Analytics. Without a control, "nothing appeared" cannot be told apart from "the generated `client_id` is not
reported".

The control is a `client_id` that gtag.js has already used on the same stream. Open a page tagged with that
stream in a browser, then read the `_ga` cookie (for example `GA1.1.123456789.1700000000`) from the browser's
developer tools, and pass it as `--control-client-id=GA1.1.123456789.1700000000`. The probe sends the reporting
events under it with `probe_arm=control`. If the control events appear and the generated ones do not, the
generated id is the cause. If neither appears, check the secret and the stream. Without a control, record a
negative result as inconclusive.

## What it does to your property

- It writes six events and one user property under one new `client_id`, plus three events under the control
  `client_id` if one is given. That is one new user and one session in the property's data. Data sent to Google Analytics cannot be deleted event by event, so use a test property or
  one where a single probe user does not matter.
- It creates nothing: no property, stream, secret or custom dimension.
- The API secret comes from `GA_API_SECRET` and is never printed or stored. The probe prints only the status
  and content type of a refused request. Validation messages are printed with the secret (in its plain,
  URL-encoded and HTML-escaped forms) and control characters removed. An error prints only its type, since its
  message could quote the URL. An unknown argument prints only the option's name.
- Requests go only to `www.google-analytics.com`, or to `region1.google-analytics.com` with `--region=eu`.
  Redirects are not followed. A refused request is not retried, and at most 64 KiB of an answer is read.
- If a request to `/mp/collect` was sent but no answer came, the probe says it may have been recorded and asks
  you to check DebugView before running again, so that a second run does not add a second probe user.
- Without `--yes` it prints the plan and sends nothing.

## Before running it

You need a GA4 property with a **web** data stream:

- The stream's Measurement ID (`G-…`), under Admin > Data streams > the stream.
- A Measurement Protocol API secret for that stream, created on the same page under Measurement Protocol API
  secrets.
- To see `probe_run` and `probe_kind` in the standard reports (DebugView shows them without this), register
  them first under Admin > Custom definitions: `probe_run` as an event-scoped and `probe_kind` as a user-scoped
  custom dimension.

## Commands

From the repository root:

    export GA_MEASUREMENT_ID=G-XXXXXXXXXX
    read -rs GA_API_SECRET && export GA_API_SECRET       # paste the secret; it is not echoed
    dart tool/analytics_probe.dart                       # prints the plan, sends nothing
    dart tool/analytics_probe.dart --yes                 # sends
    unset GA_API_SECRET

Options:

- `--control-client-id=ID` sends the reporting events under a client id from gtag.js too (see The control).
- `--region=eu` sends to `region1.google-analytics.com`.
- `--print` prints the three request bodies and exits. It needs no secret.
- `--help` prints the usage.

Exit codes: 0 when all three requests were accepted, 2 when it sent nothing for lack of `--yes`, 64 for a bad
argument or a missing variable, and 1 when a request failed or was refused.

## Recording the result

The probe ends with a checklist. Write the answers into
[analytics_protocol.md](../docs/analytics_protocol.md), section 10, with the date and the run tag:

1. Did the events of the generated `client_id` appear in DebugView? In Realtime? In the standard reports after
   24 to 48 hours? And those of the control?
2. Which country was reported, if any? The probe sends no location, and its language carries no region.

A 2xx answer from `/mp/collect` proves only that the request arrived. The endpoint answers 2xx even for data it
does not process.

**Status of the probe itself:** analyzed. Its plan output, `--print` and the refusals of bad arguments, of a
missing `--yes` and of missing variables were run locally. Its requests were checked against a local fake
server, using a copy of the script pointed at that server, in six cases: valid answers with a control,
validation messages that echo the secret and a terminal escape, a 302 whose body echoes the secret, a 400, a
500 from the validation server, and an answer that never comes. The secret did not appear in any output. An
independent review of its secret handling and of how misleading its results could be found the missing
control and the unredacted server text, both fixed here. It has not been run against Google Analytics.
