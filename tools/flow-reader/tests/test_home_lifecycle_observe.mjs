import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("./home_lifecycle_observe.js", import.meta.url), "utf8");

class Element {
  constructor(localName, parent = null) {
    this.localName = localName;
    this.parentElement = parent;
    this.children = [];
    this.attributes = {};
    this.textContent = "";
  }
  setAttribute(name, value) {
    this.attributes[name] = value;
  }
  getAttribute(name) {
    return this.attributes[name] || null;
  }
  append(...children) {
    for (const child of children) {
      child.parentElement = this;
      this.children.push(child);
    }
  }
  prepend(child) {
    child.parentElement = this;
    this.children.unshift(child);
  }
  get firstElementChild() {
    return this.children[0];
  }
  remove() {
    const siblings = this.parentElement.children;
    siblings.splice(siblings.indexOf(this), 1);
    this.parentElement = null;
  }
  closest(selector) {
    for (let node = this; node; node = node.parentElement)
      if (
        selector === ".document-card"
          ? node.className === "document-card item"
          : node.localName === selector
      )
        return node;
    return null;
  }
  querySelector(selector) {
    return selector === ".document-info h3" ? this.heading : null;
  }
}

test("observer keeps bounded ordered menu history with distinct source and no focus changes", () => {
  const listeners = new Map();
  const document = {
    body: new Element("body"),
    createElement: (name) => new Element(name),
    addEventListener: (name, fn) => listeners.set(name, fn),
  };
  const makeMenu = (name) => {
    const card = new Element("article");
    card.className = "document-card item";
    card.heading = { textContent: name };
    const menu = new Element("wa-dropdown", card);
    const item = new Element("wa-dropdown-item", menu);
    item.setAttribute("aria-label", `${name} · Paged Reader`);
    return { menu, item };
  };
  const a = makeMenu("합성 문서 A");
  const b = makeMenu("합성 문서 B");
  document.activeElement = b.item;
  let now = 5;
  vm.runInNewContext(source, {
    document,
    location: { pathname: "/slow/" },
    performance: { now: () => now },
  });
  const diagnostic = document.body.children[0];
  const [title, status, details] = diagnostic.children;
  const entries = details.children[1];
  assert.equal(title.textContent, "느린 합성 메뉴 검수");
  assert.equal(status.attributes.role, "status");
  assert.equal(details.localName, "details");
  const emit = (type, target) => listeners.get(type)({ target });
  emit("wa-show", a.menu);
  emit("wa-show", b.menu);
  emit("wa-after-show", a.menu);
  now = 6;
  emit("wa-after-show", b.menu);
  const first = entries.children.map((entry) => entry.textContent);
  assert.match(first[0], /^1 · 5\.00 ms · wa-show · 출처: 문서 \d+ \(합성 문서 A\) \/ 메뉴 \d+/);
  assert.match(first[1], /^2 · 5\.00 ms · wa-show · 출처: 문서 \d+ \(합성 문서 B\) \/ 메뉴 \d+/);
  assert.match(first[2], /^3 · 5\.00 ms · wa-after-show/);
  assert.match(first[3], /^4 · 6\.00 ms · wa-after-show/);
  const sourceId = (line) => line.match(/출처: (문서 \d+ \([^)]*\) \/ 메뉴 \d+)/)[1];
  assert.notEqual(sourceId(first[0]), sourceId(first[1]));
  assert.equal(sourceId(first[0]), sourceId(first[2]));
  assert.equal(sourceId(first[1]), sourceId(first[3]));
  for (let i = 0; i < 21; i++) emit("focusin", b.item);
  assert.equal(entries.children.length, 24);
  assert.equal(entries.children[0].textContent, first[1]);
  assert.match(entries.children.at(-1).textContent, /^25 · 6\.00 ms · focusin/);
  assert.equal(status.textContent, entries.children.at(-1).textContent);
  assert.equal(document.activeElement, b.item);
});
