# Upload benchmark

Measures the uploads of `firebase_storage_dart`: object size, chunked against single-request uploads,
added round-trip latency and bandwidth, and many uploads at once with different `maxConcurrentUploads`.
It is for the maintainers; the benchmark directory is not published.

    tool/bench_storage.sh                                   # whole matrix on a private emulator, from the repository root
    tool/bench_storage.sh --sizes=1,16 --rtt=0,50 --repeats=1
    cd firebase_storage/firebase_storage_dart
    FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9299 dart run benchmark/upload_benchmark.dart --backend=emulator
    dart run benchmark/upload_benchmark.dart --help

`tool/bench_storage.sh` starts an emulator on 9480 (hub 9580, logging 9680), runs the benchmark with
its arguments and stops the emulator. The defaults run 24 cells of the size table (1, 16, 64 and 256 MiB, chunked
and single, RTT 0, 50 and 150 ms) and 9 of the concurrency table (20 files of 2 MiB, 1, 4 and 8 uploads at once,
the same RTTs), three runs each; the whole run takes tens of minutes on the emulator.

## How latency is injected

On the emulator every cell runs through a local TCP proxy (`delay_proxy.dart`) between the client and the emulator.
Each direction delays every chunk by half the RTT; `--bandwidth-mbit` caps each direction (shared by the
connections of the run, like one link). The proxy stops reading while a megabyte waits to be released, so it does
not hold an upload in memory and the resident set stays the client's. The TCP handshake is not delayed, and RTT 0
still goes through the proxy.

## What is measured

Per run: wall time, throughput (MiB/s), the number of HTTP requests (retries included), the number of progress
events, the longest gap between two progress events (the start and the end count; a large gap is a coarse
progress bar), and the growth of the resident set (`ProcessInfo.currentRss` sampled every 20 ms, minus its value
before the uploads start; with `--source=bytes` the data is allocated before that). Each cell is repeated
`--repeats` times (default 3) and the tables show the median. A Markdown table goes to stdout and a JSON file with
every run to `benchmark/results/` (git-ignored).

- **chunked** sets `maxUploadChunkSize` to `--chunk-max-mib` (default 16): chunks start at 256 KiB and double.
- **single** leaves it null: one streamed request on the VM.
- The concurrency table uses `single` and `startUpload` for all files at once; `maxConcurrentUploads` lets that many
  run, the others queue.
- `--source=file` uploads with `putFile` from a temporary file instead of from memory.

## Production

    export FIREBASE_TEST_PROJECT_ID=my-project FIREBASE_TEST_STORAGE_BUCKET=my-project.firebasestorage.app
    export FIREBASE_API_KEY=...                                  # for --create-user
    dart run benchmark/upload_benchmark.dart --backend=production --create-user --sizes=1,16 --repeats=1   # prints the plan
    dart run benchmark/upload_benchmark.dart --backend=production --create-user --sizes=1,16 --repeats=1 --yes

It prints the project, bucket, prefix (`bench_storage/run_<utc>_<suffix>/`) and the plan first and does nothing
without `--yes`. It refuses to start when the plan uploads more than `--max-bytes` (default 1 GiB: the default
matrix is too big, choose `--sizes`). Every object is deleted after its run. `--create-user` signs up a throwaway
user with a random password that is never printed or stored and deletes it at the end (same as the verification
kit in `tool/verify_production_storage`). The real network is the only network: `--rtt` and `--bandwidth-mbit`
are refused. Uploading costs bandwidth and operations on a billed project.
