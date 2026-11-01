import {
  ConversationState,
  conversationSummary,
  sameChatSnapshot,
} from "../../reader-common/paragraph-chat/state.js";
import { bubblePosition, documentInk } from "./geometry.js";

const element = (tag, text, className) => {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  if (className) node.className = className;
  return node;
};

/** HTML and terminal share this adapter, transport and host-owned history. */
export class ParagraphChatController {
  constructor(article, view, transport) {
    Object.assign(this, { article, view, transport });
    this.state = new ConversationState();
    this.nodes = new Map();
    this.drafts = new Map();
    this.queues = new Map();
    this.pending = false;
    this.account = { notice: "Continue with ChatGPT on this Mac before sending." };
    this.models = [];
    this.article.classList.add("reader-paragraph-chat");
    this.unresolved = element("section", "", "reader-chat reader-chat-unresolved");
    this.unresolved.setAttribute("aria-label", "Unresolved paragraph conversations");
    this.unresolved.hidden = true;
    article.after(this.unresolved);
    this.resize = new ResizeObserver(() => this.schedule());
    this.resize.observe(article);
    this.mutations = new MutationObserver((changes) => {
      if (changes.some((change) => !change.target.closest?.(".reader-chat"))) this.schedule();
    });
    this.mutations.observe(article, { childList: true, subtree: true });
    this.reflow = () => this.schedule();
    window.addEventListener("resize", this.reflow);
    document.fonts?.addEventListener("loadingdone", this.reflow);
    this.exit = () => this.flushDrafts();
    window.addEventListener("pagehide", this.exit);
  }

  identity() {
    return this.state.snapshot && { ...this.state.snapshot };
  }

  onDocument(manifest) {
    if (!manifest || this.disposed) return;
    if (!this.state.document(manifest)) return this.schedule();
    this.stream?.abort();
    this.watching = false;
    this.ticket = null;
    this.clearNodes();
    this.reload();
  }

  async reload() {
    const generation = this.state.generation;
    try {
      const result = await this.transport.post("api/chat/list", this.identity(), 15000);
      if (!this.state.accept(result, generation)) return;
      this.render();
      if (result.conversations.some((record) => record.status === "streaming")) this.watch();
    } catch {
      if (generation === this.state.generation && this.nodes.size)
        this.view.announce("Chat history is unavailable. Your draft remains in this view.");
    }
  }

  dismiss() {
    this.ticket = null;
  }

  async submit(selected) {
    if (!selected || !this.state.snapshot || this.pending || !this.view.enabled("ask")) return;
    const identity = this.identity();
    if (
      !sameChatSnapshot(identity, {
        ...identity,
        revision: selected[0].revision,
        service: selected[0].service,
      })
    ) {
      this.view.announce("문서나 Reader 연결이 변경되었습니다. 갱신 후 다시 선택해 주세요.");
      return;
    }
    const ticket = (this.ticket = {});
    this.pending = true;
    this.view.changed();
    try {
      const result = await this.transport.post(
        "api/chat/open",
        { ...identity, fragments: selected },
        15000,
      );
      if (
        !this.state.accept(result) ||
        this.ticket !== ticket ||
        !this.view.sameSelection(selected, this.view.selection())
      )
        return;
      this.render();
      const id = result.conversations[0].conversation_id;
      // Release only the selection that initiated this composer.
      this.view.collapse();
      this.open(id, true);
      this.loadAccount();
    } catch {
      if (this.ticket === ticket) this.view.retain(selected);
      this.view.announce(
        "Could not open chat. Wait for any running response or interrupt it before reselecting; otherwise refresh and select again.",
      );
    } finally {
      this.pending = false;
      this.view.changed();
    }
  }

  create(record) {
    const id = record.conversation_id;
    const root = element("section", "", "reader-chat");
    root.dataset.conversationId = id;
    root.dataset.flowSelectionIgnore = "paragraph-chat";
    root.setAttribute("aria-label", "Paragraph conversation");
    const summary = element("button", "", "reader-chat-summary");
    summary.type = "button";
    summary.setAttribute("aria-expanded", "false");
    const panel = element("div", "", "reader-chat-panel");
    panel.id = `reader-chat-${id}`;
    panel.hidden = true;
    summary.setAttribute("aria-controls", panel.id);
    const quote = element("blockquote", record.quote);
    const messages = element("div", "", "reader-chat-messages");
    const status = element("p", "", "reader-chat-status");
    status.setAttribute("role", "status");
    const account = element("div", "", "reader-chat-account");
    const form = element("form");
    const input = element("textarea");
    input.setAttribute("aria-label", "Question about this paragraph");
    input.placeholder = "Ask about this paragraph…";
    input.maxLength = 8000;
    input.rows = 2;
    input.value = this.drafts.get(id) ?? record.draft;
    const send = element("button", "Send");
    send.type = "submit";
    const cancel = element("button", "Interrupt");
    cancel.type = "button";
    cancel.addEventListener("click", () => this.action(id, "cancel"));
    const close = element("button", "Close conversation");
    close.type = "button";
    close.addEventListener("click", () => this.close(id));
    const model = element("select");
    model.setAttribute("aria-label", "ChatGPT model");
    form.append(input, model, send, cancel);
    panel.append(quote, messages, status, account, form, close);
    root.append(summary, panel);
    summary.addEventListener("click", () => (panel.hidden ? this.open(id) : this.close(id)));
    root.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && !panel.hidden) {
        event.stopPropagation();
        event.preventDefault();
        this.close(id);
      }
    });
    // Native button Enter/Space and click cover keyboard, pointer and touch.
    input.addEventListener("input", () => {
      this.drafts.set(id, input.value);
      clearTimeout(node.draftTimer);
      node.draftTimer = setTimeout(() => this.action(id, "draft", { draft: input.value }), 250);
    });
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (!send.disabled) this.send(id);
    });
    const node = {
      root,
      summary,
      panel,
      quote,
      messages,
      status,
      account,
      form,
      input,
      send,
      cancel,
      model,
    };
    this.nodes.set(id, node);
    return node;
  }

  open(id, focus = false) {
    const node = this.nodes.get(id);
    if (!node) return;
    node.panel.hidden = false;
    node.summary.setAttribute("aria-expanded", "true");
    node.root.classList.remove("reader-chat-margin");
    node.summary.style.cssText = "";
    if (focus) node.input.focus({ preventScroll: true });
    else node.panel.querySelector("textarea")?.focus({ preventScroll: true });
    this.loadAccount();
    this.reload();
    this.schedule();
  }

  close(id) {
    const node = this.nodes.get(id);
    if (!node) return;
    node.panel.hidden = true;
    node.summary.setAttribute("aria-expanded", "false");
    node.summary.focus({ preventScroll: true });
    this.schedule();
  }

  render() {
    if (this.disposed) return;
    let unresolved = false;
    for (const record of this.state.records.values()) {
      const id = record.conversation_id;
      let node = this.nodes.get(id);
      if (!node) node = this.create(record);
      const attachment = record.attachment;
      const host =
        attachment.state === "attached" &&
        this.article.querySelector(`[data-reader-key="${CSS.escape(attachment.key)}"]`);
      if (attachment.state === "unresolved") {
        unresolved = true;
        if (node.root.parentNode !== this.unresolved) this.unresolved.append(node.root);
      } else if (host) {
        if (host.nextElementSibling !== node.root) host.after(node.root);
      } else {
        // Unmounted sections keep history and drafts without inventing an anchor.
        node.root.remove();
      }
      node.host = host;
      if (node.quote.textContent !== record.quote) node.quote.textContent = record.quote;
      const title = conversationSummary(record);
      if (node.summary.textContent !== title) node.summary.textContent = title;
      node.summary.title = title;
      const text = record.thread
        .map(
          (message) =>
            `${message.role === "user" ? `You [${message.revision}; selected: ${message.context?.selection ?? "unavailable"}]` : "Answer"}${message.status === "completed" ? "" : ` (${message.status})`}: ${message.text}`,
        )
        .join("\n\n");
      if (node.messages.textContent !== text) node.messages.textContent = text;
      const notice =
        attachment.state === "unresolved"
          ? `Unresolved (${attachment.reason}). History is retained. `
          : "";
      const status = `${notice}${record.status}: ${record.progress}`;
      if (node.status.textContent !== status) node.status.textContent = status;
      if (
        !this.drafts.has(id) &&
        document.activeElement !== node.input &&
        node.input.value !== record.draft
      )
        node.input.value = record.draft;
      node.send.disabled =
        record.status === "streaming" || attachment.state !== "attached" || !node.model.value;
      node.cancel.hidden = record.status !== "streaming";
      this.renderAccount(node);
    }
    this.unresolved.hidden = !unresolved;
    this.schedule();
  }

  renderAccount(node) {
    const signature = JSON.stringify([this.account, this.models]);
    if (node.accountSignature === signature) return;
    node.accountSignature = signature;
    const notice = element(
      "p",
      this.account.notice || (this.account.signedIn ? "Signed in with ChatGPT" : ""),
    );
    const picker = element("select");
    picker.setAttribute("aria-label", "Saved ChatGPT account or new registration");
    picker.hidden = Boolean(this.account.hostOnly);
    picker.append(element("option", "New ChatGPT account"));
    picker.firstChild.value = "";
    for (const account of this.account.accounts ?? []) {
      const option = element("option", account.label);
      option.value = account.id;
      option.selected = account.id === this.account.active;
      picker.append(option);
    }
    const login = element("button", "Continue with ChatGPT");
    login.type = "button";
    login.setAttribute("data-oai-siwc-button", "");
    login.disabled = Boolean(this.account.hostOnly);
    login.addEventListener("click", async () => {
      try {
        const result = await this.auth("login", { registration: picker.value || null });
        // Only the authorization URL, never tokens, is returned to this host UI.
        const link = element("a", "Open ChatGPT sign-in in this Mac's browser");
        const url = new URL(result.authUrl);
        if (url.protocol !== "https:" || url.hostname !== "auth.openai.com") throw new Error();
        link.href = this.loginURL = url.href;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        node.account.append(link);
        this.pollAccount();
      } catch (error) {
        node.status.textContent = error.message || "Sign-in could not start";
      }
    });
    const logout = element("button", "Sign out");
    logout.type = "button";
    logout.hidden = !this.account.signedIn || this.account.hostOnly;
    logout.addEventListener("click", async () => {
      try {
        await this.auth("logout");
        this.models = [];
        await this.loadAccount();
      } catch {
        node.status.textContent = "Sign-out could not complete. Try again.";
      }
    });
    const refresh = element("button", "Check sign-in / models");
    refresh.type = "button";
    refresh.addEventListener("click", () => this.loadAccount(true));
    node.account.replaceChildren(notice, picker, login, logout, refresh);
    if (!this.account.hostOnly) {
      const capability = element("input");
      capability.type = "password";
      capability.autocomplete = "off";
      capability.setAttribute("aria-label", "Host authorization token");
      capability.placeholder = "Paste the local host authorization token";
      capability.value = this.hostCapability || "";
      capability.addEventListener("input", () => {
        this.hostCapability = capability.value;
      });
      node.account.append(capability);
      if (this.account.hostCapabilityFile)
        node.account.append(
          element(
            "p",
            `For sign-in management, copy the capability value from this Mac's local file: ${this.account.hostCapabilityFile}`,
          ),
        );
    }
    if (this.loginURL && this.account.pending) {
      const link = element("a", "Open ChatGPT sign-in in this Mac's browser");
      link.href = this.loginURL;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      const cancel = element("button", "Cancel sign-in");
      cancel.type = "button";
      cancel.addEventListener("click", async () => {
        await this.auth("cancel");
        await this.loadAccount();
      });
      node.account.append(link, cancel);
    }
    const current = node.model.value;
    const placeholder = element("option", "Choose a model");
    placeholder.value = "";
    node.model.replaceChildren(
      placeholder,
      ...this.models.map((model) => {
        const option = element("option", model.label);
        option.value = model.id;
        return option;
      }),
    );
    node.model.value = this.models.some((model) => model.id === current) ? current : "";
    node.model.onchange = () => {
      const record = this.state.records.get(node.root.dataset.conversationId);
      node.send.disabled =
        !node.model.value ||
        record.status === "streaming" ||
        record.attachment.state !== "attached";
    };
  }

  async auth(operation, extra = {}) {
    const headers = { "Content-Type": "application/json" };
    if (["login", "logout", "cancel"].includes(operation)) {
      if (!this.hostCapability) throw new Error("Paste the local host authorization token first.");
      headers["X-Reader-Host-Capability"] = this.hostCapability;
    }
    const response = await fetch("api/chat/auth", {
      method: "POST",
      headers,
      body: JSON.stringify({ ...this.identity(), operation, ...extra }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "Account action failed");
    return result;
  }

  async loadAccount(models = false) {
    if (this.loadingAccount || !this.state.snapshot) return;
    this.loadingAccount = true;
    const generation = this.state.generation;
    try {
      const status = await this.auth("status");
      if (generation !== this.state.generation) return;
      this.account = status;
      if ((models || !this.models.length) && status.planEnabled) {
        const result = await this.auth("models");
        if (generation !== this.state.generation) return;
        this.models = result.models;
      }
      this.render();
    } catch (error) {
      if (generation === this.state.generation) {
        this.account = { ...this.account, notice: error.message };
        this.render();
      }
    } finally {
      this.loadingAccount = false;
    }
  }

  pollAccount() {
    clearTimeout(this.accountTimer);
    this.accountTimer = setTimeout(async () => {
      await this.loadAccount();
      if (!this.disposed && this.account.pending) this.pollAccount();
    }, 1500);
  }

  action(id, operation, extra = {}) {
    const identity = this.identity();
    const generation = this.state.generation;
    const previous = this.queues.get(id) ?? Promise.resolve();
    const next = previous
      .catch(() => {})
      .then(async () => {
        if (this.disposed || generation !== this.state.generation) return false;
        const record = this.state.records.get(id);
        const result = await this.transport.post(
          `api/chat/${operation}`,
          { ...identity, conversationID: id, version: record.version, ...extra },
          15000,
        );
        if (!this.state.accept(result, generation)) return false;
        if (operation === "draft" && this.drafts.get(id) === extra.draft) this.drafts.delete(id);
        this.render();
        return true;
      })
      .catch(async () => {
        if (!this.disposed && generation === this.state.generation) {
          await this.reload();
          if (operation === "send") {
            const record = this.state.records.get(id);
            const index = record?.thread.findIndex((message) => message.id === extra.messageID);
            if (index >= 0 && record.thread[index].text === extra.question) {
              if (record.thread[index + 1]?.status === "completed") {
                if (this.drafts.get(id) === extra.question) this.drafts.delete(id);
                const node = this.nodes.get(id);
                if (node?.input.value === extra.question) node.input.value = "";
              }
              return true; // Recover the accepted message, never automatically resend it.
            }
          }
          const node = this.nodes.get(id);
          if (node)
            node.status.textContent =
              "Chat request failed. Draft retained; check connection and retry.";
        }
        return false;
      });
    this.queues.set(id, next);
    return next;
  }

  async send(id) {
    const node = this.nodes.get(id);
    clearTimeout(node.draftTimer);
    const question = node.input.value;
    if (!question.trim()) return;
    if (!node.pendingMessage || node.pendingMessage.question !== question)
      node.pendingMessage = { question, id: crypto.randomUUID() };
    this.drafts.set(id, question);
    node.send.disabled = true;
    const ok = await this.action(id, "send", {
      question,
      model: node.model.value,
      messageID: node.pendingMessage.id,
    });
    if (ok) {
      node.pendingMessage = null;
      this.watch();
    } else this.render();
  }

  async watch() {
    if (this.watching || this.disposed) return;
    this.watching = true;
    const generation = this.state.generation;
    const controller = (this.stream = new AbortController());
    try {
      do {
        const response = await fetch("api/chat/events", {
          method: "POST",
          signal: controller.signal,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(this.identity()),
        });
        if (!response.ok) throw new Error();
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let pending = "";
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          pending += decoder.decode(value, { stream: true });
          let end;
          while ((end = pending.indexOf("\n\n")) >= 0) {
            const frame = pending.slice(0, end);
            pending = pending.slice(end + 2);
            if (frame.startsWith("event: stale")) throw new Error();
            if (frame.startsWith("data: ")) {
              const result = JSON.parse(frame.slice(6));
              if (!this.state.accept(result, generation)) return;
              for (const record of result.conversations) {
                if (
                  record.status === "completed" &&
                  this.drafts.get(record.conversation_id) ===
                    record.thread.findLast((message) => message.role === "user")?.text
                ) {
                  this.drafts.delete(record.conversation_id);
                  const node = this.nodes.get(record.conversation_id);
                  if (
                    node &&
                    node.input.value === record.thread.findLast((m) => m.role === "user")?.text &&
                    !record.draft
                  )
                    node.input.value = "";
                }
              }
              this.render();
            }
          }
        }
      } while (
        !controller.signal.aborted &&
        [...this.state.records.values()].some((record) => record.status === "streaming")
      );
    } catch {
      if (!controller.signal.aborted && generation === this.state.generation)
        this.view.announce(
          "Chat stream disconnected. History and drafts are saved; reopen to retry.",
        );
    } finally {
      if (this.stream === controller) this.watching = false;
    }
  }

  schedule() {
    if (this.frame || this.disposed) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.layout();
    });
  }

  layout() {
    // Remount only when a previously absent section appears.
    for (const record of this.state.records.values()) {
      const node = this.nodes.get(record.conversation_id);
      if (!node || record.attachment.state !== "attached") continue;
      const host = this.article.querySelector(
        `[data-reader-key="${CSS.escape(record.attachment.key)}"]`,
      );
      if (host && !node.root.isConnected) {
        host.after(node.root);
        node.host = host;
      }
    }
    // A fallback's own reserved row must not create its next margin candidate.
    for (const node of this.nodes.values()) {
      if (node.panel.hidden && node.host?.isConnected)
        node.root.classList.add("reader-chat-margin");
    }
    const style = getComputedStyle(this.article);
    const area = this.article.getBoundingClientRect();
    const edge = area.right - parseFloat(style.paddingRight);
    const obstacles = documentInk(this.article);
    for (const node of this.nodes.values()) {
      if (!node.root.isConnected || !node.host?.isConnected) continue;
      if (!node.panel.hidden) continue;
      const size = node.summary.getBoundingClientRect();
      const box =
        window.innerWidth >= 960 &&
        bubblePosition({
          edge,
          width: size.width,
          height: size.height,
          paragraph: node.host.getBoundingClientRect(),
          viewport: { left: 0, right: document.documentElement.clientWidth },
          obstacles,
        });
      node.root.classList.toggle("reader-chat-margin", Boolean(box));
      if (box) {
        const origin = node.summary.offsetParent.getBoundingClientRect();
        const left = `${box.left - origin.left}px`,
          top = `${box.top - origin.top}px`;
        if (node.summary.style.left !== left) node.summary.style.left = left;
        if (node.summary.style.top !== top) node.summary.style.top = top;
        obstacles.push(box);
      } else if (node.summary.style.left) node.summary.style.cssText = "";
    }
  }

  flushDrafts() {
    for (const [id, draft] of this.drafts) {
      const record = this.state.records.get(id);
      if (!record) continue;
      void fetch("api/chat/draft", {
        method: "POST",
        keepalive: true,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          ...this.identity(),
          conversationID: id,
          version: record.version,
          draft,
        }),
      }).catch(() => {});
    }
  }

  clearNodes() {
    for (const node of this.nodes.values()) {
      clearTimeout(node.draftTimer);
      node.root.remove();
    }
    this.nodes.clear();
    this.unresolved.hidden = true;
  }

  dispose() {
    this.dismiss();
    this.flushDrafts();
    this.disposed = true;
    this.stream?.abort();
    clearTimeout(this.accountTimer);
    cancelAnimationFrame(this.frame);
    this.resize.disconnect();
    this.mutations.disconnect();
    window.removeEventListener("resize", this.reflow);
    window.removeEventListener("pagehide", this.exit);
    document.fonts?.removeEventListener("loadingdone", this.reflow);
    this.clearNodes();
    this.unresolved.remove();
  }
}
