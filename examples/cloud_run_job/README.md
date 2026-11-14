# cloud_run_job

A one-shot job for [Cloud Run Jobs](https://cloud.google.com/run/docs/create-jobs) (or cron, or
CI) built with `cloud_firestore_dart` and compiled to a native binary:

1. **Aggregation query**: counts the paid orders of a collection and sums and averages their
   `amount` in one `aggregate([count(), sum('amount'), average('amount')])` query. The backend
   computes the result; no order document is downloaded.
2. **Transaction**: writes the summary to a report document with `runTransaction`. The report
   remembers the execution that wrote it (`CLOUD_RUN_EXECUTION`), so a retry of the same
   execution finds it written and does not count the run twice.
3. **Retries**: both steps go through `withRetries` (`lib/retry.dart`). An attempt that fails
   with `unavailable`, `deadline-exceeded`, `resource-exhausted`, `aborted` or `internal`, or
   that does not finish within 60 s, is tried again after an exponential backoff with full jitter
   (1 s doubling up to 30 s), at most `MAX_ATTEMPTS` times. Other errors end the job at once.
4. **Exit code**: `0` on success, `1` when a step failed (Cloud Run then retries the task as
   configured with `--max-retries`), `78` when no backend is configured.

The job uses the memory cache and no listeners: nothing is written to disk, and the instance is
terminated at the end so the process exits.

## Run it against the Firestore emulator

Needs the Dart SDK (3.8 or later) and a Firestore emulator. From this directory:

```sh
firebase emulators:start --only firestore --project demo-example    # in another terminal

dart pub get
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
dart run bin/seed.dart     # 10 sample orders, 7 of them paid (emulator only)
dart run bin/job.dart
# summary: 7 paid orders, revenue 280.00, average 40.00
# report reports/orders written for local-2026-...
```

`CLOUD_RUN_EXECUTION=run-1 dart run bin/job.dart`, run twice, shows the second run finding the
report already written. With `FIRESTORE_EMULATOR_HOST=127.0.0.1:9` (nothing listening) and
`MAX_ATTEMPTS=3` it shows the retries and exits with `1`.

The tests cover the retry helper on its own, and run the seed and the job as programs against
the emulator (skipped without it):

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
```

## Point it at a real project

Nothing about the project is in the files or the image; everything comes from the environment:

| Variable | Meaning |
| --- | --- |
| `FIREBASE_PROJECT_ID` | The project id. Required when `FIRESTORE_EMULATOR_HOST` is not set. |
| `FIRESTORE_DATABASE` | A named database (default `(default)`). |
| `FIREBASE_API_KEY` | Optional: the Web API key of the project, sent with each request. Unset, no key is sent. |
| `ORDERS_COLLECTION` | The orders (default `orders`). |
| `REPORT_DOCUMENT` | The report document (default `reports/orders`). |
| `MAX_ATTEMPTS` | Attempts per step (default `5`). |
| `CLOUD_RUN_EXECUTION` | Set by Cloud Run Jobs; locally a time-based id is used. |

The aggregation filters on `status` only, so it needs no composite index.

Locally:

```sh
unset FIRESTORE_EMULATOR_HOST
gcloud auth application-default login         # or GOOGLE_APPLICATION_CREDENTIALS=/path/key.json
FIREBASE_PROJECT_ID=<your project> dart run bin/job.dart
```

As a Cloud Run job (from the repository root; the build context is the root because the example
depends on the packages of this repository by path):

```sh
docker build -f examples/cloud_run_job/Dockerfile -t <region>-docker.pkg.dev/<project>/<repo>/order-report-job .
docker push <region>-docker.pkg.dev/<project>/<repo>/order-report-job
gcloud run jobs create order-report \
  --image <region>-docker.pkg.dev/<project>/<repo>/order-report-job \
  --region <region> --service-account <service account> \
  --set-env-vars FIREBASE_PROJECT_ID=<project> --max-retries 3
gcloud run jobs execute order-report --region <region>
```

The service account needs the `Cloud Datastore User` role. The job gets its access token from the
metadata server (Application Default Credentials); there is no key file in the image. These
credentials **bypass Firestore security rules**.

The `Dockerfile` builds in the `dart:3.12.2` image (pinned by digest) and copies the binary and
the image's `/runtime/` (C library, DNS resolver, CA certificates) onto `scratch`.
`Dockerfile.dockerignore` limits the build context to the files the build needs.

## What was and was not run

- The job, the seed and the tests were run against a local Firestore emulator (v1.22.0), and
  the binary from `dart compile exe bin/job.dart` against the same emulator, on macOS.
- **The Docker image was not built and the job was not deployed**: the `Dockerfile` follows the
  documented use of the official `dart` image but is unverified, and nothing in this example has
  run against a real project.

## Notes

- The packages are not on pub.dev yet, so `pubspec.yaml` takes them from this repository through
  `dependency_overrides`.
- `lib/firestore_from_env.dart` is the same file in the three examples of `examples/`.
