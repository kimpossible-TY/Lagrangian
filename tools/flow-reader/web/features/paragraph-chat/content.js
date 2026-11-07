import "../../vendor/markdown-it-12.3.2/markdown-it.min.js";
import { loadMathJax } from "../../rendering/math/loader.js";

// Parse Markdown into tokens, then construct only the small set of DOM nodes
// below. Model output is never passed to innerHTML or the document renderer.
const markdown = globalThis.markdownit({ html: false, linkify: false, maxNesting: 20 });
const mathLimit = 8000;

function inlineMath(state, silent) {
  const start = state.pos;
  const source = state.src;
  const opening = source.startsWith("\\(", start) ? "\\(" : source[start] === "$" ? "$" : null;
  if (!opening || (opening === "$" && /[\s$]/u.test(source[start + 1] || " "))) return false;
  const closing = opening === "$" ? "$" : "\\)";
  let end = start + opening.length;
  for (;;) {
    end = source.indexOf(closing, end);
    if (end < 0 || end - start > mathLimit) {
      if (!silent) state.push("text", "", 0).content = opening;
      state.pos = start + opening.length;
      return true;
    }
    let slashes = 0;
    for (let i = end - 1; source[i] === "\\"; i--) slashes++;
    if (slashes % 2 === 0) break;
    end += closing.length;
  }
  const value = source.slice(start + opening.length, end);
  if (!value.trim() || value.includes("\n") || (opening === "$" && /\s/u.test(value.at(-1))))
    return false;
  if (!silent) {
    const token = state.push("reader_math", "", 0);
    token.content = value;
    token.markup = opening;
  }
  state.pos = end + closing.length;
  return true;
}

function blockMath(state, startLine, endLine, silent) {
  const start = state.bMarks[startLine] + state.tShift[startLine];
  const opening = state.src.startsWith("$$", start)
    ? "$$"
    : state.src.startsWith("\\[", start)
      ? "\\["
      : null;
  if (!opening || state.sCount[startLine] >= 4) return false;
  const closing = opening === "$$" ? "$$" : "\\]";
  const end = state.src.indexOf(closing, start + opening.length);
  if (end < 0 || end - start > mathLimit || end >= (state.bMarks[endLine] ?? state.src.length))
    return false;
  let next = startLine;
  while (next < endLine && state.eMarks[next] < end + closing.length) next++;
  if (state.src.slice(end + closing.length, state.eMarks[next]).trim()) return false;
  if (silent) return true;
  const token = state.push("reader_math_block", "", 0);
  token.block = true;
  token.markup = opening;
  token.content = state.src.slice(start + opening.length, end).trim();
  token.map = [startLine, next + 1];
  state.line = next + 1;
  return true;
}

markdown.inline.ruler.before("escape", "reader_math", inlineMath);
markdown.block.ruler.before("fence", "reader_math_block", blockMath, {
  alt: ["paragraph", "reference", "blockquote", "list"],
});

export { stripMathDelimiters } from "../../reader-common/paragraph-chat/state.js";

export function safeChatLink(value) {
  try {
    const url = new URL(value);
    return ["https:", "http:", "mailto:"].includes(url.protocol) && !url.username && !url.password
      ? url.href
      : null;
  } catch {
    return null;
  }
}

export function chatTokens(source) {
  return markdown.parse(source, {});
}

const allowed = new Set([
  "p",
  "em",
  "strong",
  "s",
  "blockquote",
  "ul",
  "ol",
  "li",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "table",
  "thead",
  "tbody",
  "tr",
  "th",
  "td",
]);
function appendTokens(parent, tokens) {
  const document = parent.ownerDocument;
  const stack = [parent];
  const append = (node) => stack.at(-1).append(node);
  for (const token of tokens) {
    if (token.type === "inline") appendTokens(stack.at(-1), token.children || []);
    else if (["reader_math", "reader_math_block"].includes(token.type)) {
      const node = document.createElement(token.block ? "div" : "span");
      node.className = "reader-chat-math";
      node.dataset.tex = token.content;
      node.dataset.display = String(Boolean(token.block));
      const opening = token.markup || (token.block ? "\\[" : "\\(");
      const closing = opening === "$" || opening === "$$" ? opening : token.block ? "\\]" : "\\)";
      node.textContent = opening + token.content + closing;
      append(node);
    } else if (token.type === "text" || token.type === "softbreak")
      append(document.createTextNode(token.type === "softbreak" ? "\n" : token.content));
    else if (token.type === "hardbreak" || token.type === "hr")
      append(document.createElement(token.type === "hr" ? "hr" : "br"));
    else if (["fence", "code_block", "code_inline"].includes(token.type)) {
      const code = document.createElement("code");
      code.textContent = token.content;
      if (token.type === "code_inline") append(code);
      else {
        const pre = document.createElement("pre");
        pre.append(code);
        append(pre);
      }
    } else if (token.type === "image") append(document.createTextNode(token.content));
    else if (token.nesting === 1) {
      const link = token.type === "link_open";
      const tag = link ? "a" : allowed.has(token.tag) ? token.tag : "span";
      const node = document.createElement(/^h[1-6]$/u.test(tag) ? "h4" : tag);
      if (link) {
        const href = safeChatLink(token.attrGet("href"));
        if (href) {
          node.href = href;
          node.target = "_blank";
          node.rel = "noopener noreferrer";
        }
      }
      if (tag === "ol" && /^\d{1,6}$/u.test(token.attrGet("start") || ""))
        node.start = Number(token.attrGet("start"));
      append(node);
      stack.push(node);
    } else if (token.nesting === -1 && stack.length > 1) stack.pop();
    else if (token.content) append(document.createTextNode(token.content));
  }
}

const generations = new WeakMap();
// Only base + AMS TeX are loaded. No autoload, require, HTML, URL, image or
// user-defined extension packages can run from model-provided mathematics.
const forbiddenTex =
  /\\(?:href|url|style|class|cssId|html\w*|includegraphics|require|def|gdef|newcommand|renewcommand|label|tag)\b/u;
export async function renderChatContent(container, text, { complete = true } = {}) {
  const ticket = {};
  generations.set(container, ticket);
  container.replaceChildren();
  if (text.length > 120000) {
    container.textContent = text;
    return;
  }
  appendTokens(container, chatTokens(text));
  if (!complete) return;
  const maths = [...container.querySelectorAll(".reader-chat-math")];
  if (!maths.length) return;
  try {
    const mathjax = await loadMathJax();
    for (const node of maths) {
      if (generations.get(container) !== ticket || !container.isConnected) return;
      const tex = node.dataset.tex;
      if (tex.length > mathLimit || forbiddenTex.test(tex)) continue;
      try {
        const result = await mathjax.tex2chtmlPromise(tex, {
          ...mathjax.getMetricsFor(node, node.dataset.display === "true"),
          display: node.dataset.display === "true",
        });
        if (generations.get(container) !== ticket || !container.isConnected) return;
        if (result.querySelector("mjx-merror")) continue;
        // Defense in depth: the supported mathematical vocabulary has no links
        // or embedded content. Preserve the source when conversion fails.
        if (result.querySelector("a[href],img,image,foreignObject,script,iframe")) continue;
        node.replaceChildren(result);
        node.dataset.typeset = "true";
        mathjax.startup.document.reset();
        mathjax.startup.document.updateDocument();
      } catch {
        node.title = "수식 원문 · 조판하지 못했습니다";
      }
    }
  } catch {
    for (const node of maths) node.title = "수식 원문 · 조판 엔진에 연결하지 못했습니다";
  }
}

export function chatStatus(record) {
  const labels = {
    idle: "질문을 작성해 주세요",
    streaming: "답변 생성 중…",
    completed: "답변 완료",
    failed: "답변을 마치지 못했습니다. 초안을 확인하고 다시 보내세요.",
    interrupted: "답변을 중단했습니다. 부분 답변과 초안이 보존되었습니다.",
  };
  const unresolved =
    record.attachment.state === "unresolved"
      ? "문단 위치를 확인하지 못했습니다. 기록은 보존되어 있습니다. "
      : "";
  const progress = record.status === "completed" || record.status === "idle" ? "" : record.progress;
  return (
    unresolved +
    (labels[record.status] || "대화 상태 미확인 · 연결을 확인해 주세요") +
    (progress ? ` ${progress}` : "")
  );
}

/** Keyed message nodes preserve expanded context and focus during streaming. */
export class ChatTranscript {
  constructor(root) {
    this.root = root;
    this.nodes = new Map();
  }
  update(thread, { visible = true } = {}) {
    const document = this.root.ownerDocument;
    const alive = new Set();
    for (const [index, message] of thread.entries()) {
      const key = message.id || `${message.role}:${index}`;
      alive.add(key);
      let item = this.nodes.get(key);
      if (!item) {
        const root = document.createElement("article");
        root.className = "reader-chat-message";
        root.dataset.role = message.role;
        const label = document.createElement("p");
        label.className = "reader-chat-message-label";
        label.textContent = message.role === "user" ? "질문" : "답변";
        const state = document.createElement("span");
        state.className = "reader-chat-message-state";
        const content = document.createElement("div");
        content.className = "reader-chat-content";
        label.append(state);
        root.append(label, content);
        if (message.role === "user") {
          const details = document.createElement("details");
          details.className = "reader-chat-message-context";
          const summary = document.createElement("summary");
          summary.textContent = "질문 문맥 보기";
          const quote = document.createElement("blockquote");
          quote.textContent = message.context?.selection || "선택 문맥을 확인할 수 없습니다.";
          const revision = document.createElement("p");
          revision.textContent = `문서 리비전: ${message.revision || "미확인"}`;
          details.append(summary, quote, revision);
          root.append(details);
        }
        item = { root, content, state };
        this.nodes.set(key, item);
        this.root.append(root);
      }
      const signature = JSON.stringify([
        message.text,
        message.status,
        visible ? this.root.clientWidth : 0,
      ]);
      if (item.signature !== signature) {
        item.signature = signature;
        item.root.dataset.status = message.status;
        item.state.textContent =
          message.role === "assistant" && message.status !== "completed"
            ? {
                streaming: " · 생성 중",
                failed: " · 부분 답변 · 오류",
                interrupted: " · 부분 답변 · 중단됨",
              }[message.status] || " · 상태 미확인"
            : "";
        // Questions remain literal; Markdown/math belong only to answers.
        if (message.role === "user") item.content.textContent = message.text;
        else
          void renderChatContent(item.content, message.text, {
            complete: visible && message.status === "completed",
          });
      }
    }
    for (const [key, item] of this.nodes) {
      if (!alive.has(key)) {
        item.root.remove();
        this.nodes.delete(key);
      }
    }
  }
}
