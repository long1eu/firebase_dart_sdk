## 0.1.0

First version. Internal gRPC channel helpers shared by the `firebase_*_dart` packages of this repository. Not for
application code. VM only.

- `GrpcTarget`: host, port and TLS of a channel, and the origin its tokens are fetched for.
- `createGrpcChannel`: keepalive pings, a connect timeout, a 256 KiB flow-control window and a limit on the size of each
  response message, checked on the announced length before anything is allocated (`InboundLimitExceeded`).
- `GrpcCaller` and `RpcMethod`: calls with the tokens of one attempt as metadata, checked product headers and a required
  deadline.
- `rpcStatusOfGrpcError` and `grpcVersion`.
