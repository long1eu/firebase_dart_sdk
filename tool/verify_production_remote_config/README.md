# Remote Config production verification kit

`firebase_installations_dart` and `firebase_remote_config_dart` have no emulator to test against: the Firebase CLI has
none for Remote Config or Installations. This kit runs both clients against a **real** Firebase project and prints,
for each of seven checks, `PASS`, `FAIL`, `INCONCLUSIVE` or `SKIPPED` with a one-line explanation. It answers what
the unit tests cannot: that the real servers accept the requests the clients send, that the ETag round trip works,
and that a realtime update arrives.

The code is `firebase_remote_config/firebase_remote_config_dart/tool/verify_production.dart`; `run.sh` here runs it
from the right directory. It is modelled on the Storage kit (`tool/verify_production_storage`).

## Before you run it

1. Use a project you can spare, or one whose Remote Config template you may change. The kit changes nothing in the
   project itself, but the realtime check asks **you** to publish a change.
2. Register a web app in the project (project settings, "Your apps"). It gives you the **app id**
   (`1:<project number>:web:<hash>`) and the **API key**. The project number inside the app id is what the realtime
   check needs. Use an API key without restrictions, or one with no application restriction whose API restrictions allow the
   Firebase Installations API, the Firebase Remote Config API and the Firebase Remote Config Realtime API (without
   the last, check 6 fails with a 403 `stream-error`). A desktop program sends no package name, certificate or
   bundle id. The app is a web app (or any app) of the project; the console has no desktop app type.
3. In the Firebase console, open Remote Config and **publish a parameter named `rc_probe_flag`** (any type, any
   value). The checks that read values expect it; without it they end `INCONCLUSIVE`.
4. For the realtime check, have the console open on that template. You will change a value and publish while the
   kit waits (5 minutes by default).

## What it does to your project

- It registers **one installation** (Firebase Installations) and deletes it at the end, also when a check failed and
  when you press Ctrl-C. If the deletion fails it says so; the installation then stays registered on the server.
- It reads the Remote Config template as that installation twice, and once more for each realtime update it
  receives. It never writes the template.
- It stores the installation record (the id and its tokens) in a new private temporary directory and removes the
  directory at the end. If that fails it names the directory to remove by hand.
- It never prints the API key, a token or the installation id. It prints the project id and the app id first.
- Against the real project it does nothing without `--yes`: without it, it prints the plan and exits 2.

## Commands

From the repository root (the folder that holds `tool/` and `firebase_remote_config/`):

    export FIREBASE_TEST_PROJECT_ID=my-project
    export FIREBASE_TEST_APP_ID=1:123456789:web:abc123
    export FIREBASE_API_KEY=...                                  # or --api-key=

    tool/verify_production_remote_config/run.sh                  # prints the plan, does nothing
    tool/verify_production_remote_config/run.sh --yes            # runs the checks
    tool/verify_production_remote_config/run.sh --yes --skip-realtime
    tool/verify_production_remote_config/run.sh --yes --realtime-window=120

Options: `--project-id`, `--app-id`, `--api-key` (instead of the variables), `--realtime-window=SECONDS` (default 300,
from 1 to 3600), `--skip-realtime`, `--help`.

Save the report: `... --yes | tee verify_remote_config_report.txt`. It holds the project id and the app id, and no
credentials.

Exit code: 0 when no check failed, 1 when one is `FAIL`, 2 for a missing option or a missing `--yes`, 64 for an
unknown option, 130 after Ctrl-C.

## The checks and how to read them

| id | check | what a result means |
| --- | --- | --- |
| 1 | create installation | `getIdAndToken()` registers the installation: the server answers the create request, the id has 22 characters and an auth token came back. `FAIL` carries the error code and the HTTP status (`bad-config` for 400 or 403: look at the key's restrictions). |
| 2 | forced token refresh | `getIdAndToken(forceRefresh: true)` asks the server for a new auth token and the id stays the same. |
| 3 | fetch | `fetch(minimumFetchInterval: Duration.zero)` is accepted and a template version is stored. `INCONCLUSIVE` when the project has no published template. |
| 4 | activate and read | `activate()` returns true and `rc_probe_flag` reads with the source `valueRemote`. `INCONCLUSIVE` when the template has no such parameter. |
| 5 | NO_CHANGE with the stored ETag | A second fetch of the same template version must answer `unchanged`: the server returned an ETag on the first fetch (it does so only for gzip-compressed answers), the client stored it and sent it as `If-None-Match`. `FAIL` if the result is `updated`. `INCONCLUSIVE` if the template version changed between the two fetches (someone published): run the kit again. |
| 6 | realtime invalidation | The client opens the realtime stream and the kit waits for you to publish a change; `PASS` when an update arrives (the line says after how many seconds and how many keys changed). `INCONCLUSIVE` when nothing was published in the window, which says nothing against the stream. `FAIL` when the stream reports an error, such as `stream-error` for a missing project number or a refused request. |
| 7 | delete installation | `delete()` removes the installation on the server and from the store. |

A check that needs an earlier one that did not pass is `SKIPPED`. Check 6 is also `SKIPPED` with `--skip-realtime`.

What to send back: the whole report, to the maintainer who asked you to run the kit.

## Not verified

- A restricted API key (Android or iOS application restrictions): the `headers` option of `FirebaseInstallations` is
  not exercised by this kit.
- The realtime stream beyond the first update: reconnects, a stream that runs for hours, `featureDisabled`.
- A fetch while the throttle is active, and custom signals: they need many requests or a template with conditions
  on them.
- Anything on the web: the browser tests run against a local server (`tool/test_browser_remote_config.sh`), and
  `examples/remote_config_web` is a page you can open by hand.
