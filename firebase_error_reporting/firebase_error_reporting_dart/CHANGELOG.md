## Unreleased

- The README: setup, the relay and direct transports, capturing errors, users and privacy, behaviour and
  limits. Its Dart snippets are compiled by `test/readme_snippets_test.dart`.

## 0.1.0-dev.2

Fixes from an independent review:

- A `Retry-After` shorter than the backoff no longer shortens it (`Retry-After: 0` made a request loop), and
  an error recorded while a send is in flight no longer cuts a backoff short.
- Saves are serialised and coalesced, and the file store writes a temporary file of its own for each save:
  concurrent saves corrupted the file. Nothing is saved before the store was read, so `close()` during a slow
  load no longer erases the saved state.
- The file store saves without the oldest events when the state passes 8 MiB, so it never writes a file it
  refuses to read; `context.user` and the fields of `HttpRequestContext` are capped.
- Line breaks and control characters in the header become a visible `\n` or a space, so an error message can no
  longer forge stack frames.
- The fingerprint of the rate limit holds the start of the description (on the web many errors share the top
  frame), and the first virtual address of an obfuscated trace; the limiter forgets old kinds.
- The relay re-checks the collection switch right before sending; token providers time out after 10 s; a
  configured provider that fails, a token a header cannot hold, and a 401 or 403 from the relay pause the queue
  instead of dropping events. An event that fails ten times in a row is dropped.
- A request is aborted at its 30-second deadline. Refusal bodies are logged without the credentials of the
  request. A number JSON cannot hold no longer blocks the queue. A throwing `onDiagnostic` is ignored.
- `recordError(typeName:)`; `recordErrorText` with an empty stack no longer adds the reporter's own stack.

## 0.1.0-dev.1

- First version, not published: `ErrorReporter` with the relay and direct transports, the V8 and Dart
  message formats, memory, `localStorage` and file stores, a rate limit, retries with backoff, `beforeSend`,
  `runGuarded` and `watchIsolate`.
