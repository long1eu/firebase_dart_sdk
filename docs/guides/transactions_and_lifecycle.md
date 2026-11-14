# Transactions and the lifecycle

How transactions retry, what read-only transactions give you, and what `terminate()` does to
work in progress.

## Transactions

Transactions are optimistic, as in the Android and JS SDKs: `transaction.get` reads the current
version of a document, and the commit sends every write with a precondition on the version that was
read (documents that were only read are verified). When a precondition fails the whole callback is
run again, up to `TransactionOptions.maxAttempts` times (5 by default), so the callback must not
have side effects of its own.

**A commit whose answer is lost can be applied twice.** A commit is retried when it fails with
`aborted`, `failedPrecondition` or `alreadyExists`, which the backend only returns when nothing was
applied, but also on connection-level errors (`unavailable`, `unknown`, `cancelled`,
`deadlineExceeded`, `internal`, `resourceExhausted`), the same rule as upstream. If the connection
breaks after the backend applied the commit but before the client received the answer, the client
cannot tell, runs the callback again, reads the result of its own first attempt and applies the
change a second time (a counter is incremented twice). This is rare, and the Android and JS SDKs
have the same exposure. If a transaction must not be applied twice, make it idempotent: write a
value that identifies the operation (for example an operation id that the callback checks before
writing) instead of relying on a relative change.

Writes outside transactions (`set`, `update`, `delete`, `WriteBatch`) go through the write stream.
When the stream breaks, the writes that were not acknowledged are sent again on the new stream, as
upstream does. Overwrites and deletes are harmless to repeat. A relative transform such as
`FieldValue.increment` is not: in the runs of the production verification kit, the backend applied
a re-sent increment a second time after its acknowledgement was lost, as the emulator does.

### Read-only transactions

`TransactionOptions(readOnly: true)` runs a read-only transaction **of the backend** (the server
SDKs have these; the Android and JS client SDKs do not):

```dart
final total = await firestore.runTransaction((transaction) async {
  final account = await transaction.get(firestore.doc('accounts/a'));
  final orders = await transaction.getQuery(
      firestore.collection('orders').where('account', isEqualTo: 'a'));
  final count = await transaction.getAggregate(firestore.collection('orders').count());
  return (account.data, orders.docs.length, count.getCount());
}, options: TransactionOptions(readOnly: true));
```

- Every read of the transaction sees the database as it was at one point in time: documents
  (`get`), queries (`getQuery`) and aggregations (`getAggregate`) are consistent with each other,
  also while other clients write. `getQuery` and `getAggregate` only exist for read-only
  transactions; in a read-write transaction they fail with `invalidArgument`, because such a
  transaction verifies its reads at commit and the result of a query cannot be verified.
- `TransactionOptions(readOnly: true, readTime: timestamp)` reads the database as it was at
  `timestamp`. The backend keeps old versions for a limited time and rejects read times before that.
- Writes in the transaction throw. Nothing is committed and no locks are taken, so there are no
  conflicts: the callback is not run again when documents change. It is only run again (up to
  `maxAttempts` times) when the connection fails.
- The reads go to the backend: they never use the cache, do not include local writes that the
  backend has not seen, and fail when the client is offline.
- Until this change a read-only transaction read documents one by one and asked the backend at the
  end whether they had changed, running again if so. Code that relied on the callback running
  again now sees the snapshot instead.

## Lifecycle: `terminate()`

`await firestore.terminate()` stops the instance: listeners stop receiving events, the streams and
the local cache are closed, and `Firestore.instanceFor` returns a new instance from then on. What
happens to work that was in progress, as in the Android and JS SDKs:

- A write whose future has not completed (it was not acknowledged by the backend yet) **never
  completes**: its future neither succeeds nor fails. With persistence the write is still in the
  local cache and is sent by the next instance; with a memory cache it is lost. Call
  `waitForPendingWrites()` before `terminate()` if the writes matter, and do not `await` a write
  after terminating the instance.
- A transaction, an aggregate query or a server read that is in flight fails with the error of the
  closed connection; a transaction is not retried once the instance is terminated.
- Calls made after `terminate()` fail (`terminate()` itself can be called again).
- A call that the client had finished with but the backend had not closed yet (a stopped
  listener, for example) is cancelled.

In tests, terminate every instance and `await` every operation before the test ends: an operation
that is still in flight when its instance is terminated fails afterwards, and an unhandled error
then fails whichever test is running.
