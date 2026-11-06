import { readerLink } from "../ui/reader-links.js";

const $ = (id) => document.getElementById(id);
const labels = {
  ready: "HTML 문서 준비됨",
  stopped: "서비스 중지됨",
  compiling: "문서 준비 중",
  unavailable: "읽을 문서가 아직 없습니다",
  unknown: "상태 미확인",
  stale: "이전 관찰 · 재확인 필요",
};
const icons = {
  html: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v15M12 5C8 2 4 3 2 4v15c4-2 7-1 10 1 3-2 6-3 10-1V4c-2-1-6-2-10 1Z"/></svg>',
  paged:
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 2h9l5 5v15H5ZM14 2v6h5M8 12h8M8 16h6"/></svg>',
};
const node = (tag, text, className) => {
  const result = document.createElement(tag);
  if (text) result.textContent = text;
  if (className) result.className = className;
  return result;
};
let documents = [],
  inventoryKnown = false,
  csrf = "",
  capability = "",
  management = false,
  version = -1,
  instance = "",
  generation = 0,
  disposed = false,
  timer,
  busy = false,
  polling = false;
const controllers = new Set();
const channel =
  typeof BroadcastChannel === "function" ? new BroadcastChannel("lagrangian-home-account") : null;

async function request(path, body, headers = {}) {
  const controller = new AbortController();
  controllers.add(controller);
  const timeout = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(`/api/home/${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: {
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        ...(capability ? { "X-Reader-Host-Capability": capability } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: "no-store",
      signal: controller.signal,
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "연결을 확인하지 못했습니다.");
    return result;
  } finally {
    clearTimeout(timeout);
    controllers.delete(controller);
  }
}
const documentCards = new Map();

// Leave already ordered nodes in place: removing/reinserting a focused link
// during a status poll would send keyboard focus back to the document body.
function reconcileChildren(parent, children) {
  const retained = new Set(children);
  for (const child of [...parent.children]) {
    if (!retained.has(child)) child.remove();
  }
  let next = parent.firstElementChild;
  for (const child of children) {
    if (child === next) next = next.nextElementSibling;
    else parent.insertBefore(child, next);
  }
}

function documentCard(doc) {
  let record = documentCards.get(doc.id);
  if (!record) {
    const card = node("article", "", "document-card");
    const preview = node("div", "", "preview");
    preview.setAttribute("aria-hidden", "true");
    preview.append(node("span", "∫ f(x) dx", "formula"), node("small", "READ · THINK · CONNECT"));
    const info = node("div", "", "document-info");
    const title = node("h3");
    const status = node("p", "", "document-status");
    const links = node("div", "", "reader-links");
    info.append(title, status, links);
    card.append(preview, info);
    record = { card, title, status, links, variants: new Map() };
    documentCards.set(doc.id, record);
  }
  if (record.title.textContent !== doc.name) record.title.textContent = doc.name;
  const label = labels[doc.state] || labels.unknown;
  if (record.status.textContent !== label) record.status.textContent = label;
  record.status.dataset.state = doc.state;
  const variants = [...doc.variants].sort(
    (a, b) => Number(b.kind === "html") - Number(a.kind === "html"),
  );
  const keys = new Set();
  const links = variants.map((variant, index) => {
    const key = `${variant.kind}:${index}`;
    keys.add(key);
    const title = variant.kind === "html" ? "HTML Reader" : "Paged Reader";
    const url = readerLink(variant.url);
    let item = record.variants.get(key);
    if (!item || item.linked !== Boolean(url)) {
      const element = url
        ? node("a", "", `reader-link${variant.kind === "html" ? "" : " secondary"}`)
        : node("span", `${title} · 공개 주소 없음`, "unavailable-link");
      if (url) {
        // These icons are fixed application constants, never inventory markup.
        element.innerHTML = icons[variant.kind] || "";
        element.append(document.createTextNode(title));
      }
      item = { element, linked: Boolean(url) };
      record.variants.set(key, item);
    }
    if (url) {
      if (item.element.href !== url) item.element.href = url;
      item.element.setAttribute("aria-label", `${doc.name} · ${title}`);
    }
    return item.element;
  });
  reconcileChildren(record.links, links);
  for (const key of record.variants.keys()) {
    if (!keys.has(key)) record.variants.delete(key);
  }
  return record.card;
}

function renderDocuments() {
  const query = $("document-search").value.trim().toLocaleLowerCase();
  const selected = documents.filter((doc) => doc.name.toLocaleLowerCase().includes(query));
  const list = $("document-list");
  const focused = document.activeElement;
  const hadFocus = list.contains(focused);
  $("document-count").textContent = inventoryKnown ? String(documents.length) : "";
  reconcileChildren(list, selected.map(documentCard));
  const ids = new Set(documents.map((doc) => doc.id));
  for (const id of documentCards.keys()) {
    if (!ids.has(id)) documentCards.delete(id);
  }
  if (hadFocus && document.activeElement !== focused) {
    // A removed document/destination must leave focus somewhere discoverable.
    const target = focused.isConnected && list.contains(focused) ? focused : $("documents");
    target.focus({ preventScroll: true });
  }
  if (inventoryKnown && !selected.length && !$("inventory-message").dataset.error)
    $("inventory-message").textContent = query
      ? "검색 결과가 없습니다."
      : "아직 등록된 문서가 없습니다. 이 Mac의 Reader 설정에서 문서를 등록하세요.";
  else if (selected.length && !$("inventory-message").dataset.error)
    $("inventory-message").textContent = "";
}

function adopt(result) {
  if (instance && instance !== result.instance) {
    csrf = "";
    capability = "";
    management = false;
  }
  if (instance === result.instance && result.version < version) return false;
  instance = result.instance;
  version = result.version;
  return true;
}
function renderAccount(result) {
  if (!adopt(result)) return;
  management = Boolean(result.management && csrf);
  $("account-label").textContent = result.pending
    ? "로그인 대기 중"
    : result.signedIn
      ? "연결됨"
      : "연결되지 않음";
  $("account-label").dataset.state = result.signedIn ? "connected" : "unknown";
  $("plan-label").textContent = result.planEnabled
    ? "플랜 사용 권한이 부여되었습니다. 실제 모델 사용 여부는 별도 확인이 필요합니다."
    : result.signedIn
      ? "플랜 사용 권한은 확인되지 않았습니다."
      : "ChatGPT 연결 후 문서에서 대화를 시작할 수 있어요.";
  $("account-notice").textContent = result.notice || "";
  $("management-hint").textContent = result.eligible
    ? management
      ? "이 Mac에서 관리 중"
      : "계정 관리 전에 이 Mac을 확인하세요."
    : "계정 관리는 이 Mac의 로컬 홈 화면에서 할 수 있어요. (Manage on this Mac)";
  $("unlock").hidden = !result.eligible || management;
  $("account-controls").hidden = !management;
  $("cancel").hidden = !result.pending;
  $("logout").hidden = !result.signedIn;
  $("login").hidden = Boolean(result.pending);
  if (!result.pending || !management) {
    $("login-link").hidden = true;
    $("login-link").removeAttribute("href");
  }
  const picker = $("account-picker"),
    previous = picker.value;
  const choices = [{ id: "", label: "새 ChatGPT 계정" }, ...(result.accounts || [])];
  if (JSON.stringify(choices) !== picker.dataset.choices) {
    picker.replaceChildren(
      ...choices.map((a) => {
        const option = node("option", a.label);
        option.value = a.id;
        return option;
      }),
    );
    picker.dataset.choices = JSON.stringify(choices);
    picker.value = choices.some((a) => a.id === previous) ? previous : result.active || "";
  }
  $("models").hidden = !result.planEnabled;
  if (!result.signedIn) {
    $("model-list").replaceChildren();
    $("model-notice").textContent = "";
  }
}
function unavailable() {
  capability = "";
  csrf = "";
  management = false;
  $("account-label").textContent = "상태 미확인";
  $("account-label").dataset.state = "unknown";
  $("plan-label").textContent =
    "호스트 연결을 확인하세요. 이전 연결 상태를 현재 상태로 표시하지 않습니다.";
  $("account-controls").hidden = true;
  $("unlock").hidden = true;
  $("models").hidden = true;
  $("login-link").hidden = true;
  $("model-list").replaceChildren();
}
function schedule() {
  clearTimeout(timer);
  if (!disposed && !document.hidden) timer = setTimeout(refresh, 15000);
}
async function refresh() {
  if (disposed || document.hidden || polling || busy) return;
  polling = true;
  const current = generation;
  await Promise.allSettled([
    request("documents")
      .then((result) => {
        if (disposed || current !== generation) return;
        documents = result.documents;
        inventoryKnown = !result.loading;
        $("inventory-message").textContent =
          result.error || (result.loading ? "문서 목록을 확인하는 중…" : "");
        $("inventory-message").dataset.error = result.error || "";
        renderDocuments();
        $("host-state").textContent = "연결됨";
        const html = documents.filter((d) => d.variants.some((v) => v.kind === "html"));
        const ready = html.filter((d) => d.state === "ready").length;
        $("document-state").textContent = `${ready}개 준비 · ${html.length - ready}개 그 외 상태`;
        $("last-checked").textContent = result.checkedAt
          ? new Date(result.checkedAt * 1000).toLocaleTimeString("ko-KR", {
              hour: "2-digit",
              minute: "2-digit",
            })
          : "아직 확인하지 않음";
      })
      .catch(() => {
        if (disposed || current !== generation) return;
        $("host-state").textContent = "연결 확인 필요";
        documents = documents.map((d) => ({ ...d, state: "stale" }));
        $("inventory-message").textContent = "문서 목록을 갱신하지 못했습니다. 이전 목록입니다.";
        $("inventory-message").dataset.error = "stale";
        renderDocuments();
      }),
    request("account")
      .then((result) => {
        if (!disposed && current === generation) renderAccount(result);
      })
      .catch(() => {
        if (!disposed && current === generation) unavailable();
      }),
  ]);
  polling = false;
  schedule();
}
async function change(operation) {
  if (busy || disposed) return;
  busy = true;
  generation++;
  clearTimeout(timer);
  for (const controller of controllers) controller.abort();
  const current = generation;
  for (const button of $("account-controls").querySelectorAll("button")) button.disabled = true;
  try {
    const result = await request(
      "account",
      { operation, registration: $("account-picker").value || null },
      { "X-Reader-CSRF": csrf },
    );
    if (disposed || current !== generation) return;
    if (!adopt(result)) return;
    csrf = result.csrf || "";
    if (operation === "logout") capability = "";
    const status = await request("account");
    if (disposed || current !== generation) return;
    renderAccount(status);
    if (result.authUrl) {
      const url = new URL(result.authUrl);
      if (url.origin !== "https://auth.openai.com")
        throw new Error("로그인 주소를 확인할 수 없습니다.");
      $("login-link").href = url.href;
      $("login-link").hidden = false;
    }
    $("account-notice").textContent =
      result.notice || status.notice || "이 Mac의 브라우저에서 로그인을 완료하세요.";
    channel?.postMessage("changed");
  } catch (error) {
    if (!disposed && current === generation) {
      unavailable();
      $("account-notice").textContent =
        `${error.message} 작업을 자동으로 다시 실행하지 않습니다. 상태를 새로고침하세요.`;
    }
  } finally {
    busy = false;
    for (const button of $("account-controls").querySelectorAll("button")) button.disabled = false;
    schedule();
  }
}
$("unlock").addEventListener("submit", async (event) => {
  event.preventDefault();
  if (busy) return;
  busy = true;
  generation++;
  const current = generation,
    proof = $("host-proof").value;
  $("host-proof").value = "";
  try {
    const result = await request("session", {}, { "X-Reader-Host-Capability": proof });
    if (disposed || current !== generation) return;
    if (!result.management) throw new Error("이 Mac의 확인값을 입력하세요.");
    adopt(result);
    capability = proof;
    csrf = result.csrf;
    const status = await request("account");
    if (!disposed && current === generation) renderAccount(status);
  } catch (error) {
    if (!disposed && current === generation) $("account-notice").textContent = error.message;
  } finally {
    busy = false;
    schedule();
  }
});
for (const operation of ["login", "cancel", "logout"])
  $(operation).addEventListener("click", () => change(operation));
$("models").addEventListener("click", async () => {
  const current = generation;
  $("models").disabled = true;
  try {
    const result = await request("models");
    if (disposed || current !== generation || !adopt(result)) return;
    $("model-notice").textContent = result.notice;
    $("model-list").replaceChildren(...result.models.map((m) => node("li", m.label)));
  } catch {
    if (!disposed && current === generation)
      $("model-notice").textContent = "모델 목록을 확인하지 못했습니다.";
  } finally {
    $("models").disabled = false;
  }
});
$("document-search").addEventListener("input", renderDocuments);
$("refresh").addEventListener("click", refresh);
document.addEventListener("visibilitychange", () => {
  clearTimeout(timer);
  if (document.hidden) {
    generation++;
    for (const c of controllers) c.abort();
  } else refresh();
});
window.addEventListener("pagehide", () => {
  capability = "";
  csrf = "";
  disposed = true;
  generation++;
  clearTimeout(timer);
  for (const c of controllers) c.abort();
  channel?.close();
});
window.addEventListener("pageshow", (event) => {
  if (event.persisted) location.reload();
});
window.addEventListener("offline", () => {
  generation++;
  for (const c of controllers) c.abort();
  unavailable();
  $("host-state").textContent = "오프라인";
});
window.addEventListener("online", refresh);
if (channel)
  channel.onmessage = () => {
    generation++;
    csrf = "";
    unavailable();
    refresh();
  };
refresh();
