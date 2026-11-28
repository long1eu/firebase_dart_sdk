# _firebase_transport_grpc_dart

Internal gRPC channel helpers shared by the `firebase_*_dart` packages of this repository. This package is internal to
this repository and not for application code: it can change between versions, and the products that use it do not
expose its types or exceptions in their own API. It follows pub's version rules: a change that can break a dependent's
compile or behaviour bumps the second number (0.1.x to 0.2.0); an addition bumps the third.

It runs on the Dart VM only (it imports `dart:io`); a product imports it only behind `if (dart.library.io)`. It is not
published on pub.dev yet.

## What it holds

- **`GrpcTarget`.** Host, port and TLS of a channel: the one source for both the channel and the token check, whose
  `origin` is what `TokenSource.tokensFor` of `_firebase_transport_dart` is called with.
- **`createGrpcChannel`.** A channel with keepalive pings while calls are active (30 s, 20 s ping timeout), a 15 s
  connect timeout, a 256 KiB HTTP/2 flow-control window for the connection and each call, and a limit on the size of
  each response message.
- **`GrpcCaller` and `RpcMethod`.** Starts a call with the tokens of one attempt as its metadata, plus the product's own
  headers, and a required deadline.
- **`InboundLimitExceeded`.** The error a call's response stream ends with when a response message announces more bytes
  than the limit.
- **`rpcStatusOfGrpcError`** and **`grpcVersion`**.

## Rules

**Inbound message limit.** `package:grpc` allocates a buffer of the length a message announces in its 5-byte prefix
before it checks anything, so a peer could make the client allocate up to 4 GiB. The channel's HTTP/2 connection
follows the gRPC framing of each call's incoming data and, when a prefix announces more than `maxInboundMessageBytes`,
terminates that call's HTTP/2 stream before the data reaches `package:grpc`; the call then fails with
`InboundLimitExceeded`, which holds the limit and the announced length and nothing of the message. No codec registry is
set on the channel, so a compressed message is refused by `package:grpc` and cannot be used to pass the limit.

**Metadata.** The metadata of a call is the token headers of its `RequestTokens`, for the target's origin, plus the
product's headers, all names in lowercase. Tokens fetched for another origin, or used before, are refused with a
`StateError` and nothing is sent. A header name must match `^[a-z0-9][a-z0-9_.-]*$` after lowercasing, must not start
with `grpc-` and must not be `authorization`, `x-firebase-auth-token` or `x-firebase-appcheck` (those come only from the
tokens); a value must be a header value (`isHeaderValue`). A refusal is an `ArgumentError` that names the header and
never the value.

**Fail-fast after a lost connection.** When a connection is lost before any call used it, the next connection attempt
within 10 s fails at once instead of connecting, so the waiting calls fail with `UNAVAILABLE` instead of `package:grpc`
reconnecting many times a second.

**Deadline.** Every call has one; there is no call without a deadline.

## Copied code

`lib/src/keep_alive_transport.dart`, `lib/src/flow_control_window.dart` and `lib/src/grpc_channel.dart` are derived from
the files of the same names in Firestore's `cloud_firestore/cloud_firestore_dart/lib/src/firebase/firestore/remote/datastore/`,
which keeps its own copies. Each file's header names its source file and commit: a fix to one copy must be made in the
other.

## Limits

- `package:grpc` and `package:http2` move together: the keepalive transport implements an `http2` interface, so this
  package and Firestore move to `http2` 3.x in the same release.
- Retry, streams with backoff and resume, and proto3 JSON helpers are not in this package.
