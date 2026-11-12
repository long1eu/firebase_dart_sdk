# Upstream commit analysis: brief (shared by 5 agents)

Goal: the Dart port in cloud_firestore_vm was last synced with firebase-android-sdk commit 576da00e85 (2019-07-23). 707 commits have touched `firebase-firestore` since. Each agent analyzes ONE chunk of ~140 commits (oldest first) and writes a classification so we can plan what the Dart port is missing. READ-ONLY: edit nothing in the repo; write only your output file.

Inputs (all under <scratchpad>/upstream/):
- chunk_N: TSV `sha<TAB>date<TAB>subject` for your chunk (chunks: chunk_0..chunk_4, chronological).
- android-sdk/: sparse partial clone of firebase-android-sdk (only firebase-firestore checked out; blobs are fetched lazily, so `git show` may pause a moment; if git reports a lock or transient fetch error, retry). Do not modify it, don't check out other revisions in it (use `git show <sha>`, `git show <sha> --stat`, `git diff a b -- path`, `git log -p`).
- android_firestore_changelog.md (in ../runs/): release notes per Android Firestore version, to map commits to released features.
- The Dart port: <scratchpad>/mine/repo/cloud_firestore/cloud_firestore_vm/lib/src/firebase/firestore/ (it mirrors the Java structure 1:1: model/, core/, local/, remote/, util/, and top-level API files). Use grep to check whether the code a commit touches exists in the Dart port and whether the bug/feature is already handled.

For every commit in your chunk produce one row. Triage by subject first; read the diff (`git show --stat`, then the relevant hunks) for anything touching src/main logic. Commits that are only tests, docs, build/gradle/CI, changelog, version bumps, formatting, mergebacks or Android-only (Android Context, ProGuard, Kotlin extensions, Robolectric, instrumentation) get a one-line classification without deep reading. Be efficient; do not read every diff fully, but DO read every non-trivial src/main logic change.

Columns (markdown table, one row per commit, in chunk order):
`sha7 | date | PR# | category | area | relevance | in Dart? | what changed and why it matters for the port`
- category: BUGFIX-correctness | BUGFIX-crash | FEATURE-public-API | FEATURE-internal | PERF | PERSISTENCE-schema (needs a SQLite migration) | PROTOCOL-wire | REFACTOR | TEST | DOCS | BUILD | ANDROID-ONLY | MERGEBACK
- area: model | core | local | remote | util | api | index | bundle | other
- relevance for the Dart port: MUST (correctness, data safety, wire/protocol compat, persistence), SHOULD (user-visible behaviour/feature parity), COULD (nice to have, perf), N/A
- in Dart?: YES (already handled), NO (missing, applies), PARTIAL, N/A, or UNKNOWN; name the Dart file when you checked.
- last column: one or two sentences. For MUST/SHOULD rows cite the Dart file(s) that would change and the changelog version if it's a released feature.

Output: write `<scratchpad>/upstream/analysis_N.md` (N = your chunk number) containing, in this order: (1) 10-line summary of the chunk's themes; (2) a "Top items" list: the 10-20 most important commits for the Dart port with one-line reasons and a rough size S/M/L for porting; (3) the full table; (4) "Dependencies and ordering": which commits must be ported together (e.g. a feature spread over several commits), and any that revert or supersede earlier ones (incl. across chunks: say so, don't guess the other chunk's content). Mark anything you inferred without reading the diff as (unverified). Final message: a short report with counts by relevance (MUST/SHOULD/COULD/N/A), the top 5 items, and any commits you could not classify.
