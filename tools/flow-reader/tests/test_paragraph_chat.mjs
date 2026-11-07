import assert from "node:assert/strict";
import test from "node:test";
import { bubblePosition } from "../web/features/paragraph-chat/geometry.js";
import { ParagraphChatController } from "../web/features/paragraph-chat/controller.js";
import { stripMathDelimiters } from "../web/features/paragraph-chat/content.js";

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

function setupDocument(t) {
  const createElement = (tagName) =>
    Object.assign(new EventTarget(), {
      tagName,
      children: [],
      attributes: {},
      value: "",
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
  return { createElement };
}

function createMockNode(id, initialModel = "") {
  return {
    root: { dataset: { conversationId: id } },
    send: { disabled: false },
    input: { value: "" },
    model: Object.assign(new EventTarget(), {
      value: initialModel,
      children: [],
      replaceChildren(...children) {
        this.children = children;
      },
    }),
    summary: { textContent: "", title: "" },
  };
}

test("collapsed summary converts raw LaTeX math delimiters to plain text without raw HTML", () => {
  assert.equal(stripMathDelimiters("What is \\(e_1,e_2\\)?"), "What is e_1,e_2?");
  assert.equal(stripMathDelimiters("Solve \\[ X=3e_1+2e_2 \\] now"), "Solve X=3e_1+2e_2 now");
  assert.equal(
    stripMathDelimiters("Formula \\(e_1,e_2\\) and \\[ X=3e_1+2e_2 \\] · Ask"),
    "Formula e_1,e_2 and X=3e_1+2e_2 · Ask",
  );
  assert.equal(
    stripMathDelimiters("<img src=x> with \\(e_1,e_2\\)"),
    "<img src=x> with e_1,e_2",
  );
});

test("conversation switch preserves chosen model per conversation", (t) => {
  setupDocument(t);
  const controller = {
    chosenModels: new Map(),
    models: [
      { id: "gpt-4o", label: "GPT-4o" },
      { id: "o1-mini", label: "o1-mini" },
    ],
    getChosenModel: ParagraphChatController.prototype.getChosenModel,
    setChosenModel: ParagraphChatController.prototype.setChosenModel,
    renderModels: ParagraphChatController.prototype.renderModels,
    updateSend: ParagraphChatController.prototype.updateSend,
    state: {
      records: new Map([
        ["conv-1", { status: "idle", attachment: { state: "attached" } }],
        ["conv-2", { status: "idle", attachment: { state: "attached" } }],
      ]),
    },
  };
  const node1 = createMockNode("conv-1");
  const node2 = createMockNode("conv-2");

  controller.renderModels(node1);
  controller.renderModels(node2);

  // User selects "gpt-4o" in conversation 1
  node1.model.value = "gpt-4o";
  node1.model.onchange();

  // User selects "o1-mini" in conversation 2
  node2.model.value = "o1-mini";
  node2.model.onchange();

  assert.equal(controller.getChosenModel("conv-1"), "gpt-4o");
  assert.equal(controller.getChosenModel("conv-2"), "o1-mini");

  // Re-render conversation 1 (simulating returning / switching to conv-1)
  controller.renderModels(node1);
  assert.equal(node1.model.value, "gpt-4o");

  // Re-render conversation 2
  controller.renderModels(node2);
  assert.equal(node2.model.value, "o1-mini");
});

test("resend and follow-up keeps chosen model and enables send with input text", async (t) => {
  setupDocument(t);
  const controller = {
    chosenModels: new Map(),
    drafts: new Map(),
    models: [{ id: "gpt-4o", label: "GPT-4o" }],
    getChosenModel: ParagraphChatController.prototype.getChosenModel,
    setChosenModel: ParagraphChatController.prototype.setChosenModel,
    renderModels: ParagraphChatController.prototype.renderModels,
    updateSend: ParagraphChatController.prototype.updateSend,
    send: ParagraphChatController.prototype.send,
    action: async () => true,
    watch: () => {},
    state: {
      records: new Map([
        ["conv-1", { status: "idle", attachment: { state: "attached" } }],
      ]),
    },
  };
  const node = createMockNode("conv-1");
  controller.nodes = new Map([["conv-1", node]]);
  controller.renderModels(node);

  // User chooses model and types question
  node.model.value = "gpt-4o";
  node.model.onchange();
  node.input.value = "First question";
  controller.updateSend(node);
  assert.equal(node.send.disabled, false);

  // Send question
  await controller.send("conv-1");

  // Follow-up: model is preserved
  assert.equal(node.model.value, "gpt-4o");
  assert.equal(controller.getChosenModel("conv-1"), "gpt-4o");

  // Re-render simulates stream completion
  controller.renderModels(node);
  assert.equal(node.model.value, "gpt-4o");

  // User types follow-up
  node.input.value = "Follow up question";
  controller.updateSend(node);
  assert.equal(node.send.disabled, false);
});

test("model list refresh with chosen model removed falls back to empty and disables send", (t) => {
  setupDocument(t);
  const controller = {
    chosenModels: new Map(),
    models: [
      { id: "model-a", label: "Model A" },
      { id: "model-b", label: "Model B" },
    ],
    getChosenModel: ParagraphChatController.prototype.getChosenModel,
    setChosenModel: ParagraphChatController.prototype.setChosenModel,
    renderModels: ParagraphChatController.prototype.renderModels,
    updateSend: ParagraphChatController.prototype.updateSend,
    state: {
      records: new Map([
        ["conv-1", { status: "idle", attachment: { state: "attached" } }],
      ]),
    },
  };
  const node = createMockNode("conv-1");
  controller.renderModels(node);

  // Select Model A
  node.model.value = "model-a";
  node.model.onchange();
  node.input.value = "Hello";
  controller.updateSend(node);
  assert.equal(node.send.disabled, false);

  // Model list refreshes: Model A is removed, only Model B remains
  controller.models = [{ id: "model-b", label: "Model B" }];
  controller.renderModels(node);

  // Falls back to empty
  assert.equal(node.model.value, "");
  assert.equal(controller.getChosenModel("conv-1"), "");

  // Send is disabled correctly because no model is selected
  controller.updateSend(node);
  assert.equal(node.send.disabled, true);
});
