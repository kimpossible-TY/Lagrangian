// Quotations are stored locally. DOM ranges paint them without wrapping MathML.
const excluded = "svg,script,style,nav,.flow-notes,[data-flow-targets]";

export function textIndex(block) {
  const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return !node.parentElement.closest(excluded) &&
        node.parentElement.closest("[data-reader-key]") === block
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_REJECT;
    },
  });
  let text = "";
  const points = [];
  let space = null;
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    for (let offset = 0; offset < node.data.length; offset++) {
      const point = { start: [node, offset], end: [node, offset + 1] };
      if (/\s/.test(node.data[offset])) {
        if (space) space.end = point.end;
        else space = point;
      } else {
        if (space && text) {
          text += " ";
          points.push(space);
        }
        space = null;
        text += node.data[offset];
        points.push(point);
      }
    }
  }
  return { text, points };
}

export function occurrences(text, exact) {
  const result = [];
  for (let start = text.indexOf(exact); start >= 0; start = text.indexOf(exact, start + 1)) {
    result.push(start);
  }
  return result;
}

function rangeFor(index, start, end) {
  if (!index.points[start] || !index.points[end - 1]) return null;
  const range = document.createRange();
  range.setStart(...index.points[start].start);
  range.setEnd(...index.points[end - 1].end);
  return range;
}

function validRecord(record) {
  return (
    typeof record?.id === "string" &&
    Array.isArray(record.fragments) &&
    record.fragments.length > 0 &&
    record.fragments.length <= 32 &&
    record.fragments.every(
      (part) =>
        typeof part.key === "string" &&
        part.key.length <= 128 &&
        typeof part.exact === "string" &&
        part.exact.length > 0 &&
        part.exact.length <= 20000 &&
        typeof part.prefix === "string" &&
        part.prefix.length <= 120 &&
        typeof part.suffix === "string" &&
        part.suffix.length <= 120,
    )
  );
}

export class ReaderHighlights {
  constructor(article, navigate) {
    this.article = article;
    this.navigate = navigate;
    this.records = [];
    this.locations = new Map();
    this.sequence = 0;
    this.dialog = document.querySelector("#reader-highlights");
    this.list = document.querySelector("#reader-highlights-list");
    this.action = document.querySelector("#reader-selection");
    this.message = document.querySelector("#reader-highlight-message");
    this.button = document.querySelector("#reader-highlights-open");
    this.button.disabled = false;
    this.supportsPaint = typeof Highlight === "function" && Boolean(globalThis.CSS?.highlights);
    this.button.addEventListener("click", () => {
      this.updateList();
      this.dialog.showModal();
    });
    document
      .querySelector("#reader-highlights-close")
      .addEventListener("click", () => this.dialog.close());
    document
      .querySelector("#reader-highlight-save")
      .addEventListener("pointerdown", (event) => event.preventDefault());
    document.querySelector("#reader-highlight-save").addEventListener("click", () => this.save());
    document.querySelector("#reader-selection-cancel").addEventListener("click", () => {
      window.getSelection()?.removeAllRanges();
      this.action.hidden = true;
    });
    document.addEventListener("selectionchange", () => {
      clearTimeout(this.selectionTimer);
      this.selectionTimer = setTimeout(() => this.capture(), 80);
    });
    window.addEventListener("storage", (event) => {
      if (event.key === this.storageKey) {
        this.read();
        this.resolve();
      }
    });
  }

  announce(text) {
    clearTimeout(this.messageTimer);
    this.message.textContent = text;
    this.messageTimer = setTimeout(() => {
      this.message.textContent = "";
    }, 7000);
  }

  onDocument(manifest, section) {
    this.manifest = manifest;
    this.section = section;
    this.selection = null;
    this.action.hidden = true;
    const storageKey = `flow-reader:${manifest.documentID}:highlights:v1`;
    if (storageKey !== this.storageKey) {
      this.storageKey = storageKey;
      this.read();
    }
    this.repaint();
    this.resolve();
  }

  read() {
    try {
      const value = JSON.parse(localStorage.getItem(this.storageKey));
      this.records = Array.isArray(value) ? value.filter(validRecord).slice(0, 200) : [];
    } catch {
      this.records = [];
    }
    this.locations.clear();
  }

  persist(records) {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(records));
      this.records = records;
      return true;
    } catch {
      this.announce("저장 공간을 사용할 수 없습니다. 표시를 저장하지 못했습니다.");
      return false;
    }
  }

  capture() {
    const selection = window.getSelection();
    if (
      !this.manifest ||
      !selection?.rangeCount ||
      selection.isCollapsed ||
      this.dialog.open ||
      document.querySelector("dialog[open]") ||
      !this.article.contains(selection.anchorNode) ||
      !this.article.contains(selection.focusNode)
    ) {
      if (!this.action.contains(document.activeElement)) {
        this.selection = null;
        this.action.hidden = true;
      }
      return;
    }
    const range = selection.getRangeAt(0);
    const fragments = [];
    for (const block of this.article.querySelectorAll("[data-reader-key]")) {
      if (block.closest(excluded) || !range.intersectsNode(block)) continue;
      const index = textIndex(block);
      let start = -1,
        end = -1;
      for (let i = 0; i < index.points.length; i++) {
        const point = index.points[i];
        if (range.comparePoint(...point.start) >= 0 && range.comparePoint(...point.end) <= 0) {
          if (start < 0) start = i;
          end = i + 1;
        }
      }
      while (start >= 0 && start < end && index.text[start] === " ") start++;
      while (end > start && index.text[end - 1] === " ") end--;
      if (start < 0 || end <= start) continue;
      fragments.push({
        key: block.dataset.readerKey,
        exact: index.text.slice(start, end),
        prefix: index.text.slice(Math.max(0, start - 64), start).trim(),
        suffix: index.text.slice(end, end + 64).trim(),
      });
    }
    this.selection = fragments.length ? fragments : null;
    this.action.hidden = !this.selection;
    const tooLarge =
      fragments.length > 32 ||
      fragments.reduce((size, part) => size + part.exact.length, 0) > 20000;
    document.querySelector("#reader-highlight-save").disabled = tooLarge;
    document.querySelector("#reader-selection-hint").textContent = tooLarge
      ? "구절을 조금 짧게 선택해 주세요."
      : "선택한 구절";
  }

  save() {
    if (!this.selection || !this.storageKey) return;
    if (this.records.length >= 200) {
      this.announce("표시는 200개까지 저장할 수 있습니다. 이전 표시를 지운 뒤 다시 시도해 주세요.");
      return;
    }
    const record = {
      id: globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
      createdAt: Date.now(),
      fragments: this.selection,
    };
    if (!validRecord(record) || !this.persist([...this.records, record])) return;
    this.selection = null;
    this.action.hidden = true;
    window.getSelection()?.removeAllRanges();
    this.announce("표시를 이 브라우저에 저장했습니다.");
    this.resolve();
  }

  async resolve() {
    if (!this.manifest) return;
    const sequence = ++this.sequence;
    this.resolveError = false;
    const revision = this.manifest.revision;
    const parts = this.records.flatMap((record) =>
      record.fragments.map((fragment, index) => ({
        key: `${record.id}:${index}`,
        fragment,
      })),
    );
    this.locations.clear();
    this.repaint();
    this.updateList();
    try {
      for (let offset = 0; offset < parts.length; ) {
        const batch = [];
        let bytes = 0;
        while (offset < parts.length && batch.length < 32) {
          const size = new TextEncoder().encode(JSON.stringify(parts[offset].fragment)).length;
          if (batch.length && bytes + size > 200000) break;
          bytes += size;
          batch.push(parts[offset++]);
        }
        const response = await fetch("api/locate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ revision, fragments: batch.map((part) => part.fragment) }),
        });
        if (!response.ok) throw new Error(`Passage HTTP ${response.status}`);
        const result = await response.json();
        if (sequence !== this.sequence || result.revision !== revision) return;
        if (!Array.isArray(result.locations) || result.locations.length !== batch.length)
          throw new Error("Invalid locations");
        batch.forEach((part, index) => this.locations.set(part.key, result.locations[index]));
      }
    } catch {
      if (sequence !== this.sequence) return;
      this.resolveError = true;
      this.announce("저장한 구절은 보관 중입니다. 연결 후 현재 위치를 다시 확인할 수 있습니다.");
    }
    if (sequence === this.sequence) {
      this.repaint();
      this.updateList();
    }
  }

  repaint() {
    const ranges = [];
    this.article
      .querySelectorAll(".reader-saved-block")
      .forEach((node) => node.classList.remove("reader-saved-block"));
    const nodes = new Map(
      [...this.article.querySelectorAll("[data-reader-key]")].map((node) => [
        node.dataset.readerKey,
        node,
      ]),
    );
    for (const record of this.records) {
      record.fragments.forEach((part, i) => {
        const location = this.locations.get(`${record.id}:${i}`);
        if (!location || location.state !== "located" || location.section !== this.section) return;
        const block = nodes.get(location.key);
        if (!block) return;
        const index = textIndex(block);
        const start = occurrences(index.text, part.exact)[location.occurrence];
        if (start === undefined) return;
        const range = rangeFor(index, start, start + part.exact.length);
        if (range) ranges.push(range);
        if (!this.supportsPaint) block.classList.add("reader-saved-block");
      });
    }
    if (this.supportsPaint) CSS.highlights.set("reader-saved", new Highlight(...ranges));
  }

  updateList() {
    this.button.textContent = this.records.length ? `표시 ${this.records.length}` : "표시";
    this.button.setAttribute("aria-label", `저장한 표시 ${this.records.length}개 보기`);
    this.list.replaceChildren();
    document.querySelector("#reader-highlights-empty").hidden = this.records.length > 0;
    for (const record of [...this.records].reverse()) {
      const row = document.createElement("li");
      const jump = document.createElement("button");
      jump.className = "reader-highlight-jump";
      const quote = document.createElement("span");
      quote.className = "reader-highlight-quote";
      quote.textContent = record.fragments.map((part) => part.exact).join("\n");
      const label = document.createElement("span");
      label.className = "reader-highlight-location";
      const locations = record.fragments.map((_, i) => this.locations.get(`${record.id}:${i}`));
      const location = locations.find((item) => item?.state === "located");
      const uncertain = locations.some((item) => item?.state !== "located");
      label.textContent = location
        ? uncertain
          ? "일부 구절의 위치를 찾았습니다 · 이동"
          : "본문으로 이동"
        : locations.some((item) => item?.state === "ambiguous")
          ? "같은 구절이 여러 곳에 있어 위치를 확인해야 합니다"
          : locations.some((item) => item?.state === "missing")
            ? "수정된 문서에서 찾지 못했습니다 · 원문은 보관 중"
            : this.resolveError
              ? "연결 후 현재 위치를 확인할 수 있습니다"
              : "현재 위치 확인 중";
      jump.disabled = !location;
      jump.append(quote, label);
      jump.addEventListener("click", async () => {
        this.dialog.close();
        window.getSelection()?.removeAllRanges();
        await this.navigate(location.id);
      });
      const remove = document.createElement("button");
      remove.textContent = "삭제";
      remove.setAttribute("aria-label", `${record.fragments[0].exact.slice(0, 30)} 표시 삭제`);
      remove.addEventListener("click", () => {
        if (this.persist(this.records.filter((item) => item.id !== record.id))) this.resolve();
      });
      row.append(jump, remove);
      this.list.append(row);
    }
  }
}
