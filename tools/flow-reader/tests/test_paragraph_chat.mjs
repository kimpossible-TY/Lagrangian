import assert from "node:assert/strict";
import test from "node:test";
import { bubblePosition } from "../web/features/paragraph-chat/geometry.js";
import { ParagraphChatController } from "../web/features/paragraph-chat/controller.js";

test("host capability input disables autofill and text transformations and stays in memory", (t) => {
  const createElement = (tagName) =>
    Object.assign(new EventTarget(), {
      tagName,
      children: [],
      attributes: {},
      setAttribute(name, value) {
        this.attributes[name] = value;
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
  const input = () => node.account.children.find((child) => child.tagName === "input");
  render();
  assert.equal(input().type, "text");
  assert.equal(input().autocomplete, "off");
  assert.equal(input().spellcheck, false);
  assert.equal(input().autocapitalize, "off");
  assert.equal(input().className, "reader-chat-host-capability");
  assert.equal(input().attributes["aria-label"], "Host authorization token");
  input().value = "locally-entered-capability";
  input().dispatchEvent(new Event("input"));
  assert.equal(controller.hostCapability, "locally-entered-capability");
  controller.account = { signedIn: true };
  render();
  assert.equal(input().value, controller.hostCapability);
  controller.account = { hostOnly: true };
  render();
  assert.equal(input(), undefined);
});

test("account mutations require an explicitly entered local host capability", async (t) => {
  const requests = [];
  t.mock.method(globalThis, "fetch", async (path, options) => {
    requests.push({ path, ...options });
    return { ok: true, json: async () => ({ signedIn: true }) };
  });
  const controller = { identity: () => ({ revision: "r1" }) };
  for (const operation of ["login", "logout", "cancel"])
    await assert.rejects(
      ParagraphChatController.prototype.auth.call(controller, operation),
      /local host authorization token/,
    );
  assert.equal(requests.length, 0);
  controller.hostCapability = "locally-entered-capability";
  for (const operation of ["login", "logout", "cancel", "status", "models"])
    await ParagraphChatController.prototype.auth.call(controller, operation);
  assert.deepEqual(
    requests.map((request) => request.headers["X-Reader-Host-Capability"]),
    [
      controller.hostCapability,
      controller.hostCapability,
      controller.hostCapability,
      undefined,
      undefined,
    ],
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
