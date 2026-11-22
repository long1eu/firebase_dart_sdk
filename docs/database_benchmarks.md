# Realtime Database client: benchmark report

This report measures `firebase_database_dart`, the pure-Dart Realtime Database client of this repository, against the
official Firebase JS SDK and, in some cells, against the community Dart client `firebase_dart`. It is written for two
readers: someone deciding whether to use the client, and a maintainer of the official SDK who will check it for
fairness. Every number is copied from a result file of the harness; nothing was measured while writing it. A number
marked "computed" is a ratio or difference of two table cells. Every table names its source file in the line under it.

All comparisons between clients come from one session, `2026-11-23-ab`. Earlier runs are not cited. They were
withdrawn after a review of the harness found unfair spots (section 2.3); the harness was corrected and this session
was taken afterwards.

## 1. Summary

- One session (2026-11-23), Apple M5, local emulator, 5 repeats. The reference for every cell is the JS SDK.
- Ahead (p50 ranges do not overlap): cold connect to first value in a fresh process, 1.58 against 5.62 ms (compiled
  Dart against JavaScript not yet optimised; warm 0.82 against 4.84 ms); the 1,000-child read, 3.14 against 7.57 ms;
  pipelined `update` of 1,000 children of one parent, 11,170 against 903 a second (the best case of one fix);
  pipelined `push`; child events a second.
- No winner, or 0.4 ms or less apart: sequential `set` acknowledgement, pipelined `set`, the last-50 query,
  transactions with two clients, the 10,000 and 100,000-child reads without the value (349 against 329 ms).
- Behind: the 100,000-child read with the value (448 against 360 ms; the value takes 95.44 ms here against 29.27 ms,
  an unmodifiable copy that is built once and kept); the 10,000-child read with the value; `update` of the same path
  (483 against 563 a second). `firebase_dart` reads 100,000 children in 197 ms, faster than both.
- Against this client's own earlier build: `update` of the same path is slower, 483 now against 710 a second;
  the cause is found (an overlap check that ran for every pending write on each acknowledgement) and the fix is
  under review, not in this run. The first value of the 100,000-child snapshot, 95.44 against 76.08 ms, has
  overlapping ranges and is not a change in the work done: measured separately on both builds, the first value
  costs about 55 ms of CPU in each, and the newer build's read allocates less, so a garbage collection that used
  to fall inside the read now often falls inside the first value (about 20 ms). That measurement is outside this
  session (`first_value_regression.md` of the round's reports).

## 2. Method and environment

### 2.1 Environment

| Key | Value |
|---|---|
| machine_model | Mac17,2 |
| cpu | Apple M5, 10 cores, 32 GB |
| os | macOS 27.2.1 |
| power | Now drawing from 'AC Power' |
| low_power_mode | 0 |
| thermal | No thermal warning level, no performance warning level and no CPU power status recorded |
| dart | 3.12.2; the Dart drivers are AOT builds (`dart compile exe`) |
| node | v26.10.0 |
| js_sdk | firebase 13.4.0, @firebase/database 1.1.6 (Node build, transport faye-websocket 0.11.4) |
| appsup_firebase_dart | firebase_dart 2.0.0-dev.14 (the community Dart client) |
| java | openjdk version "24.0.2" 2025-07-15 |
| firebase_tools | 15.36.0 |
| database_emulator_jar | firebase-database-emulator-v4.11.2.jar |
| harness git_commit | 973e1545, clean |
| ours_b | commit 2b7a3b96 (the client before the four performance changes of section 4) |
| dataset sha256 | tiny 19aea01cdf5b, flat_1k 89867f6e68c1, flat_10k d35d9b071901, flat_100k 4d9d132ea50b |

Source: `2026-11-23-ab.md`, "Environment".

The four drivers are `js` (the Firebase JS SDK on Node), `appsup` (`firebase_dart`, called "firebase_dart" below),
`ours` (this client; its sources at harness commit 973e1545 and at trunk 425ee19d are identical, read from an empty
`git diff` of `firebase_database_dart/lib` and `firebase_app_dart/lib`) and `ours_b` (this client at 2b7a3b96). The
two builds of this client run the same driver code; they differ only in the client library.

The whole suite ran 5 times, each repeat from a fresh emulator process. A cell shows the median over the repeats of
the per-run p50, with the minimum and maximum of that p50 across the repeats in brackets. The order of the drivers
rotates between repeats:

| repeat | order |
|---|---|
| 1 | js, appsup, ours, ours_b |
| 2 | ours_b, ours, appsup, js |
| 3 | appsup, ours, ours_b, js |
| 4 | js, ours_b, ours, appsup |
| 5 | ours, ours_b, js, appsup |

Source: `2026-11-23-ab.md`, "Environment".

Everything runs on one machine: the emulator (a JVM), the counting proxy and the driver. The proxy counts HTTP
requests, connections, WebSocket frames, messages and bytes, and can delay traffic by a round-trip time (0 or 50 ms).
A TCP handshake is not delayed by the proxy.

### 2.2 How to read the tables

- Values are medians of the five per-repeat medians with the range of those five in brackets, in the unit of the
  source (ms, or operations or events a second).
- "ours against JS" applies the file's overlap rule to this client and the JS SDK only: a winner is named when the p50
  ranges across repeats do not overlap. The rule is applied to the rounded numbers printed in the file (computed).
- "file verdict, four drivers" is the file's own line. The file names a winner only when that driver's range overlaps
  no other driver's. Because `ours_b` is the same client, its range often overlaps `ours`, and the file then says "no
  winner" although `ours` and `js` are apart. That is why both columns are shown. The `ours_b` numbers are in section
  4.
- The reference for every cell is the JS SDK.

### 2.3 What was wrong with the earlier run and how the harness handles it now

An earlier run was withdrawn after a review of the harness (`bench_challenge.md`). The eight points that matter for
fairness, and what the harness does now:

| # | Problem found | What the harness does now |
|---|---|---|
| 1 | Drivers ran in the same order in every repeat, so the first driver after the 100,000-child cell paid for it. | The order rotates by one every second repeat and is reversed on odd repeats; the order of every repeat is in the file header (table above). |
| 2 | Peak memory was measured differently: an exact maximum for Dart, samples every 100 ms for Node; and a bare Node process starts about 40 MB above a bare Dart AOT process. | Every driver reports its own process maximum (Dart `ProcessInfo.maxRss`, Node `process.resourceUsage().maxRSS`). The `ps` sample every 100 ms is a cross-check. A `baseline` cell (runtime and client library loaded, no client) is subtracted to give "over baseline". |
| 3 | The checks did not compare data (a snapshot only had to be non-empty). | Every snapshot, connect and query run is hashed after the timer stops and compared with the dataset hash. Write cells are compared with the expected server state after the run. Transactions compare the final server value with the committed count. The `correct` column counts runs. |
| 4 | A second read of the value was not separated from the first. | `first_val_ms` and `second_val_ms` are two reads of the value of one snapshot. |
| 5 | The timer for a fresh connection included client creation, connection and request in one number. | `open_ms`, `connected_ms` and `read_after_connect_ms` time the parts; the totals are kept. |
| 6 | The connect and read paths of the JS SDK were measured before V8 had optimised them. | The `cold_connect_warm` and `snapshot_1k_warm` cells repeat the same operation after 200 runs in the same process, beside the fresh-process cells. |
| 7 | p90 and p99 were printed for 3 to 5 values. | p90 and p99 are printed only for runs of 20 or more values. Below that the cell shows min, median, max and n. |
| 8 | Winners were named where the ranges overlap. | A winner is named only when the p50 range over the repeats overlaps no other driver's; otherwise "no winner". |

Sources: `bench_challenge.md` (the problems); `2026-11-23-ab.md`, first paragraph and "Environment";
`tool/bench_rtdb/README.md` (the handling).

Remaining limits a reader should know:

- Cold connect and the fresh-connection reads compare AOT-compiled Dart with JavaScript in a fresh process. V8 runs
  the connect path at most 22 times in such a process, so it has not optimised it. That is what an app sees at start,
  and it is not a statement about steady-state client code. The warm cells give the steady-state numbers.
- The Node JS SDK uses faye-websocket, a JavaScript WebSocket implementation; this client uses `dart:io`. Each is what
  a user of that client gets.
- The dataset is flat: 1,000, 10,000 and 100,000 children with short keys in sorted order, depth 3, small strings,
  floats, integers and booleans. It does not represent large strings or deep trees.
- Each cell has 3 to 20 runs per repeat and 5 repeats. The ranges are over five numbers.
- No collection is forced on either side, so each runtime collects the garbage of earlier runs inside later timed
  regions (per `bench_challenge.md`, which read the earlier harness; the README of this one does not say otherwise).
- Wire counts include the connect and the warm-up of the whole process (section 6).
- "ours second_val_ms" of 0.00 ms is not a speed claim: this client returns the value it built on the first read
  (`second_val_identical` is true for it and for `ours_b`, false for `firebase_dart`), so the second read does no
  work.

## 3. Results

Each table has one row per metric. Cells are `median (min-max of the per-repeat medians)`. Lower is better for ms;
higher is better for operations and events a second.

### 3.1 Cold connect (fresh process, 15 runs, no warm-up)

A new client per run in a fresh process. `connect_to_first_value_ms` is `open_ms` (client objects created) plus
`connected_ms` (handshake done) plus `read_after_connect_ms` (a read of a one-node dataset).

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| connect_to_first_value_ms | 0 | 5.62 (5.51-6.04) | 14.49 (14.45-14.63) | 1.58 (1.53-1.71) | ours ahead | no winner |
| connect_to_first_value_ms | 50 | 119 (116-123) | 124 (122-124) | 114 (113-114) | ours ahead | no winner |
| open_ms | 0 | 0.06 (0.05-0.06) | 0.00 (0.00-0.00) | 0.01 (0.01-0.02) | ours ahead | winner appsup |
| open_ms | 50 | 0.21 (0.17-0.22) | 0.01 (0.01-0.01) | 0.07 (0.07-0.08) | ours ahead | winner appsup |
| connected_ms | 0 | 4.99 (4.89-5.30) | 5.66 (5.59-5.74) | 1.00 (0.97-1.08) | ours ahead | no winner |
| connected_ms | 50 | 61.84 (59.89-64.31) | 56.48 (56.37-57.07) | 56.59 (56.19-56.70) | ours ahead | no winner |
| read_after_connect_ms | 0 | 0.66 (0.62-0.80) | 8.90 (8.81-8.96) | 0.59 (0.56-0.62) | no winner | no winner |
| read_after_connect_ms | 50 | 56.16 (54.89-56.45) | 65.96 (65.42-66.73) | 56.79 (56.54-57.50) | JS ahead | no winner |

Source: `2026-11-23-ab.md`, "cold_connect". With 50 ms of round-trip time the connect takes 2.2 to 2.3 round trips for
every client (section 6.2), so the 5 ms between 119 and 114 ms (computed) is a small part of the total.

### 3.2 Cold connect after 200 connects in the same process

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| connect_to_first_value_ms | 0 | 4.84 (4.78-4.96) | 14.53 (14.45-14.79) | 0.82 (0.61-0.88) | ours ahead | no winner |
| open_ms | 0 | 0.03 (0.02-0.03) | 0.00 (0.00-0.01) | 0.01 (0.01-0.01) | ours ahead | winner appsup |
| connected_ms | 0 | 4.49 (4.43-4.53) | 5.70 (5.63-5.71) | 0.53 (0.40-0.56) | ours ahead | no winner |
| read_after_connect_ms | 0 | 0.39 (0.36-0.43) | 8.76 (8.76-8.96) | 0.29 (0.21-0.32) | ours ahead | no winner |

Source: `2026-11-23-ab.md`, "cold_connect_warm". This is the warm variant of 3.1, run at 0 ms only.

### 3.3 Snapshot of 1,000 children

`get` of a path with 1,000 children on a fresh connection (20 runs after 2 warm-up). `fresh_connection_read_ms` is the
read after the handshake; `get_ms` is client creation, connection and read together; `get_plus_val_ms` adds the first
read of the value. `get_ms_warm_connection` is a `get` on a client that is already connected.

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| fresh_connection_connected_ms | 0 | 4.68 (4.64-4.86) | 5.32 (5.28-5.36) | 0.68 (0.66-0.71) | ours ahead | no winner |
| fresh_connection_read_ms | 0 | 2.70 (2.59-3.12) | 9.82 (9.71-10.02) | 2.49 (2.43-2.54) | ours ahead | winner ours |
| fresh_connection_get_ms | 0 | 7.57 (7.30-8.04) | 15.10 (15.07-15.30) | 3.14 (3.08-3.19) | ours ahead | winner ours |
| fresh_connection_get_plus_val_ms | 0 | 7.86 (7.76-8.39) | 16.33 (16.29-16.66) | 3.58 (3.54-3.65) | ours ahead | winner ours |
| first_val_ms | 0 | 0.30 (0.28-0.34) | 1.26 (1.19-1.35) | 0.45 (0.45-0.47) | JS ahead | winner js |
| second_val_ms | 0 | 0.21 (0.20-0.23) | 1.25 (1.18-1.34) | 0.00 (0.00-0.00) | ours ahead | no winner |
| get_ms_warm_connection | 0 | 2.54 (2.43-2.60) | - | 2.40 (2.34-2.48) | no winner | no winner |
| repeat_get_ms_served_from_memory | 0 | - | 0.01 (0.01-0.01) | - | - | no winner |

Source: `2026-11-23-ab.md`, "snapshot_1k". The lead in `get_ms` comes from connection set-up (`connected_ms` 0.68
against 4.68 ms). The read alone is 2.49 against 2.70 ms, and on a warm connection the ranges overlap (2.40 and 2.54
ms). `repeat_get_ms_served_from_memory` is `firebase_dart` only: a repeat `get` that it answers from memory without
wire traffic.

Warm variant, after 200 fresh-connection reads in the same process:

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| fresh_connection_connected_ms | 0 | 4.44 (4.39-4.48) | 5.27 (5.21-5.32) | 0.60 (0.57-0.60) | ours ahead | no winner |
| fresh_connection_read_ms | 0 | 2.30 (2.28-2.35) | 9.76 (9.75-9.83) | 2.35 (2.32-2.41) | no winner | no winner |
| fresh_connection_get_ms | 0 | 6.71 (6.66-6.83) | 15.01 (14.97-15.15) | 2.93 (2.90-3.03) | ours ahead | winner ours |
| fresh_connection_get_plus_val_ms | 0 | 6.99 (6.93-7.13) | 16.31 (16.30-16.52) | 3.38 (3.35-3.50) | ours ahead | winner ours |
| first_val_ms | 0 | 0.27 (0.27-0.29) | 1.33 (1.25-1.36) | 0.45 (0.44-0.47) | JS ahead | winner js |
| second_val_ms | 0 | 0.20 (0.20-0.20) | 1.34 (1.25-1.35) | 0.00 (0.00-0.00) | ours ahead | no winner |
| get_ms_warm_connection | 0 | 2.19 (2.14-2.37) | - | 2.27 (2.24-2.34) | no winner | no winner |

Source: `2026-11-23-ab.md`, "snapshot_1k_warm".

### 3.4 Snapshot of 10,000 children (10 runs after 1 warm-up)

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| fresh_connection_connected_ms | 0 | 4.40 (4.34-4.83) | 5.53 (5.50-5.55) | 0.91 (0.90-0.98) | ours ahead | no winner |
| fresh_connection_read_ms | 0 | 28.18 (27.78-29.68) | 22.80 (22.60-22.89) | 31.75 (30.83-32.46) | JS ahead | winner appsup |
| fresh_connection_get_ms | 0 | 33.18 (32.35-34.24) | 28.29 (28.08-28.48) | 33.25 (31.77-33.74) | no winner | winner appsup |
| fresh_connection_get_plus_val_ms | 0 | 35.20 (34.45-36.58) | 43.30 (43.03-43.89) | 38.80 (37.72-39.49) | JS ahead | winner js |
| first_val_ms | 0 | 2.08 (2.04-2.11) | 14.41 (14.20-15.03) | 4.87 (4.84-5.24) | JS ahead | winner js |
| second_val_ms | 0 | 1.80 (1.77-1.82) | 13.55 (13.33-13.68) | 0.00 (0.00-0.00) | ours ahead | no winner |
| get_ms_warm_connection | 0 | 28.38 (27.99-29.18) | - | 31.85 (31.08-33.27) | JS ahead | winner js |
| repeat_get_ms_served_from_memory | 0 | - | 0.01 (0.01-0.01) | - | - | no winner |

Source: `2026-11-23-ab.md`, "snapshot_10k". The `get_ms` row has no winner between this client and the JS SDK because
this client connects 3.49 ms faster (computed: 4.40 minus 0.91) and reads 3.57 ms slower (computed: 31.75 minus
28.18); the request alone (`fresh_connection_read_ms`) is behind. This client's read is 1.13 times the JS SDK's time
(computed), with the value 1.10 times (computed), on a warm connection 1.12 times (computed).

### 3.5 Snapshot of 100,000 children (5 runs after 1 warm-up)

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| fresh_connection_connected_ms | 0 | 5.29 (4.56-5.47) | 5.57 (5.27-5.65) | 1.03 (0.95-1.07) | ours ahead | no winner |
| fresh_connection_read_ms | 0 | 324 (316-341) | 192 (180-193) | 348 (340-355) | no winner | winner appsup |
| fresh_connection_get_ms | 0 | 329 (320-346) | 197 (186-199) | 349 (341-356) | no winner | winner appsup |
| fresh_connection_get_plus_val_ms | 0 | 360 (350-375) | 335 (328-336) | 448 (438-451) | JS ahead | winner appsup |
| first_val_ms | 0 | 29.27 (27.43-30.34) | 130 (128-131) | 95.44 (89.56-108) | JS ahead | winner js |
| second_val_ms | 0 | 28.72 (28.20-29.10) | 141 (140-144) | 0.00 (0.00-0.00) | ours ahead | no winner |
| get_ms_warm_connection | 0 | 319 (316-321) | - | 346 (339-355) | JS ahead | winner js |
| repeat_get_ms_served_from_memory | 0 | - | 0.01 (0.01-0.01) | - | - | no winner |

Source: `2026-11-23-ab.md`, "snapshot_100k".

- Read without the value: 349 ms against 329 ms; the ranges overlap (341-356 and 320-346). This client's time is 1.06
  times the JS SDK's (computed).
- Read with the value: 448 ms against 360 ms, 1.24 times (computed). The first value costs 95.44 ms here and 29.27 ms
  in the JS SDK, 3.26 times (computed). This client builds an unmodifiable copy of the tree on the first read and
  keeps it: a decided behaviour. What the copy buys is the second value: 0.00 ms here (it returns the same object)
  against 28.72 ms in the JS SDK, which builds a new tree on every call.
- On a warm connection the read is 346 ms against 319 ms, 1.08 times (computed), ranges apart.
- `firebase_dart` reads 100,000 children in 197 ms (186-199), faster than both clients. With the value it needs 335 ms
  against the JS SDK's 360 ms. Its first value costs 130 ms and its second 141 ms.

### 3.6 Writes

Each write cell sends 200 sequential operations (`seq_ack_ms`: the time until the acknowledgement) and 1,000 in flight
(`pipelined_ops_per_s`), 3 runs after 20 warm-up. The pipelined `update` cases:

- `write_update`: 1,000 updates to different children of one parent, `update(root, {i/i, i/name, i/pad})`.
- `write_update_spread`: every update at a parent of its own.
- `write_update_same`: every update writes the same child.

`write_set`, sequential and pipelined:

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| seq_ack_ms | 0 | 0.16 (0.15-0.36) | 0.21 (0.15-0.33) | 0.14 (0.13-0.33) | no winner | no winner |
| pipelined_ops_per_s | 0 | 14683 (8434-17185) | 11155 (8705-13726) | 13924 (9185-16370) | no winner | no winner |

Source: `2026-11-23-ab.md`, "write_set".

`set_ack_sequential`, 300 sequential `set` operations, at 0 and 50 ms:

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| seq_ack_ms | 0 | 0.14 (0.14-0.15) | 0.14 (0.14-0.14) | 0.13 (0.12-0.13) | ours ahead | no winner |
| seq_ack_ms | 50 | 55.62 (55.51-55.68) | 55.31 (55.25-55.37) | 55.23 (54.90-55.25) | ours ahead | no winner |

Source: `2026-11-23-ab.md`, "set_ack_sequential". The ranges do not overlap, and the medians differ by 0.01 ms at 0 ms
and by 0.39 ms at 50 ms (computed). Both clients need 1.1 round trips for an acknowledgement (section 6.2).

`update`, 1,000 different children of one parent. This is the best case of one fix, which removes an acknowledged
merge without rebuilding the visible writes:

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| seq_ack_ms | 0 | 0.22 (0.21-0.28) | 0.85 (0.76-0.95) | 0.19 (0.19-0.24) | no winner | no winner |
| pipelined_ops_per_s | 0 | 903 (895-918) | 188 (185-192) | 11170 (10886-11292) | ours ahead | winner ours |

Source: `2026-11-23-ab.md`, "write_update". This client's rate is 12.37 times the JS SDK's (computed).

`update`, every update at a parent of its own:

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| seq_ack_ms | 0 | 0.20 (0.17-0.21) | 0.17 (0.17-0.21) | 0.15 (0.15-0.19) | no winner | no winner |
| pipelined_ops_per_s | 0 | 10444 (10401-10562) | 12186 (12047-12442) | 17247 (17201-17421) | ours ahead | winner ours |

Source: `2026-11-23-ab.md`, "write_update_spread". 1.65 times the JS SDK's rate (computed).

`update`, every update writes the same child. This is the case where this client is behind:

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| seq_ack_ms | 0 | 0.20 (0.16-0.20) | 0.20 (0.17-0.20) | 0.15 (0.14-0.18) | no winner | no winner |
| pipelined_ops_per_s | 0 | 563 (530-564) | 12924 (12548-13221) | 483 (477-494) | JS ahead | winner appsup |

Source: `2026-11-23-ab.md`, "write_update_same". This client's rate is 0.86 times the JS SDK's (computed).
`firebase_dart` is at 12,924 per second here and is the file's winner.

`push`:

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| seq_ack_ms | 0 | 0.15 (0.15-0.20) | 0.15 (0.14-0.19) | 0.13 (0.12-0.13) | ours ahead | no winner |
| pipelined_ops_per_s | 0 | 16905 (14667-17536) | 16390 (15626-16673) | 20058 (19321-20322) | ours ahead | no winner |

Source: `2026-11-23-ab.md`, "write_push". The file says "no winner" because the `ours_b` range (18,310-20,544)
overlaps the `ours` range; the `ours` range does not overlap the JS SDK's. 1.19 times the JS SDK's rate (computed).

### 3.7 Child events

Writer and listener are two connections in one process; 2,000 writes are issued at once and the listener counts the
events (3 runs). Event latency has 6,000 samples per repeat.

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| events_per_s | 0 | 12803 (10351-13419) | 1121 (1085-1148) | 17191 (15924-17479) | ours ahead | no winner |
| event_latency_ms | 0 | 81.91 (74.03-83.04) | 677 (640-684) | 74.49 (59.95-85.85) | no winner | no winner |

Source: `2026-11-23-ab.md`, "child_events". Events a second: 1.34 times the JS SDK's (computed). The latency ranges
overlap.

### 3.8 Query, last 50

`orderByChild("score").limitToLast(50)` on the 100,000-child dataset with an index declared in the emulator rules (20
runs after 3 warm-up).

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| query_ms | 0 | 32.84 (32.35-33.63) | 40.74 (39.32-41.48) | 32.67 (31.94-33.62) | no winner | no winner |

Source: `2026-11-23-ab.md`, "query_last_50".

### 3.9 Transactions with two clients

Two clients each commit 100 increments of one counter (3 runs). The correctness column of the file is 5/5 for every
driver: the server value after each run equals the number of committed transactions. `firebase_dart` committed 591 to
596 of 600 and gave up the rest with `max-retries`; the JS SDK and this client committed 600 of 600 in every repeat.

| metric | rtt ms | JS SDK | firebase_dart | ours | ours against JS | file verdict, four drivers |
|---|---|---|---|---|---|---|
| total_ms | 0 | 71.11 (63.17-106) | 4793 (4632-4871) | 74.48 (61.72-103) | no winner | no winner |
| total_ms | 50 | 12035 (11901-12250) | 15439 (15377-15475) | 11554 (11539-11882) | ours ahead | no winner |

Source: `2026-11-23-ab.md`, "transaction_2clients" and its outcome table. At 50 ms the ranges do not overlap
(11,539-11,882 against 11,901-12,250), with a 19 ms gap between them (computed); the medians differ by 481 ms, this
client's time being 0.96 times the JS SDK's (computed). The file says "no winner" because `ours_b` (11,682-11,965)
overlaps both.

## 4. What the four performance changes bought

The `ours_b` and `ours` columns of this one session are a real pair: same session, same harness, same driver code,
rotated order. They differ by every commit between 2b7a3b96 and 425ee19d (75 commits). Four of those commits are the
performance changes:

| commit | change |
|---|---|
| cbadbd1f | Remove acknowledged merges without rebuilding the write tree |
| cdef3fa9 | Keep small sorted maps as arrays |
| 3ef9e06c | One `ChildKey` per distinct name within a `nodeFromJson` call |
| 459c42b7 | Keep three fields in a leaf node |

The session compares two builds; it does not isolate the four changes from the other 71 commits and cannot attribute a
difference to one of them.

| scenario | metric | rtt ms | ours_b | ours | result |
|---|---|---|---|---|---|
| cold_connect | connect_to_first_value_ms | 0 | 1.52 (1.42-1.80) | 1.58 (1.53-1.71) | no difference (ranges overlap) |
| snapshot_1k | fresh_connection_get_ms | 0 | 3.49 (3.43-3.59) | 3.14 (3.08-3.19) | ours better |
| snapshot_1k | get_ms_warm_connection | 0 | 2.72 (2.64-2.85) | 2.40 (2.34-2.48) | ours better |
| snapshot_10k | fresh_connection_read_ms | 0 | 38.93 (38.76-40.94) | 31.75 (30.83-32.46) | ours better |
| snapshot_10k | fresh_connection_get_ms | 0 | 39.73 (39.66-41.95) | 33.25 (31.77-33.74) | ours better |
| snapshot_10k | fresh_connection_get_plus_val_ms | 0 | 49.22 (46.79-52.56) | 38.80 (37.72-39.49) | ours better |
| snapshot_10k | first_val_ms | 0 | 10.37 (7.75-10.81) | 4.87 (4.84-5.24) | ours better |
| snapshot_10k | get_ms_warm_connection | 0 | 39.64 (37.58-41.11) | 31.85 (31.08-33.27) | ours better |
| snapshot_100k | fresh_connection_read_ms | 0 | 414 (409-427) | 348 (340-355) | ours better |
| snapshot_100k | fresh_connection_get_ms | 0 | 416 (411-428) | 349 (341-356) | ours better |
| snapshot_100k | fresh_connection_get_plus_val_ms | 0 | 492 (487-532) | 448 (438-451) | ours better |
| snapshot_100k | first_val_ms | 0 | 76.08 (75.69-104) | 95.44 (89.56-108) | no difference (ranges overlap) |
| snapshot_100k | get_ms_warm_connection | 0 | 440 (430-450) | 346 (339-355) | ours better |
| write_set | pipelined_ops_per_s | 0 | 13710 (9845-17271) | 13924 (9185-16370) | no difference (ranges overlap) |
| write_update | pipelined_ops_per_s | 0 | 799 (786-812) | 11170 (10886-11292) | ours better |
| write_update_spread | pipelined_ops_per_s | 0 | 6318 (6117-6439) | 17247 (17201-17421) | ours better |
| write_update_same | pipelined_ops_per_s | 0 | 710 (696-714) | 483 (477-494) | ours worse |
| write_push | pipelined_ops_per_s | 0 | 20379 (18310-20544) | 20058 (19321-20322) | no difference (ranges overlap) |
| child_events | events_per_s | 0 | 17119 (16328-17278) | 17191 (15924-17479) | no difference (ranges overlap) |
| query_last_50 | query_ms | 0 | 32.40 (32.32-33.00) | 32.67 (31.94-33.62) | no difference (ranges overlap) |
| transaction_2clients | total_ms | 0 | 70.56 (56.12-100) | 74.48 (61.72-103) | no difference (ranges overlap) |
| transaction_2clients | total_ms | 50 | 11817 (11682-11965) | 11554 (11539-11882) | no difference (ranges overlap) |
| set_ack_sequential | seq_ack_ms | 0 | 0.13 (0.13-0.13) | 0.13 (0.12-0.13) | no difference (ranges overlap) |

Source: `2026-11-23-ab.md`; "result" applies the overlap rule to `ours` and `ours_b` (computed).

What the pair shows:

- Write tree: pipelined `update` of different children of one parent went from 799 to 11,170 operations a second
  (13.98 times, computed); `update` at separate parents from 6,318 to 17,247 (2.73 times, computed).
- Read path: the 100,000-child read from 416 to 349 ms, with the value from 492 to 448 ms, on a warm connection from
  440 to 346 ms. The 10,000-child read from 39.73 to 33.25 ms and with the value from 49.22 to 38.80 ms.
- Where the pair shows no difference: cold connect, the first value of the 100,000-child snapshot (see "open" below),
  pipelined `set` and `push`, child events, the last-50 query, transactions, and the sequential acknowledgement.
- A stage measurement of the 100,000-child read (section 5) lists the stage "last frame to payload at ServerActions",
  which includes the check of the read answer. It is 117.3 ms in `stages_100k_quiet_2026-11-23.txt` and 111.7 ms in
  `stages_100k_after_conn_tests_2026-11-23.txt`. The ranges of the two (107.9-143.4 and 109.2-128.2) overlap, so this
  is within noise. The brief attributes the difference to a change that validates read answers in a single walk; the
  two stage files do not name the build each was taken on, and no commit in the range carries that name.

Peak memory, whole process, from the same file (MB, median and maximum over the repeats; "over baseline" subtracts the
runtime baseline of section 6.3):

| scenario | JS SDK | firebase_dart | ours_b | ours |
|---|---|---|---|---|
| snapshot_1k | 140 (142), over baseline 83.1 | 55.5 (56.0), 38.9 | 58.5 (58.9), 42.3 | 57.0 (57.4), 40.9 |
| snapshot_10k | 253 (254), 196 | 92.3 (94.0), 75.6 | 218 (225), 202 | 159 (214), 143 |
| snapshot_100k | 1338 (1531), 1281 | 436 (442), 419 | 438 (448), 422 | 328 (398), 312 |

Source: `2026-11-23-ab.md`, wire and memory tables of "snapshot_1k", "snapshot_10k" and "snapshot_100k". Baselines
(runtime with the client library loaded, no client opened): JS SDK 57.2 MB, firebase_dart 16.6 MB, ours 16.1 MB,
ours_b 16.1 MB (section 6.3 lists all cells).

For the 100,000-child read this client's median peak is 328 MB against 1,338 MB for the JS SDK; over baseline it is
312 against 1,281 MB. V8 lets the heap grow before it collects, so part of the JS figure is runtime policy and not
live data; the file measures process peak, not live heap.

### Open: two differences against this client's own earlier build

Both were found by this session and are not explained. They are under investigation.

1. Pipelined `update` of the same path: 483 operations a second now against 710 on `ours_b` (ranges 477-494 and
   696-714 do not overlap; 0.68 times, computed). Peak memory in the same cell is 64.1 MB against 41.4 MB. Among the
   75 commits between the builds, `a5e448fd` ("Keep a server leaf when a write below it is acknowledged") touches the
   acknowledgement path; it has not been tested as the cause.
2. The first value of the 100,000-child snapshot: 95.44 ms now against 76.08 ms on `ours_b`. The ranges overlap
   (89.56-108 and 75.69-104), so this session does not establish a difference; it is listed because the medians moved
   against this client while the read itself got faster.

## 5. Where the time of a 100,000-child read goes

The stage harness times each step of one `get` of the 100,000-child dataset (12,807,114 characters in 783 frames, 7
rounds after 2 warm-up) against an in-process replay server that answers at once, on a quiet machine. Two files were
taken. The unit is not printed in the files; the values are read as milliseconds because the end-to-end stage C
(312.4) is of the order of the 349 ms read of section 3.5 (inferred). The stage harness uses no emulator, so its
end-to-end numbers do not equal the benchmark's.

A, client CPU on the answer, offline:

| stage | quiet | after_conn_tests |
|---|---|---|
| A1 utf8Length of each frame (assembler byte count) | 6.9 (6.8-7.1) | 7.0 (6.8-7.1) |
| A2 join | 1.0 (1.0-1.8) | 0.9 (0.9-8.1) |
| A3 checkJsonDepth | 12.1 (11.9-13.7) | 13.7 (12.9-15.0) |
| A4 jsonDecode | 75.5 (62.9-87.9) | 76.5 (72.7-83.8) |
| A5 decodeServerMessage | 7.1 (6.9-10.7) | 7.7 (7.3-8.3) |
| A6 isValidServerData (get answer check) | 13.2 (12.8-14.8) | 13.3 (13.1-17.1) |
| A7 nodeFromJson | 142.0 (116.2-152.2) | 135.6 (120.0-154.2) |
| A8 setQueryActive + keepSynced(true) | 0.0 (0.0-0.0) | 0.0 (0.0-0.0) |
| A9 applyServerOverwrite (get answer) | 56.4 (51.3-69.6) | 63.0 (48.6-76.1) |
| A10 keepSynced(false) | 0.0 (0.0-0.0) | 0.0 (0.0-0.0) |
| A11 withIndex(query index) | 0.0 (0.0-0.0) | 0.0 (0.0-0.0) |
| sum of the stage medians A1-A11 | 314.2 | 317.8 |
| A12 applyServerOverwrite with one value listener | 50.4 (49.1-66.5) | 49.9 (49.3-66.9) |
| A13 node.value (snap.value, after get) | 70.9 (66.7-93.8) | 75.9 (67.1-90.9) |
| B1 dart:io WebSocket: go -> first frame | 0.1 (0.1-0.1) | 0.1 (0.1-0.1) |
| B2 dart:io WebSocket: first -> last frame | 6.4 (6.2-9.4) | 6.9 (5.7-9.4) |
| B3 library channel: go -> first frame | 0.1 (0.1-0.1) | 0.1 (0.1-0.1) |
| B4 library channel: first -> last frame | 7.5 (6.1-9.3) | 6.8 (5.7-7.2) |
| B5 library channel + assembler: go -> first frame | 0.1 (0.1-0.1) | 0.1 (0.1-0.1) |
| B6 library channel + assembler: first -> last frame decoded | 94.0 (86.0-104.2) | 98.6 (93.8-107.8) |

C, the real client, fresh connection per `get`, and D, warm connection:

| stage | quiet | after_conn_tests |
|---|---|---|
| C1 open -> channel open (tokens, timer, TCP, upgrade) | 0.4 (0.3-0.4) | 0.3 (0.3-0.3) |
| C2 channel open -> hello | 0.0 (0.0-0.0) | 0.0 (0.0-0.0) |
| C3 hello -> get request sent | 0.0 (0.0-0.0) | 0.0 (0.0-0.0) |
| C4 request sent -> first answer frame (replay server) | 0.1 (0.1-0.1) | 0.1 (0.1-0.1) |
| C5 first -> last answer frame (socket, A1 per frame) | 15.2 (13.0-21.8) | 16.5 (12.9-17.7) |
| C6 last frame -> payload at ServerActions (A2-A6) | 117.3 (107.9-143.4) | 111.7 (109.2-128.2) |
| C7 payload -> DataSnapshot returned (Repo, A7-A11) | 186.1 (172.3-213.2) | 186.3 (175.2-214.8) |
| sum of the stage medians C1-C7 | 319.1 | 314.9 |
| C end to end: get() (or open) -> DataSnapshot | 312.4 (299.0-363.5) | 324.2 (300.3-339.2) |
| C snap.value | 88.5 (74.5-113.2) | 86.6 (72.7-94.7) |
| D3 get() called -> get request sent | 0.0 (0.0-0.3) | 0.0 (0.0-0.0) |
| D4 request sent -> first answer frame (replay server) | 27.8 (26.6-35.9) | 29.1 (26.0-37.0) |
| D5 first -> last answer frame (socket, A1 per frame) | 13.0 (12.8-21.7) | 12.8 (12.7-14.1) |
| D6 last frame -> payload at ServerActions (A2-A6) | 109.8 (101.7-120.4) | 109.8 (98.7-125.6) |
| D7 payload -> DataSnapshot returned (Repo, A7-A11) | 181.3 (171.9-196.7) | 190.4 (174.9-218.4) |
| sum of the stage medians D3-D7 | 331.9 | 342.2 |
| D end to end: get() (or open) -> DataSnapshot | 338.0 (331.3-351.8) | 340.0 (328.2-378.6) |
| D snap.value | 87.3 (70.0-89.4) | 87.2 (67.8-94.4) |
| E1 get() -> DataSnapshot (nodeFromJson, sync tree, API) | 199.0 (192.0-224.8) | 206.3 (191.4-208.2) |
| sum of the stage medians E1 | 199.0 | 206.3 |

Source: `stages_100k_quiet_2026-11-23.txt` and `stages_100k_after_conn_tests_2026-11-23.txt` (stage harness).

Reading of the quiet file, as the answer to why this client is slower than the JS SDK on large reads:

- Of the 312.4 ms end to end on a fresh connection, 15.2 ms is the socket (C5), 117.3 ms is turning the frames into a
  payload (C6: join, depth check, JSON decode 75.5 ms, message decode, validation) and 186.1 ms is turning the payload
  into the snapshot (C7: `nodeFromJson` 142.0 ms, applying the answer 56.4 ms).
- Producing the value afterwards takes 88.5 ms (C `snap.value`; 70.9 ms in A13).
- The JS SDK was not run through the stage harness. This report has no stage split for it. What the benchmark gives
  for it is 329 ms for the read, 360 ms with the value, and 29.27 ms for the first value.

## 6. Wire behaviour

The counting proxy sees the same server messages for all clients. Counts are for the whole process lifetime, including
connect and warm-up, divided by the operations counted (`ops`), medians over the repeats. `firebase_dart` counts one
operation fewer in each snapshot cell (42 against 44, 21 against 22, 11 against 12; 240 against 440 in the warm 1k
cell) because its driver issues one uncounted priming read (per `bench_challenge.md`, which examined an earlier run of
the same driver), so its per-operation figures are not per read.

### 6.1 Messages and bytes

| scenario | rtt ms | client | ops | conns | c2s msg/op | s2c msg/op | s2c frames/op | c2s KB/op | s2c KB/op |
|---|---|---|---|---|---|---|---|---|---|
| baseline | 0 | JS SDK | 0 | 0 | - | - | - | - | - |
| baseline | 0 | firebase_dart | 0 | 0 | - | - | - | - | - |
| baseline | 0 | ours | 0 | 0 | - | - | - | - | - |
| cold_connect | 0 | JS SDK | 15 | 15 | 2.00 | 3.00 | 4.00 | 0.38 | 0.56 |
| cold_connect | 0 | firebase_dart | 15 | 15 | 1.00 | 3.00 | 3.13 | 0.39 | 0.57 |
| cold_connect | 0 | ours | 15 | 15 | 1.00 | 2.00 | 2.07 | 0.34 | 0.51 |
| cold_connect | 50 | JS SDK | 15 | 15 | 2.00 | 3.00 | 3.93 | 0.38 | 0.56 |
| cold_connect | 50 | firebase_dart | 15 | 15 | 1.00 | 3.00 | 3.00 | 0.39 | 0.56 |
| cold_connect | 50 | ours | 15 | 15 | 1.00 | 2.00 | 2.00 | 0.34 | 0.51 |
| cold_connect_warm | 0 | JS SDK | 215 | 215 | 2.00 | 3.00 | 4.00 | 0.38 | 0.56 |
| cold_connect_warm | 0 | firebase_dart | 215 | 215 | 1.00 | 3.00 | 3.47 | 0.40 | 0.57 |
| cold_connect_warm | 0 | ours | 215 | 215 | 1.00 | 2.00 | 2.12 | 0.34 | 0.51 |
| snapshot_1k | 0 | JS SDK | 44 | 23 | 1.55 | 10.07 | 10.57 | 0.23 | 123 |
| snapshot_1k | 0 | firebase_dart | 42 | 23 | 0.57 | 6.07 | 6.12 | 0.22 | 67.71 |
| snapshot_1k | 0 | ours | 44 | 23 | 1.02 | 9.55 | 9.55 | 0.22 | 123 |
| snapshot_1k_warm | 0 | JS SDK | 440 | 221 | 1.50 | 10.01 | 10.51 | 0.22 | 123 |
| snapshot_1k_warm | 0 | firebase_dart | 240 | 221 | 0.93 | 10.14 | 10.18 | 0.37 | 114 |
| snapshot_1k_warm | 0 | ours | 440 | 221 | 1.00 | 9.50 | 9.51 | 0.21 | 123 |
| snapshot_10k | 0 | JS SDK | 22 | 12 | 1.59 | 80.14 | 80.64 | 0.24 | 1242 |
| snapshot_10k | 0 | firebase_dart | 21 | 12 | 0.62 | 46.38 | 46.43 | 0.23 | 710 |
| snapshot_10k | 0 | ours | 22 | 12 | 1.05 | 79.59 | 79.64 | 0.22 | 1241 |
| snapshot_100k | 0 | JS SDK | 12 | 7 | 1.67 | 784 | 785 | 0.26 | 12510 |
| snapshot_100k | 0 | firebase_dart | 11 | 7 | 0.73 | 500 | 500 | 0.26 | 7961 |
| snapshot_100k | 0 | ours | 12 | 7 | 1.08 | 784 | 784 | 0.24 | 12510 |
| write_set | 0 | JS SDK | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.18 | 0.05 |
| write_set | 0 | firebase_dart | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.18 | 0.05 |
| write_set | 0 | ours | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.18 | 0.05 |
| set_ack_sequential | 0 | JS SDK | 320 | 1 | 1.01 | 1.01 | 1.01 | 0.18 | 0.05 |
| set_ack_sequential | 0 | firebase_dart | 320 | 1 | 1.00 | 1.01 | 1.01 | 0.18 | 0.05 |
| set_ack_sequential | 0 | ours | 320 | 1 | 1.00 | 1.01 | 1.01 | 0.18 | 0.05 |
| set_ack_sequential | 50 | JS SDK | 320 | 1 | 1.01 | 1.01 | 1.01 | 0.18 | 0.05 |
| set_ack_sequential | 50 | firebase_dart | 320 | 1 | 1.01 | 1.01 | 1.01 | 0.18 | 0.05 |
| set_ack_sequential | 50 | ours | 320 | 1 | 1.00 | 1.01 | 1.01 | 0.18 | 0.05 |
| write_update | 0 | JS SDK | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update | 0 | firebase_dart | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update | 0 | ours | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update_spread | 0 | JS SDK | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update_spread | 0 | firebase_dart | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update_spread | 0 | ours | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update_same | 0 | JS SDK | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update_same | 0 | firebase_dart | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_update_same | 0 | ours | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.19 | 0.05 |
| write_push | 0 | JS SDK | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.20 | 0.05 |
| write_push | 0 | firebase_dart | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.20 | 0.05 |
| write_push | 0 | ours | 3220 | 1 | 1.00 | 1.00 | 1.00 | 0.20 | 0.05 |
| child_events | 0 | JS SDK | 6000 | 2 | 1.00 | 2.00 | 2.00 | 0.20 | 0.25 |
| child_events | 0 | firebase_dart | 6000 | 2 | 1.00 | 2.00 | 2.00 | 0.20 | 0.25 |
| child_events | 0 | ours | 6000 | 2 | 1.00 | 2.00 | 2.00 | 0.20 | 0.25 |
| query_last_50 | 0 | JS SDK | 23 | 1 | 1.09 | 1.13 | 1.13 | 0.11 | 7.70 |
| query_last_50 | 0 | firebase_dart | 23 | 1 | 1.04 | 2.13 | 2.13 | 0.13 | 7.77 |
| query_last_50 | 0 | ours | 23 | 1 | 1.04 | 1.09 | 1.09 | 0.11 | 7.70 |
| transaction_2clients | 0 | JS SDK | 600 | 2 | 4.47 | 7.38 | 7.38 | 0.39 | 0.45 |
| transaction_2clients | 0 | firebase_dart | 600 | 5 | 1.29 | 3.22 | 3.23 | 0.14 | 0.20 |
| transaction_2clients | 0 | ours | 600 | 2 | 4.43 | 7.22 | 7.22 | 0.39 | 0.44 |
| transaction_2clients | 50 | JS SDK | 600 | 2 | 4.13 | 6.71 | 6.71 | 0.35 | 0.40 |
| transaction_2clients | 50 | firebase_dart | 600 | 5 | 1.44 | 3.08 | 3.08 | 0.16 | 0.19 |
| transaction_2clients | 50 | ours | 600 | 2 | 4.08 | 6.64 | 6.64 | 0.35 | 0.39 |

Source: `2026-11-23-ab.md`, the wire tables. The `ours_b` rows equal the `ours` rows to the printed precision except
in three cells: `cold_connect_warm` s2c frames 2.06 against 2.12, `snapshot_10k` s2c frames 79.59 against 79.64, and
`transaction_2clients` at 50 ms (c2s 4.11 against 4.08, s2c 6.67 against 6.64).

Reading: bytes from the server per operation are the same for the JS SDK and this client in every snapshot cell (123
KB, 1,242 and 1,241 KB, 12,510 KB for 1,000, 10,000 and 100,000 children). Server frames per operation are 1 higher
for the JS SDK in each snapshot cell (10.57 against 9.55, 80.64 against 79.64, 785 against 784). The JS SDK sends two
messages per connect where this client sends one (the JS SDK sends a statistics message before the first read); in the
connect cells that is 2.00 and 3.00 client and server messages for the JS SDK against 1.00 and 2.00 for this client. A
write and its acknowledgement are about one message each way for all three.

### 6.2 Round trips on the critical path

(p50 at 50 ms minus p50 at 0 ms) divided by 50 ms, as computed by the file. A TCP handshake is not delayed by the
proxy, so the connect counts the HTTP upgrade and the protocol handshake only.

| scenario | metric | JS SDK | firebase_dart | ours | ours_b |
|---|---|---|---|---|---|
| cold_connect | connect_to_first_value_ms | 2.3 | 2.2 | 2.2 | 2.3 |
| cold_connect | connected_ms | 1.1 | 1.0 | 1.1 | 1.1 |
| cold_connect | read_after_connect_ms | 1.1 | 1.1 | 1.1 | 1.1 |
| set_ack_sequential | seq_ack_ms | 1.1 | 1.1 | 1.1 | 1.1 |
| transaction_2clients | total_ms (200 contended increments per run) | 239 | 213 | 230 | 235 |

Source: `2026-11-23-ab.md`, "Round trips per operation (derived from the delay proxy)".

### 6.3 Peak memory, every cell

Peak RSS in MB, median and maximum over the repeats; "over baseline" subtracts the `baseline` cell of the same client.

| scenario | rtt ms | client | peak RSS MB median (max) | over baseline MB |
|---|---|---|---|---|
| baseline | 0 | JS SDK | 57.2 (57.3) | 0.0 |
| baseline | 0 | firebase_dart | 16.6 (16.7) | 0.0 |
| baseline | 0 | ours | 16.1 (16.2) | 0.0 |
| baseline | 0 | ours_b | 16.1 (16.2) | 0.0 |
| cold_connect | 0 | JS SDK | 63.3 (63.4) | 6.1 |
| cold_connect | 0 | firebase_dart | 20.0 (20.3) | 3.4 |
| cold_connect | 0 | ours | 19.3 (19.3) | 3.2 |
| cold_connect | 0 | ours_b | 19.1 (19.1) | 3.0 |
| cold_connect | 50 | JS SDK | 63.3 (63.5) | 6.0 |
| cold_connect | 50 | firebase_dart | 20.5 (20.5) | 3.8 |
| cold_connect | 50 | ours | 19.3 (19.4) | 3.2 |
| cold_connect | 50 | ours_b | 19.1 (19.1) | 3.0 |
| cold_connect_warm | 0 | JS SDK | 82.0 (82.2) | 24.7 |
| cold_connect_warm | 0 | firebase_dart | 20.4 (20.6) | 3.8 |
| cold_connect_warm | 0 | ours | 20.0 (20.1) | 3.9 |
| cold_connect_warm | 0 | ours_b | 20.0 (20.0) | 3.8 |
| snapshot_1k | 0 | JS SDK | 140 (142) | 83.1 |
| snapshot_1k | 0 | firebase_dart | 55.5 (56.0) | 38.9 |
| snapshot_1k | 0 | ours | 57.0 (57.4) | 40.9 |
| snapshot_1k | 0 | ours_b | 58.5 (58.9) | 42.3 |
| snapshot_1k_warm | 0 | JS SDK | 183 (190) | 126 |
| snapshot_1k_warm | 0 | firebase_dart | 55.8 (56.0) | 39.2 |
| snapshot_1k_warm | 0 | ours | 57.3 (57.4) | 41.1 |
| snapshot_1k_warm | 0 | ours_b | 58.7 (59.2) | 42.5 |
| snapshot_10k | 0 | JS SDK | 253 (254) | 196 |
| snapshot_10k | 0 | firebase_dart | 92.3 (94.0) | 75.6 |
| snapshot_10k | 0 | ours | 159 (214) | 143 |
| snapshot_10k | 0 | ours_b | 218 (225) | 202 |
| snapshot_100k | 0 | JS SDK | 1338 (1531) | 1281 |
| snapshot_100k | 0 | firebase_dart | 436 (442) | 419 |
| snapshot_100k | 0 | ours | 328 (398) | 312 |
| snapshot_100k | 0 | ours_b | 438 (448) | 422 |
| write_set | 0 | JS SDK | 92.6 (93.0) | 35.4 |
| write_set | 0 | firebase_dart | 64.7 (65.3) | 48.1 |
| write_set | 0 | ours | 53.4 (53.5) | 37.3 |
| write_set | 0 | ours_b | 54.4 (55.0) | 38.3 |
| set_ack_sequential | 0 | JS SDK | 68.8 (69.0) | 11.6 |
| set_ack_sequential | 0 | firebase_dart | 20.5 (20.6) | 3.8 |
| set_ack_sequential | 0 | ours | 19.9 (20.0) | 3.8 |
| set_ack_sequential | 0 | ours_b | 20.0 (20.0) | 3.8 |
| set_ack_sequential | 50 | JS SDK | 63.4 (64.5) | 6.2 |
| set_ack_sequential | 50 | firebase_dart | 20.5 (20.5) | 3.8 |
| set_ack_sequential | 50 | ours | 20.0 (20.0) | 3.9 |
| set_ack_sequential | 50 | ours_b | 19.9 (20.0) | 3.8 |
| write_update | 0 | JS SDK | 147 (148) | 90.3 |
| write_update | 0 | firebase_dart | 94.1 (94.8) | 77.4 |
| write_update | 0 | ours | 64.1 (64.4) | 48.0 |
| write_update | 0 | ours_b | 64.7 (65.0) | 48.6 |
| write_update_spread | 0 | JS SDK | 112 (113) | 54.8 |
| write_update_spread | 0 | firebase_dart | 84.8 (85.2) | 68.2 |
| write_update_spread | 0 | ours | 58.8 (58.9) | 42.7 |
| write_update_spread | 0 | ours_b | 63.3 (63.8) | 47.2 |
| write_update_same | 0 | JS SDK | 195 (197) | 138 |
| write_update_same | 0 | firebase_dart | 68.0 (68.1) | 51.4 |
| write_update_same | 0 | ours | 64.1 (64.5) | 48.0 |
| write_update_same | 0 | ours_b | 41.4 (41.5) | 25.3 |
| write_push | 0 | JS SDK | 132 (132) | 74.4 |
| write_push | 0 | firebase_dart | 64.7 (65.0) | 48.1 |
| write_push | 0 | ours | 53.4 (53.8) | 37.3 |
| write_push | 0 | ours_b | 53.4 (53.8) | 37.2 |
| child_events | 0 | JS SDK | 161 (162) | 104 |
| child_events | 0 | firebase_dart | 85.3 (93.0) | 68.7 |
| child_events | 0 | ours | 71.4 (72.4) | 55.2 |
| child_events | 0 | ours_b | 73.6 (74.4) | 57.4 |
| query_last_50 | 0 | JS SDK | 70.4 (70.6) | 13.2 |
| query_last_50 | 0 | firebase_dart | 28.0 (28.1) | 11.3 |
| query_last_50 | 0 | ours | 20.1 (20.2) | 4.0 |
| query_last_50 | 0 | ours_b | 20.0 (20.0) | 3.9 |
| transaction_2clients | 0 | JS SDK | 75.5 (75.8) | 18.2 |
| transaction_2clients | 0 | firebase_dart | 20.5 (20.6) | 3.9 |
| transaction_2clients | 0 | ours | 20.1 (20.1) | 4.0 |
| transaction_2clients | 0 | ours_b | 20.0 (20.1) | 3.9 |
| transaction_2clients | 50 | JS SDK | 73.6 (74.3) | 16.4 |
| transaction_2clients | 50 | firebase_dart | 20.6 (20.6) | 4.0 |
| transaction_2clients | 50 | ours | 20.1 (20.2) | 4.0 |
| transaction_2clients | 50 | ours_b | 20.0 (20.1) | 3.9 |

Source: `2026-11-23-ab.md`, the wire and memory tables.

## 7. The disk cache

Another machine and another day: a Mac mini (M4 Pro), AC power, Dart 3.11.5, `dart compile exe`, medians of 5, rows of
about 100 bytes (`{name: 40 chars, count: int, done: bool}`), `synchronous=FULL`. Not the machine, Dart version or
harness of the sections above. All times are on the calling isolate: the SQLite engine is synchronous, so each is the
time an app's main isolate is blocked.

| Cache | Rows | Write | Reopen | Load all | Load one child | One pending write | Load 200 pending |
|---|---|---|---|---|---|---|---|
| 1 MB | 10000 | 51.9 ms | 3.4 ms | 56.2 ms | 0.1 ms | 0.1 ms | 0.5 ms |
| 10 MB | 100000 | 483.8 ms | 12.7 ms | 615.2 ms | 0.2 ms | 0.1 ms | 0.4 ms |
| 50 MB | 500000 | 2123.7 ms | 55.5 ms | 2968.3 ms | 0.2 ms | 0.1 ms | 0.5 ms |

Source: `rtdb/reports/sqlite-load-bench.md` (script `tool/bench_load.dart` of the `firebase_database_dart_sqlite`
package, branch `rtdb/sqlite`). Loading or writing a whole subtree is linear, about 60 ms per MB; a listener on the
root of a full 10 MB cache blocks the isolate for about 0.6 s at start, 50 MB for about 3 s. Reopen grows with the
cache. macOS `fsync` does not force the drive's cache, so 0.1 ms per commit is not the cost on Linux or Windows; this
was not measured there. There is no disk-cache cell in the harness session of section 3: its persistence scenarios are
not part of it.

## 8. How to reproduce

The harness is on a branch that is not merged into trunk: branch `rtdb/bench` of this repository (remote-tracking name
`m5/rtdb/bench`), at the time of writing commit 835d354f. The session of this report ran at harness commit 973e1545;
the harness files differ between the two commits only by the added result files. The result files are
`tool/bench_rtdb/results/2026-11-23-ab/` (`RESULTS.md`, `numbers.json`); the numbers in this report come from the copy
`2026-11-23-ab.md` of 1,046 lines. The documentation is `tool/bench_rtdb/README.md`, the scenarios are
`tool/bench_rtdb/scenarios.json`.

```
# whole suite, 5 repeats, results in tool/bench_rtdb/results/<date>/
tool/bench_rtdb.sh

# two builds of this client in one session: ours_b is built from a checkout of the earlier commit
git worktree add /tmp/rtdb_before 2b7a3b96
OURS_B_TREE=/tmp/rtdb_before tool/bench_rtdb.sh --drivers=js,appsup,ours,ours_b --repeats=5 \
  --out=results/$(date +%F)-ab
```

Needs Dart, Node, Java, a working firebase-tools CLI and the Database emulator jar (`firebase
setup:emulators:database`). The script starts a private emulator (project `demo-rtdb-bench`, ports 9410, 9510, 9610),
runs the orchestrator `bin/run.dart` and stops the emulator again. It never logs in and never touches a real project.
Drivers: `js/driver.mjs` (npm `firebase` 13.4.0), `appsup/bin/driver.dart` (`firebase_dart`), `ours/bin/driver.dart`.
The stage harness of section 5 is separate from this harness.

## 9. Not measured

- A production database: the emulator acknowledges a write after a loopback round trip (about 0.05 ms), with no
  replication; production acknowledgements take longer. The delay proxy shows how many round trips an operation needs,
  not what they cost.
- Real networks: no TLS (all connections are plain `ws://` and `http://` on loopback), no HTTP/2, no load balancer, no
  packet loss; reconnect timing, backoff and dead-link detection.
- Server query and rules cost: rules are open and the emulator holds the index in memory.
- Scale and quotas: one tenant, no throttling, no connection cap, no 16 MB write limit.
- Other machines: one Apple M5. Linux and Windows are not measured.
- The browser builds of this client, and the JS SDK in a browser.
- Phones.
- More than two clients: the third client is `firebase_dart` only; no other Dart or native client is measured.
- Persistence in this session (see section 7 for another machine's disk-cache numbers).
- Large strings and deep trees: the dataset is flat with short values.
