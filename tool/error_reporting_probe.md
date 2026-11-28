# Error Reporting probe

`firebase_error_reporting_dart` will send Dart errors to Cloud Error Reporting, which parses stack traces of
Java, Python, JavaScript (V8), Ruby, C#, PHP, Go and Rust, not Dart
([error_reporting_spec.md](../docs/error_reporting_spec.md), section 3.4). The client therefore either rewrites
Dart frames into the V8 format (format A) or sends the raw Dart trace with a `reportLocation` (format B). This
probe sends both, with variations, so the console shows which one groups and displays Dart errors well. It
answers the questions of section 11 of the spec. The client keeps the choice behind one formatter, so the result
changes only that part.

The code is `tool/error_reporting_probe.dart`. It needs only the Dart SDK: no `pub get`, no packages from this
repository.

## Before running it

The maintainer runs it, in a project of their own. Nothing in this repository creates a project, an API key, a
service account or a role binding.

1. Choose a Google Cloud project (the project behind a Firebase app is fine) and enable the Error Reporting API
   in it.
2. Get one credential:
   - **An access token** of an account with the Error Reporting Writer role (`roles/errorreporting.writer`) or
     Owner: `export ER_ACCESS_TOKEN="$(gcloud auth print-access-token)"`. The probe sends the project as the
     quota project (`x-goog-user-project`), which a user's token needs.
   - **Or an API key** restricted to the Error Reporting API: `read -rs ER_API_KEY && export ER_API_KEY`.
     Error Reporting documents API keys for `events:report`.
3. Optionally, `ER_OTHER_API_KEY`: a key restricted to a different API, for case K1.

```
export ER_PROJECT_ID=my-project
dart tool/error_reporting_probe.dart          # prints the plan, sends nothing
dart tool/error_reporting_probe.dart --print  # prints the request bodies, needs no credential
dart tool/error_reporting_probe.dart --yes    # sends
```

`--only=A1,B1` sends some cases only. The credential is never printed, and the probe redacts it from server
text. Unset it afterwards (`unset ER_ACCESS_TOKEN ER_API_KEY ER_OTHER_API_KEY`) and delete a key made only for
this.

## What it sends

Every event has the service `error-reporting-probe`, the run tag as its version, and a message ending in
`[probe <run tag> <case>]`. The error is a `StateError` in an invented app, `probe_notes`, with `package:` frames,
two `dart:` frames on top (as a core error has), and a `package:flutter` frame where a case says so.

| Case | What it is | What it tells |
|---|---|---|
| A1 | format A, no `reportLocation` | is a V8-shaped Dart trace parsed? (question 1) |
| A2 | A1 with another message | does grouping ignore the message? (2) |
| A3 | A1 with other top frames | do frames split groups? (2) |
| A4 | A1 with `reportLocation` | does a location change grouping or display? (3) |
| A5, A6 | app frames under library frames, and the app frames alone | are `dart:` and `package:flutter` frames skipped? (4) |
| F1, F2 | A1 with `[fatal]` after the colon, and before the type | can the header keep fatal errors apart? (5) |
| B1, B2 | format B, two messages | how format B groups and shows (2) |
| B3 | format B without `reportLocation` | refused, or kept without a trace? (8) |
| O1 | an obfuscated trace with `build_id` | what the console shows |
| U1 | A1 with `context.user` and `httpRequest` | where they appear (7) |
| S16, S64, S256 | format A of about 16, 64 and 256 KiB | the size limit (6) |
| T1 | `eventTime` 25 hours ahead | the documented refusal, status and body (8) |
| K1 | A1 with `ER_OTHER_API_KEY` | how a key for another API is refused (8) |

The probe sends the cases one at a time, a second apart, prints each status, and stops if the first request is
refused with 401 or 403 (a wrong credential, a missing role, or the API not enabled). At the end it prints the
statuses and what to look for.

## What to record

Open Google Cloud console > Error Reporting in the project, filter by the service and the run tag, open each group,
and note which cases it holds. Groups can take a few minutes to appear. Then add a section to
`docs/error_reporting_spec.md` with the date, the run tag, and the answers:

1. Is A1's trace shown as parsed frames, with file and line?
2. Is A2 in A1's group, and A3 in its own? Are B1 and B2 in one group?
3. Is A4 in A1's group, and does the location change what is shown?
4. Are A5 and A6 in one group?
5. Are F1 and F2 in A1's group or apart from it?
6. The statuses of S16, S64 and S256.
7. Where U1's user and request appear.
8. The statuses and messages of B3, T1 and K1, and how O1 is shown.

The 17 or 18 events leave a handful of groups in the project. They expire with the 30-day retention, or can be muted.
