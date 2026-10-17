const article = document.querySelector("#reader-document");
const status = document.querySelector("#reader-status");
const outline = document.querySelector("#reader-outline");
const menu = document.querySelector("#reader-menu");
const noteDialog = document.querySelector("#reader-note");
const storageKey = `flow-reader:${location.pathname}`;
let revision = null;
let pending = null;
let blocks = [];
let fontSize = 18;

function readStored(key, fallback) {
  try {
    return JSON.parse(localStorage.getItem(`${storageKey}:${key}`)) ?? fallback;
  } catch {
    return fallback;
  }
}
function store(key, value) {
  try {
    localStorage.setItem(`${storageKey}:${key}`, JSON.stringify(value));
  } catch {
    /* Reading still works in private mode or when storage is full. */
  }
}
function fingerprint(text) {
  let hash = 2166136261;
  for (const char of text) {
    hash ^= char.codePointAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
}
function textOf(node) {
  return node.textContent.replace(/\s+/g, " ").trim();
}

function readingAnchor() {
  const block = blocks.find((node) => node.getBoundingClientRect().bottom > 90);
  if (!block) return null;
  return {
    key: block.dataset.readerKey,
    text: textOf(block).slice(0, 180),
    offset: block.getBoundingClientRect().top - 90,
  };
}
function restoreAnchor(anchor) {
  if (!anchor) return;
  const block =
    blocks.find((node) => node.dataset.readerKey === anchor.key) ??
    blocks.find((node) => textOf(node).startsWith(anchor.text));
  if (block) window.scrollBy(0, block.getBoundingClientRect().top - 90 - anchor.offset);
}
function setFont(size) {
  const anchor = readingAnchor();
  fontSize = Math.max(14, Math.min(30, size));
  document.documentElement.style.setProperty("--reader-font-size", `${fontSize}px`);
  document.querySelector("#reader-size").value = fontSize;
  document.querySelector("#reader-smaller").disabled = fontSize === 14;
  document.querySelector("#reader-larger").disabled = fontSize === 30;
  store("fontSize", fontSize);
  requestAnimationFrame(() => restoreAnchor(anchor));
}

function noteGroup(after) {
  let group = after.nextElementSibling;
  if (!group?.classList.contains("flow-notes")) {
    group = document.createElement("details");
    group.className = "flow-notes";
    const summary = document.createElement("summary");
    summary.textContent = "수식 해설";
    group.append(summary);
    after.after(group);
  }
  return group;
}

function prepareNotes(root) {
  const marks = new Map();
  let noteNumber = 0;
  // Traverse in document order: a repeated tag resolves to its preceding mark.
  const nodes = [...root.querySelectorAll("[data-flow-mark], [data-flow-targets]")];
  for (const node of nodes) {
    if (node.hasAttribute("data-flow-mark")) {
      marks.set(node.dataset.flowMark, node);
      continue;
    }
    const targets = JSON.parse(node.dataset.flowTargets);
    const destination = node.closest(".flow-equation") ?? node.closest("p") ?? node;
    const group = noteGroup(destination);
    const note = document.createElement("div");
    note.className = "flow-note";
    note.id = `reader-note-${++noteNumber}`;
    note.append(...node.childNodes);
    if (node.dataset.flowDiagnostic) {
      note.classList.add("flow-unresolved");
      note.dataset.flowDiagnostic = node.dataset.flowDiagnostic;
    }
    group.append(note);
    for (const target of targets) {
      const mark = marks.get(target);
      if (!mark) continue;
      const ids = (mark.dataset.readerNote ?? "").split(" ").filter(Boolean);
      ids.push(note.id);
      mark.dataset.readerNote = ids.join(" ");
      mark.setAttribute("tabindex", "0");
      mark.setAttribute("role", "button");
      mark.setAttribute("aria-label", `${textOf(mark) || "표시된 수식"}: 해설 보기`);
      mark.setAttribute("aria-haspopup", "dialog");
    }
    // Empty MathML token containers would otherwise retain unwanted spacing.
    const parent = node.parentElement;
    node.remove();
    if (parent?.localName === "mtext" && !parent.childNodes.length) parent.remove();
  }
}

function indexDocument() {
  let heading = "document";
  const counts = new Map();
  blocks = [...article.querySelectorAll("h1,h2,h3,h4,h5,p,.flow-equation,figcaption")].filter(
    (node) => !node.closest("svg,math,.flow-notes,nav"),
  );
  for (const node of blocks) {
    if (/^H[1-5]$/.test(node.tagName)) heading = node.id || fingerprint(textOf(node));
    const base = node.id || `${heading}-${fingerprint(textOf(node))}`;
    const count = (counts.get(base) ?? 0) + 1;
    counts.set(base, count);
    node.dataset.readerKey = `${base}:${count}`;
    if (!node.id) node.id = `reader-block-${base}-${count}`;
  }
  outline.replaceChildren();
  for (const node of article.querySelectorAll("h1,h2,h3,h4")) {
    if (!node.id || node.closest("nav")) continue;
    const link = document.createElement("a");
    link.href = `#${encodeURIComponent(node.id)}`;
    link.textContent = textOf(node);
    link.dataset.level = node.tagName[1];
    outline.append(link);
  }
}

function containWideMathematics(root) {
  for (const math of root.querySelectorAll("math")) {
    if (math.closest("svg,.flow-equation") || math.parentElement.closest("math")) continue;
    const container = document.createElement("span");
    container.className = "flow-inline-equation";
    math.replaceWith(container);
    container.append(math);
  }
}

function selectionActive() {
  return !window.getSelection()?.isCollapsed || noteDialog.open;
}

function renderDocument(html, nextRevision) {
  if (selectionActive()) {
    pending = { html, revision: nextRevision };
    return;
  }
  const anchor = revision ? readingAnchor() : readStored("position", null);
  const parsed = new DOMParser().parseFromString(html, "text/html");
  // Typst output is document content; it does not control the reader shell.
  parsed.querySelectorAll("script,iframe,object,embed,form,base").forEach((node) => node.remove());
  for (const node of parsed.querySelectorAll("*")) {
    for (const attribute of [...node.attributes]) {
      if (
        /^on/i.test(attribute.name) ||
        (/^(href|src|xlink:href)$/i.test(attribute.name) &&
          /^\s*javascript:/i.test(attribute.value))
      ) {
        node.removeAttribute(attribute.name);
      }
    }
  }
  document
    .querySelector("#reader-document-styles")
    .replaceChildren(...parsed.head.querySelectorAll("style"));
  prepareNotes(parsed.body);
  containWideMathematics(parsed.body);
  article.replaceChildren(...parsed.body.childNodes);
  document.title = parsed.title ? `${parsed.title} · Flow Reader` : "Flow Reader";
  indexDocument();
  article.setAttribute("aria-busy", "false");
  const firstLoad = !revision;
  revision = nextRevision;
  pending = null;
  requestAnimationFrame(() => {
    if (firstLoad && location.hash)
      document.getElementById(decodeURIComponent(location.hash.slice(1)))?.scrollIntoView();
    else restoreAnchor(anchor);
  });
}

function showNote(mark) {
  const notes = mark.dataset.readerNote
    .split(" ")
    .map((id) => document.getElementById(id))
    .filter(Boolean);
  const body = document.querySelector("#reader-note-body");
  body.replaceChildren(...notes.map((note) => note.cloneNode(true)));
  body.querySelectorAll("[id]").forEach((node) => node.removeAttribute("id"));
  noteDialog.showModal();
}
article.addEventListener("click", (event) => {
  const mark = event.target.closest("[data-reader-note]");
  if (mark && window.getSelection()?.isCollapsed) showNote(mark);
});
article.addEventListener("keydown", (event) => {
  const mark = event.target.closest("[data-reader-note]");
  if (mark && (event.key === "Enter" || event.key === " ")) {
    event.preventDefault();
    showNote(mark);
  }
});
document.querySelector("#reader-note-close").addEventListener("click", () => noteDialog.close());
document.querySelector("#reader-smaller").addEventListener("click", () => setFont(fontSize - 2));
document.querySelector("#reader-larger").addEventListener("click", () => setFont(fontSize + 2));
menu.addEventListener("click", () => {
  outline.hidden = !outline.hidden;
  menu.setAttribute("aria-expanded", !outline.hidden);
});
outline.addEventListener("click", (event) => {
  if (event.target.closest("a")) {
    outline.hidden = true;
    menu.setAttribute("aria-expanded", "false");
  }
});
let saveTimer;
window.addEventListener(
  "scroll",
  () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => store("position", readingAnchor()), 300);
  },
  { passive: true },
);
window.addEventListener("pagehide", () => store("position", readingAnchor()));
setFont(Number(readStored("fontSize", 18)) || 18);

async function refresh() {
  try {
    const response = await fetch("api/state", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const state = await response.json();
    const original = document.querySelector("#reader-original");
    if (state.originalURL) {
      original.href = state.originalURL;
      original.hidden = false;
    }
    status.dataset.state = state.compiling
      ? "compiling"
      : state.exitCode
        ? "error"
        : state.contentGatePassed
          ? "ready"
          : "incomplete";
    status.textContent = state.compiling
      ? "저장된 변경 사항을 반영하는 중…"
      : state.exitCode
        ? "컴파일 오류가 있어 마지막으로 읽을 수 있었던 문서를 표시합니다."
        : state.contentGatePassed
          ? "저장된 문서 · 화면에 맞춰 읽기"
          : "개발 중인 읽기 화면입니다. 일부 그림·주석은 원본 확인이 필요합니다.";
    if (state.revision && state.revision !== revision && state.revision !== pending?.revision) {
      const documentResponse = await fetch(
        `document.html?revision=${encodeURIComponent(state.revision)}`,
      );
      if (!documentResponse.ok) throw new Error(`HTTP ${documentResponse.status}`);
      renderDocument(await documentResponse.text(), state.revision);
    }
    if (pending && !selectionActive()) renderDocument(pending.html, pending.revision);
  } catch {
    status.dataset.state = "error";
    status.textContent = revision
      ? "연결이 끊겼습니다. 현재 문서는 계속 읽을 수 있습니다."
      : "문서를 불러오지 못했습니다. 연결을 확인하고 다시 시도합니다.";
  } finally {
    setTimeout(refresh, 3000);
  }
}
refresh();
