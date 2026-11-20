// Drives the interop check between the official JS SDK (interop.js) and the IndexedDB engine (interop_engine.dart):
// serves static/ on 127.0.0.1:8766, starts headless Chrome on a fresh profile, opens one page per step (several
// tabs at once for the lease steps), reads the result each page leaves in window.interopResult (JSON) through the
// DevTools protocol and prints PASS or FAIL per check (KNOWN for a failure of a check marked as a known difference,
// which does not fail the run). Run through interop_check.sh.
//
//   node interop_check.mjs [emulator port, default 8395] [only these parts, e.g. AB]
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, extname } from 'node:path';

const emulatorPort = Number(process.argv[2] ?? 8395);
const parts = process.argv[3] ?? 'ABCD';
const httpPort = 8766;
const debugPort = 9335;
const staticDir = join(import.meta.dirname, 'static');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm' };

const server = createServer((req, res) => {
  const path = join(staticDir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  try {
    const body = readFileSync(path);
    res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
}).listen(httpPort, '127.0.0.1');

const profile = mkdtempSync(join(tmpdir(), 'interop-profile-'));
// CHROME, else Chrome where macOS and the Linux runners have it.
const chromeBinary = process.env.CHROME ?? (process.platform === 'darwin'
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  : 'google-chrome');
const chrome = spawn(chromeBinary, [
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  // The Linux runners do not allow the sandbox's user namespaces to an unprivileged process.
  ...(process.platform === 'linux' ? ['--no-sandbox'] : []),
  `--remote-debugging-port=${debugPort}`, '--remote-allow-origins=*', `--user-data-dir=${profile}`, 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const devtools = (path, method = 'GET') => fetch(`http://127.0.0.1:${debugPort}${path}`, { method });

async function waitForChrome() {
  for (let i = 0; i < 60; i++) {
    try { if ((await devtools('/json/version')).ok) return; } catch {}
    await sleep(250);
  }
  throw new Error('Chrome did not start');
}

const run = Date.now().toString(36);
const project = (name) => `demo-interop-${run}-${name}`;
let failures = 0;

/** Opens [page] with [params] in a new tab; returns its id. */
async function open(page, params) {
  const url = `http://127.0.0.1:${httpPort}/${page}#${encodeURIComponent(JSON.stringify({ port: emulatorPort, user: 'alice', ...params }))}`;
  return (await (await devtools(`/json/new?${encodeURIComponent(url)}`, 'PUT')).json()).id;
}

/** Evaluates [expression] in the tab [id] through the DevTools protocol, returns its JSON value. */
async function evaluate(id, expression) {
  const tab = (await (await devtools('/json/list')).json()).find((t) => t.id === id);
  if (!tab?.webSocketDebuggerUrl) return null;
  const socket = new WebSocket(tab.webSocketDebuggerUrl);
  try {
    await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
    const reply = new Promise((resolve) => { socket.onmessage = (m) => resolve(JSON.parse(m.data)); });
    socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
    return (await reply).result?.result?.value ?? null;
  } finally {
    socket.close();
  }
}

/** Waits until the tab [id] reports (`window.interopResult`), prints its checks and returns whether it holds its
 * client. */
async function result(id, label, timeoutMs = 240000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const text = await evaluate(id, 'window.interopResult ?? null').catch(() => null);
    if (text) {
      const { state, checks } = JSON.parse(text);
      if (checks.length === 0) { console.log(`FAIL ${label}: no checks reported`); failures++; }
      for (const c of checks) {
        if (!c.pass && !c.known) failures++;
        console.log(`${c.pass ? 'PASS' : c.known ? 'KNOWN' : 'FAIL'} ${c.name}${c.detail ? `  (${c.detail.replace(/\s+/g, ' ').slice(0, 600)})` : ''}`);
      }
      return state === 'holding';
    }
    await sleep(500);
  }
  const tab = (await (await devtools('/json/list')).json()).find((t) => t.id === id);
  console.log(`FAIL ${label}: timed out at "${tab?.title}"`);
  failures++;
  return false;
}

const close = async (id) => { await devtools(`/json/close/${id}`); await sleep(1500); };

/** One step: a page that reports and is closed. */
async function step(page, params, label) {
  const id = await open(page, params);
  await result(id, label);
  await close(id);
}

const JS = 'interop.html';
const ENGINE = 'interop_engine.html';

try {
  await waitForChrome();
  console.log(`emulator 127.0.0.1:${emulatorPort}, run ${run}`);

  if (parts.includes('A')) {
    console.log('-- A: the JS SDK writes, the engine reads');
    const p = project('a');
    await step(JS, { step: 'a-write', project: p }, 'A1');
    await step(JS, { step: 'a-write-bob', project: p, user: 'bob' }, 'A2');
    await step(ENGINE, { step: 'a-read', project: p }, 'A3');
    await step(ENGINE, { step: 'a-read-bob', project: p, user: 'bob' }, 'A4');
  }

  if (parts.includes('B')) {
    console.log('-- B: the engine writes, the JS SDK reads (and collects garbage, about 1 min)');
    const p = project('b');
    await step(ENGINE, { step: 'b-write', project: p }, 'B1');
    await step(ENGINE, { step: 'b-write-bob', project: p, user: 'bob' }, 'B2');
    await step(JS, { step: 'b-read', project: p }, 'B3');
    await step(JS, { step: 'b-read-bob', project: p, user: 'bob' }, 'B4');
  }

  if (parts.includes('C')) {
    console.log('-- C: the lease, one SDK at a time');
    const p = project('c');
    const js = await open(JS, { step: 'c-hold', project: p });
    await result(js, 'C js holds');
    await step(ENGINE, { step: 'c-refused', project: p }, 'C engine refused');
    await close(js);
    const engine = await open(ENGINE, { step: 'c-open', project: p });
    await result(engine, 'C engine opens');
    await step(JS, { step: 'c-refused', project: p }, 'C js refused');
    await close(engine);
    await step(JS, { step: 'c-open', project: p }, 'C js opens');
  }

  if (parts.includes('D')) {
    console.log('-- D: index entries of each value kind, both ways');
    const p1 = project('d1');
    await step(JS, { step: 'd-write', project: p1 }, 'D1');
    await step(ENGINE, { step: 'd-read', project: p1 }, 'D2');
    const p2 = project('d2');
    await step(ENGINE, { step: 'd-write', project: p2 }, 'D3');
    await step(JS, { step: 'd-read', project: p2 }, 'D4');
  }
} catch (e) {
  console.log(`FAIL the driver: ${e.stack ?? e}`);
  failures++;
} finally {
  chrome.kill();
  server.close();
  await sleep(500);
  rmSync(profile, { recursive: true, force: true });
}
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
