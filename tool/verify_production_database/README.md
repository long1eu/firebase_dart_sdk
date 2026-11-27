# Realtime Database production verification kit

This kit runs 42 named checks against a **real** Realtime Database and prints, for each one, `PASS`, `FAIL`,
`INCONCLUSIVE` or `SKIPPED` with a one-line explanation. It asks what the emulator cannot answer (TLS and the host the
server names, rules with a real ID token, a token refresh and a sign-out on a live connection, priorities on the real
server, timings), runs a base line of the public API on both backends, and runs the core side's production questions
(`rtdb/from_helper/reports/production_questions.md`) as informational checks 27 to 36, plus checks 37 to 42.

The code is `firebase_database/firebase_database_dart/test/production/verify_production.dart`; `run.sh` here runs it
from the right directory. It is modelled on the Storage kit (`tool/verify_production_storage`).

**Status of the kit itself:** it runs against the Database emulator (v4.11.2) and the Auth emulator, where every
check passes (`test/production/verify_production_test.dart` pins the results below). Run 15 on 2026-11-27 ran the
whole kit in one run on the final client of this version: 41 of 41 PASS on the emulator and 41 of 41 PASS against a
dedicated production database. Check 42 was added after run 15; run 16 on 2026-11-28 ran it alone: PASS on both.

## Before you run it against production

- **Use a database no app uses**: a throwaway project, or a second database instance in a project (Realtime
  Database > Create database). The kit needs its rules installed, and publishing `rules.json` **replaces every rule of
  that database**: on a database an app uses, every other path is refused from then on.
- **A shared database anyway:** save its current rules first (copy them from the console, or `firebase
  database:get --instance <instance> /.settings/rules.json > saved_rules.json`), then add only the three
  `verify_database_kit*` keys of `rules.json` to them, never its root `.read` and `.write` (check 15 then reports
  what your root allows, as an observation).
- **After the run:** publish the saved rules again (or remove the three keys), or delete the instance. The kit's
  rules let any signed-in user read and write below `verify_database_kit/` and its owner path without a size limit,
  so do not leave them in place. Turn the Email/Password sign-in provider off again if you turned it on for the kit.
- **Auth triggers run.** `--create-user` signs up a real user in the project: Cloud Functions on user creation,
  blocking functions (`beforeCreate`) and extensions of the project run for it, may write elsewhere, mail
  `database-verify-<run>@example.com`, or refuse the sign-up. Use a project without them.
- **Name the instance.** The kit writes to the database URL you give (`FIREBASE_TEST_DATABASE_URL` or
  `--database-url`) and prints it first; there is no default.

## What it does to your project

- It writes only below one path that is unique to the run: `verify_database_kit/run_<utc>_<suffix>/`. Two
  exceptions: check 16 writes `verify_database_kit_owner/<uid>/run_<utc>_<suffix>` under the throwaway user's own
  uid, and check 15 tries one tiny write at `verify_database_kit_denied/run_<utc>_<suffix>`, which the rules refuse;
  if it is wrongly accepted the check removes it at once.
- At the end it removes the run's path and the owner path, also when checks failed, and reads the run's path back
  to see that it is empty. Before that it cancels every onDisconnect it registered and closes every client. When a
  write could still land afterwards (check 33's onDisconnect had not run, a client did not close in time, a check
  timed out, or the run was stopped) it waits 60 s and removes the run's path a second time. If the clean-up or the
  deletion of the user fails it says so, names the paths and the user to remove by hand, and exits 3. `--keep` skips
  the clean-up.
- Ctrl-C or SIGTERM: the running check is abandoned, the clean-up runs, and the kit exits 130. A second signal
  exits at once and prints the paths and the user to remove by hand.
- Before the checks it writes and reads `<run>/preflight` as the user. If the rules refuse that, no check runs and
  the kit exits 2 with "install the rules"; after it, a refusal in a check is a `FAIL`.
- It prints the project, the database URL and the run's path first. Against production it does nothing more without
  `--yes`.
- Size and load: 42 checks. The largest write is one string of 1,000,000 bytes (check 32, read back once); every
  other write is at most about 1.4 KB, so a full run writes about 1.1 MB in total (inferred from the values in the
  code, not counted). Check 36 sends 1,000 updates, check 34 200 increments, check 31 at least 100 transactions.
  Check 31 opens about ten clients over its five steps, at most three at a time; check 30 opens five; every other
  check opens at most three clients and, in checks 28, 29, 33, 37, 38, 39, 40 and 42, one raw connection (check 39
  opens three more in turn for Q13, one at a time beside its first; check 41 opens three raw connections and no
  client). The 16 MB write of question 28 is not tried.
- Time: about 6 minutes on the emulator (373 s measured for the whole kit of 40 checks with `dart run`'s start; before
  check 40 was added, check 39 alone 294 s, the other 38 checks 59 s; check 41 was not timed, it waits at least 1.8 s in
  each of its six cases; check 42 was not timed, it waits 0.8 s after each of its seven listens). Check 39 waits 20 s
  for each request the server does not answer (Q3, Q8, Q9) and 20 s after each Q8 merge; checks 22 and 30 each wait
  5 s for their second reading.
  Each check may take up to 3 minutes, checks 39 to 41 up to 8 (checks 40 and 41 wait 20 s for each write or request
  that does not complete); check 33 waits up to 150 s for the server, and the clean-up waits 60 s more when a write
  could still land (below). A run is longer than the five minutes after a sign-in in which Auth accepts the deletion
  of a user (later it answers `requires-recent-login`), so the kit signs the throwaway user in again, with the password
  it keeps in memory, right before deleting it.
- Checks 28, 29, 33, 37, 38, 39, 40 and 42 open a raw protocol connection of their own, check 41 three (version 5, the
  throwaway user's token in an `auth` request), because the public API does not show frames. It only listens (in
  checks 38, 39 and 42 also with a hash, in check 39 with a compound hash), unlistens and, in checks 38 to 42, gets
  below the run's path; in checks 39 to 42 it also puts there and in checks 39 and 41 merges (some puts with a hash,
  as a transaction does); in check 33 it registers one onDisconnect write there and drops the socket without a close,
  and check 39 does the same with one onDisconnect merge on each of its three Q13 connections. The
  auth request and its answer are never printed (an auth answer holds the token's claims); the report prints the
  pushed frames and, in checks 38 to 42, the answers to its other requests, which hold only the kit's own data.
- Credentials: the kit never reads or prints any. With `--create-user` it signs up a throwaway user
  (`database-verify-<run>@example.com`, a random 32-character password that lives in memory and is never printed or
  stored) through `FirebaseUserAuth` (`firebase_auth_providers_dart`), and deletes that user at the end, also when
  checks failed. If the deletion fails it prints the uid to delete by hand. The ID token is handed to the client and
  to the kit's own REST calls (`?auth=`); the URL of a REST call is never printed, and an HTTP error is reported by
  its type only, because its text would quote the URL. No service account is used.
- The API key is read from the environment or `--api-key` and never printed.
- Every network wait has a timeout (20 s for one step, 3 minutes for a whole check); a wait that times out is reported
  with what it waited for, as `INCONCLUSIVE` or, where it means the client misbehaved, `FAIL`. A run never hangs.
- The production leg never reads or changes the rules.

## The rules the database needs

`rules.json` next to this file, shown below (the kit's test checks that this copy equals the file). Publish it on the
database you named (see "Before you run it against production"); the kit does not touch the rules of a real
project. On the emulator the kit
installs the same rules itself, on its own namespace (`PUT /.settings/rules.json?ns=verify-database-kit` as the
emulator's owner).

```json
{
  "rules": {
    ".read": false,
    ".write": false,
    "verify_database_kit": {
      "$run": {
        ".read": "auth != null",
        ".write": "auth != null",
        "indexed": {".indexOn": ["score"]},
        "values": {".indexOn": ".value"},
        "validated": {"$k": {".validate": "newData.isNumber()"}},
        "leaf_rule": {"a": {".validate": "false"}}
      }
    },
    "verify_database_kit_owner": {
      "$uid": {".read": "auth.uid === $uid", ".write": "auth.uid === $uid"}
    }
  }
}
```

`verify_database_kit_denied` has no rule, so every request there is refused. `"values": {".indexOn": ".value"}` is
there for the `orderByValue` queries of check 8, and `leaf_rule` refuses a write of `a` below it for check 30. The
root `.read` and `.write` of `false` are part of the expectation; if your database's root is more open, check 15
reports `FAIL` (the refusals do not happen).

## Commands

Production, from the repository root, after the steps of "Before you run it against production":

    unset FIREBASE_DATABASE_EMULATOR_HOST                      # the kit refuses to guess between the two
    export FIREBASE_TEST_PROJECT_ID=my-project
    export FIREBASE_TEST_DATABASE_URL=https://my-project-kit-check.europe-west1.firebasedatabase.app   # the instance
    export FIREBASE_API_KEY=...                                 # the Web API key, for --create-user
    export FIREBASE_TEST_APP_ID=1:123:web:abc                   # optional: the app id the connection sends

    tool/verify_production_database/run.sh --backend=production --create-user          # the plan, nothing else
    tool/verify_production_database/run.sh --backend=production --create-user --yes    # runs it
    tool/verify_production_database/run.sh --backend=production --create-user --yes --only=18,19,21

`--create-user` needs the Email/Password sign-in provider. Without it only checks 15 and 20 run (the rules refuse
everything else without a user) and the others are `SKIPPED`.

Save the report: `... --yes | tee verify_database_report.txt`. It holds the project, the database URL, the run's path,
the uid of the throwaway user and the data the kit wrote; no token, password or API key.

Emulator (to see a run, or to check the kit), from the repository root:

    tool/start_database_emulator.sh 9130
    AUTH_HUB_PORT=9498 AUTH_LOGGING_PORT=9598 tool/start_auth_emulators.sh 9398 9397
    export FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9130 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9398
    tool/verify_production_database/run.sh --backend=emulator --create-user
    (cd firebase_database/firebase_database_dart && dart test test/production)   # the kit's own test
    tool/stop_database_emulator.sh 9130; tool/stop_auth_emulators.sh 9398 9397

Options: `--database-url=URL` (instead of the variable; on the emulator the default is
`http://<host>?ns=verify-database-kit`), `--api-key=KEY`, `--create-user`, `--only=1,2`, `--keep`,
`--expect-emptied-node-fix` (below), `--list` (the checks and their scope), `--help`. Exit code: 0 when no check
failed, 1 when one is `FAIL`, 2 for a usage error (a missing variable, a URL that is not https or carries a query
other than `ns`, an unknown check id, a failed sign-up), a missing `--yes` or rules that refuse the preflight, 3 when
the clean-up or the deletion of the user failed, 130 when a signal stopped the run, 64 for an unknown flag.

`--expect-emptied-node-fix`: pass it only for a client that has the emptied-node priority fix (the client keeps the
server's priority of a node emptied by its own write). The trunk and release 0.1 do not have it; they keep the JS
SDK's behaviour there. With the flag, checks 22 and 38 (c), (e), (f) decide as written below. Without it they print
what they observe, say whether the client keeps the JS SDK's behaviour, and are `PASS`; the plan names the mode in
its `client:` line.

## The checks and how to read them

"Scope" says where a check can tell something: `both` checks have a known result on the emulator and must give the
same on production; `production only` checks run on the emulator as a base line, but only production answers their
question. For the informational checks (21, 22, 24 to 26) `PASS` means the calls worked; the finding is in the line.

- **1. Connect, TLS and the server host** (production only). Connects, goes offline and online once, and prints the host
  of every connection attempt (the client's debug line `connecting to <host>`; the host the server names in its hello is
  used from the second connection on). `FAIL` if the URL is not https. Production: whether the server sends the client
  to another host.
- **2. Server time offset** (both). `.info/serverTimeOffset` is a number and below 5 minutes.
- **3. Every value type** (both). One `set` of strings (unicode, empty), booleans, ints (0, -42, +-(2^53-1)), doubles
  (3.14159, 1.5e-10, 1e300, -0.5), a list and nested maps; then, each by its own `set`, a chain of maps 32 segments
  deep, a punctuation key, a non-ASCII key and the longest key the path allows (768 bytes). A second client reads it
  back; then an `update` (with a deep path and a null) and a `remove`, read back again. The line after it says whether
  the server takes all of it in **one** `set` (informational). A refusal of one of the limit keys is `INCONCLUSIVE`
  with the server's text (the limits were sized on the emulator); a refusal of the plain types is `FAIL`.
- **4. `ServerValue.timestamp`** (both). The stored value lies between the estimated server time before the set and
  after its acknowledgement, 2 s either side.
- **5. `ServerValue.increment`** (both). Two increments of 1 on a missing value give 2; 5 incremented by -2.5 gives 2.5.
- **6. Push keys** (both). 20 push keys of 20 characters sort in the order they were made, and the server returns them
  in that order.
- **7. Listeners** (both). A second client writes a, b, c, changes a's order and removes b; `onChildEvents` of
  `orderByChild('n')` gives added a, b, c, moved a, changed a, removed b (with the previous keys), and `onValue` ends at
  the right value.
- **8. Queries** (both). 9 queries (`orderByChild` with the declared index: ranges, limits, `equalTo`, `startAfter`;
  `orderByKey`; `orderByValue` with `endBefore`) by `get()` (sent to the server) and `once()`, compared with the order
  and window computed in the kit.
- **9. Undeclared index** (production only). `orderByChild('other').limitToFirst(3)` with no `.indexOn`: `once()` must
  be right; the line says whether the server sent the `no_index` warning and what a filtered `get()` answered.
- **10. Transaction against a second client** (both). The second client writes 10; the first runs a transaction with no
  data cached, so its first run sees null, the server refuses the stale hash, the handler runs again and commits 11.
- **11. Transaction abort** (both). `committed: false` with the value the handler saw (11); the server keeps 11.
- **12. onDisconnect** (both). `set`, `remove` and `update` are registered, a second `set` is registered and cancelled;
  the first client closes, and a second client sees the three fire and the cancelled one not. The line gives the time
  from the close.
- **13. Queued offline, delivered once** (both). A push and an increment made offline are delivered once after
  `goOnline`: one child at the observer, count 1.
- **14. keepSynced, then offline get()** (both). After `keepSynced(true)` and `goOffline`, `get()` answers from the
  cache (the line gives how fast).
- **15. Refused without a user** (both). A write without a user is refused with `permission-denied` (code, message and
  server status are in the report); the same write as the user is accepted; a write at `verify_database_kit_denied` is
  refused. Runs without `--create-user` too.
- **16. Owner rule** (both). The user may write below its own uid and not below another.
- **17. `.validate` refusal** (both). A string where the rule wants a number: the write fails with `permission-denied`,
  the listener shows the string at once and returns to the old value, the server keeps it.
- **18. Token refresh** (production only). A forced refresh of the ID token: the client sends the new token on the live
  connection (`auth` in its log), and listening and writing go on (else `FAIL` or `INCONCLUSIVE`). Whether the
  connection dropped is printed as an observation (`DROPPED`). The emulator never checks token expiry, so only
  production answers whether the server takes the new token without a drop.
- **19. Sign-out** (production only). A second session of the same user listens below the run's path and signs out: the
  listener must be cancelled with `permission-denied`, and a write must be refused with it (both make the verdict).
  `INCONCLUSIVE` if the server does not cancel the listener within 20 s.
- **20. Listener at a refused path** (both). A listener at `verify_database_kit_denied` is cancelled with
  `permission-denied`, and `get()` fails with it. Runs without `--create-user` too.
- **21. Priority over REST** (production only). The kit's own REST calls as the user: `PUT r {"a":1,".priority":0}`,
  `DELETE r/a`, `PUT r/b 1`, with `GET r.json?format=export` after each. The three exports are printed: does the server
  keep the priority of a node that was emptied and refilled?
- **22. Priority by the client** (production only). The same through the client (a `set` with a priority, a `remove`, a
  `set`; and a `set` then one `update` of both children), read back by a fresh client. Also prints the priority the
  writer's own listener shows, and for the `update` form the priority of the writer's listener and of its `get()`,
  0 s and 5 s after the update. With `--expect-emptied-node-fix` the `update` form decides: `FAIL` when at 5 s the
  writer's listener or its `get()` shows another priority than the fresh client; without the flag it is printed.
- **23. Write below a primitive** (both). The server holds 1 at r; offline the client sets `r/c` to `{v:1}` and then to
  null, and goes online. The listener, `get()` and a fresh client must all end at null.
- **24. Timing: cold connect** (production only). Milliseconds from creating a client to its first value.
- **25. Timing: write round trip** (production only). Median, min and max of 20 `set()` acknowledgements.
- **26. Timing: reconnect** (production only). Milliseconds from `goOnline` to `.info/connected`, three times, and the
  hosts connected to.

Checks 27 to 36 answer the core side's questions; the numbers in their lines ("line 4") are the line numbers of
`production_questions.md`. Each is informational: `PASS` means the sequence ran, and the line says whether the
observation matched what the emulator showed (one exception: leaf B of check 30, which can `FAIL`). Their code is
`test/production/production_questions.dart`.

- **27. Questions 1-3: priorities** (production only). `set` of `{a:1}` with priority 5, remove `a`, a fresh read
  and a REST export (line 1); `setPriority` on a missing path, with the raw `serverStatus` (line 2); `set` of a leaf
  then `setPriority(3)`, REST export (line 3).
- **28. Questions 4-10: frames to a limit query** (production only). On a raw connection, a tagged
  `orderByKey().limitToFirst(2)` listen on a, b, c, d (each `{n}`, with priorities), then one write by a client per
  case: a `set` at the query path (line 4), an `update` keeping the members (5), an `update` where a leaves and c
  enters (6), a `set` below a in the window (7), a `set` below d outside it (8), a `remove` of a (9), a new child `aa`
  that sorts into the window (10), and four extras: `limitToLast(2)`, a priority-ordered `limitToFirst(2)` where a
  gets priority 0, an `update` inside and outside the window, and an `update` of `a/n` alone (below one window
  child, no key outside the window). Each case prints the initial frames and the frames
  after the write (action, path below the run, tag, data), or `NO FRAME`.
- **29. Question 11: tagged before untagged** (production only). The tagged limit listen and a default listen on one
  path of one raw connection; five writes; which frame came first each time.
- **30. Questions 12-14: writes below a leaf** (production only). Online `set` of a leaf, then a child (line 12); the
  child refused by `leaf_rule` (13); a refused and an accepted write below the leaf at once (14). Prints the value
  events and the server's value. Then "leaf B", the sequence of the JS leg: `leaf_rule` is 1 (REST); a new client
  listens there, sets `leaf_rule/a` to 1 (refused) and to null without waiting for the first, and 0 s and 5 s after
  both settle prints the server (REST), its listener's last value, its `get()` and a fresh client's `get()`. Leaf B
  makes the verdict, as in check 23: `FAIL` when the listener, `get()` or the fresh client differ from the server at
  5 s, `INCONCLUSIVE` when the rule did not refuse the first write.
- **31. Questions 15-19: transactions** (production only). Two clients run 50 increment transactions each (15); a
  transaction at the refused path, counting its put frames from the client's log (16); a transaction followed at once
  by a `set` of the same client (17); a transaction started offline (18); a transaction whose handler makes a second
  client write the path on every run (19; this races the transaction, so max-retries is not forced).
- **32. Question 23: a 1 MB child and a small listener** (production only). A `get()` of a 1,000,000-byte string and
  a write to a small sibling with a listener: the time of each.
- **33. Question 24: onDisconnect after a dropped socket** (production only). A raw connection registers an
  onDisconnect write and drops its TCP socket without a close; how long until an observer sees the write (up to
  150 s, else `INCONCLUSIVE`).
- **34. Question 26: pipelined increments** (production only). 100 increments from each of two clients without
  waiting; the final value.
- **35. Question 28: server limits** (production only). A REST `PUT` at a path of depth 33 (the status and body),
  and the same through the client.
- **36. Question 29: pipelined updates** (production only). 1,000 `update` calls without waiting: acknowledgement
  order, value events that go back, the final value, operations per second.
- **37. Priority window** (production only). On a raw connection, `orderByPriority().limitToFirst(2)` over c1..c4
  with priorities 1..4; a client sets the priority of c4 to 0 (into the window), then to 9 (out of it). Prints every
  frame of each step, in order, with tag and path.
- **38. Priority of an emptied node: frames, update, hash, deletion** (production only). (a), (b) and (d) are
  informational; with `--expect-emptied-node-fix` the transactions of (c), (e) and (f) decide: `FAIL` when one does
  not commit within two runs of its handler, `INCONCLUSIVE` when they commit but (f) did not reopen a durable cache.
  Without the flag they are printed and the check is `PASS`. Each node below
  `<run>/emptied/` is set to `{a:1}` with priority 5 and emptied by removing `a`.
  (a) On the raw connection, a listen and a get (`g`) of the emptied node and of its parent: the answers and the
  frames, printed in full. (b) `update(n, {a: null, '.priority': 7})` on `{a:1}` with priority 5 (the public API
  takes `.priority` as the last key of an update path), and `setPriority(9)` on an emptied node: each outcome and the
  REST export after it. (c) A transaction by a new client on an emptied node (the handler's runs, committed or the
  error, the export), and raw listens with a hash: the hash the kit forms for a node with priority 5 and no children
  (SHA-1 of `priority:number:<IEEE 754 hex>:`, as the JS SDK hashes a children node; the client never forms it) and,
  as controls, the hash of `{b:1}` and a hash that does not match it; whether the server sends the data.
  (d) `set(n, null)`, export, then `set(n/b, 1)`, export: does the priority come back. (e) `set(n, {a:1})` with
  no priority, `update(n, {a: null, '.priority': 7})`, the export, then a transaction by a new client (it must commit
  whether the server keeps n as `{".priority":7}` or removes it). (f) A restart on the SQLite cache
  (`firebase_database_dart_sqlite`, a dev dependency of this package): a client with `sqlitePersistence` in a new
  temporary directory listens to n, sets `{a:1}` with priority 5 and empties it, and closes; a second client on the
  same app and directory listens to n and runs a transaction there. Prints whether each client owned the file
  (`persistenceEnabled`). The directory is deleted at the end.
- **39. Server rules for an emptied node's priority** (production only). Informational. Raw frames only, no client
  node code: for each case below `<run>/server_rules/<id>` the raw connection writes the setup, listens, sends the
  case's writes, and prints the listen answer, the initial frame, each write's answer (`NO ANSWER` when none comes in
  20 s), the frames after, a `g` answer, the REST export, and then offers a transaction put (a marker value) with
  the candidate hashes of the `g` data (as stored, without the kept priorities, `''`) and prints which one the
  server accepts. Q1: `{a:1}` without priority, merge `{a:null, .priority:7}`; `{a:1, b:2}`, merge
  `{a:null, b:null, .priority:7}`; control `{a:1}` priority 5. Q2: `{c: {x:1} priority 3}`, remove `c/x`, `g`, put
  `.priority` 9. Q3: put `{".priority":5}` on a missing node, put `{".priority":8}` on an emptied node with priority
  5. Q4: put `a` 1, put `.priority` 7, put `a` null, sent without waiting. Q6: the deep form of Q1, a merge at the
  parent `{x/a: null, x/.priority: 3}`, with x without priority and with priority 5. Q7: a REST PUT of
  `{".priority":5}` on a missing node and of `{"n":{".priority":5},"z":1}`. Q5: about 1.3 KB at `q5` with `b`
  emptied (priority 5) between `a` and `c` and `d/f` emptied (priority 2) inside `d`; five listens with a compound
  hash (`ch`, Android's `CompoundHash` ranges, formed by the kit): ranges without the kept priorities (what the client
  sends), with them as a `.priority` leaf, with them as an empty range, a control with every range wrong, and a
  control whose simple hash matches. Each prints the `ch` sent, the answer, whether data came as nothing, a full `d`
  or a range merge `rm`, and the frames (the long filler strings printed as `<540 x>`).
- **40. A null priority set on a missing node** (production only). Informational. (a) Through the public API, each
  at its own missing path below `<run>/null_priority/api/`: `setPriority(null)` and every `set` form with no value
  that the validation lets through (`set(null, priority: 3)`, `set({}, priority: 3)`, `set([], priority: 3)`,
  `set({'.priority': 3})`, `set({'.value': null, '.priority': 3})`, `set({'.value': {}, '.priority': 3})`,
  `set({'.priority': null})`; the client sends each of these as a removal, `p <path> null`). For each: how the Future
  ended (or `NOT COMPLETED` after 20 s), the events of a value listener attached before, the writer's `get()`, a
  fresh client's `get()` and the REST export. Then five value-less calls the client refuses at the call, with the
  error (nothing is sent). (b) On the raw connection at `<run>/null_priority/raw/<id>` (r): `p r/x/.priority null`
  with r missing, with r = `{k:1}` and x missing, and as controls with x `{v:1}`, x `{v:1}` priority 2 and x emptied
  keeping priority 5; and `p r/x/.priority 3` with x missing. Each prints the setup, a listen at r, the frame sent and
  every frame received verbatim, a `g` of r and the export; then one ordinary put on the same connection. (c)
  `setPriority(3)` on a missing path, reported as in (a).
- **41. A merge key that names the location itself, raw frames** (production only). Informational. Three raw
  connections: a writer, a listener at the merge's location and a listener above it. For each case at
  `<run>/empty_merge_key/<id>` (up), the writer puts up = `{loc: {k:1, j:2}, sib: 5}`, the listeners listen at
  `up/loc` and at up, and the writer sends a merge (`m`) at `up/loc` with the key `""`, `"/"` or `"//"` (each parses
  to the empty path, the location itself) alone (`{"":7}`, a1 to a3) and beside a normal key (`{"":7,"n":3}`, a4 to
  a6). Each prints the setup, both listen answers, the frame sent, the answer, every frame each of the three
  connections received within 1 s after the merge, a `g` of up and the export of up; then one ordinary put on the
  writer connection. A raw connection sends each form as given: the client's `update` and `OnDisconnect.update`
  refuse every one of them with an `ArgumentError` and send nothing (`{'': 7}` points to `set()`, `{'': null}` to
  `remove()`).
- **42. Hash of a query window that holds an emptied node, raw frames** (production only). Informational. One raw
  connection puts `<run>/emptied_window` = `{a, h, c, d}` with priorities 1 to 4 (`h` = `{v:1}` priority 2, the others
  `{n:...}`), then `h/v` null, so the server holds `h` as `{".priority":2}`; it prints both answers, a `g` and the
  export, and the hash of `h` as stored next to SHA-1 of `priority:number:<IEEE 754 hex of 2>:`. Then two tagged
  queries by priority: `limitToFirst(3)` (wire `{"l":3,"vf":"l"}`) and `startAt(1).endAt(3)` (wire
  `{"sp":1,"sin":true,"ep":3,"ein":true}`). Each is listened with no hash, then with the simple hash, formed by the kit
  from the `g` data, of its window counting `h` (`withH`: a, h, c) and of its window without `h` (`withoutH`: a, c,
  what the client holds, since it drops a node that keeps only a priority); the limit query also with a, c, d
  (`refilled`: the window if the server did not count `h` toward the limit). Each listen has a tag of its own and is
  ended before the next. For each it prints the hash, the answer, whether data came (`DATA SENT`, the hash was not
  accepted) or not (`no data`, accepted), the shape of `h` in the data, and every frame; then which candidates the
  server accepted. A reader can tell from it whether the server's window hash counts an emptied node.

What to send back: the whole report. The most valuable lines are 1, 9, 15, 18, 19, 21, 22 and 27 to 42, and the line
after check 3 ("all of it in one set").

## Known results

On the emulator: the Database emulator v4.11.2 with the kit's rules on the namespace `verify-database-kit`, and the
Auth emulator of firebase-tools 15.18.0. Production: checks 1 to 39 ran as one run on 2026-11-25 and 26 (39 PASS, with
the client before the emptied-node fix), check 40 alone (2026-11-26) and check 41 alone (2026-11-27). Run 15
(2026-11-27, the whole kit of 41 checks in one run, 41 PASS on the emulator and 41 PASS on production) ran without
`--expect-emptied-node-fix`, so checks 22 and 38 (c), (e) and (f) were informational and recorded that the client
drops the priority of an emptied node, as the JS SDK does. Where production gave another observation than the
emulator, a line "N on production" follows the check; without one, production gave the same, timings aside.

- **1**: PASS: plain ws to 127.0.0.1, no other host
- **1 on production** (2026-11-26): wss with TLS, the certificate checked by `dart:io`; the hello named a server host
  and the next connection went there
- **2**: PASS: offset of a few ms
- **3**: PASS; but the whole value in **one** `set` is refused: `invalid_parameters: Path specified exceeds the maximum
  length that can be written (768 bytes)`, although each part alone is accepted
- **3 on production** (2026-11-26): the whole value in **one** `set` is accepted; the 768-byte refusal is the
  emulator's only
- **4 to 8**: PASS
- **9**: PASS: the `no_index` warning is sent in two of three runs and not in the third (on the emulator, 3 runs); a
  filtered `get()` answers `index-not-defined` in all three
- **9 on production** (2026-11-26): the `no_index` warning sent, as in two of the three emulator runs; a filtered
  `get()` answers `index-not-defined`
- **10**: PASS: two runs of the handler (null, then 10)
- **11 to 13**: PASS
- **14**: PASS: answered at once (0 ms) from the view `keepSynced` holds
- **15**: PASS: `permission_denied: Permission denied`; message "This client does not have permission to perform this
  operation."
- **16, 17**: PASS; the listener of 17 saw null, 5, not-a-number, 5
- **18**: PASS: the new token was sent, no disconnect
- **19**: PASS: cancelled with `permission_denied`; the write is refused
- **20**: PASS
- **21**: PASS, priority KEPT: `{".priority":0.0,"a":1}`, then `{".priority":0.0}`, then `{".priority":0.0,"b":1}`
- **22**: PASS: a fresh client reads priority 0 after both forms; the writer's own listener shows priority null after
  both; in the `update` form the writer's listener and its `get()` show null at 0 s and at 5 s (listener values: null,
  `{a:1}` with priority 0, `{b:1}` with priority null). The client of the repository has no emptied-node fix. With
  `--expect-emptied-node-fix` this part decides: a client with the fix shows priority 0 in the writer's listener and
  its `get()` at 0 s and at 5 s
- **23**: PASS
- **24 to 26**: PASS, a few ms each on loopback
- **4** (question 25): the writer saw the local estimate, then the server's value 1 ms later (two events) in two runs,
  and a single event in the third (on the emulator, 3 runs)
- **27**: line 1: null with no priority from a fresh client, but the REST export of the emptied node is
  `{".priority":5.0}`; line 2: refused, `unknown: invalid_parameters: could not set priority on non-existent node`;
  line 3: `{".value":"leaf",".priority":3.0}`
- **28**: line 4 one tagged put of the window at the query path; line 5 a tagged merge `{"a":{"n":11}}`; line 6 a
  tagged merge `{"c":{"n":33},"a":null}`; line 7 a tagged put at `a/n`; line 8 no frame; line 9 a tagged merge
  `{"c":{...},"a":null}`; line 10 a tagged put of `aa` alone. `limitToLast`: a put at `d/n`; by priority: a put of
  `a` alone; the mixed update: a put of `a` alone (the change outside the window sends nothing); `a/n` alone: a
  tagged merge at the query path, `{"a/n":7}`
- **29**: tagged first in 5 of 5
- **30**: line 12 `{a:1}` on both; line 13 the client ends at `leaf` (events null, leaf, `{a:1}`, leaf); line 14
  client and server `{b:2}`; leaf B: the first write refused with `permission_denied`, the removal accepted; the
  listener (events 1, `{a:1}`, null, 1), `get()` and a fresh client at 1, the server's value, at 0 s and 5 s
- **31**: line 15 **98 or 99 of 100 committed, the rest failed with `max-retries`** (final 98 or 99, no value went
  back; on the emulator, 3 runs); line 16 one put frame, `permission-denied`; line 17 the transaction **committed**
  and the `set` won (99): the transaction had been sent, and a sent transaction the server accepts completes as
  committed, as in the JS SDK; line 18 two runs (null, then 5), committed 6; line 19 `max-retries` after 25 runs in
  two of three runs, and in the third it committed after 15 runs (the rival's writes race the transaction)
- **31 on production** (2026-11-26 and run 15): line 15 99 of 100 committed, 1 failed with `max-retries` (final 99), and
  98 of 100 in run 15 (2 failed with `max-retries`, final 98); no value went back in either; line 19 `max-retries`
  after 25 runs on 2026-11-26, and committed after 18 runs in run 15; lines 16 to 18 as on the emulator
- **32**: on loopback the 1 MB `get()` took 4 to 6 ms and the small event came after it (on the emulator, 3 runs)
- **32 on production** (2026-11-26 and run 15): on 2026-11-26 the small event came **before** the 1 MB `get()`
  finished; in run 15 the `get()` took 364 ms and the small event came at 377 ms, after it, as on loopback
- **33**: the onDisconnect write ran about 12 ms after the dropped socket
- **34**: 200; **35**: REST 400 "Invalid path: Path specified exceeds the maximum depth that can be written (32).",
  the client refuses before sending; **36**: acknowledgements in order, final 999, no value went back, 4,975 to
  8,403 operations per second on loopback (on the emulator, 3 runs)
- **37**: into the window, one tagged put of `c4` alone (`{".priority":0,"n":4}`); out of it, one tagged merge at the
  query path with c2 (re-entering) and **c4 whole with priority 9, not null**
- **38**: (a) the listen of the emptied node answers `{"s":"ok","d":{}}` and pushes `{".priority":5.0}`, the get
  answers the same data; the parent pushes and gets `{"n":{".priority":5.0}}`. (b) the update is accepted, export
  `{".priority":7}`; `setPriority(9)` is accepted, export `{".priority":9}`. (c) the transaction fails with
  `max-retries` after 25 runs of the handler (null each time), export `{".priority":5.0}`; the listens with the
  kit's hashes get no data for either the emptied node or the control (the hash matched), the one with a wrong hash
  gets `{"b":1}`. (d) export
  `{".priority":5.0}`, then `null` after `set(n, null)`, then `{"b":1}` after `set(n/b, 1)`: the priority does not
  come back. (e) export `null` after the update (the node is removed), the transaction commits after 1 run.
  (f) the SQLite cache is durable before and after the reopen; the transaction fails with `max-retries` after 25
  runs of the handler (null each time), export `{".priority":5.0}`. The client of the repository has no emptied-node
  fix. With `--expect-emptied-node-fix` (c) and (f) decide: a client with the fix commits (c) after 2 runs (null,
  null, export `{"t":2}`) and (f) after 1 run (null) (on the emulator, one run)
- **39**: Q1 without priority: the merge is accepted and the node is **removed** (`null`, both forms); control: kept
  as `{".priority":7}`. Q2: n holds `{"c":{".priority":3.0}}` after the removal, the put of `.priority` 9 is
  accepted: `{".priority":9,"c":{".priority":3.0}}`. Q3: a raw put of `{".priority":5}` gets **no answer**, on a
  missing node and on an emptied one (which stays `{".priority":5.0}`). Q4: `{".priority":7}`. Q6: as Q1 (`null`;
  control `{"x":{".priority":3}}`). Q7: REST answers HTTP 400 "Invalid data; couldn't parse JSON object, array, or
  value." for both. In every case the accepted transaction hash is the one of the data as stored (kept priorities
  counted). Q5: ranges without the kept priorities get an `rm` with the ranges b..c and d (b as
  `{".priority":5.0}`, d with `f` as `{".priority":2.0}`); with them as a `.priority` leaf, `rm []` (every range
  matched); as an empty range, the same `rm` as without; with a matching simple hash, no data
- **39 on production** (2026-11-26): Q1 to Q7 as on the emulator. A merge that removes the children of a node and
  writes `.priority` on it keeps the priority on production (`{".priority":2}`; a nested `.priority` 3 kept in one
  case, `{"b":{".priority":2}}` in another), where the emulator removes the node (`null`): five cases, in question
  10 (`o2`) and question 11 (`f1a`, `f2a`, `f7b`, `f6b`)
- **40**: (a) `setPriority(null)` and every value-less `set` form complete ok; the listener sees only its first
  `null` (no event after the write), both `get()`s give `null`, the export is `null`. (b) `p r/x/.priority null` is
  answered `{"s":"ok","d":""}` with r missing, with x missing, and in the three controls; the listen at r gets a
  `d` push at `r/x/.priority` with data null each time; r stays missing or `{"k":1}`; with x `{v:1}` priority 2 the
  priority is removed (`{"k":1,"x":{"v":1}}`); x emptied keeping priority 5 is removed (`{"k":1}`).
  `p r/x/.priority 3` with x missing: `invalid_parameters` "could not set priority on non-existent node". (c)
  `setPriority(3)` fails with `unknown`, server status `invalid_parameters: could not set priority on non-existent
  node`; export `null`
- **40 on production** (2026-11-26): every answer, export and client view as on the emulator; the `d` push at
  `r/x/.priority` comes only where the write changed something (x with priority 2, x emptied keeping priority 5),
  none with x missing or without a priority
- **41**: each of the six merges (`""`, `"/"`, `"//"`, alone and beside `n`) is answered
  `{"s":"invalid_parameters","d":"Empty strings are not valid keys"}` within 22 ms; no frame to either listener; `g`
  and export of up unchanged (`{"loc":{"j":2,"k":1},"sib":5}`); the writer's next put is answered ok
- **41 on production** (2026-11-27, alone and in run 15): every answer, frame, `g` and export as on the emulator; the
  answers came within 161 ms alone and within 178 ms in run 15
- **42**: `h` is stored as `{".priority":2.0}` and its hash is the emptied-node form. `limitToFirst(3)`: a listen
  without a hash gets data with `h` as `{".priority":2.0}`; the hash of a, h, c (h counted) is accepted, no data;
  the hash of a, c and the hash of a, c, d (the window refilled) each get data. `startAt(1).endAt(3)`: the hash with
  `h` counted is accepted; the hash without it gets data. So the server counts an emptied node in a query window's
  hash and toward a limit
- **42 on production** (2026-11-28, run 16, alone): every answer as on the emulator

## Questions the kit does not answer

From `production_questions.md`: line 21 (a rules change while a listener is attached: the kit never changes the rules
of a real project), line 27 (a token that expires while offline: it would take an hour), and the 16 MB half of line
28 (the kit writes small data only). Lines 20 and 22 are answered by checks 20 and 9, line 25 by check 4.

## Not verified

- App Check: the kit sets no App Check provider.
- A custom domain and the legacy `firebaseio.com` host; give one with `--database-url` to see check 1. Run 15 used a
  regional `*.firebasedatabase.app` database.
- Size limits beyond the 768-byte path and 32 levels of check 3, and quotas.
- A token that expires on its own (check 18 forces a refresh) and a revoked token.
- Browser behaviour: the kit runs on the Dart VM.
