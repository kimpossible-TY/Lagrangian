import assert from "node:assert/strict";
import test from "node:test";
import { panelPosition, overlapsInk } from "../web/features/paragraph-chat/geometry.js";
import { ParagraphChatController } from "../web/features/paragraph-chat/controller.js";
import { stripMathDelimiters } from "../web/features/paragraph-chat/content.js";
import { conversationSummary } from "../../reader-common/paragraph-chat/state.js";

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

test("expanded capsules stay near the annotation and spill at most 24px into the margin", () => {
  const base = { edge: 1000, start: 100, anchor: { left: 256, right: 300, top: 100, bottom: 144 }, viewport: { right: 1456 }, height: 200 };
  const box = panelPosition(base);
  assert.equal(box.left, 316);
  assert.equal(box.top, 100);
  assert.ok(box.right <= base.edge + 24);
  assert.equal(panelPosition({ ...base, start: 900 }), null);
  assert.equal(panelPosition({ ...base, viewport: { right: 390 } }), null);
});

test("side panels avoid source ink, annotations and other open panels", () => {
  const box = { left: 1024, right: 1444, top: 120, bottom: 520 };
  assert.equal(overlapsInk(box, [{ left: 900, right: 1000, top: 100, bottom: 400 }]), false);
  assert.equal(overlapsInk(box, [{ left: 1030, right: 1100, top: 140, bottom: 160 }]), true);
  assert.equal(overlapsInk(box, [{ left: 1024, right: 1444, top: 510, bottom: 900 }]), true);
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

test("initial empty model catalog does not delete persisted model across catalog arrival and reload", (t) => {
  setupDocument(t);
  const storage = new Map([["reader_chat_model_conv-1", "gpt-4o"]]);
  const previousStorage = Object.getOwnPropertyDescriptor(globalThis, "sessionStorage");
  Object.defineProperty(globalThis, "sessionStorage", {
    configurable: true,
    value: {
      getItem(key) {
        return storage.get(key) ?? null;
      },
      setItem(key, val) {
        storage.set(key, String(val));
      },
      removeItem(key) {
        storage.delete(key);
      },
    },
  });
  t.after(() => {
    if (previousStorage) Object.defineProperty(globalThis, "sessionStorage", previousStorage);
    else delete globalThis.sessionStorage;
  });

  const controller = {
    chosenModels: new Map(),
    models: [],
    modelsLoaded: false,
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

  // 1. Initial render with models = [] before catalog arrives
  controller.renderModels(node);
  assert.equal(node.model.value, "");
  // Stored model must NOT be wiped out
  assert.equal(controller.getChosenModel("conv-1"), "gpt-4o");
  assert.equal(storage.get("reader_chat_model_conv-1"), "gpt-4o");

  // 2. Catalog arrives with gpt-4o
  controller.models = [
    { id: "gpt-4o", label: "GPT-4o" },
    { id: "o1-mini", label: "o1-mini" },
  ];
  controller.modelsLoaded = true;
  controller.renderModels(node);
  assert.equal(node.model.value, "gpt-4o");
  assert.equal(controller.getChosenModel("conv-1"), "gpt-4o");
  assert.equal(storage.get("reader_chat_model_conv-1"), "gpt-4o");

  // 3. Conversation reload keeps the model
  const reloadedNode = createMockNode("conv-1");
  controller.renderModels(reloadedNode);
  assert.equal(reloadedNode.model.value, "gpt-4o");
  assert.equal(controller.getChosenModel("conv-1"), "gpt-4o");

  // 4. Successful empty catalog receipt legitimately clears model
  controller.models = [];
  controller.modelsLoaded = true;
  controller.renderModels(reloadedNode);
  assert.equal(reloadedNode.model.value, "");
  assert.equal(controller.getChosenModel("conv-1"), "");
});

test("sessionStorage delete failure preserves authoritative empty memory tombstone and prevents resurrection", (t) => {
  setupDocument(t);
  let removeItemThrew = false;
  const previousStorage = Object.getOwnPropertyDescriptor(globalThis, "sessionStorage");
  Object.defineProperty(globalThis, "sessionStorage", {
    configurable: true,
    value: {
      getItem(key) {
        return key === "reader_chat_model_conv-1" ? "gpt-4o" : null;
      },
      setItem() {},
      removeItem() {
        removeItemThrew = true;
        throw new Error("SecurityError: Storage access is denied");
      },
    },
  });
  t.after(() => {
    if (previousStorage) Object.defineProperty(globalThis, "sessionStorage", previousStorage);
    else delete globalThis.sessionStorage;
  });

  const controller = {
    chosenModels: new Map(),
    models: [{ id: "gpt-4o", label: "GPT-4o" }],
    modelsLoaded: true,
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

  // Initial read gets gpt-4o from storage
  assert.equal(controller.getChosenModel("conv-1"), "gpt-4o");

  // User or fallback clears the model (removeItem throws)
  controller.setChosenModel("conv-1", "");
  assert.equal(removeItemThrew, true);

  // Authoritative memory tombstone keeps empty
  assert.equal(controller.getChosenModel("conv-1"), "");

  // Re-render stays empty
  controller.renderModels(node);
  assert.equal(node.model.value, "");
  controller.updateSend(node);
  assert.equal(node.send.disabled, true);

  // Model removed from catalog
  controller.models = [{ id: "other", label: "Other" }];
  controller.renderModels(node);
  assert.equal(node.model.value, "");

  // Model reappears in catalog later: must NOT resurrect old gpt-4o
  controller.models = [{ id: "gpt-4o", label: "GPT-4o" }];
  controller.renderModels(node);
  assert.equal(node.model.value, "");
  assert.equal(controller.getChosenModel("conv-1"), "");
  controller.updateSend(node);
  assert.equal(node.send.disabled, true);
});

test("conversationSummary strips math on full question/answer before 65/90 truncation and preserves literal dollars", () => {
  // Single-dollar math expression longer than 65 chars
  const longMathQ = "$" + "x+".repeat(40) + "y$";
  const rec1 = {
    quote: "quote",
    status: "idle",
    thread: [{ role: "user", text: longMathQ, status: "completed" }],
  };
  const summary1 = conversationSummary(rec1);
  assert.equal(summary1.includes("$"), false);
  assert.equal(
    summary1,
    "x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+… · Ask",
  );

  // Display math \\[...\\] longer than 65 chars
  const longLatexQ = "\\[" + "a+".repeat(40) + "b\\]";
  const rec2 = {
    quote: "quote",
    status: "idle",
    thread: [{ role: "user", text: longLatexQ, status: "completed" }],
  };
  const summary2 = conversationSummary(rec2);
  assert.equal(summary2.includes("\\["), false);
  assert.equal(summary2.includes("\\]"), false);

  // Block math $$...$$ in assistant answer longer than 90 chars
  const longAnswer = "$$" + "c+".repeat(50) + "d$$";
  const rec3 = {
    quote: "quote",
    status: "idle",
    thread: [
      { role: "user", text: "Question?", status: "completed" },
      { role: "assistant", text: longAnswer, status: "completed" },
    ],
  };
  const summary3 = conversationSummary(rec3);
  assert.equal(summary3.includes("$$"), false);

  // Literal and currency dollars preserved through conversationSummary
  const currencyRec = {
    quote: "quote",
    status: "idle",
    thread: [{ role: "user", text: "Lunch costs $5 and $10", status: "completed" }],
  };
  assert.equal(conversationSummary(currencyRec), "Lunch costs $5 and $10 · Ask");

  // Escaped dollars preserved
  const escapedRec = {
    quote: "quote",
    status: "idle",
    thread: [{ role: "user", text: "Price is \\$5 and \\$10", status: "completed" }],
  };
  assert.equal(conversationSummary(escapedRec), "Price is \\$5 and \\$10 · Ask");

  // Single dollar literal preserved
  const singleDollarRec = {
    quote: "quote",
    status: "idle",
    thread: [{ role: "user", text: "Symbol \\$ alone", status: "completed" }],
  };
  assert.equal(conversationSummary(singleDollarRec), "Symbol \\$ alone · Ask");

  // Currency ranges preserved verbatim through conversationSummary
  assert.equal(
    conversationSummary({
      quote: "quote",
      status: "idle",
      thread: [{ role: "user", text: "Budget is $5-$10", status: "completed" }],
    }),
    "Budget is $5-$10 · Ask",
  );
  assert.equal(
    conversationSummary({
      quote: "quote",
      status: "idle",
      thread: [{ role: "user", text: "$5–$10", status: "completed" }],
    }),
    "$5–$10 · Ask",
  );
  assert.equal(
    conversationSummary({
      quote: "quote",
      status: "idle",
      thread: [{ role: "user", text: "US$5–US$10", status: "completed" }],
    }),
    "US$5–US$10 · Ask",
  );
});

test("controller summary UI renders plain-text title preserving currency ranges verbatim while stripping math", (t) => {
  setupDocument(t);
  const testCases = [
    { text: "**Bold $x^2$** and __clear__", expected: "Bold x^2 and clear · Ask" },
    { text: "Unmatched **bold", expected: "Unmatched **bold · Ask" },
    { text: "Escaped \\*\\*literal\\*\\*", expected: "Escaped \\*\\*literal\\*\\* · Ask" },
    { text: "Budget is $5-$10", expected: "Budget is $5-$10 · Ask" },
    { text: "$5–$10", expected: "$5–$10 · Ask" },
    { text: "US$5–US$10", expected: "US$5–US$10 · Ask" },
    { text: "Numeric math $x^2$", expected: "Numeric math x^2 · Ask" },
    { text: "Formula $2+3$", expected: "Formula 2+3 · Ask" },
    { text: "Price is \\$5 and \\$10", expected: "Price is \\$5 and \\$10 · Ask" },
    { text: "Lunch costs $5 and $10", expected: "Lunch costs $5 and $10 · Ask" },
    {
      text: "$" + "x+".repeat(40) + "y$",
      expected: "x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+x+… · Ask",
    },
  ];

  for (let i = 0; i < testCases.length; i++) {
    const { text, expected } = testCases[i];
    const convId = `conv-curr-${i}`;
    const record = {
      conversation_id: convId,
      quote: "quote",
      status: "idle",
      thread: [{ role: "user", text, status: "completed" }],
      attachment: { state: "unresolved" },
    };

    // 1. Direct conversationSummary check
    const summary = conversationSummary(record);
    assert.equal(summary, expected);

    // 2. Real controller summary UI path: render() -> node.summary.textContent & node.summary.title
    const node = {
      root: { parentNode: null, remove() {} },
      quote: { textContent: "" },
      summary: { textContent: "", title: "", set innerHTML(_value) { throw new Error("Summary must remain plain text"); } },
      panel: { hidden: true },
      transcript: { update() {} },
      status: { dataset: {}, textContent: "" },
      inputLabel: { textContent: "" },
      input: { value: "", style: {}, scrollHeight: 44 },
      cancel: { hidden: true },
      model: { value: "" },
      send: { disabled: false },
    };
    const controller = {
      render: ParagraphChatController.prototype.render,
      renderModels() {},
      updateSend() {},
      renderAccount() {},
      schedule() {},
      nodes: new Map([[convId, node]]),
      state: { records: new Map([[convId, record]]) },
      unresolved: { append() {}, hidden: false },
      article: { querySelector() { return null; } },
      drafts: new Map(),
      accountSettings: {},
    };

    controller.render();

    assert.equal(node.summary.textContent, expected);
    assert.equal(node.summary.title, expected);
  }
});


test("local capsule searches nearby ink edges and preserves a safe prior placement", () => {
  const base = { edge: 900, start: 0, anchor: { left: 256, right: 300, top: 100, bottom: 144 }, viewport: { right: 1280 }, height: 200, obstacles: [] };
  assert.equal(panelPosition(base).left, 316);
  assert.equal(panelPosition({ ...base, obstacles: [{ left: 0, right: 1000, top: 95, bottom: 130 }] }).top, 138);
  assert.equal(panelPosition({ ...base, previous: { left: 60, top: 50 } }).top, 150);
  assert.equal(panelPosition({ ...base, obstacles: [{ left: 0, right: 1200, top: -500, bottom: 900 }] }), null);
  assert.equal(panelPosition({ ...base, anchor: { left: 0, right: 44, top: 100, bottom: 144 }, obstacles: [{ left: 0, right: 600, top: -500, bottom: 900 }] }), null);
});
