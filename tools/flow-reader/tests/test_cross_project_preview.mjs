import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { CrossProjectReturnStack, CROSS_PROJECT_RETURN_KEY, CROSS_PROJECT_PENDING_KEY } from "../../reader-common/navigation/cross-project-return.js";
import { CrossProjectPreview, createCrossProjectPosition, crossProjectTarget } from "../web/features/navigation/cross-project-preview.js";

// A small event/DOM surface: unsafe HTML writes throw, so text rendering is exercised.
class Element {
  constructor(tag, doc) {
    this.tagName = tag.toUpperCase();
    this.ownerDocument = doc;
    this.children = [];
    this.attributes = new Map();
    this.dataset = {};
    this.style = {};
    this.listeners = new Map();
    this.textContent = "";
    this.offsetWidth = 300;
    this.offsetHeight = 200;
  }
  set innerHTML(_) { throw new Error("HTML injection"); }
  addEventListener(type, fn) {
    this.listeners.set(type, [...(this.listeners.get(type) || []), fn]);
  }
  removeEventListener(type, fn) {
    this.listeners.set(type, (this.listeners.get(type) || []).filter((f) => f !== fn));
  }
  async emit(type, event = {}) {
    event.target ??= this;
    event.button ??= 0;
    event.preventDefault ??= () => { event.defaultPrevented = true; };
    for (const fn of this.listeners.get(type) || []) await fn(event);
    return event;
  }
  setAttribute(k, v) { this.attributes.set(k, v); }
  getAttribute(k) { return this.attributes.get(k) ?? null; }
  hasAttribute(k) { return this.attributes.has(k); }
  append(...nodes) {
    for (const node of nodes) { node.parentElement = this; this.children.push(node); }
  }
  remove() {
    if (this.parentElement) this.parentElement.children = this.parentElement.children.filter((n) => n !== this);
    this.parentElement = null;
  }
  contains(node) { return this === node || this.children.some((n) => n.contains(node)); }
  get isConnected() { return this.ownerDocument.body.contains(this); }
  closest(selector) {
    if (selector.split(",").some((s) => s.toUpperCase() === this.tagName)) return this;
    return this.parentElement?.closest(selector) ?? null;
  }
  querySelectorAll(selector) {
    return this.children.flatMap((n) => [
      ...(selector === "[data-reader-section]" && n.dataset.readerSection ? [n] : []),
      ...n.querySelectorAll(selector),
    ]);
  }
  focus() { this.ownerDocument.activeElement = this; }
  getBoundingClientRect() {
    return { left: 50, bottom: 100, top: (this.documentTop ?? 0) - this.ownerDocument.defaultView.scrollY };
  }
}
const result = (extra = {}) => ({ status: "unique", projectTitle: "Target Book", label: "thm",
  refText: "Theorem 1", snippet: "Canonical theorem text", targetUrl: "/d/target/#thm", ...extra });
const origin = { path: "/d/origin/?section=s2#old", documentTitle: "Origin Book", sectionId: "s2",
  anchor: "old", scrollOffset: 134.5 };
const flush = () => new Promise((resolve) => setImmediate(resolve));

function setup({ request = async () => result(), restore = () => true, capture = () => origin } = {}) {
  const values = new Map(), assigned = [], external = [];
  const storage = { getItem: (k) => values.get(k) ?? null, setItem: (k, v) => values.set(k, v), removeItem: (k) => values.delete(k) };
  const stack = new CrossProjectReturnStack({ storage });
  const doc = new Element("document", null);
  doc.ownerDocument = doc;
  doc.body = new Element("body", doc);
  doc.createElement = (tag) => new Element(tag, doc);
  const location = { origin: "https://reader.test", pathname: "/d/origin/", search: "?section=s2", hash: "#old",
    assign: (url) => assigned.push(url) };
  doc.defaultView = Object.assign(new Element("window", doc), {
    location, innerWidth: 800, innerHeight: 600, scrollY: 400,
    scrollTo({ top }) { this.scrollY = top; },
  });
  doc.title = "Origin Book · Lagrangian Web Viewer";
  const article = doc.createElement("main"), button = doc.createElement("button");
  doc.body.append(article, button);
  const link = doc.createElement("a");
  link.setAttribute("data-project-ref-project", "target");
  link.setAttribute("data-project-ref-label", "thm");
  link.dataset = { projectRefProject: "target", projectRefLabel: "thm" };
  link.setAttribute("href", "#ignored-explicit-fragment");
  article.append(link);
  let identity = "document-1/service-1/revision-1", enabled = true;
  const controller = new CrossProjectPreview(article, { stack, returnButton: button, capture, restore,
    request, location, identity: () => identity, enabled: () => enabled,
    openExternal: (url) => external.push(url), transitionId: () => "return-transition-1" });
  return { doc, article, button, link, stack, values, storage, assigned, external, controller, location,
    identity: (v) => { identity = v; }, enabled: (v) => { enabled = v; } };
}
const jump = (f) => f.controller.card.children.find((n) => n.getAttribute("aria-label") === "해당 문서로 이동");

test("first click fetches metadata before any navigation, renders accessible text, second click captures and navigates a full page", async () => {
  const requests = [];
  const f = setup({ request: async (...args) => { requests.push(args); return result(); } });
  const event = await f.article.emit("click", { target: f.link });
  assert.equal(event.defaultPrevented, true);
  assert.match(requests[0][0], /^api\/cross-project\/preview\?project=target&label=thm$/u);
  assert.ok(requests[0][1].signal instanceof AbortSignal);
  assert.deepEqual(f.assigned, []);
  assert.equal(f.stack.canGoBack, false);
  const card = f.controller.card;
  assert.equal(card.getAttribute("role"), "dialog");
  assert.ok(card.getAttribute("aria-label"));
  assert.equal(card.children[0].textContent, "Target Book");
  assert.equal(card.children[1].textContent, "thm · Theorem 1");
  assert.equal(card.children[2].textContent, "Canonical theorem text");
  assert.equal(f.doc.activeElement, jump(f));
  await jump(f).emit("click");
  assert.deepEqual(f.assigned, ["/d/target/#thm"]);
  assert.deepEqual(new CrossProjectReturnStack({ storage: f.storage }).pop(), origin);
});

test("preview card activation also jumps once; failed persistence or assign preserves recoverable history", async () => {
  const f = setup();
  await f.article.emit("click", { target: f.link });
  await f.controller.card.emit("click", { target: f.controller.card.children[2] });
  assert.deepEqual(f.assigned, ["/d/target/#thm"]);
  const denied = setup();
  await denied.article.emit("click", { target: denied.link });
  denied.storage.setItem = () => { throw Error("quota"); };
  await jump(denied).emit("click");
  assert.equal(denied.assigned.length, 0);
  assert.equal(denied.stack.canGoBack, false);
  const g = setup();
  await g.article.emit("click", { target: g.link });
  g.location.assign = () => { throw Error("navigation"); };
  await jump(g).emit("click");
  assert.equal(g.stack.canGoBack, false);
});

test("new clicks abort old fetches and ignore out-of-order completion, document changes and dispose", async () => {
  const pending = [];
  const f = setup({ request: (url, { signal }) => new Promise((resolve) => pending.push({ resolve, signal })) });
  const first = f.article.emit("click", { target: f.link });
  const second = f.article.emit("click", { target: f.link });
  assert.equal(pending[0].signal.aborted, true);
  pending[1].resolve(result({ snippet: "new" }));
  await second;
  pending[0].resolve(result({ snippet: "old" }));
  await first;
  assert.equal(f.controller.card.children[2].textContent, "new");
  const third = f.article.emit("click", { target: f.link });
  f.identity("document-1/service-2/revision-1");
  f.controller.update();
  pending[2].resolve(result());
  await third;
  assert.equal(f.controller.card, null);
  const fourth = f.article.emit("click", { target: f.link });
  f.controller.dispose();
  assert.equal(pending[3].signal.aborted, true);
  pending[3].resolve(result());
  await fourth;
  assert.equal(f.controller.card, null);
  assert.equal(f.button.hidden, true);
  assert.equal((f.article.listeners.get("click") || []).length, 0);
});

test("Escape, outside click, close and dispose dismiss and restore focus without reviving late requests", async () => {
  const f = setup();
  await f.article.emit("click", { target: f.link });
  assert.equal((await f.doc.emit("keydown", { key: "Escape" })).defaultPrevented, true);
  assert.equal(f.controller.card, null);
  assert.equal(f.doc.activeElement, f.link);
  await f.article.emit("click", { target: f.link });
  await f.doc.emit("click", { target: f.article });
  assert.equal(f.controller.card, null);
  assert.equal(f.doc.activeElement, f.link);
  await f.article.emit("click", { target: f.link });
  const outside = f.doc.createElement("button");
  f.doc.body.append(outside);
  outside.focus();
  await f.doc.emit("click", { target: outside });
  assert.equal(f.doc.activeElement, outside);
  await f.article.emit("click", { target: f.link });
  await f.controller.card.children.at(-1).emit("click");
  assert.equal(f.controller.card, null);
});

test("outside click cancels an implicit loading request; stale failures cannot follow an external link", async () => {
  for (const cancel of ["outside", "identity", "pagehide"]) {
    let reject, signal;
    const f = setup({ request: (_, options) => {
      signal = options.signal;
      return new Promise((_, fail) => { reject = fail; });
    } });
    const link = f.doc.createElement("a");
    link.setAttribute("href", "https://example.test/book.pdf#page=2");
    f.article.append(link);
    const loading = f.article.emit("click", { target: link });
    if (cancel === "outside") {
      await f.doc.emit("click", { target: f.article });
      assert.equal(signal.aborted, true);
    } else if (cancel === "pagehide") {
      await f.doc.defaultView.emit("pagehide", { persisted: true });
      assert.equal(signal.aborted, true);
    } else f.identity("other revision");
    reject(Error("late failure"));
    await loading;
    assert.deepEqual(f.assigned, []);
    assert.equal(f.controller.card, null);
  }
});

test("XSS payloads remain literal text and ambiguous/unresolved/metadata-only states never guess a target", async () => {
  const payload = '<img src=x onerror="alert(1)">';
  for (const response of [result({ projectTitle: payload, snippet: payload }),
    result({ snippet: null, targetUrl: null, pdfUrl: "https://example.test/book.pdf" }),
    result({ status: "ambiguous", targetUrl: null }), result({ status: "unresolved", targetUrl: null })]) {
    const f = setup({ request: async () => response });
    await f.article.emit("click", { target: f.link });
    assert.equal(jump(f).disabled, response.targetUrl === null);
    assert.ok(f.controller.card.children.every((n) => !["IMG", "SCRIPT"].includes(n.tagName)));
    if (response.snippet === payload) assert.equal(f.controller.card.children[2].textContent, payload);
    if (response.pdfUrl) assert.equal(f.controller.card.children.find((n) => n.tagName === "A").href, response.pdfUrl);
    assert.deepEqual(f.assigned, []);
  }
});

test("mounted route validation rejects executable, cross-origin, encoded, traversal and noncanonical targets", async () => {
  for (const target of ["javascript:alert(1)", "//evil/d/a/", "/d/a/../b/", "/d/%61/", "/d/a/?secret=x", "/d/a", "/d/A/", "/d/a_b/", "https://evil/d/a/", "/other/"])
    assert.equal(crossProjectTarget(target, "https://reader.test"), null, target);
  assert.equal(crossProjectTarget("https://reader.test/d/a/#x", "https://reader.test"), "/d/a/#x");
  const f = setup({ request: async () => result({ targetUrl: "https://peer.test/d/a/#x" }) });
  await f.article.emit("click", { target: f.link });
  assert.equal(jump(f).disabled, true);
  const external = f.controller.card.children.find((n) => n.tagName === "A");
  assert.equal(external.target, "_blank");
  assert.match(external.rel, /noopener/u);
  assert.equal(external.href, "https://peer.test/d/a/#x");
  assert.equal(f.stack.canGoBack, false);
});

test("ordinary links, fragments, modifiers and disabled capability retain existing navigation; PDF candidates preserve unresolved fallback", async () => {
  let requests = 0;
  const f = setup({ request: async () => { requests++; return result({ status: "unresolved" }); } });
  const link = f.doc.createElement("a");
  f.article.append(link);
  for (const href of ["#anchor", "https://example.test/ordinary", "mailto:me@example.test", "/d/target/#x", "https://reader.test/d/target/#page=2"]) {
    link.setAttribute("href", href);
    assert.equal((await f.article.emit("click", { target: link })).defaultPrevented, undefined);
  }
  link.setAttribute("href", "https://example.test/book.pdf#page=2");
  f.enabled(false);
  await f.article.emit("click", { target: link });
  f.enabled(true);
  await f.article.emit("click", { target: link, ctrlKey: true });
  assert.equal(requests, 0);
  await f.article.emit("click", { target: link });
  assert.equal(requests, 1);
  assert.deepEqual(f.assigned, ["https://example.test/book.pdf#page=2"]);
  assert.equal(f.controller.card, null);
  assert.equal(f.stack.canGoBack, false);
  const g = setup();
  const pdf = g.doc.createElement("a");
  pdf.textContent = "Theorem 1";
  pdf.setAttribute("href", "https://example.test/book.pdf#page=2");
  g.article.append(pdf);
  await g.article.emit("click", { target: pdf });
  assert.ok(g.controller.card);
  assert.deepEqual(g.assigned, []);
  pdf.setAttribute("href", "https://reader.test/book.pdf#page=2");
  await g.article.emit("click", { target: pdf });
  assert.ok(g.controller.card, "same-origin PDF candidates also use catalog resolution");
});

test("Back visibility, durable pending-before-pop ordering, exact section/offset restoration and single consumption", async () => {
  const f = setup();
  assert.equal(f.button.hidden, true);
  f.stack.push(origin);
  f.controller.update();
  assert.equal(f.button.hidden, false);
  assert.equal(f.button.textContent, "← Origin Book");
  const writes = [];
  f.storage.setItem = (key, value) => { writes.push(key); f.values.set(key, value); };
  await f.button.emit("click");
  assert.deepEqual(writes, [CROSS_PROJECT_PENDING_KEY, CROSS_PROJECT_RETURN_KEY]);
  assert.deepEqual(f.assigned, [origin.path]);
  assert.equal(f.button.hidden, true);
  const record = f.controller.pendingReturn();
  assert.deepEqual(record.entry, origin);
  let ready = false, held = 0;
  const section = f.doc.createElement("section");
  section.dataset = { readerSection: "s2", sectionState: "ready" };
  section.documentTop = 500;
  f.article.append(section);
  const position = createCrossProjectPosition(f.article, { ready: () => ready, readSection: () => "s1",
    captureAnchor: () => ({ section: "s2", id: "old" }), release() {}, holdAnchor() { held++; } });
  f.controller.restore = position.restore;
  assert.equal(f.controller.restorePending(record), false);
  assert.ok(f.values.has(CROSS_PROJECT_PENDING_KEY));
  ready = true;
  f.article.setAttribute("aria-busy", "true");
  assert.equal(f.controller.restorePending(record), false);
  f.article.setAttribute("aria-busy", "false");
  assert.equal(f.controller.restorePending(record), true);
  assert.equal(f.doc.defaultView.scrollY, 634.5);
  assert.equal(held, 1);
  assert.deepEqual(position.capture(), origin);
  assert.equal(f.controller.restorePending(record), false);
  assert.equal(held, 1);
  assert.equal(f.values.has(CROSS_PROJECT_PENDING_KEY), false);
  f.stack.savePending(origin, "new-return");
  assert.equal(f.controller.restorePending(record), false);
  f.location.pathname = "/d/unrelated/";
  assert.equal(f.controller.pendingReturn(), null);
  assert.ok(f.values.has(CROSS_PROJECT_PENDING_KEY));
});

test("Back write/assign failures keep history and failed geometry never consumes a pending return", async () => {
  const f = setup();
  f.stack.push(origin);
  f.storage.setItem = () => { throw Error("quota"); };
  await f.button.emit("click");
  assert.deepEqual(f.assigned, []);
  assert.deepEqual(f.stack.peek(), origin);
  const g = setup();
  g.stack.push(origin);
  g.location.assign = () => { throw Error("navigation"); };
  await g.button.emit("click");
  assert.deepEqual(g.stack.peek(), origin);
  assert.equal(g.controller.pendingReturn(), null);
  g.stack.savePending(origin, "r");
  const position = createCrossProjectPosition(g.article, { ready: () => true,
    captureAnchor: () => null, readSection: () => "missing", release() {}, holdAnchor() {} });
  g.controller.restore = position.restore;
  assert.equal(position.capture(), null);
  assert.equal(g.controller.restorePending(g.controller.pendingReturn()), false);
  assert.ok(g.values.has(CROSS_PROJECT_PENDING_KEY));
});

test("clamped scroll and denied pending removal retain restoration state for recovery", () => {
  const f = setup();
  const section = f.doc.createElement("section");
  section.dataset = { readerSection: origin.sectionId, sectionState: "ready" };
  section.documentTop = 500;
  f.article.append(section);
  const position = createCrossProjectPosition(f.article, { ready: () => true,
    captureAnchor: () => null, readSection: () => "s2", release() {}, holdAnchor() {} });
  f.controller.restore = position.restore;
  f.stack.savePending(origin, "clamped");
  const record = f.controller.pendingReturn();
  f.doc.defaultView.scrollTo = () => {};
  assert.equal(f.controller.restorePending(record), false);
  assert.deepEqual(f.controller.pendingReturn(), record);
  f.doc.defaultView.scrollTo = function ({ top }) { this.scrollY = top; };
  f.storage.removeItem = () => { throw Error("denied"); };
  assert.equal(f.controller.restorePending(record), false);
  assert.deepEqual(f.controller.pendingReturn(), record);
});

test("restoration verifies finite geometry and the final scroll after semantic holding", () => {
  const f = setup();
  const section = f.doc.createElement("section");
  section.dataset = { readerSection: origin.sectionId, sectionState: "ready" };
  section.documentTop = 500;
  f.article.append(section);
  let shift = 40;
  f.controller.restore = createCrossProjectPosition(f.article, { ready: () => true,
    captureAnchor: () => null, readSection: () => "s2", release() {},
    holdAnchor() { f.doc.defaultView.scrollY += shift; },
  }).restore;
  f.stack.savePending(origin, "final-position");
  const record = f.controller.pendingReturn();
  assert.equal(f.controller.restorePending(record), false);
  assert.deepEqual(f.controller.pendingReturn(), record);
  shift = 0;
  section.documentTop = NaN;
  assert.equal(f.controller.restorePending(record), false);
  assert.deepEqual(f.controller.pendingReturn(), record);
  section.documentTop = 500;
  assert.equal(f.controller.restorePending(record), true);
  assert.equal(f.doc.defaultView.scrollY, 634.5);
  assert.equal(f.controller.pendingReturn(), null);
});

test("delivered section loader preserves pending return section instead of applying update anchoring", async () => {
  const source = readFileSync(new URL("../web/reader.js", import.meta.url), "utf8");
  const loader = source.slice(source.indexOf("async function loadSection("), source.indexOf("function sectionFor("));
  const nextManifest = { documentID: "origin-document", revision: "accepted" };
  const f = setup();
  let rendered;
  // Execute the real loader with its section fetch/render operations substituted.
  const load = new Function("article", "manifest", "fetchSection", "renderDocument", `
    let loadSequence = 0;
    const serverState = manifest, disposed = false;
    const activity = { state: { begin() {}, cancel() {}, error() { throw Error("unexpected failure"); } }, refresh() {} };
    const sameSession = () => true, sameSnapshot = () => true, selectionActive = () => false;
    const changes = { allowPublication: () => true };
    const readingAnchor = () => { throw Error("return section overridden"); };
    ${loader}
    return loadSection;
  `)(f.article, nextManifest, async () => "accepted section HTML", (...args) => { rendered = args; });
  const record = { version: 1, transitionId: "return", entry: origin };
  await load(nextManifest, origin.sectionId, { update: true, target: "conflicting-fragment", crossProjectReturn: record });
  assert.equal(rendered[2], origin.sectionId);
  assert.equal(rendered[3].crossProjectReturn, record);
});

test("Homepage delivered explicit-open handlers reset both records, including alternative menu items", async () => {
  const source = readFileSync(new URL("../web/home/home.js", import.meta.url), "utf8");
  // Execute the actual registration block for both emitted document destinations.
  const block = source.slice(source.indexOf('      const resetCrossProjectReturn ='), source.indexOf('      entry = { link, item };'));
  assert.ok(block.includes('item.addEventListener'));
  const f = setup();
  const item = f.doc.createElement("wa-dropdown-item");
  new Function("link", "item", "sessionStorage", block)(f.link, item, f.storage);
  for (const node of [f.link, item]) {
    f.stack.push(origin);
    f.stack.savePending(origin, "r");
    assert.equal(f.values.size, 2);
    await node.emit("click");
    assert.equal(f.values.size, 0);
  }
  await flush();
});

test("bfcache re-entry rereads stack changes from other documents and Homepage resets", async () => {
  const f = setup();
  await f.article.emit("click", { target: f.link });
  await jump(f).emit("click");
  assert.equal(f.controller.navigating, true);
  await f.doc.defaultView.emit("pageshow", { persisted: true });
  assert.equal(f.controller.navigating, false);
  assert.equal(f.controller.card, null);
  new CrossProjectReturnStack({ storage: f.storage }).push(origin);
  await f.doc.defaultView.emit("pageshow", { persisted: true });
  assert.equal(f.button.hidden, false);
  f.storage.removeItem(CROSS_PROJECT_RETURN_KEY);
  await f.doc.defaultView.emit("pageshow", { persisted: true });
  assert.equal(f.button.hidden, true);
  assert.equal(f.stack.canGoBack, false);
  f.controller.dispose();
  assert.equal(f.doc.defaultView.listeners.get("pageshow").length, 0);
});

test("manifest registers both modules in sorted order and reader bootstrap wires pending restoration before fragment navigation", () => {
  const assets = JSON.parse(readFileSync(new URL("../web/assets.json", import.meta.url), "utf8"));
  assert.deepEqual(Object.keys(assets), Object.keys(assets).sort());
  for (const path of ["features/navigation/cross-project-preview.js", "reader-common/navigation/cross-project-return.js"])
    assert.equal(assets[path], path);
  const html = readFileSync(new URL("../web/index.html", import.meta.url), "utf8");
  assert.match(html, /id="reader-cross-project-return"[^>]*hidden/u);
  const reader = readFileSync(new URL("../web/reader.js", import.meta.url), "utf8");
  assert.match(reader, /if \(options.crossProjectReturn\)[\s\S]*?restorePending[\s\S]*?else if \(options.target\)/u);
  assert.match(reader, /returnSection && pending.sections.some/u);
  assert.match(reader, /crossProjects.dispose\(\)/u);
});
