## 0.1.0

First version. Internal request helpers shared by the `firebase_*_dart` packages of this repository. Not for
application code.

- Hosts: `isLoopbackHost` (rule L), `isHostLabel` and `EmulatorHost` (rule E).
- Tokens: `TokenSource`, `RequestTokens` and the token rules (rule T); one failure rule for Auth and App Check tokens.
- Headers: `FirebaseHeaders`, `AuthHeaderStyle` and the header value checks.
- Status mapping: `RpcStatus` and `RpcErrorBody`.
- Capped send and read: `sendCapped`, `sendStreaming` and `readCapped` with `CappedResponse`, `TransportException` and
  `CapExceededException`.
- Bounded numbers, a JSON depth guard and a one-time log: `parseBoundedInt`, `decodeGuardedBytes`,
  `decodeGuardedText` and `LogOnce`.
- Server-sent events: `SseDecoder`.
