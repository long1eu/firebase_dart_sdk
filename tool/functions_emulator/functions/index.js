// Fixture functions of the Functions emulator (tool/start_functions_emulator.sh) and, deployed by the owner, of
// the production verification kit (tool/verify_production_functions). The tests of cloud_functions_dart call
// these by name; their behaviour is the one measured in the emulator probe, so change one only together with
// the tests that read it.
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const opts = { region: "us-central1", cors: true };

// Returns the request data unchanged.
exports.echo = onCall(opts, (req) => {
  logger.info("ECHO", {
    data: JSON.stringify(req.data),
    typeofData: typeof req.data,
    auth: req.auth ? JSON.stringify(req.auth) : null,
    app: req.app ? JSON.stringify(req.app) : null,
    instanceIdToken: req.instanceIdToken || null,
    accepts: req.acceptsStreaming,
  });
  return req.data;
});

// Returns what the server saw of the caller: the user, the App Check result and how the data arrived.
exports.context = onCall(opts, (req) => ({
  auth: req.auth ? { uid: req.auth.uid, token: req.auth.token } : null,
  app: req.app || null,
  instanceIdToken: req.instanceIdToken || null,
  acceptsStreaming: req.acceptsStreaming,
  dataType: typeof req.data,
  dataIsNull: req.data === null,
  dataUndefined: req.data === undefined,
}));

// Throws an HttpsError built from the request: {code, message?, details?}.
exports.fail = onCall(opts, (req) => {
  const d = req.data || {};
  throw new HttpsError(d.code, d.message ?? "msg for " + d.code, d.details);
});

// Answers after 5 seconds.
exports.slow = onCall(opts, async () => {
  await new Promise((r) => setTimeout(r, 5000));
  return "done";
});

// Three chunks, then {final: true, accepts}.
exports.stream = onCall(opts, async (req, res) => {
  logger.info("STREAM", { accepts: req.acceptsStreaming, canStream: !!res });
  if (req.acceptsStreaming) {
    await res.sendChunk({ n: 1 });
    await res.sendChunk("two");
    await res.sendChunk(3);
  }
  return { final: true, accepts: req.acceptsStreaming };
});

// A chunk, a 12 second silence, a chunk. The default heartbeat is 30 seconds, so no ping fills the gap.
exports.streamSlow = onCall(opts, async (req, res) => {
  if (req.acceptsStreaming) {
    await res.sendChunk("a");
    await new Promise((r) => setTimeout(r, 12000));
    await res.sendChunk("b");
  }
  return "end";
});

// Two chunks, then an error in the stream.
exports.streamFailMid = onCall(opts, async (req, res) => {
  if (req.acceptsStreaming) {
    await res.sendChunk("c1");
    await res.sendChunk("c2");
  }
  throw new HttpsError("failed-precondition", "mid fail", { at: 2 });
});

// A chunk, a 7 second gap filled by a ping every 2 seconds, a chunk.
exports.streamHb = onCall({ ...opts, heartbeatSeconds: 2 }, async (req, res) => {
  if (req.acceptsStreaming) {
    await res.sendChunk("first");
    await new Promise((r) => setTimeout(r, 7000));
    await res.sendChunk("late");
  }
  return "end";
});

// Chunks with a map, a null and undefined (which arrives as `data: {}`).
exports.streamTypes = onCall(opts, async (req, res) => {
  if (req.acceptsStreaming) {
    await res.sendChunk({ a: 1, n: null, s: "é\nline2", d: [1, 2] });
    await res.sendChunk(null);
    await res.sendChunk(undefined);
  }
  return { r: [1, 2] };
});

// No chunk at all.
exports.streamNoChunks = onCall(opts, async () => "just result");

// A server that sends 64-bit wrappers, which no measured server does by itself.
exports.wrappedInt64 = onCall(opts, () => ({
  v: { "@type": "type.googleapis.com/google.protobuf.Int64Value", value: "9223372036854775807" },
}));

exports.wrappedUInt64Max = onCall(opts, () => ({
  u: { "@type": "type.googleapis.com/google.protobuf.UInt64Value", value: "18446744073709551615" },
}));

// A map with another @type, which the client must return unchanged.
exports.wrappedUnknownType = onCall(opts, () => ({ other: { "@type": "x", value: "1" } }));

// Shows how the server decoded each value of the request: "<typeof>:<String(value)>" per key.
exports.echoTypes = onCall(opts, (req) => {
  const out = {};
  for (const key of Object.keys(req.data || {})) {
    const value = req.data[key];
    out[key] = typeof value + ":" + String(value);
  }
  return out;
});
