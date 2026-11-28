# firebase_transport_dart

Internal request helpers shared by the `firebase_*_dart` packages of this repository. This package is shared by those
packages, not for application code: it can change between versions, and the products that use it do not expose its types
or exceptions in their own API. It follows pub's version rules: a change that can break a dependent's compile or
behaviour bumps the second number (0.1.x to 0.2.0); an addition bumps the third.

The package works on every platform, in the browser too. It is not published on pub.dev yet.

## What it holds

- **Hosts.** The rules for loopback hosts, emulator hosts and the URLs that may carry tokens.
- **Tokens.** One source of Auth and App Check tokens per attempt, bound to the origin they were fetched for.
- **Headers.** The names of the Firebase request headers and checks of header values.
- **Status mapping.** The gRPC status codes, their Firebase exception codes and the mapping from HTTP statuses and
  error bodies.
- **Capped send and read.** Sending a request and reading a response with a limit on the bytes read.
- **Bounded numbers, a JSON depth guard and a one-time log.**
- **Server-sent events.** A decoder with limits on event and stream size.

## Rules

**Rule L (loopback).** After lowercasing and removing one pair of surrounding brackets, a host is loopback when it is
`localhost`; or four dot-separated parts, each 1 to 3 ASCII digits with value at most 255 and either `0` or starting with 1 to 9 (so `127.0.0.09` is not loopback), the first being `127`; or it
contains `:` and parses as the IPv6 address `::1`. Nothing else is loopback: not `*.localhost`, not `0.0.0.0`, not
`::ffff:127.0.0.1`, not a name that resolves to a loopback address, not a name with a trailing dot.

**Rule E (emulator host).** `EmulatorHost.parse` accepts `host:port` or `[ipv6]:port`. The port must be 1 to 65535. A
bracketed host must be an IPv6 address. A host equal to, or ending with a dot and one of, a list of production domains
(`googleapis.com`, `google.com`, `cloudfunctions.net`, `run.app`, `firebaseio.com`, `firebasedatabase.app`,
`firebaseapp.com`, `web.app`, `appspot.com`, `firebasestorage.app`) is refused. A text with a scheme, a path, user info,
`%` or whitespace is refused. A host that starts or ends with `.`, or has an empty label, is refused. The error message
names the rule that failed and never repeats any part of the input. The list of domains is a best effort: a production
service behind a custom domain passes it, and then only the application's explicit configuration protects.

**Rule T (tokens).** `mayCarryTokens` is true only when the URL has a non-empty host and empty user info, and: the
scheme is `https` or `wss`; or the scheme is `http` or `ws` and the host is loopback; or the scheme is `http` or `ws`,
an emulator is given and it owns the URL. Every other URL is false.

## Limits

- The package does not resolve names. `localhost` is trusted as loopback even if the machine's hosts file points it
  elsewhere.
- A provider that ignores the limited-use contract and returns its session token cannot be detected by a caller.
- Tokens sent to a configured emulator travel in clear text, also when the emulator is on another machine.
- Limited-use tokens cost one mint per attempt. Each attempt, each retry and each stream reconnect asks the provider
  for a new token, and the token is never kept. A mint is an attestation round trip and counts against the project's
  App Check quota. Concurrent requests are not coalesced: ten calls in flight are ten mints. When the caller's wait
  ends before the mint does, the minted token is discarded. A product's deadline for the whole call includes the mint.
  Applications should ask for limited-use tokens only on calls whose backend consumes them.
