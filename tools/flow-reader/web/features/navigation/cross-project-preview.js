import { isReturnPath } from "../../reader-common/navigation/cross-project-return.js";

/** Only canonical mounted routes can participate in tab-local Back navigation. */
export function crossProjectTarget(value, origin) {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value, origin);
    const path = url.pathname + url.search + url.hash;
    if (url.origin !== origin || url.username || url.password || url.search ||
      !/^\/d\/[a-z0-9][a-z0-9-]{0,63}\/$/u.test(url.pathname)) return null;
    // Do not let URL normalization turn traversal or network paths into routes.
    if (value.startsWith("/") ? value !== path : value !== url.href) return null;
    return isReturnPath(path) ? path : null;
  } catch {
    return null;
  }
}

function externalUrl(value) {
  try {
    const url = new URL(value);
    return ["https:", "http:"].includes(url.protocol) && !url.username && !url.password
      ? url.href : null;
  } catch { return null; }
}

/** Section-relative offsets survive continuous-section mounting and parking. */
export function createCrossProjectPosition(article, {
  ready, readSection, captureAnchor, release, holdAnchor,
}) {
  const doc = article.ownerDocument;
  const view = doc.defaultView;
  const sectionNode = (id) => [...article.querySelectorAll("[data-reader-section]")]
    .find((node) => node.dataset.readerSection === id && node.dataset.sectionState === "ready");
  const available = () => ready() && article.getAttribute("aria-busy") !== "true";
  return {
    capture() {
      if (!available()) return null;
      const anchor = captureAnchor();
      const sectionId = anchor?.section ?? readSection();
      const section = sectionNode(sectionId);
      if (!section) return null;
      const location = view.location;
      return {
        path: location.pathname + location.search + location.hash,
        documentTitle: doc.title.replace(/ · Lagrangian Web Viewer$/u, ""),
        sectionId, anchor: anchor?.id || null,
        scrollOffset: -section.getBoundingClientRect().top,
      };
    },
    restore(entry) {
      if (!available()) return false;
      const section = sectionNode(entry.sectionId);
      if (!section) return false;
      release();
      const top = view.scrollY + section.getBoundingClientRect().top + entry.scrollOffset;
      if (!Number.isFinite(top)) return false;
      view.scrollTo({ top, behavior: "instant" });
      if (Math.abs(view.scrollY - top) > 1) return false;
      holdAnchor();
      article.focus({ preventScroll: true });
      // Semantic holding can adjust scroll during layout. Verify the final
      // position before allowing the pending record to be consumed.
      const restored = Math.abs(view.scrollY - top) <= 1;
      if (!restored) release();
      return restored;
    },
  };
}

export class CrossProjectPreview {
  constructor(article, { stack, returnButton, capture, restore, enabled = () => false,
    identity = () => null, request, location = article.ownerDocument.defaultView.location,
    transitionId = () => globalThis.crypto.randomUUID(),
  }) {
    Object.assign(this, { article, stack, returnButton, capture, restore, enabled,
      identity, request, location, transitionId });
    this.document = article.ownerDocument;
    this.generation = 0;
    this.listeners = [];
    const listen = (node, type, handler, options) => {
      node.addEventListener(type, handler, options);
      this.listeners.push(() => node.removeEventListener(type, handler, options));
    };
    // Run before the existing fragment adapter; explicit project metadata wins.
    listen(article, "click", (event) => this.click(event), true);
    listen(this.document, "click", (event) => {
      if ((this.card || this.controller) && !this.card?.contains(event.target) && !this.link?.contains(event.target))
        this.dismiss(Boolean(this.card?.contains(this.document.activeElement)));
    });
    listen(this.document, "keydown", (event) => {
      if (event.key === "Escape" && (this.card || this.controller)) {
        event.preventDefault();
        this.dismiss(true);
      }
    });
    listen(returnButton, "click", () => this.back());
    listen(this.document.defaultView, "pagehide", () => this.dismiss(false));
    listen(this.document.defaultView, "pageshow", (event) => {
      if (event.persisted) {
        this.dismiss(false);
        this.navigating = false;
        this.stack.reload();
        this.update();
      }
    });
    this.update();
  }

  returnPath(path) {
    return isReturnPath(path) && crossProjectTarget(new URL(path, this.location.origin).pathname, this.location.origin);
  }

  path() { return this.location.pathname + this.location.search + this.location.hash; }

  update() {
    if (this.requestIdentity !== undefined && this.requestIdentity !== this.identity())
      this.dismiss(false);
    const entry = this.stack.peek();
    this.returnButton.hidden = !this.stack.canGoBack;
    this.returnButton.textContent = entry?.documentTitle ? `← ${entry.documentTitle}` : "← 원래 문서로";
  }

  async click(event) {
    if (this.disposed || event.defaultPrevented || event.button !== 0 ||
      event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const link = event.target.closest("a");
    if (!link || !this.article.contains(link) || link.hasAttribute("download")) return;
    const explicit = link.hasAttribute("data-project-ref-project") &&
      link.hasAttribute("data-project-ref-label");
    const href = link.getAttribute("href") || "";
    let query;
    if (explicit) {
      query = new URLSearchParams({ project: link.dataset.projectRefProject, label: link.dataset.projectRefLabel });
    } else {
      if (!this.enabled() || !externalUrl(href)) return;
      const url = new URL(href);
      // Ordinary links (including fragments and links to this reader) stay native.
      if (crossProjectTarget(href, this.location.origin) || !/^#page=[1-9]\d*$/u.test(url.hash)) return;
      query = new URLSearchParams({ href });
      if (link.textContent.trim()) query.set("text", link.textContent.trim());
    }
    event.preventDefault();
    this.dismiss(false);
    this.link = link;
    const generation = this.generation;
    this.requestIdentity = this.identity();
    const controller = this.controller = new AbortController();
    if (explicit) this.show({ status: "loading" });
    try {
      const result = await this.request(`api/cross-project/preview?${query}`, { signal: controller.signal });
      if (this.disposed || generation !== this.generation || this.requestIdentity !== this.identity()) return;
      if (!link.isConnected) {
        this.dismiss(false);
        return;
      }
      if (!explicit && result.status === "unresolved") {
        this.show({ ...result, originalUrl: href, originalTarget: link.target });
        return;
      }
      this.show(result);
    } catch {
      if (generation !== this.generation || this.disposed ||
        this.requestIdentity !== this.identity() || !link.isConnected || controller.signal.aborted) return;
      // Transport timeouts also reject with AbortError, but do not abort this
      // caller's signal. Only user/lifecycle cancellation is silent.
      this.show({ status: "error", ...(!explicit && { originalUrl: href, originalTarget: link.target }) });
    }
  }

  show(result) {
    this.card?.remove();
    const card = this.document.createElement("div");
    this.card = card;
    card.className = "reader-cross-project-preview";
    card.setAttribute("role", "dialog");
    card.setAttribute("aria-label", "다른 프로젝트 참조 미리보기");
    card.tabIndex = -1;
    const add = (tag, text) => {
      const node = this.document.createElement(tag);
      node.textContent = typeof text === "string" ? text : "";
      card.append(node);
      return node;
    };
    add("strong", result.projectTitle || "프로젝트 참조");
    add("p", [result.label, result.refText || result.title].filter(Boolean).join(" · "));
    const unique = result.status === "unique";
    add("p", unique ? (result.snippet || "미리보기 본문을 사용할 수 없습니다.") : {
      loading: "참조를 확인하는 중…", ambiguous: "여러 대상이 있어 문서를 선택할 수 없습니다.",
      unresolved: "참조 대상을 찾을 수 없습니다.", error: "참조를 불러오지 못했습니다. 다시 시도해 주세요.",
    }[result.status] || "참조 대상을 확인할 수 없습니다.");
    const target = unique && crossProjectTarget(result.targetUrl, this.location.origin);
    const jump = add("button", "해당 문서로 이동");
    jump.type = "button";
    jump.setAttribute("aria-label", "해당 문서로 이동");
    jump.disabled = !target;
    if (target) {
      const navigate = () => {
        if (this.navigating || !this.card || this.disposed || this.requestIdentity !== this.identity()) return;
        const entry = this.capture();
        if (!entry || !this.returnPath(entry.path) || !this.stack.push(entry)) {
          add("p", "돌아올 위치를 저장하지 못했습니다.");
          return;
        }
        this.navigating = true;
        try { this.location.assign(target); }
        catch {
          this.navigating = false;
          this.stack.pop();
          this.update();
          add("p", "문서를 열지 못했습니다. 다시 시도해 주세요.");
        }
      };
      jump.addEventListener("click", navigate);
      card.addEventListener("click", (event) => {
        if (!event.target.closest("button,a")) navigate();
      });
    } else if (result.status !== "loading") {
      add("p", "이 대상의 웹 뷰어 경로를 사용할 수 없습니다.");
      const external = unique && externalUrl(result.targetUrl);
      const original = externalUrl(result.originalUrl);
      const fallback = original || (external && new URL(external).origin !== this.location.origin
        ? external : externalUrl(result.pdfUrl));
      if (fallback) {
        const link = add("a", original ? "원래 링크 열기" : external === fallback ? "외부 웹 뷰어 열기" : "외부 PDF 열기");
        link.href = fallback;
        link.target = original ? (result.originalTarget || "_self") : "_blank";
        link.rel = "noopener noreferrer";
      }
    }
    const close = add("button", "닫기");
    close.type = "button";
    close.addEventListener("click", () => this.dismiss(true));
    this.document.body.append(card);
    const rect = this.link.getBoundingClientRect();
    const view = this.document.defaultView;
    card.style.left = `${Math.max(8, Math.min(rect.left, view.innerWidth - card.offsetWidth - 8))}px`;
    card.style.top = `${Math.max(8, Math.min(rect.bottom + 8, view.innerHeight - card.offsetHeight - 8))}px`;
    (target ? jump : card).focus({ preventScroll: true });
  }

  back() {
    if (this.navigating || this.disposed) return;
    const entry = this.stack.peek();
    if (!entry || !this.returnPath(entry.path)) return;
    const id = this.transitionId();
    if (!this.stack.savePending(entry, id)) return;
    if (!this.stack.pop()) {
      this.stack.consumePending(entry.path, id);
      return;
    }
    this.navigating = true;
    try { this.location.assign(entry.path); }
    catch {
      this.navigating = false;
      this.stack.push(entry);
      this.stack.consumePending(entry.path, id);
    }
    this.update();
  }

  pendingReturn() { return this.stack.peekPending(this.path()); }

  restorePending(record) {
    if (this.disposed || !record || this.pendingReturn()?.transitionId !== record.transitionId) return false;
    if (!this.restore(record.entry)) return false;
    return Boolean(this.stack.consumePending(this.path(), record.transitionId));
  }

  dismiss(restoreFocus = false) {
    this.generation++;
    this.controller?.abort();
    this.controller = null;
    this.card?.remove();
    this.card = null;
    if (restoreFocus && this.link?.isConnected) this.link.focus({ preventScroll: true });
    this.link = null;
    this.requestIdentity = undefined;
  }

  dispose() {
    this.dismiss(true);
    this.disposed = true;
    for (const remove of this.listeners) remove();
    this.returnButton.hidden = true;
  }
}
