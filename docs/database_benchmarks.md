# Realtime Database client: benchmark report

> **Draft, do not quote.** A review of the harness found that this run cannot support several statements below; a
> corrected run is being taken. Known so far:
>
> - The drivers ran in the same order in every cell and repeat, and the first driver after the 100,000-child cell is
>   slowed. The JS SDK went first, which is where its 0.39 ms `set` acknowledgement comes from. The like-for-like cell
>   shows 0.17 against 0.17 ms: the two clients are level on a sequential write, not 2.4 times apart. The same holds
>   for the sequential `update`.
> - Peak memory is not measured the same way for the two clients (an exact maximum for ours, samples every 100 ms for
>   the JS SDK), and Node starts about 40 MB above a Dart AOT process.
> - Cold connect and the 1,000-child read compare AOT code with JS code that has not been optimised yet: true for a
>   first connection in a fresh process, not a steady-state comparison.
> - The two targets for the 100,000-child read (191 ms, 308 MB) came from a client whose loop answered most reads
>   from memory, so they were never like for like. The reference for that read is the JS SDK, which is faster than
>   ours there.
> - The 9,726 against 878 pipelined updates a second is the best case of one fix (1,000 updates to different children
>   of one parent).
> - Four cells have overlapping ranges and no winner: transactions at 50 ms, cold connect at 50 ms, the 1,000-child
>   warm read, the last-50 query.
>
> What holds in both runs taken so far: the same bytes and round trips on the wire as the JS SDK; the JS SDK is
> faster on the 10,000 and 100,000-child reads; ours is ahead on pipelined `set`, `push` and child events.

This report covers `firebase_database_dart`, the pure-Dart Realtime Database client of this repository, measured against
the official Firebase JS SDK and, for some cells, against the community Dart client `firebase_dart`. Every number below
is copied from a result file of the harness (the source of each table is named in its heading or legend); nothing here
was measured while writing the report. Numbers that are computed from two table cells (the ratio columns) say so.

## 1. Summary

Run A (Apple M5, AC power, Low Power Mode off, 5 repeats, local emulator), our client against the JS SDK:

1. Ours is ahead in cold connect at 0 ms (1.41 against 5.67 ms), 1,000-child snapshot (3.77 against 8.61 ms), `set` ack
   (0.16 against 0.39 ms).
2. Ours is also ahead in pipelined `update` (9726 against 878 per second), child events (16895 against 11660 per second)
   and peak RSS for 100,000 children (321 against 1526 MB).
3. Ours trails at 10,000 children (get plus val 44.99 against 38.24 ms) and at 100,000 (478 against 369 ms; get 382
   against 337 ms).
4. Ours also trails in warm `get` at 10,000 and 100,000 children (34.81 against 29.64 ms; 376 against 326 ms).
5. Round trips are equal (2.4 to first value, 1.1 per set); every transaction committed in both clients and every
   counter was correct.
6. Targets (section 5): round trips met, write ack met at the median, the 100,000-child snapshot (191 ms, 308 MB) missed
   at 382 ms, 321 MB.
7. Of the 478 ms about 300 are attributed (value 96, JSON 83, tree 121) and about 180 are not yet split (section 4).
8. Not measured: production, other machines, Linux, Windows, browser builds, real networks, phones (section 8).

## 2. Method and environment

### What was run

The harness is `tool/bench_rtdb/` (commit `b6ea15d7` of branch `rtdb/bench`). One orchestrator starts a private Database
emulator (project `demo-rtdb-bench`, ports 9410, 9510 and 9610, open rules, `.indexOn: score` for the 10,000 and 100,000
datasets), puts a counting proxy between every driver and the emulator, and starts one fresh process per scenario,
client and round-trip delay. Datasets come from a seeded generator (seed 42; checksums in the environment table), so
every client loads the same JSON. Every client runs the same operations in the same order from the same scenario file
(`scenarios.json`); the drivers mirror each other's metric names and correctness checks.

A cell shows the median over the 5 repeats of the per-run p50, with the minimum and maximum of that p50 across the
repeats in brackets. The whole suite ran 5 times, each repeat from a fresh emulator process. Scenarios have a stated
number of runs after a number of warm-up runs; cold connect runs in a fresh process each time. Dart drivers are compiled
with `dart compile exe` (AOT). The JS SDK runs on Node v26.10.0, which uses the global WebSocket and not
`faye-websocket` (recorded in each JS result). The proxy counts HTTP requests, connections, WebSocket frames, messages
and bytes in each direction, and can delay traffic by a round-trip time (0 or 50 ms). A TCP handshake is not delayed by
the proxy, so the connect scenario counts the HTTP upgrade and the protocol handshake only. Peak RSS is the larger of
`ps` samples taken every 100 ms and the driver's own figure; for short cells it is a lower bound.

### Environment of run A

| Key | Value |
|---|---|
| machine_model | Mac17,2 |
| cpu | Apple M5, 10 cores, 32 GB |
| os | macOS 27.2.1 |
| power | Now drawing from 'AC Power' |
| low_power_mode | 0 |
| thermal | No thermal warning level, no performance warning level and no CPU power status recorded |
| dart | 3.12.2, AOT (`dart compile exe`) for the Dart drivers |
| node | v26.10.0 |
| js_sdk | firebase 13.4.0, @firebase/database 1.1.6 |
| java | openjdk version "24.0.2" 2025-07-15 |
| firebase_tools | 15.36.0 |
| database_emulator_jar | firebase-database-emulator-v4.11.2.jar |
| git_commit | b6ea15d7 (clean) |
| dataset sha256 | tiny 19aea01cdf5b, flat_1k 89867f6e68c1, flat_10k d35d9b071901, flat_100k 4d9d132ea50b |

Run A contains our client and the JS SDK only. Date 2026-11-22; the files are `2026-11-22-ac-after-100k-fixes.md` and
`.json`.

### The runs that appear in this report

| Label | File | Commit | Power | Contains |
|---|---|---|---|---|
| A | `2026-11-22-ac-after-100k-fixes` | b6ea15d7 | AC power, Low Power Mode off | ours, JS SDK |
| B | `2026-11-22-ours` | 80757902 | the file records 'Battery Power' and has no low_power_mode key | ours (before four fixes), JS SDK, `firebase_dart` 2.0.0-dev.14, REST floor |
| C | `2026-11-22-ours-after-update-fix` | 4a2dd644 | 'Battery Power' with Low Power Mode on (stated in the file) | ours, JS SDK; write, child event and transaction scenarios only |

The tables in section 3 have a `run` column. Rows marked A are the run to read. Rows marked B come from another run, are
shown for the "before" state of our client and for the third client, and are not to be compared with rows marked A as if
they were one run: B ran on battery power and its power state is not fully recorded. For the JS SDK, which did not
change between the runs, the 100,000-child get plus val is 360 ms in B and 369 ms in A, and its peak RSS for 100,000
children is 1424 MB in B and 1526 MB in A. Run C is used only for ratios inside that run, never for absolute numbers.

### What the emulator and the proxy make meaningful

Meaningful: client-side CPU and memory (decoding, building the tree, events, garbage collection), the number and size of
messages on the wire, the number of round trips on the critical path of an operation (from the delayed proxy), and
correctness under load. The three clients receive the same server messages from the same emulator, so a difference in a
client-bound cell is a difference in the client.

Not meaningful (from the "What the emulator cannot show" section of the result files):

- Ack latency. The emulator acknowledges a write after a loopback round trip (about 0.05 ms) and with no replication;
  production takes tens to hundreds of milliseconds. The delay proxy shows how many round trips an operation needs, not
  what they cost.
- Reconnect timing, TLS (every connection is plain `ws://` and `http://` on loopback), server query and rules cost
  (rules are open), scale and quotas (one tenant, no throttling, no connection cap).
- The emulator (a JVM), the proxy and the driver run on one machine, so CPU contention is part of every number; the
  proxy runs in the orchestrator process.

Nothing was measured against a production database. Disk persistence is not part of this baseline (section 6 is another
benchmark).

### Choices a reader may want to check

- Fresh connection for snapshots. `firebase_dart` keeps data it has listened to in memory for a few seconds after
  `once()`, and answers a repeat read in 0.01 ms (run B). The snapshot cells therefore use a fresh connection per run
  for every client; the warm-connection cell exists for the JS SDK and our client only. The query scenario asks for
  `limit + run number` so that no client can answer from memory.
- `get` and `get plus val` (read in the drivers `js/driver.mjs` and `ours/bin/driver.dart`). The clock starts before the
  client is opened, so `fresh_connection_get_ms` includes opening the client, connecting and the `get()` call;
  `fresh_connection_get_plus_val_ms` adds `snap.val()` (JS) or `snap.value` (ours). Our `value` returns an unmodifiable
  value, a decided behaviour of the client; the JS `val()` builds a mutable object.
- Write scenarios. In `write_set`, `write_update` and `write_push` one process runs 20 warm-up operations, then the
  sequential acknowledged operations, then the pipelined runs (1,000 in flight). `set_ack_sequential` is a separate
  scenario for the same sequential `set`. The JS SDK's sequential `set` ack is 0.39 ms in `write_set` and 0.17 ms in
  `set_ack_sequential`; the result files do not explain the difference.
- The JS SDK's memory includes the Node runtime; our client's includes the Dart AOT runtime. Both are whole-process peak
  RSS.
- Wire counts include connect and warm-up, divided by the number of operations of the whole process lifetime.

## 3. Measurements

Reading the tables: the cell is the median over the repeats of the per-run p50, and the minimum to maximum of that p50
over the repeats. For times, lower is better; for operations or events per second, higher is better. `ratio` is the
median of our client divided by the median of the JS SDK, computed from the two cells, within the same run.
`firebase_dart` is the community Dart client (`firebase_dart` 2.0.0-dev.14 on pub.dev); it appears only in run B.

### Cold connect (15 runs per repeat, fresh process each, tiny dataset)

**connect_to_first_value_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 1.41 (1.36 to 1.50) | 0.25 |
| JS SDK | A | 0 | 5.67 (5.57 to 6.07) |  |
| ours | B | 0 | 1.47 (1.26 to 2.25) | 0.24 |
| JS SDK | B | 0 | 6.18 (5.93 to 7.30) |  |
| firebase_dart | B | 0 | 8.53 (8.27 to 9.14) |  |
| ours | A | 50 | 121 (115 to 127) | 0.95 |
| JS SDK | A | 50 | 127 (125 to 129) |  |
| ours | B | 50 | 119 (117 to 125) | 0.93 |
| JS SDK | B | 50 | 128 (125 to 131) |  |
| firebase_dart | B | 50 | 124 (117 to 127) |  |


### Snapshot of 1,000 children

**fresh_connection_get_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 3.77 (3.61 to 5.56) | 0.44 |
| JS SDK | A | 0 | 8.61 (8.08 to 10.64) |  |
| ours | B | 0 | 3.73 (3.50 to 6.85) | 0.44 |
| JS SDK | B | 0 | 8.54 (8.20 to 11.59) |  |
| firebase_dart | B | 0 | 9.28 (8.84 to 10.39) |  |


**fresh_connection_get_plus_val_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 4.34 (4.09 to 6.39) | 0.49 |
| JS SDK | A | 0 | 8.88 (8.34 to 11.27) |  |
| ours | B | 0 | 4.22 (3.96 to 7.78) | 0.47 |
| JS SDK | B | 0 | 8.94 (8.47 to 12.36) |  |
| firebase_dart | B | 0 | 10.49 (10.18 to 12.51) |  |


**get_ms_warm_connection** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 2.82 (2.73 to 4.11) | 1.05 |
| JS SDK | A | 0 | 2.69 (2.62 to 3.64) |  |
| ours | B | 0 | 2.85 (2.76 to 5.53) | 1.07 |
| JS SDK | B | 0 | 2.67 (2.63 to 5.11) |  |


### Snapshot of 10,000 children

**fresh_connection_get_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 37.85 (37.77 to 39.38) | 1.06 |
| JS SDK | A | 0 | 35.64 (34.71 to 37.51) |  |
| ours | B | 0 | 43.99 (42.25 to 83.82) | 1.23 |
| JS SDK | B | 0 | 35.78 (34.84 to 64.06) |  |
| firebase_dart | B | 0 | 23.50 (22.72 to 37.21) |  |


**fresh_connection_get_plus_val_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 44.99 (44.35 to 47.49) | 1.18 |
| JS SDK | A | 0 | 38.24 (37.66 to 39.72) |  |
| ours | B | 0 | 51.09 (47.73 to 95.37) | 1.33 |
| JS SDK | B | 0 | 38.36 (36.87 to 68.53) |  |
| firebase_dart | B | 0 | 37.10 (36.38 to 63.80) |  |


**get_ms_warm_connection** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 34.81 (33.99 to 35.63) | 1.17 |
| JS SDK | A | 0 | 29.64 (29.28 to 33.60) |  |
| ours | B | 0 | 40.55 (37.19 to 78.14) | 1.43 |
| JS SDK | B | 0 | 28.44 (28.30 to 56.57) |  |


### Snapshot of 100,000 children

**fresh_connection_get_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 382 (378 to 384) | 1.13 |
| JS SDK | A | 0 | 337 (334 to 350) |  |
| ours | B | 0 | 427 (424 to 817) | 1.30 |
| JS SDK | B | 0 | 329 (325 to 625) |  |
| firebase_dart | B | 0 | 187 (181 to 336) |  |


**fresh_connection_get_plus_val_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 478 (466 to 484) | 1.30 |
| JS SDK | A | 0 | 369 (362 to 383) |  |
| ours | B | 0 | 522 (505 to 1001) | 1.45 |
| JS SDK | B | 0 | 360 (356 to 680) |  |
| firebase_dart | B | 0 | 317 (309 to 604) |  |


**get_ms_warm_connection** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 376 (368 to 382) | 1.15 |
| JS SDK | A | 0 | 326 (322 to 333) |  |
| ours | B | 0 | 428 (424 to 829) | 1.35 |
| JS SDK | B | 0 | 318 (311 to 613) |  |


### Writes: set

**seq_ack_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 0.16 (0.16 to 0.17) | 0.41 |
| JS SDK | A | 0 | 0.39 (0.38 to 0.40) |  |
| ours | B | 0 | 0.14 (0.13 to 0.25) | 0.61 |
| JS SDK | B | 0 | 0.23 (0.23 to 0.45) |  |
| firebase_dart | B | 0 | 0.22 (0.17 to 0.39) |  |


**pipelined_ops_per_s** (operations per second; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 10650 (9896 to 10865) | 1.35 |
| JS SDK | A | 0 | 7901 (7336 to 8330) |  |
| ours | B | 0 | 13304 (9263 to 13737) | 1.44 |
| JS SDK | B | 0 | 9257 (6385 to 10764) |  |
| firebase_dart | B | 0 | 9655 (6858 to 9917) |  |


### Writes: sequential set, with and without 50 ms round trip

**seq_ack_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 0.17 (0.14 to 0.19) | 1.00 |
| JS SDK | A | 0 | 0.17 (0.16 to 0.22) |  |
| ours | B | 0 | 0.16 (0.13 to 0.21) | 1.07 |
| JS SDK | B | 0 | 0.15 (0.15 to 0.26) |  |
| firebase_dart | B | 0 | 0.19 (0.15 to 0.32) |  |
| ours | A | 50 | 55.51 (55.43 to 55.75) | 0.99 |
| JS SDK | A | 50 | 55.94 (55.72 to 57.56) |  |
| ours | B | 50 | 55.45 (55.33 to 57.46) | 0.99 |
| JS SDK | B | 50 | 55.82 (55.80 to 57.64) |  |
| firebase_dart | B | 50 | 55.64 (55.54 to 57.69) |  |


### Writes: update (three paths)

**seq_ack_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 0.16 (0.15 to 0.19) | 0.50 |
| JS SDK | A | 0 | 0.32 (0.26 to 0.36) |  |
| ours | B | 0 | 0.18 (0.15 to 0.26) | 0.95 |
| JS SDK | B | 0 | 0.19 (0.18 to 0.34) |  |
| firebase_dart | B | 0 | 0.85 (0.78 to 1.72) |  |


**pipelined_ops_per_s** (operations per second; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 9726 (9147 to 11122) | 11.08 |
| JS SDK | A | 0 | 878 (854 to 890) |  |
| ours | B | 0 | 802 (413 to 811) | 0.89 |
| JS SDK | B | 0 | 897 (454 to 919) |  |
| firebase_dart | B | 0 | 190 (95.28 to 194) |  |


### Writes: push

**seq_ack_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 0.13 (0.13 to 0.13) | 0.81 |
| JS SDK | A | 0 | 0.16 (0.14 to 0.17) |  |
| ours | B | 0 | 0.13 (0.13 to 0.20) | 0.81 |
| JS SDK | B | 0 | 0.16 (0.15 to 0.27) |  |
| firebase_dart | B | 0 | 0.15 (0.15 to 0.23) |  |


**pipelined_ops_per_s** (operations per second; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 20133 (19990 to 20331) | 1.28 |
| JS SDK | A | 0 | 15749 (15089 to 17155) |  |
| ours | B | 0 | 20341 (10941 to 20657) | 1.26 |
| JS SDK | B | 0 | 16207 (9472 to 17453) |  |
| firebase_dart | B | 0 | 16227 (9402 to 16519) |  |


### Child events (writer and listener are two connections in one process)

**events_per_s** (events per second; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 16895 (16714 to 17270) | 1.45 |
| JS SDK | A | 0 | 11660 (8827 to 12484) |  |
| ours | B | 0 | 16780 (8855 to 16974) | 1.36 |
| JS SDK | B | 0 | 12357 (6708 to 12621) |  |
| firebase_dart | B | 0 | 1127 (585 to 1172) |  |


**event_latency_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 60.93 (59.28 to 90.23) | 0.64 |
| JS SDK | A | 0 | 94.69 (82.21 to 110) |  |
| ours | B | 0 | 62.33 (58.81 to 120) | 0.74 |
| JS SDK | B | 0 | 84.25 (81.78 to 141) |  |
| firebase_dart | B | 0 | 656 (635 to 1260) |  |


### Query: orderByChild(score), limitToLast(50 + run number), 100,000 children

**query_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 33.45 (32.91 to 34.11) | 0.97 |
| JS SDK | A | 0 | 34.49 (33.72 to 35.26) |  |
| ours | B | 0 | 33.01 (32.83 to 63.46) | 0.99 |
| JS SDK | B | 0 | 33.45 (32.61 to 65.09) |  |
| firebase_dart | B | 0 | 41.71 (40.62 to 71.36) |  |


### Transactions: 2 clients, 100 increments each, one counter

**total_ms** (ms; ratio = ours / JS SDK, same run)

| client | run | rtt ms | median (min to max of the per-run p50) | ratio |
|---|---|---|---|---|
| ours | A | 0 | 75.16 (71.82 to 98.46) | 0.59 |
| JS SDK | A | 0 | 127 (123 to 140) |  |
| ours | B | 0 | 67.72 (65.20 to 110) | 0.57 |
| JS SDK | B | 0 | 119 (114 to 163) |  |
| firebase_dart | B | 0 | 4996 (4946 to 5018) |  |
| ours | A | 50 | 12071 (11740 to 14729) | 0.97 |
| JS SDK | A | 50 | 12490 (11599 to 12846) |  |
| ours | B | 50 | 13430 (12145 to 15304) | 0.92 |
| JS SDK | B | 50 | 14633 (13683 to 15001) |  |
| firebase_dart | B | 50 | 15732 (15683 to 16427) |  |

### Snapshot of 100,000 children: the REST floor (run B)

A plain HTTP GET of the same dataset (one request, no client sync logic): get plus decode 139 ms (134 to 274), get 69.09
ms (63.88 to 128), peak RSS 316 MB (max 348). It is in run B only.

### Wire and memory per operation

Counts from the counting proxy over the whole process lifetime including connect and warm-up, divided by the number of
operations; medians over the repeats. `c2s` is client to server, `s2c` server to client.

| scenario | client | run | rtt ms | c2s msg/op | s2c msg/op | s2c KB/op | peak RSS MB (median, max) |
|---|---|---|---|---|---|---|---|
| cold_connect | JS SDK | A | 0 | 2.00 | 3.00 | 0.56 | 61.0, 61.2 |
| cold_connect | ours | A | 0 | 1.00 | 2.00 | 0.51 | 18.7, 18.7 |
| cold_connect | JS SDK | A | 50 | 2.00 | 3.00 | 0.56 | 62.0, 62.1 |
| cold_connect | ours | A | 50 | 1.00 | 2.00 | 0.51 | 18.7, 18.7 |
| cold_connect | firebase_dart | B | 0 | 1.00 | 3.00 | 0.57 | 20.5, 20.5 |
| cold_connect | firebase_dart | B | 50 | 1.00 | 3.00 | 0.56 | 20.4, 20.4 |
| snapshot_1k | JS SDK | A | 0 | 1.55 | 10.07 | 123 | 117, 132 |
| snapshot_1k | ours | A | 0 | 1.02 | 9.55 | 123 | 56.1, 56.3 |
| snapshot_1k | firebase_dart | B | 0 | 0.57 | 6.07 | 67.71 | 54.9, 54.9 |
| snapshot_10k | JS SDK | A | 0 | 1.59 | 80.14 | 1242 | 236, 244 |
| snapshot_10k | ours | A | 0 | 1.05 | 79.59 | 1241 | 207, 210 |
| snapshot_10k | firebase_dart | B | 0 | 0.62 | 46.38 | 710 | 89.3, 211 |
| snapshot_100k | JS SDK | A | 0 | 1.67 | 784 | 12510 | 1526, 1536 |
| snapshot_100k | ours | A | 0 | 1.08 | 784 | 12510 | 321, 328 |
| snapshot_100k | firebase_dart | B | 0 | 0.73 | 500 | 7961 | 310, 328 |
| write_set | JS SDK | A | 0 | 1.00 | 1.00 | 0.05 | 92.1, 93.0 |
| write_set | ours | A | 0 | 1.00 | 1.00 | 0.05 | 52.8, 53.3 |
| write_set | firebase_dart | B | 0 | 1.00 | 1.00 | 0.05 | 64.8, 65.1 |
| set_ack_sequential | JS SDK | A | 0 | 1.01 | 1.01 | 0.05 | 60.1, 60.4 |
| set_ack_sequential | ours | A | 0 | 1.00 | 1.01 | 0.05 | 20.0, 20.0 |
| set_ack_sequential | JS SDK | A | 50 | 1.01 | 1.01 | 0.05 | 63.2, 63.3 |
| set_ack_sequential | ours | A | 50 | 1.00 | 1.01 | 0.05 | 19.9, 19.9 |
| set_ack_sequential | firebase_dart | B | 0 | 1.00 | 1.01 | 0.05 | 20.6, 20.9 |
| set_ack_sequential | firebase_dart | B | 50 | 1.01 | 1.01 | 0.05 | 20.5, 20.6 |
| write_update | JS SDK | A | 0 | 1.00 | 1.00 | 0.05 | 148, 150 |
| write_update | ours | A | 0 | 1.00 | 1.00 | 0.05 | 63.9, 64.0 |
| write_update | firebase_dart | B | 0 | 1.00 | 1.00 | 0.05 | 93.9, 94.5 |
| write_push | JS SDK | A | 0 | 1.00 | 1.00 | 0.05 | 108, 109 |
| write_push | ours | A | 0 | 1.00 | 1.00 | 0.05 | 53.2, 53.3 |
| write_push | firebase_dart | B | 0 | 1.00 | 1.00 | 0.05 | 65.1, 65.1 |
| child_events | JS SDK | A | 0 | 1.00 | 2.00 | 0.25 | 141, 159 |
| child_events | ours | A | 0 | 1.00 | 2.00 | 0.25 | 70.8, 72.0 |
| child_events | firebase_dart | B | 0 | 1.00 | 2.00 | 0.25 | 92.3, 93.5 |
| query_last_50 | JS SDK | A | 0 | 1.09 | 1.13 | 7.70 | 69.9, 69.9 |
| query_last_50 | ours | A | 0 | 1.04 | 1.09 | 7.70 | 20.0, 20.0 |
| query_last_50 | firebase_dart | B | 0 | 1.04 | 2.13 | 7.77 | 28.2, 28.3 |
| transaction_2clients | JS SDK | A | 0 | 4.28 | 7.10 | 0.43 | 75.5, 76.3 |
| transaction_2clients | ours | A | 0 | 4.36 | 7.13 | 0.43 | 19.9, 20.0 |
| transaction_2clients | JS SDK | A | 50 | 4.29 | 6.95 | 0.42 | 74.3, 74.4 |
| transaction_2clients | ours | A | 50 | 4.26 | 6.88 | 0.41 | 20.0, 20.0 |
| transaction_2clients | firebase_dart | B | 0 | 1.30 | 3.22 | 0.20 | 20.6, 20.7 |
| transaction_2clients | firebase_dart | B | 50 | 1.44 | 3.08 | 0.19 | 20.6, 20.6 |

`firebase_dart` receives fewer messages and fewer bytes for the same snapshot (100,000 children: 500 messages and 7961
KB per operation in run B, against 784 messages and 12510 KB for our client and the JS SDK). The result files do not
explain the difference. A maintainer comparing the clients should treat the `firebase_dart` snapshot cells with that in
mind.

### Round trips on the critical path of one operation

(p50 at 50 ms minus p50 at 0 ms) / 50 ms, from the result files.

| scenario | client | run | p50 at 0 ms | p50 at 50 ms | round trips |
|---|---|---|---|---|---|
| cold_connect | ours | A | 1.41 | 121 | 2.4 |
| cold_connect | JS SDK | A | 5.67 | 127 | 2.4 |
| cold_connect | firebase_dart | B | 8.53 | 124 | 2.3 |
| set_ack_sequential | ours | A | 0.17 | 55.51 | 1.1 |
| set_ack_sequential | JS SDK | A | 0.17 | 55.94 | 1.1 |
| set_ack_sequential | firebase_dart | B | 0.19 | 55.64 | 1.1 |
| transaction_2clients | ours | A | 75.16 | 12071 | 240 |
| transaction_2clients | JS SDK | A | 127 | 12490 | 247 |
| transaction_2clients | ours | B | 67.72 | 13430 | 267 |
| transaction_2clients | JS SDK | B | 119 | 14633 | 290 |
| transaction_2clients | firebase_dart | B | 4996 | 15732 | 215 |

In run B the same table gives 2.3 round trips for our client at cold connect and 2.4 for the JS SDK; in run A both are
2.4. The values are computed from rounded p50 values.

### Transactions: outcomes and retries

Two clients each run 100 increments of one counter, 3 runs per repeat, 5 repeats. Each run is correct only if the final
server value equals the number of committed transactions.

| client | run | rtt ms | committed of 600, every repeat | failed | final values | correct |
|---|---|---|---|---|---|---|
| ours | A | 0 and 50 | 600 | none | 200 in every run | 5 of 5 repeats at each rtt |
| JS SDK | A | 0 and 50 | 600 | none | 200 in every run | 5 of 5 repeats at each rtt |
| firebase_dart | B | 0 | 594, 595, 594, 594, 595 | `max-retries`: 6, 5, 6, 6, 5 | 198 or 199 | yes |
| firebase_dart | B | 50 | 591 in every repeat | `max-retries`: 9 in every repeat | 197 in every run | yes |

Retries per commit and commits per second (run A, from the `extra` field): at 0 ms, the JS SDK 1.252 retries per commit
and 1622.036 commits per second, our client 1.343 and 2700.805; at 50 ms, the JS SDK 1.27 and 15.348, our client 1.068
and 16.898.

### Update throughput against set throughput (the case behind fix 1)

| client | run | `update` / `set` pipelined throughput | source cells |
|---|---|---|---|
| ours | B | 802 / 13304 (the file header of C gives 0.06 for this ratio before the fix) | B |
| JS SDK | B | 897 / 9257 | B |
| ours | C (Low Power Mode on) | 5806 / 6626 (the file header of C gives 0.88) | C |
| JS SDK | C (Low Power Mode on) | 459 / 4195 (the file header of C gives 0.11) | C |
| ours | A | 9726 / 10650 | A |
| JS SDK | A | 878 / 7901 | A |

## 4. What we changed and what it bought

These four changes were made after run B. The figures for fixes 1 to 4 were reported by the engineer who ran the
measurements; the before and after of fixes 2 to 4 were taken in an offline harness for the data layer, and those
figures are not in a result file of the harness. Fix 1 has result files (runs B and C). Each pair was taken within one
power state.

| # | Change | What it bought |
|---|---|---|
| 1 | Acknowledge pipelined updates without rebuilding the visible writes | Update to set throughput ratio from 0.06 to 0.88 (run C, one power state). The JS SDK is at 0.11 in the same run and has the same quadratic cost. |
| 2 | Small maps stored as sorted arrays | Building the tree of the 100,000-child snapshot: 176 to 121 ms. Retained size of that tree: 176 to 155 MB. |
| 3 | One key object per distinct name per message | Build time unchanged; tree 155 to 115 MB. |
| 4 | A three-field leaf node | Build 127 to 121 ms; producing the value 95 to 78 ms; tree 115 to 94 MB. |

End to end, the 100,000-child read (get plus val) went from 522 ms (run B) to 478 ms (run A), and peak memory from 460
MB (run B) to 321 MB (run A). These are two separate runs, not one pair: run A was taken on AC power with Low Power Mode
off, and run B, taken before the four fixes, on battery power. The JS SDK in the two runs, which did not change, was 360
ms and 369 ms, and 1424 MB and 1526 MB.

Where the 478 ms goes, as measured so far (not from a result file; the split is in progress):

| part | ms |
|---|---|
| producing the unmodifiable value (a decided behaviour of the API) | about 96 |
| JSON decoding | about 83 |
| building the tree | about 121 |
| not yet split: socket and frames, safety scans, sync tree, hashing | about 180 |

The four parts as given add to 480; they are rounded.

## 5. Targets

Three targets were set before the client existed, from the baseline measured with the other clients
(`from_helper/11_bench_harness_baseline.md`, run `2026-11-22-r5`, AC power, another run than A and B).

| Target | Where it came from | Our client in run A | Result |
|---|---|---|---|
| At most 2.4 round trips to first value | JS SDK: 2.4 (124.3 ms against 6.5 ms) | 2.4 (1.41 ms at 0 ms, 121 ms at 50 ms); 2 messages from the server and 1 from the client | Met. Equal to the JS SDK (2.4, 3 messages from the server, 2 from the client). |
| 100,000-child snapshot, fresh connection, get: at most 191 ms and 308 MB | `firebase_dart`: 191 ms (get plus val 328 ms), peak RSS 308 MB | get 382 ms (378 to 384), get plus val 478 ms (466 to 484), peak RSS 321 MB (maximum 328) | Missed on both. In run B, `firebase_dart` get was 187 ms (181 to 336) and our client's 427 ms, a different run on battery power. |
| A write acknowledged in at most 0.17 ms with one message each way | JS SDK: 0.17 ms, 1.01 messages each way | `set_ack_sequential` at 0 ms: 0.17 ms (0.14 to 0.19); `write_set`: 0.16 ms (0.16 to 0.17); 1.00 client to server and 1.01 server to client per operation | Met at the median. The upper end of the range in `set_ack_sequential` is 0.19 ms. |

The miss on the 100,000-child snapshot has a measured cause only in part. The engineer's split of the 478 ms (section 4)
puts the largest identified parts at building the tree (about 121 ms), producing the value (about 96 ms, a decided
behaviour), and JSON decoding (about 83 ms), with about 180 ms not yet attributed. The `get` alone (382 ms) excludes
producing the value. `firebase_dart`'s get completes with fewer bytes received than ours (section 3, wire table); the
sources do not say why.

Snapshot of 10,000 children, where our client also trails the JS SDK (run A):

| metric | ours | JS SDK | ratio |
|---|---|---|---|
| fresh_connection_get_ms | 37.85 (37.77 to 39.38) | 35.64 (34.71 to 37.51) | 1.06 |
| fresh_connection_get_plus_val_ms | 44.99 (44.35 to 47.49) | 38.24 (37.66 to 39.72) | 1.18 |
| get_ms_warm_connection | 34.81 (33.99 to 35.63) | 29.64 (29.28 to 33.60) | 1.17 |

In run B, `firebase_dart` measured 23.50 ms (22.72 to 37.21) for the fresh get on 10,000 children, 37.10 ms for get plus
val, with our client at 43.99 ms and 51.09 ms in that run.

## 6. The disk cache

Source: `reports/sqlite-load-bench.md`. This is **another machine and another day's run**: a Mac mini (M4 Pro), AC
power, Dart 3.11.5, `dart compile exe`, medians of 5, rows of about 100 bytes (`{name: 40 chars, count: int, done:
bool}`), `synchronous=FULL`. The script is `firebase_database/firebase_database_dart_sqlite/tool/bench_load.dart`
(branch `rtdb/sqlite`). All times are on the calling isolate: the engine is synchronous, so this is how long an app's
main isolate is blocked.

| Cache | Rows | Write | Reopen | Load all | Load one child | One pending write | Load 200 pending |
|---|---|---|---|---|---|---|---|
| 1 MB | 10000 | 51.9 ms | 3.4 ms | 56.2 ms | 0.1 ms | 0.1 ms | 0.5 ms |
| 10 MB | 100000 | 483.8 ms | 12.7 ms | 615.2 ms | 0.2 ms | 0.1 ms | 0.4 ms |
| 50 MB | 500000 | 2123.7 ms | 55.5 ms | 2968.3 ms | 0.2 ms | 0.1 ms | 0.5 ms |

As read in the source report: a pending write costs 0.1 ms and a small read 0.1 to 0.2 ms whatever the cache size;
loading or writing a whole subtree is linear, about 60 ms per MB (6 microseconds per row), so a listener on the root of
a full 10 MB cache (the default limit) blocks the isolate for about 0.6 s at start and 50 MB for about 3 s; reopen grows
with the cache (55 ms at 50 MB) and is not yet split. macOS `fsync` does not force the drive's cache (SQLite's
`fullfsync` pragma is off), so 0.1 ms per commit is not the cost on Linux or Windows, where it was not measured.

The JS SDK has no disk persistence, so there is no JS column. No run compared our disk cache with another client's.

## 7. How to reproduce

Needs Dart, Node, Java, a working firebase-tools CLI (a local npm install is preferred; set `FIREBASE_CLI` to override)
and the database emulator jar (`firebase setup:emulators:database`). The script never logs in and never touches a real
project. From the root of a checkout of branch `rtdb/bench` (run A was taken at commit `b6ea15d7`):

```
tool/bench_rtdb.sh                      # whole suite 5 times (--repeats=N), about 6 minutes per repeat; writes results/<date>/{numbers.json,RESULTS.md}
tool/bench_rtdb.sh --quick              # without the 100k scenarios
tool/bench_rtdb.sh --drivers=rest,js --scenarios=snapshot_1k,write_set --rtt-override=0
```

The harness README is `tool/bench_rtdb/README.md`. Before a comparison, put the machine on AC power with Low Power Mode
off (`pmset -g`), as run A did, and keep other heavy work off the machine: the emulator, the proxy and the drivers share
the CPU.

| Piece | Path |
|---|---|
| Scenarios, shared by all drivers | `tool/bench_rtdb/scenarios.json` |
| Counting and delay proxy | `tool/bench_rtdb/lib/proxy.dart` |
| Statistics, dataset generator, result line | `tool/bench_rtdb/lib/kit.dart` |
| Orchestrator, loader, Markdown | `tool/bench_rtdb/bin/run.dart` |
| Official JS SDK driver (npm `firebase` 13.4.0) | `tool/bench_rtdb/js/driver.mjs` |
| `firebase_dart` driver (its own pubspec) | `tool/bench_rtdb/appsup/bin/driver.dart` |
| Our client's driver (its own package) | `tool/bench_rtdb/ours/bin/driver.dart` |
| Disk cache load benchmark | `firebase_database/firebase_database_dart_sqlite/tool/bench_load.dart` |

## 8. What was not measured

- A production database. Every cell ran against the local emulator; ack latency, reconnect, TLS, server query cost,
  quotas and multi-region behaviour are not represented.
- Any machine other than one Apple M5 (and, for the disk cache, one Mac mini). One day, one operating system version.
- Linux and Windows.
- The browser builds of our client.
- Real networks: only a fixed delay of 0 or 50 ms per round trip through the proxy.
- Phones (Android and iOS) and the FlutterFire native SDKs.
- Reconnect, many listeners on overlapping paths, memory per node, and startup from the disk cache against another
  client (scenarios planned in the design, not run).
- Disk persistence of other clients.
- Run-to-run drift beyond the 5 repeats: the three runs A, B and C were taken on the same day, but not interleaved.
