## 0.1.0

First version. Internal request helpers shared by the `firebase_*_dart` packages of this repository. Not for
application code.

- Hosts: `isLoopbackHost` (rule L), `isHostLabel` and `EmulatorHost` (rule E). Rule L: a host is loopback only when it is
  `localhost`, a `127.x.x.x` address or the IPv6 `::1`; rule E: an emulator host is `host:port` and never a production
  domain.
- Tokens: `TokenSource`, `RequestTokens` and the token rules (rule T: tokens go only to `https` or `wss` hosts, which
  includes production, to the configured emulator, or to a loopback host); one failure rule for Auth and App Check tokens.
- Headers: `FirebaseHeaders`, `AuthHeaderStyle` and the header value checks.
- Status mapping: `RpcStatus` and `RpcErrorBody`.
- Capped send and read: `sendCapped`, `sendStreaming` and `readCapped` with `CappedResponse`, `TransportException` and
  `CapExceededException`.
- Bounded numbers, a JSON depth guard and a one-time log: `parseBoundedInt`, `decodeGuardedBytes`,
  `decodeGuardedText` and `LogOnce`.
- Server-sent events: `SseDecoder`.

Limits: the package does not resolve names, a provider that returns its session token as a limited-use token cannot be
detected, tokens sent to an emulator travel in clear text, and each limited-use token costs one mint per attempt (see the
README).
