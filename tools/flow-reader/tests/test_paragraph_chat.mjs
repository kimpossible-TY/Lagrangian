import assert from "node:assert/strict";
import test from "node:test";
import { bubblePosition } from "../web/features/paragraph-chat/geometry.js";
import { ParagraphChatController } from "../web/features/paragraph-chat/controller.js";

test("document account entry uses configured Homepage and never includes host proof", (t) => {
  const createElement = (tagName) =>
    Object.assign(new EventTarget(), {
      tagName,
      children: [],
      attributes: {},
      setAttribute(name, value) {
        this.attributes[name] = value;
      },
      removeAttribute(name) {
        delete this.attributes[name];
      },
      append(...children) {
        this.children.push(...children);
        this.firstChild = this.children[0];
      },
      replaceChildren(...children) {
        this.children = children;
        this.firstChild = this.children[0];
      },
    });
  const previous = Object.getOwnPropertyDescriptor(globalThis, "document");
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: { createElement },
  });
  t.after(() => {
    if (previous) Object.defineProperty(globalThis, "document", previous);
    else delete globalThis.document;
  });
  const controller = { account: {}, models: [] };
  const node = { account: createElement("section"), model: createElement("select") };
  const render = () => ParagraphChatController.prototype.renderAccount.call(controller, node);
  controller.account = { homepageURL: "https://home.example/" };
  render();
  const link = node.account.children.find((child) => child.tagName === "a");
  assert.equal(link.href, "https://home.example/#connection");
  assert.equal(link.target, "_blank");
  assert.equal(link.rel, "noopener noreferrer");
  assert.equal(
    node.account.children.some((child) => child.tagName === "input"),
    false,
  );
  controller.account = { homepageURL: "http://127.0.0.1:8769/" };
  render();
  assert.equal(
    node.account.children.find((child) => child.tagName === "a").href,
    "http://127.0.0.1:8769/#connection",
  );
  controller.account = { homepageURL: null };
  render();
  assert.equal(node.account.children.find((child) => child.tagName === "a").href, undefined);
  controller.account = { homepageURL: "javascript:alert(1)" };
  render();
  assert.equal(node.account.children.find((child) => child.tagName === "a").href, undefined);
});

test("document account transport never sends credential mutations or host proof", async (t) => {
  const requests = [];
  t.mock.method(globalThis, "fetch", async (path, options) => {
    requests.push({ path, ...options });
    return { ok: true, json: async () => ({ signedIn: true }) };
  });
  const controller = { identity: () => ({ revision: "r1" }) };
  for (const operation of ["login", "logout", "cancel"])
    await assert.rejects(
      ParagraphChatController.prototype.auth.call(controller, operation),
      /Homepage/,
    );
  assert.equal(requests.length, 0);
  for (const operation of ["status", "models"])
    await ParagraphChatController.prototype.auth.call(controller, operation);
  assert.deepEqual(
    requests.map((request) => request.headers["X-Reader-Host-Capability"]),
    [undefined, undefined],
  );
  assert.ok(requests.every((request) => !request.body.includes("capability")));
});

test("summary crosses exactly one third of an empty reading edge and searches nearby rows", () => {
  const geometry = {
    edge: 700,
    width: 240,
    height: 32,
    paragraph: { top: 100, bottom: 180 },
    viewport: { left: 0, right: 1024 },
    obstacles: [{ left: 100, right: 700, top: 100, bottom: 125 }],
  };
  const result = bubblePosition(geometry);
  assert.equal(result.left, 620);
  assert.equal(result.right, 860);
  assert.equal(700 - result.left, 240 / 3);
  assert.equal(result.right - 700, (240 * 2) / 3);
  assert.ok(result.top >= 130);
});

test("summary falls back inline when prose, math or annotations occupy local whitespace", () => {
  const base = {
    edge: 700,
    width: 240,
    height: 32,
    paragraph: { top: 100, bottom: 180 },
    viewport: { left: 0, right: 1024 },
    obstacles: [{ left: 600, right: 1000, top: 0, bottom: 240 }],
  };
  assert.equal(bubblePosition(base), null);
  assert.equal(bubblePosition({ ...base, obstacles: [], viewport: { left: 0, right: 800 } }), null);
});

test("late send completion disables a composer removed by document replacement", () => {
  const node = {
    root: { dataset: { conversationId: "old" } },
    send: {},
    model: { value: "model" },
    input: { value: "draft" },
  };
  ParagraphChatController.prototype.updateSend.call({ state: { records: new Map() } }, node);
  assert.equal(node.send.disabled, true);
});
