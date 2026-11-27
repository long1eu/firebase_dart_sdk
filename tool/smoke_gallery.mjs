#!/usr/bin/env node
// Clicks through the two Realtime Database web examples of the gallery (rtdb_web_app and
// rtdb_playground) in headless Google Chrome, for the dart2js and the dart2wasm build, and prints
// one PASS or FAIL line per step. Drives Chrome over the DevTools protocol; no npm package.
//
// Needs: the built gallery served over HTTP (tool/build_gallery.sh, then for example
// `python3 -m http.server 8080 --bind 127.0.0.1 --directory build/gallery`) and a Realtime
// Database emulator (tool/start_database_emulator.sh 9100). The script starts neither.
//
// Usage: node tool/smoke_gallery.mjs [--base http://127.0.0.1:8080] [--emulator 127.0.0.1:9100]
//          [--only web_app|playground] [--compiler js|wasm] [--hidden-tab-measure]
//
// Every run uses its own projects (demo-smoke-<random>-<compiler>), so runs do not share data.
// --hidden-tab-measure skips the click-through and instead times how long rtdb_web_app takes to
// show 20 000 items, with the tab visible and with the window minimised (hidden).
//
// Environment: CHROME, the Chrome binary (default: the macOS Google Chrome app).
// Exit code: 0 when every step passed, 1 otherwise, 2 on a usage error.

import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME =
  process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function parseArgs(argv) {
  const opts = { base: 'http://127.0.0.1:8080', emulator: '127.0.0.1:9100', only: null,
    compiler: null, hidden: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => {
      if (i + 1 >= argv.length) usage(`${a} needs a value`);
      return argv[++i];
    };
    if (a === '--base') opts.base = next().replace(/\/$/, '');
    else if (a === '--emulator') opts.emulator = next();
    else if (a === '--only') opts.only = next();
    else if (a === '--compiler') opts.compiler = next();
    else if (a === '--hidden-tab-measure') opts.hidden = true;
    else usage(`unknown argument ${a}`);
  }
  if (opts.only && !['web_app', 'playground'].includes(opts.only)) {
    usage('--only takes web_app or playground');
  }
  if (opts.compiler && !['js', 'wasm'].includes(opts.compiler)) {
    usage('--compiler takes js or wasm');
  }
  return opts;
}

function usage(message) {
  console.error(`smoke_gallery: ${message}`);
  console.error('usage: node tool/smoke_gallery.mjs [--base URL] [--emulator HOST:PORT] ' +
    '[--only web_app|playground] [--compiler js|wasm] [--hidden-tab-measure]');
  process.exit(2);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------------------------
// Chrome and the DevTools protocol.

async function launchChrome() {
  const profile = await mkdtemp(join(tmpdir(), 'smoke-gallery-'));
  const proc = spawn(CHROME, [
    '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--window-size=1200,900', 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  const wsUrl = await new Promise((resolve, reject) => {
    let err = '';
    const timer = setTimeout(() => reject(new Error(`Chrome did not start: ${err}`)), 20000);
    proc.on('error', (e) => {
      clearTimeout(timer);
      reject(new Error(`cannot run ${CHROME}: ${e.message}`));
    });
    proc.stderr.on('data', (d) => {
      err += d;
      const m = /DevTools listening on (ws:\/\/\S+)/.exec(err);
      if (m) { clearTimeout(timer); resolve(m[1]); }
    });
  });
  const cdp = await Cdp.open(wsUrl);
  return {
    cdp, proc, profile,
    async close() {
      try { await cdp.send('Browser.close', {}, undefined, 5000); } catch (_) {}
      cdp.ws.close();
      if (proc.exitCode === null) {
        await Promise.race([new Promise((r) => proc.once('exit', r)), sleep(5000)]);
        if (proc.exitCode === null) proc.kill('SIGKILL');
      }
      await rm(profile, { recursive: true, force: true, maxRetries: 3 });
    },
  };
}

class Cdp {
  static open(url) {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url);
      ws.onopen = () => resolve(new Cdp(ws));
      ws.onerror = () => reject(new Error(`cannot open ${url}`));
    });
  }

  constructor(ws) {
    this.ws = ws;
    this.nextId = 0;
    this.calls = new Map();
    this.listeners = new Set();
    ws.onmessage = (m) => {
      const msg = JSON.parse(m.data);
      if (msg.id !== undefined) {
        const call = this.calls.get(msg.id);
        if (!call) return;
        this.calls.delete(msg.id);
        if (msg.error) call.reject(new Error(`${call.method}: ${msg.error.message}`));
        else call.resolve(msg.result);
      } else {
        for (const l of this.listeners) l(msg);
      }
    };
  }

  send(method, params = {}, sessionId, timeout = 60000) {
    const id = ++this.nextId;
    this.ws.send(JSON.stringify({ id, method, params, sessionId }));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.calls.delete(id);
        reject(new Error(`${method} timed out`));
      }, timeout);
      this.calls.set(id, {
        method,
        resolve: (v) => { clearTimeout(timer); resolve(v); },
        reject: (e) => { clearTimeout(timer); reject(e); },
      });
    });
  }
}

// In-page helpers, put in front of every evaluated body.
const HELPERS = `
const $ = (id) => document.getElementById(id);
const txt = (id) => { const e = $(id); return e ? e.textContent : null; };
const lis = (id) => $(id) ? Array.from($(id).children).map((li) => li.textContent) : null;
const setVal = (id, v) => {
  const e = $(id); e.value = v;
  e.dispatchEvent(new Event('input', { bubbles: true }));
  e.dispatchEvent(new Event('change', { bubbles: true }));
};
const submitForm = (id) => $(id).querySelector('button[type=submit]').click();
const wa = () => !$('items') ? null : ({
  compiler: txt('compiler'), backend: txt('backend'), noticeHidden: $('notice').hidden,
  connected: txt('connected'), connClass: $('connected').className, toggle: txt('toggle'),
  toggleDisabled: $('toggle').disabled, addDisabled: document.querySelector('#add button').disabled,
  pending: txt('pending'), error: txt('error'), items: lis('items'),
  classes: Array.from($('items').children).map((l) => l.className), text: $('text').value,
});
const tree = (id) => {
  const ul = $(id).querySelector(':scope > ul');
  if (!ul) return null;
  const parse = (ul) => {
    const o = {};
    for (const li of ul.children) {
      const k = li.querySelector(':scope > span.k').textContent.replace(/: $/, '');
      const sub = li.querySelector(':scope > ul');
      o[k] = sub ? parse(sub) : JSON.parse(li.querySelector(':scope > span:not(.k)').textContent);
    }
    return o;
  };
  return parse(ul);
};
const pg = () => !$('client-tree') ? null : ({
  compiler: txt('compiler'), conn: txt('conn'), connClass: $('conn').className,
  client: tree('client-tree'), server: tree('server-tree'), serverLog: lis('server-log'),
  events: lis('events'), pendingCount: txt('pending-count'), pending: lis('pending'),
  error: txt('error'), listeners: lis('listeners'), reject: txt('reject'),
  rejectPressed: $('reject').getAttribute('aria-pressed'),
});
`;

class Page {
  static async open(browser, label, { newWindow = false } = {}) {
    const { targetId } = await browser.cdp.send('Target.createTarget',
      { url: 'about:blank', newWindow });
    const { sessionId } = await browser.cdp.send('Target.attachToTarget',
      { targetId, flatten: true });
    const page = new Page(browser.cdp, targetId, sessionId, label);
    await page.send('Runtime.enable');
    await page.send('Log.enable');
    await page.send('Page.enable');
    return page;
  }

  constructor(cdp, targetId, sessionId, label) {
    Object.assign(this, { cdp, targetId, sessionId, label });
    this.consoleErrors = [];
    this.csp = [];
    this.exceptions = [];
    this.listener = (msg) => {
      if (msg.sessionId !== sessionId) return;
      const p = msg.params;
      if (msg.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(p.type)) {
        const text = p.args.map((a) => a.value ?? a.description ?? '').join(' ');
        this.note(`console.${p.type}: ${text}`);
      } else if (msg.method === 'Log.entryAdded' && ['error', 'warning'].includes(p.entry.level)) {
        this.note(`log ${p.entry.source} ${p.entry.level}: ${p.entry.text}` +
          (p.entry.url ? ` (${p.entry.url})` : ''));
      } else if (msg.method === 'Runtime.exceptionThrown') {
        const d = p.exceptionDetails;
        this.exceptions.push(`${d.exception?.description ?? d.text}`.split('\n')[0]);
      }
    };
    cdp.listeners.add(this.listener);
  }

  note(line) {
    if (/Content.Security.Policy/i.test(line)) this.csp.push(line);
    else this.consoleErrors.push(line);
  }

  send(method, params = {}, timeout) {
    return this.cdp.send(method, params, this.sessionId, timeout);
  }

  // Runs [body] (statements ending in `return ...`) in the page, awaiting a returned promise.
  async eval(body) {
    const r = await this.send('Runtime.evaluate', {
      expression: `(async () => { ${HELPERS}\n${body}\n})()`,
      awaitPromise: true, returnByValue: true,
    });
    if (r.exceptionDetails) {
      throw new Error(r.exceptionDetails.exception?.description?.split('\n')[0] ??
        r.exceptionDetails.text);
    }
    return r.result.value;
  }

  async goto(url) {
    await this.send('Page.navigate', { url });
    await this.waitUntil(`return location.href === ${JSON.stringify(url)} &&
      document.readyState !== 'loading' ? true : null`, (v) => v === true, 15000);
  }

  // Polls `return <snapshot>` until [ok] accepts it; returns the snapshot or throws with the
  // last one.
  async waitUntil(body, ok, timeout = 10000, show = (v) => v) {
    const end = Date.now() + timeout;
    let last;
    let lastError = null;
    for (;;) {
      try {
        last = await this.eval(body);
        lastError = null;
        if (ok(last)) return last;
      } catch (e) {
        lastError = e.message;
      }
      if (Date.now() > end) {
        throw new Error(`timed out after ${timeout} ms; actual: ` +
          (lastError ?? JSON.stringify(show(last))));
      }
      await sleep(100);
    }
  }

  async close() {
    this.cdp.listeners.delete(this.listener);
    try { await this.cdp.send('Target.closeTarget', { targetId: this.targetId }); } catch (_) {}
  }
}

// ---------------------------------------------------------------------------------------------
// Results.

const results = [];

async function step(group, name, expected, body) {
  try {
    const actual = await body();
    results.push({ group, name, ok: true });
    console.log(`PASS ${group} ${name} | expected: ${expected} | ` +
      `actual: ${actual ?? 'as expected'}`);
  } catch (e) {
    results.push({ group, name, ok: false });
    console.log(`FAIL ${group} ${name} | expected: ${expected} | actual: ${e.message}`);
  }
}

function check(cond, actual) {
  if (!cond) throw new Error(typeof actual === 'string' ? actual : JSON.stringify(actual));
}

async function reportPage(group, pages) {
  for (const p of pages) {
    for (const line of p.consoleErrors) console.log(`  console ${group} [${p.label}] ${line}`);
    for (const line of p.csp) console.log(`  csp ${group} [${p.label}] ${line}`);
    for (const line of p.exceptions) console.log(`  exception ${group} [${p.label}] ${line}`);
  }
  const csp = pages.flatMap((p) => p.csp);
  const exc = pages.flatMap((p) => p.exceptions);
  await step(group, 'csp', 'no Content-Security-Policy violation', async () => {
    check(csp.length === 0, `${csp.length} violation(s): ${csp.join(' / ')}`);
  });
  await step(group, 'exceptions', 'no uncaught exception', async () => {
    check(exc.length === 0, `${exc.length}: ${exc.join(' / ')}`);
  });
}

// ---------------------------------------------------------------------------------------------
// The emulator REST API.

function rest(opts, ns) {
  const url = (path) => `http://${opts.emulator}/${path}.json?ns=${encodeURIComponent(ns)}`;
  const call = async (method, path, body) => {
    const res = await fetch(url(path), {
      method, headers: { Authorization: 'Bearer owner' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${url(path)}: ${res.status} ${text}`);
    return text ? JSON.parse(text) : null;
  };
  return {
    get: (path) => call('GET', path),
    put: (path, body) => call('PUT', path, body),
    del: (path) => call('DELETE', path),
    rules: (read, write) =>
      call('PUT', '.settings/rules', { rules: { '.read': read, '.write': write } }),
  };
}

// ---------------------------------------------------------------------------------------------
// rtdb_web_app.

const WA = 'return wa();';
const showWa = (s) => s;

async function webApp(browser, opts, rid, compiler) {
  const c = await webAppContext(browser, opts, rid, compiler);
  try {
    await webAppLive(c);
    await webAppOffline(c);
    await webAppPanel(c);
    await webAppSkew(c);
    await webAppRules(c);
    await webAppHiddenBurst(c);
  } finally {
    try {
      await c.db.rules(true, true);
    } catch (e) {
      console.log(`  could not restore rules: ${e.message}`);
    }
    await reportPage(c.group, c.pages);
    for (const page of c.pages) await page.close();
  }
}

// The names and helpers the web_app steps share.
async function webAppContext(browser, opts, rid, compiler) {
  const group = `web_app/${compiler}`;
  const project = `demo-smoke-${rid}-${compiler}`;
  const other = `demo-smoke-${rid}-${compiler}-other`;
  const ns = `${project}-default-rtdb`;
  const db = rest(opts, ns);
  const url = `${opts.base}/rtdb_web_app/?emulator=${opts.emulator}&project=${project}` +
    `&compiler=${compiler}`;
  const compilerName = compiler === 'js' ? 'dart2js' : 'dart2wasm';
  const backend = `emulator ${opts.emulator}`;
  const tab1 = await Page.open(browser, 'tab 1');
  const pages = [tab1];
  const add = async (page, text) => {
    await page.eval(`setVal('text', ${JSON.stringify(text)}); submitForm('add'); return true;`);
  };
  const items = (page, want, timeout = 10000) => page.waitUntil(WA,
    (s) => s && JSON.stringify(s.items) === JSON.stringify(want), timeout, (s) => s?.items);
  const idle = (s) => s.pending === 'No writes waiting';
  const ready = (page, extra = () => true) => page.waitUntil(WA, (s) => s &&
    s.compiler === compilerName && s.backend === backend && s.noticeHidden === true &&
    s.toggle === 'Go offline' && !s.toggleDisabled && !s.addDisabled &&
    s.connected === 'Connected' && s.connClass === 'online' && idle(s) && s.error === '' &&
    extra(s), 15000, showWa);
  const keyOf = async (text) => {
    const all = (await db.get('rtdb_web_app/items')) ?? {};
    const key = Object.keys(all).find((k) => all[k].text === text);
    if (!key) throw new Error(`no item "${text}" in the emulator: ${JSON.stringify(all)}`);
    return key;
  };
  const four = ['second', 'third', 'from tab 2', 'offline item'];
  return { browser, opts, compiler, rid, group, other, db, url, backend, tab1, tab2: null, pages, add,
    items, idle, ready, keyOf, four };
}

// Steps 1 to 4: open, add, order, a second tab.
async function webAppLive(c) {
  const { browser, group, db, url, compiler, tab1, pages, add, items, idle, ready } = c;
  const compilerName = compiler === 'js' ? 'dart2js' : 'dart2wasm';
  const backend = c.backend;
  await step(group, '1 open', `#compiler ${compilerName}, #backend "${backend}", notice ` +
    'hidden, "Go offline" and Add enabled, Connected, "No writes waiting", empty list, no error',
  async () => {
    await tab1.goto(url);
    await ready(tab1, (s) => s.items.length === 0);
  });

  await step(group, '2 add first',
    '#text empties; one li "first" without class; "No writes waiting"', async () => {
      await add(tab1, 'first');
      await tab1.waitUntil(WA, (s) => s.text === '' && JSON.stringify(s.items) === '["first"]' &&
        s.classes[0] === '' && idle(s), 10000, showWa);
    });

  await step(group, '3 add second, third', 'li order first, second, third', async () => {
    // Records each li insertion with the li before it, for the failure message.
    await tab1.eval(`window.__ins = [];
      new MutationObserver((ms) => { for (const m of ms) for (const n of m.addedNodes)
        window.__ins.push([n.textContent, n.previousSibling?.textContent ?? null,
          Math.round(performance.now())]); }).observe($('items'), { childList: true });
      return true;`);
    try {
      await add(tab1, 'second');
      await items(tab1, ['first', 'second']);
      await add(tab1, 'third');
      await tab1.waitUntil(WA, (s) => s.items.join() === 'first,second,third' && idle(s), 10000,
        showWa);
    } catch (e) {
      const ins = await tab1.eval('return window.__ins;');
      const all = await db.get('rtdb_web_app/items');
      throw new Error(`${e.message}; insertions [text, li before, ms]: ${JSON.stringify(ins)}; ` +
        `emulator: ${JSON.stringify(all)}`);
    }
  });

  await step(group, '4 second tab', 'tab 2 shows first, second, third and Connected; ' +
    '"from tab 2" added there appears last in tab 1', async () => {
    const tab2 = await Page.open(browser, 'tab 2');
    c.tab2 = tab2;
    pages.push(tab2);
    await tab2.goto(url);
    await ready(tab2, (s) => s.items.join() === 'first,second,third');
    await add(tab2, 'from tab 2');
    await items(tab1, ['first', 'second', 'third', 'from tab 2']);
  });
}

// Steps 5 to 9: child changed and removed from the REST API, offline and back online.
async function webAppOffline(c) {
  const { group, db, tab1, tab2, add, items, idle, keyOf } = c;
  await step(group, '5 onChildChanged (REST PUT)', 'li "first" becomes "first edited" at index 0',
    async () => {
      const key = await keyOf('first');
      await db.put(`rtdb_web_app/items/${key}`, { text: 'first edited', at: 1 });
      await items(tab1, ['first edited', 'second', 'third', 'from tab 2']);
    });

  await step(group, '6 onChildRemoved (REST DELETE)', 'li "first edited" disappears',
  async () => {
    const key = await keyOf('first edited');
    await db.del(`rtdb_web_app/items/${key}`);
    await items(tab1, ['second', 'third', 'from tab 2']);
  });

  await step(group, '7 go offline', '#toggle "Go online"; "Not connected" (class offline); ' +
    '"No writes waiting"', async () => {
    await tab1.eval(`$('toggle').click(); return true;`);
    await tab1.waitUntil(WA, (s) => s.toggle === 'Go online' && s.connected === 'Not connected' &&
      s.connClass === 'offline' && idle(s), 10000, showWa);
  });

  const offlinePending = '1 write(s) waiting for the server (offline: they appear in the ' +
    'list at once and are sent when you go online)';
  await step(group, '8 add while offline', 'li "offline item" last with class local; #pending ' +
    `"${offlinePending}"; not in the emulator nor in tab 2`, async () => {
    await add(tab1, 'offline item');
    await tab1.waitUntil(WA, (s) => s.items.at(-1) === 'offline item' &&
      s.classes.at(-1) === 'local' && s.pending === offlinePending, 5000, showWa);
    await sleep(1000);
    const all = (await db.get('rtdb_web_app/items')) ?? {};
    const inEmu = Object.values(all).some((v) => v.text === 'offline item');
    check(!inEmu, 'emulator already has "offline item"');
    const s2 = await tab2.eval(WA);
    check(!s2.items.includes('offline item'), `tab 2 shows it: ${JSON.stringify(s2.items)}`);
  });

  await step(group, '9 go online', '#toggle "Go offline"; Connected; "No writes waiting"; ' +
    'li loses class local; tab 2 shows "offline item" last', async () => {
    await tab1.eval(`$('toggle').click(); return true;`);
    await tab1.waitUntil(WA, (s) => s.toggle === 'Go offline' && s.connected === 'Connected' &&
      idle(s) && s.items.at(-1) === 'offline item' && s.classes.at(-1) === '', 10000, showWa);
    await items(tab2, ['second', 'third', 'from tab 2', 'offline item']);
  });
}

// Step 10: the connect panel and the stored settings.
async function webAppPanel(c) {
  const { group, opts, compiler, other, backend, tab1, ready, four } = c;
  if (c.tab2) await c.tab2.close();
  const hostError = 'The emulator host must be 127.0.0.1:<port> or localhost:<port> ' +
    '(the page may only connect to this machine).';
  await step(group, '10a connect panel: bad host', `#error "${hostError}", #backend none, ` +
    'notice visible, empty list, toggle and Add disabled', async () => {
    await tab1.eval(`$('connect-panel').querySelector('summary').click();
      setVal('f-emulator', 'example.com:9100'); submitForm('connect'); return true;`);
    await tab1.waitUntil(WA, (s) => s.error === hostError && s.backend === 'none' &&
      s.noticeHidden === false && s.items.length === 0 && s.toggleDisabled && s.addDisabled,
    10000, showWa);
  });
  await step(group, '10b connect panel: back to 127.0.0.1', 'no error, connected, the four items',
    async () => {
      await tab1.eval(`setVal('f-emulator', ${JSON.stringify(opts.emulator)});
        submitForm('connect'); return true;`);
      await ready(tab1, (s) => s.items.join() === four.join());
    });
  await step(group, '10c connect panel: other project', 'empty list (other namespace), Connected',
    async () => {
      await tab1.eval(`setVal('f-project', ${JSON.stringify(other)}); submitForm('connect');
        return true;`);
      await sleep(500);
      await ready(tab1, (s) => s.items.length === 0);
    });
  await step(group, '10d remember and reload without query', 'reconnects from localStorage: ' +
    `#backend "${backend}", project ${other}, box ticked`, async () => {
    await tab1.eval(`$('f-remember').checked = true; submitForm('connect'); return true;`);
    await ready(tab1);
    await tab1.goto(`${opts.base}/rtdb_web_app/?compiler=${compiler}`);
    await ready(tab1);
    const f = await tab1.eval(`return { project: $('f-project').value,
      remember: $('f-remember').checked };`);
    check(f.project === other && f.remember === true, f);
  });
  await step(group, '10e forget', '#error "Stored settings removed."', async () => {
    await tab1.eval(`$('forget').click(); return true;`);
    await tab1.waitUntil(WA, (s) => s.error === 'Stored settings removed.', 5000, showWa);
    const stored = await tab1.eval(`return localStorage.getItem('rtdb_web_app.settings');`);
    check(stored === null, `localStorage still has ${stored}`);
  });
}

// Step 13: a late handshake makes the server time offset too small, so a local
// ServerValue.timestamp estimate sorts before an item the server already stamped, and the real value moves it later
// (onChildMoved). The page is not changed: a script added before the page loads wraps the
// WebSocket `onmessage` setter (the client sets that property, `ws_channel_web.dart`) so the first
// message of each socket, the handshake, waits SKEW_STALL_MS first. The stall is far longer than
// the time between the two adds, so the estimate of "two" always sorts first until the server
// value arrives.
const SKEW_STALL_MS = 3000;

async function webAppSkew(c) {
  const { browser, opts, compiler, group, pages, rid } = c;
  const project = `demo-smoke-${rid}-${compiler}-skew`;
  const compilerName = compiler === 'js' ? 'dart2js' : 'dart2wasm';
  await step(group, '13 server time offset skew', `with a ${SKEW_STALL_MS} ms stall on the ` +
    'handshake, "two" added right after "one" is first shown before "one", then moved: the list ' +
    'ends one, two', async () => {
    const page = await Page.open(browser, 'skew');
    pages.push(page);
    await page.send('Page.addScriptToEvaluateOnNewDocument', { source: `(() => {
      window.__stalls = 0;
      const d = Object.getOwnPropertyDescriptor(WebSocket.prototype, 'onmessage');
      Object.defineProperty(WebSocket.prototype, 'onmessage', {
        configurable: true, enumerable: d.enumerable, get() { return d.get.call(this); },
        set(fn) {
          if (typeof fn !== 'function') return d.set.call(this, fn);
          let first = true;
          d.set.call(this, function (...args) {
            if (first) {
              first = false;
              window.__stalls++;
              const end = performance.now() + ${SKEW_STALL_MS};
              while (performance.now() < end);
            }
            return fn.apply(this, args);
          });
        },
      });
    })();` });
    await page.goto(`${opts.base}/rtdb_web_app/?emulator=${opts.emulator}&project=${project}` +
      `&compiler=${compiler}`);
    await page.waitUntil(WA, (s) => s && s.compiler === compilerName &&
      s.connected === 'Connected' && s.pending === 'No writes waiting', 20000, showWa);
    const stalls = await page.eval('return window.__stalls;');
    check(stalls >= 1, `the handshake was not stalled (${stalls} stalls)`);
    await page.eval(`window.__orders = [];
      new MutationObserver(() => window.__orders.push(lis('items').join())).observe($('items'),
        { childList: true });
      setVal('text', 'one'); submitForm('add'); return true;`);
    await page.waitUntil(WA, (s) => s.items.join() === 'one' && s.classes[0] === '', 10000, showWa);
    await page.eval(`setVal('text', 'two'); submitForm('add'); return true;`);
    await page.waitUntil(WA, (s) => s.items.join() === 'one,two' &&
      s.pending === 'No writes waiting', 10000, showWa);
    await page.waitUntil(WA, (s) => s.items.join() === 'one,two', 1000, showWa);
    const orders = await page.eval('return window.__orders;');
    check(orders.includes('two,one'), `"two" was never shown first: ${JSON.stringify(orders)}`);
    return `orders seen: ${orders.join(' | ')}`;
  });
}

// Steps 11 and 12: closed rules on the emulator.
async function webAppRules(c) {
  const { group, db, url, tab1, idle, ready, four } = c;
  await step(group, '11 write denied', 'li "denied" shows, then is removed; #error starts ' +
    '"The write failed: " and names permission denied; "No writes waiting"', async () => {
    await db.rules(true, false);
    await tab1.goto(url);
    await ready(tab1, (s) => s.items.join() === four.join());
    await tab1.eval(`window.__seen = [];
      new MutationObserver((ms) => { for (const m of ms) for (const n of m.addedNodes)
        window.__seen.push(n.textContent); }).observe($('items'), { childList: true });
      setVal('text', 'denied'); submitForm('add'); return true;`);
    const s = await tab1.waitUntil(WA, (s) => s.error !== '' && idle(s) &&
      !s.items.includes('denied'), 10000, showWa);
    const seen = await tab1.eval('return window.__seen;');
    check(seen.includes('denied'), `li "denied" never shown; error ${JSON.stringify(s.error)}`);
    check(s.error.startsWith('The write failed: ') && /permission.denied/i.test(s.error),
      `#error ${JSON.stringify(s.error)}`);
    return `#error ${JSON.stringify(s.error)}`;
  });

  await step(group, '12 read denied', '#error holds the listener error, empty list', async () => {
    await db.rules(false, true);
    await tab1.goto(url);
    const s = await tab1.waitUntil(WA, (s) => s && s.error !== '' && s.items.length === 0,
      10000, showWa);
    check(/permission.denied/i.test(s.error), `#error ${JSON.stringify(s.error)}`);
    return `#error ${JSON.stringify(s.error)}`;
  });
}

// Step 14: more separate changes than one drain slice, queued in one task, in a hidden tab. The
// event dispatcher yields to the event loop every 1000 events; a hidden tab delays chained timers
// to about one a second, so the yield must not be a timer. Server pushes do not reach this path
// (each WebSocket message is its own task, and the drain runs after it), so the page goes offline
// and its own form is submitted BURST times in one evaluation: one local write, one change, per
// submit. The time counted is from the end of that loop to the last li.
const BURST = 20000;
const BURST_BOUND_MS = 1500;

async function webAppHiddenBurst(c) {
  const { browser, opts, compiler, group, pages, rid } = c;
  const project = `demo-smoke-${rid}-${compiler}-burst`;
  const compilerName = compiler === 'js' ? 'dart2js' : 'dart2wasm';
  await step(group, '14 hidden tab burst', `offline, ${BURST} adds in one task in a minimised ` +
    `window (visibilityState hidden); the ${BURST} li show within ${BURST_BOUND_MS} ms of the ` +
    'end of that task', async () => {
    const page = await Page.open(browser, 'burst', { newWindow: true });
    pages.push(page);
    await page.send('Emulation.setFocusEmulationEnabled', { enabled: false });
    const { windowId } = await browser.cdp.send('Browser.getWindowForTarget',
      { targetId: page.targetId });
    await browser.cdp.send('Browser.setWindowBounds',
      { windowId, bounds: { windowState: 'minimized' } });
    await page.goto(`${opts.base}/rtdb_web_app/?emulator=${opts.emulator}&project=${project}` +
      `&compiler=${compiler}`);
    await page.waitUntil(WA, (s) => s && s.compiler === compilerName &&
      s.connected === 'Connected' && !s.addDisabled && s.items.length === 0, 15000, showWa);
    await page.eval(`$('toggle').click(); return true;`);
    await page.waitUntil(WA, (s) => s.toggle === 'Go online' && s.connected === 'Not connected',
      10000, showWa);
    const vis = await page.eval('return document.visibilityState;');
    check(vis === 'hidden', `visibilityState ${vis}`);
    // A MutationObserver callback is a microtask, so the time it records is not delayed by the
    // hidden tab's timer throttling.
    await page.eval(`window.__burst = null;
      const list = $('items');
      new MutationObserver((_, o) => {
        if (list.children.length >= ${BURST}) {
          window.__burst = performance.now(); o.disconnect();
        }
      }).observe(list, { childList: true });
      const t0 = performance.now();
      for (let i = 0; i < ${BURST}; i++) { setVal('text', 'b' + i); submitForm('add'); }
      window.__loop = [t0, performance.now()];
      return true;`);
    const r = await page.waitUntil(`return { done: window.__burst, loop: window.__loop,
      n: $('items').children.length, vis: document.visibilityState };`,
    (v) => v.done !== null, 120000, (v) => v);
    const ms = Math.round(r.done - r.loop[1]);
    const actual = `${r.n} li ${ms} ms after the loop (the loop took ` +
      `${Math.round(r.loop[1] - r.loop[0])} ms; visibilityState ${r.vis})`;
    check(r.vis === 'hidden' && ms < BURST_BOUND_MS, actual);
    return actual;
  });
}

// ---------------------------------------------------------------------------------------------
// rtdb_playground.

const PG = 'return pg();';

async function playground(browser, opts, compiler) {
  const c = await playgroundContext(browser, opts, compiler);
  try {
    await playgroundWrites(c);
    await playgroundTxListeners(c);
    await playgroundOffline(c);
  } finally {
    await reportPage(c.group, [c.page]);
    await c.page.close();
  }
}

// The names and helpers the playground steps share.
async function playgroundContext(browser, opts, compiler) {
  const group = `playground/${compiler}`;
  const compilerName = compiler === 'js' ? 'dart2js' : 'dart2wasm';
  const page = await Page.open(browser, 'playground');
  const events = async () => (await page.eval(PG)).events;
  const since = (s, n) => s.events.slice(n);
  const wait = (ok, timeout = 10000) => page.waitUntil(PG, (s) => s && ok(s), timeout,
    (s) => s && { conn: s.conn, client: s.client, server: s.server, events: s.events.slice(-6),
      serverLog: s.serverLog.slice(-6), pendingCount: s.pendingCount, pending: s.pending,
      error: s.error, listeners: s.listeners, reject: s.reject, rejectPressed: s.rejectPressed });
  // Key order differs between the trees (the client sorts children by key), so compare sorted.
  const canon = (v) => (v && typeof v === 'object' && !Array.isArray(v)
    ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, canon(v[k])])) : v);
  const same = (a, b) => JSON.stringify(canon(a)) === JSON.stringify(canon(b));
  const run = (js) => page.eval(`${js}; return true;`);
  const todosOf = (t) => (t && t.todos) || {};
  const bValue = '{"title":"Try offline","done":false}';
  return { opts, compiler, group, compilerName, page, events, since, wait, same, run, todosOf,
    bValue };
}

// Steps 1 to 5: open, set, update, push, remove.
async function playgroundWrites(c) {
  const { opts, compiler, group, compilerName, page, events, since, wait, same, run, todosOf,
  bValue } = c;
  await step(group, '1 open', `#compiler ${compilerName}, "client connected" (badge on), ` +
    'both trees counter 1 and todos/a, server log "answered listen /", pending 0 / none, ' +
    'no error', async () => {
    await page.goto(`${opts.base}/rtdb_playground/?compiler=${compiler}`);
    const initial = { counter: 1, todos: { a: { title: 'Read the docs', done: false } } };
    await wait((s) => s.compiler === compilerName && s.conn === 'client connected' &&
      s.connClass === 'badge on' && same(s.client, initial) && same(s.server, initial) &&
      s.serverLog.includes('answered listen /') && s.pendingCount === '0' &&
      same(s.pending, ['none']) && s.error === '');
  });

  await step(group, '2 set', `events "local  set /todos/b ${bValue}" then ` +
    '"server confirmed"; b ' +
    'in both trees; server log "applied set /todos/b"', async () => {
    const n = (await events()).length;
    await run(`submitForm('f-set')`);
    await wait((s) => same(since(s, n), [`local  set /todos/b ${bValue}`,
      `server confirmed  set /todos/b ${bValue}`]) &&
      todosOf(s.client).b && todosOf(s.server).b &&
      s.serverLog.includes('applied set /todos/b'));
  });

  await step(group, '3 update', 'done: true under a in both trees; then [1] gives #error with ' +
    '"update needs a JSON object"', async () => {
    const n = (await events()).length;
    await run(`submitForm('f-update')`);
    await wait((s) => same(since(s, n), ['local  update /todos/a {"done":true}',
      'server confirmed  update /todos/a {"done":true}']) &&
      todosOf(s.client).a.done === true && todosOf(s.server).a.done === true);
    await run(`setVal('upd-value', '[1]'); submitForm('f-update')`);
    const s = await wait((s) => s.error !== '');
    check(s.error.includes('update needs a JSON object'), `#error ${JSON.stringify(s.error)}`);
    await run(`setVal('upd-value', '{"done": true}')`);
    return `#error ${JSON.stringify(s.error)}`;
  });

  let pushed = null;
  const pushLine = /^local {2}push \/?todos\/([^ /]+) /;
  await step(group, '4 push',
    '"local  push todos/<key>" then "server confirmed"; key in both trees', async () => {
      const n = (await events()).length;
      await run(`submitForm('f-push')`);
      const s = await wait((s) => {
        const m = since(s, n).map((l) => pushLine.exec(l)).find(Boolean);
        return m && since(s, n).some((l) => l.startsWith('server confirmed  push')) &&
          todosOf(s.client)[m[1]] && todosOf(s.server)[m[1]];
      });
      pushed = since(s, n).map((l) => pushLine.exec(l)).find(Boolean)[1];
      return `key ${pushed} (${pushed.length} characters)`;
    });

  await step(group, '5 remove',
    '"local  remove /todos/a", "server confirmed"; a gone from both trees', async () => {
      const n = (await events()).length;
      await run(`setVal('rm-path', 'todos/a'); submitForm('f-remove')`);
      await wait((s) => same(since(s, n), ['local  remove /todos/a',
        'server confirmed  remove /todos/a']) && !todosOf(s.client).a && !todosOf(s.server).a);
    });
}

// Steps 6 and 7: transactions and listeners.
async function playgroundTxListeners(c) {
  const { group, page, events, since, wait, run, todosOf } = c;
  const tx = async (path, op, want) => {
    const n = (await events()).length;
    await run(`setVal('tx-path', ${JSON.stringify(path)}); setVal('tx-op', ${JSON.stringify(op)});
      submitForm('f-tx')`);
    await wait((s) => since(s, n).includes(want));
  };
  await step(group, '6 transactions',
    'inc on counter committed 2 (both trees); once on counter ' +
    'aborted; once on fresh committed "first"; bang on counter committed "hello!"', async () => {
    await tx('counter', 'inc', 'transaction /counter committed 2');
    await wait((s) => s.client.counter === 2 && s.server.counter === 2);
    await tx('counter', 'once', 'transaction /counter aborted');
    await tx('fresh', 'once', 'transaction /fresh committed "first"');
    await tx('counter', 'bang', 'transaction /counter committed "hello!"');
    await wait((s) => s.client.counter === 'hello!' && s.server.counter === 'hello!');
  });

  await step(group, '7 listeners',
    'value, childAdded (one per child), childChanged, childRemoved ' +
    'lines; stop removes every chip and no more lines', async () => {
    const listen = (type) => run(`setVal('l-path', 'todos'); setVal('l-type', '${type}');
      submitForm('f-listen')`);
    let n = (await events()).length;
    await listen('value');
    await wait((s) => s.listeners.includes('value /todosstop') &&
      since(s, n).some((l) => /^#\d+ value \/todos \{/.test(l)));
    n = (await events()).length;
    await listen('added');
    const s0 = await wait((s) => {
      const kids = Object.keys(todosOf(s.client));
      const added = since(s, n).filter((l) => /^#\d+ childAdded \/todos key=/.test(l));
      return added.length === kids.length;
    });
    n = s0.events.length;
    await run(`setVal('push-path', 'todos'); submitForm('f-push')`);
    await wait((s) => since(s, n).some((l) => /^#\d+ value \/todos/.test(l)) &&
      since(s, n).some((l) => /^#\d+ childAdded \/todos key=/.test(l)));
    await listen('changed');
    n = (await events()).length;
    await run(`setVal('upd-path', 'todos/b'); setVal('upd-value', '{"done": true}');
      submitForm('f-update')`);
    await wait((s) => since(s, n).some((l) => /^#\d+ childChanged \/todos key=b /.test(l)));
    await listen('removed');
    n = (await events()).length;
    await run(`setVal('rm-path', 'todos/b'); submitForm('f-remove')`);
    await wait((s) => since(s, n).some((l) => /^#\d+ childRemoved \/todos key=b /.test(l)));
    await run(`for (const b of Array.from(document.querySelectorAll('#listeners button'))) {
      b.click(); }`);
    await wait((s) => s.listeners.length === 0);
    n = (await events()).length;
    await run(`submitForm('f-push')`);
    await wait((s) => since(s, n).some((l) => l.startsWith('server confirmed  push')));
    await sleep(300);
    const after = since(await page.eval(PG), n);
    check(!after.some((l) => /^#\d+ /.test(l)), `lines after stop: ${JSON.stringify(after)}`);
    await run(`setVal('upd-path', 'todos/a')`);
  });
}

// Steps 8 to 10: offline and catch-up, rejection, invalid JSON.
async function playgroundOffline(c) {
  const { group, page, events, since, wait, same, run, todosOf, bValue } = c;
  await step(group, '8 offline and catch-up',
    '"connection lost", "client offline"; set and push ' +
    'wait (count 1, 2); reachable again: "connections accepted again", "client connected", ' +
    'both applied and confirmed, count 0, trees equal', async () => {
    let logN = (await page.eval(PG)).serverLog.length;
    await run(`$('reachable').click()`);
    await wait((s) => s.serverLog.slice(logN).includes('connection lost') &&
      s.conn === 'client offline' && s.connClass === 'badge off');
    let n = (await events()).length;
    await run(`setVal('set-path', 'todos/b'); submitForm('f-set')`);
    await wait((s) => same(since(s, n), [`local  set /todos/b ${bValue}`]) &&
      todosOf(s.client).b && !todosOf(s.server).b && s.pendingCount === '1' &&
      s.pending.length === 1 && s.pending[0].startsWith('set /todos/b'));
    await run(`submitForm('f-push')`);
    await wait((s) => s.pendingCount === '2');
    await sleep(300);
    check(!since(await page.eval(PG), n).some((l) => l.startsWith('server confirmed')),
      'a write was confirmed while unreachable');
    logN = (await page.eval(PG)).serverLog.length;
    await run(`$('reachable').click()`);
    const s = await wait((s) => {
      const log = s.serverLog.slice(logN);
      return log.includes('connections accepted again') && log.includes('answered listen /') &&
        log.includes('applied set /todos/b') &&
        log.some((l) => /^applied set \/todos\/(?!b$)/.test(l)) &&
        s.conn === 'client connected' && s.pendingCount === '0' &&
        since(s, n).filter((l) => l.startsWith('server confirmed')).length === 2 &&
        same(s.client, s.server);
    });
    return `server log: ${JSON.stringify(s.serverLog.slice(logN))}`;
  });

  await step(group, '9 rejection and rollback', 'button "Next write will be rejected (click to ' +
    'cancel)" pressed; set /todos/z shows z, then "rejected ... permission_denied", z gone, ' +
    'server log "refused set /todos/z: permission_denied"', async () => {
    await run(`$('reject').click()`);
    await wait((s) => s.reject === 'Next write will be rejected (click to cancel)' &&
      s.rejectPressed === 'true');
    const n = (await events()).length;
    await run(`window.__z = false;
      new MutationObserver(() => { if ($('client-tree').textContent.includes('z: '))
        window.__z = true; }).observe($('client-tree'), { childList: true, subtree: true });
      setVal('set-path', 'todos/z'); setVal('set-value', '{"x":1}'); submitForm('f-set')`);
    const rejected = 'rejected  set /todos/z {"x":1}: ';
    const s = await wait((s) => since(s, n).some((l) => l.startsWith(rejected)) &&
      !todosOf(s.client).z && s.serverLog.includes('refused set /todos/z: permission_denied'));
    const line = since(s, n).find((l) => l.startsWith('rejected'));
    check(/permission_denied/.test(line), `line ${JSON.stringify(line)}`);
    check(await page.eval('return window.__z;'), 'z never appeared in the client tree');
    return JSON.stringify(line);
  });

  await step(group, '9b reject button after the rejection',
    'button back to "Server rejects next ' +
    'write", aria-pressed false (the server has reset rejectNext)', async () => {
    await wait((s) => s.reject === 'Server rejects next write' &&
      s.rejectPressed === 'false', 2000);
  });

  await step(group, '10 invalid JSON', '#error has a FormatException; cleared on the next submit',
    async () => {
      await run(`setVal('set-value', '{'); submitForm('f-set')`);
      const s = await wait((s) => s.error !== '');
      check(/FormatException/.test(s.error), `#error ${JSON.stringify(s.error)}`);
      await run(`setVal('set-value', '{"x":2}'); submitForm('f-set')`);
      await wait((s) => s.error === '');
      return `#error was ${JSON.stringify(s.error)}`;
    });
}

// ---------------------------------------------------------------------------------------------
// Hidden-tab measure.

async function hiddenMeasure(browser, opts, rid, compiler) {
  const group = `hidden/${compiler}`;
  const project = `demo-smoke-${rid}-big-${compiler}`;
  const db = rest(opts, `${project}-default-rtdb`);
  const N = 20000;
  const items = {};
  for (let i = 0; i < N; i++) {
    items[`k${String(i).padStart(5, '0')}`] = { text: `item ${i}`, at: i };
  }
  const t0 = Date.now();
  await db.put('rtdb_web_app/items', items);
  console.log(`  ${group}: seeded ${N} items in ${Date.now() - t0} ms`);
  const url = `${opts.base}/rtdb_web_app/?emulator=${opts.emulator}&project=${project}` +
    `&compiler=${compiler}`;

  const time = async (page) => {
    await page.send('Page.navigate', { url });
    // The page times itself: performance.now() is measured from the start of the navigation.
    const r = await page.waitUntil(`const n = document.querySelectorAll('#items li').length;
      return { n, t: performance.now(), vis: document.visibilityState,
        url: location.href, error: txt('error') };`,
    (v) => v.url === url && v.n === N, 300000, (v) => v);
    return r;
  };

  for (const mode of ['visible', 'hidden']) {
    await step(group, mode, `${N} li; visibilityState ${mode}`, async () => {
      const page = await Page.open(browser, mode, { newWindow: true });
      try {
        await page.send('Emulation.setFocusEmulationEnabled', { enabled: false });
        if (mode === 'hidden') {
          const { windowId } = await browser.cdp.send('Browser.getWindowForTarget',
            { targetId: page.targetId });
          await browser.cdp.send('Browser.setWindowBounds',
            { windowId, bounds: { windowState: 'minimized' } });
        }
        const before = await page.eval('return document.visibilityState;');
        check(before === mode, `visibilityState ${before} before navigation`);
        const r = await time(page);
        check(r.vis === mode, `visibilityState ${r.vis} at the end`);
        // Whether this tab throttles timers: 20 nested setTimeout(0), as Timer.run chains them.
        const probe = await page.eval(`return await new Promise((res) => {
          const t0 = performance.now(); let n = 0;
          const f = () => { if (++n === 20) res(Math.round(performance.now() - t0));
            else setTimeout(f, 0); };
          setTimeout(f, 0); });`);
        return `${Math.round(r.t)} ms from navigation start to ${N} li ` +
          `(visibilityState ${r.vis}, ` +
          'method: own window, Browser.setWindowBounds minimized for hidden); ' +
          `20 nested setTimeout(0) took ${probe} ms`;
      } finally {
        await page.close();
      }
    });
  }
}

// ---------------------------------------------------------------------------------------------

async function main() {
  // A closed stdout (`| head`) must not end the script before Chrome is closed.
  process.stdout.on('error', () => {});
  const opts = parseArgs(process.argv.slice(2));
  const rid = randomBytes(4).toString('hex');
  const compilers = opts.compiler ? [opts.compiler] : ['js', 'wasm'];
  console.log(`smoke_gallery: base ${opts.base}, emulator ${opts.emulator}, run ${rid}`);
  const browser = await launchChrome();
  const onSignal = async () => { await browser.close(); process.exit(1); };
  process.once('SIGINT', onSignal);
  process.once('SIGTERM', onSignal);
  try {
    for (const compiler of compilers) {
      if (opts.hidden) {
        await hiddenMeasure(browser, opts, rid, compiler);
        continue;
      }
      if (opts.only !== 'playground') await webApp(browser, opts, rid, compiler);
      if (opts.only !== 'web_app') await playground(browser, opts, compiler);
    }
  } finally {
    await browser.close();
  }
  const groups = [...new Set(results.map((r) => r.group))];
  for (const g of groups) {
    const rs = results.filter((r) => r.group === g);
    const passed = rs.filter((r) => r.ok).length;
    console.log(`${g}: ${passed} passed, ${rs.length - passed} failed`);
  }
  process.exit(results.every((r) => r.ok) && results.length > 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(`smoke_gallery: ${e.stack ?? e}`);
  process.exit(1);
});
