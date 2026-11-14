# server_shelf

A small task API on [`package:shelf`](https://pub.dev/packages/shelf) that reads and writes
Firestore with `cloud_firestore_dart`, and keeps one real-time listener on the collection whose
changes it sends to every connected client as [server-sent events][sse].

| Route | What it does |
| --- | --- |
| `GET /tasks` | All tasks, ordered by `createdAt`. `?done=true` or `?done=false` filters (unordered). |
| `POST /tasks` `{"title": "..."}` | Creates a task with a server timestamp; `201 {"id": "..."}`. |
| `GET /tasks/<id>` | One task, or `404`. |
| `PATCH /tasks/<id>` `{"done": true}` | Marks it done or open; `404` for a missing task. |
| `DELETE /tasks/<id>` | Deletes it; `204`. |
| `GET /events` | `text/event-stream`: a `snapshot` event with the current tasks, then `added`, `modified` and `removed` events, and a `: ping` comment every 15 s. |
| `GET /healthz` | `ok` |

What it shows:

- One `Firestore` instance for the process, created at startup from environment variables
  (`lib/firestore_from_env.dart`) and terminated on `SIGINT` / `SIGTERM`, so the process exits
  cleanly on Cloud Run and in containers.
- No cache on disk: the default memory cache.
- Reads with `Source.server`, so a response is never served from a stale cache. Writes are
  awaited, so a `201` means the backend accepted the write.
- One listener shared by every client (`lib/change_feed.dart`) instead of one per HTTP
  connection. A task created through the API shows up as `added` with the local estimate of its
  server timestamp, then as `modified` once the backend has filled the timestamp in.
- Firestore errors mapped to HTTP statuses (`not-found` 404, `permission-denied` 403,
  `unavailable` 503, ...).

[sse]: https://html.spec.whatwg.org/multipage/server-sent-events.html

## Run it against the Firestore emulator

Needs the Dart SDK (3.8 or later) and a Firestore emulator. From this directory:

```sh
# In one terminal: an emulator (firebase CLI), or the emulator JAR directly:
#   java -jar cloud-firestore-emulator-v1.22.0.jar --host 127.0.0.1 --port 8080
firebase emulators:start --only firestore --project demo-example

# In another:
dart pub get
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 PORT=8000 dart run bin/server.dart
```

Then:

```sh
curl -N localhost:8000/events &                            # watch the changes
curl -X POST -d '{"title":"Write the docs"}' localhost:8000/tasks
curl localhost:8000/tasks
curl -X PATCH -d '{"done":true}' localhost:8000/tasks/<id>
curl -X DELETE localhost:8000/tasks/<id>
```

The tests run the same API in-process against the emulator (skipped without it):

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
```

## Point it at a real project

Nothing about the project is in the files; everything comes from the environment:

| Variable | Meaning |
| --- | --- |
| `FIREBASE_PROJECT_ID` | The project id. Required when `FIRESTORE_EMULATOR_HOST` is not set. |
| `FIRESTORE_DATABASE` | A named database (default `(default)`). |
| `FIREBASE_API_KEY` | Optional: the Web API key of the project, sent with each request. Unset, no key is sent. |
| `GOOGLE_APPLICATION_CREDENTIALS` | A service account key file, if you use one (see below). |
| `TASKS_COLLECTION` | The collection (default `tasks`). |
| `PORT` | The HTTP port (default `8000`; Cloud Run sets it). |

```sh
unset FIRESTORE_EMULATOR_HOST
gcloud auth application-default login         # or GOOGLE_APPLICATION_CREDENTIALS=/path/key.json
FIREBASE_PROJECT_ID=<your project> dart run bin/server.dart
```

The requests carry Application Default Credentials (on Cloud Run, the service account of the
service). **These credentials bypass Firestore security rules**: access is decided by IAM (the
`Cloud Datastore User` role). Add your own authentication in front of the API before you expose
it. Do not commit key files.

This program has been run against the emulator only, not against a real project. The
credential path it uses is the one of `firebase_auth_providers_dart`, whose own status is in
[docs/guides/authentication.md](../../docs/guides/authentication.md).

## Notes

- `pubspec.yaml` takes the three packages from this repository (path dependencies and
  `dependency_overrides`), so the example runs against the code next to it. Outside the
  repository, replace both with the versions on pub.dev (`^0.1.0`).
- [dart_frog](https://dartfrog.vgv.dev) would also work; it needs its own CLI (`dart_frog_cli`)
  to generate the server, so this example sticks to plain shelf, which runs with `dart run`.
