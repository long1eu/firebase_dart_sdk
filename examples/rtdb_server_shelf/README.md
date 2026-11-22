# rtdb_server_shelf

| | |
| --- | --- |
| Product | Realtime Database (`firebase_database_dart`) |
| Platform | Dart server (VM), `package:shelf` |
| Backend | Realtime Database emulator, project `demo-example`; start it from the repository root with `tool/start_database_emulator.sh` (port 9100) |
| Run | `FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 PORT=8000 dart run bin/server.dart` |
| CI | not in CI yet; run by hand against the emulator |
| Web gallery | - |

A small notes API that shares **one** `FirebaseDatabase` between all requests, plus a
[server-sent events][sse] route that streams the value of a path.

| Route | What it does |
| --- | --- |
| `GET /notes?limit=20` | The newest notes (push ids sort by time), at most `limit` (1 to 200). |
| `POST /notes` JSON object | Creates a note with `push()` and a server `createdAt`; `201 {"id": "..."}`. |
| `GET /notes/<id>` | One note, or `404`. |
| `PATCH /notes/<id>` JSON object | `update()` of the given fields; `404` for a missing note. |
| `DELETE /notes/<id>` | Removes it; `204`. |
| `GET /events/<path>` | `text/event-stream`: a `value` event with the current value of the path, then one per change; `: ping` every 15 s. |
| `GET /healthz` | `{"connected": true}` from `.info/connected`, `503` when not connected. |

Each event stream holds one `onValue` listener, cancelled when the client disconnects. On `SIGINT`
or `SIGTERM` the server stops accepting, ends the streams (cancelling their listeners), and closes
the database. Database errors become statuses (`permission-denied` 403, `unavailable` 503, ...).

## Run

```sh
dart pub get
FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 PORT=8000 dart run bin/server.dart
```

| Variable | Meaning |
| --- | --- |
| `FIREBASE_DATABASE_EMULATOR_HOST` | `host:port` of a Database emulator. Required unless `DATABASE_URL` is set. |
| `DATABASE_URL` | An explicit database URL. The only way to reach a real database; no credentials are set up. |
| `PORT` | HTTP port (default `8000`). |

## curl

```sh
curl -N localhost:8000/events/notes &                      # watch the list
curl -X POST -d '{"text":"hello"}' localhost:8000/notes    # {"id":"..."}
curl 'localhost:8000/notes?limit=5'
curl localhost:8000/notes/<id>
curl -X PATCH -d '{"text":"hello again"}' localhost:8000/notes/<id>
curl -X DELETE localhost:8000/notes/<id>
curl localhost:8000/healthz
```

Run against the Database emulator: every route above, the event stream and the shutdown on `SIGTERM`.

[sse]: https://html.spec.whatwg.org/multipage/server-sent-events.html
