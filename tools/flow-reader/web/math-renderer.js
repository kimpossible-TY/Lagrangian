import { MathIdentity, logicalTextIndex, selectedIntervals } from "./math-identity.js";
import {
  mathOverflow,
  prepareNativeDecorations,
  promoteInlineMath,
  restoreNativeDecorations,
  splitDerivations,
} from "./math-layout.js";
import { namespaceClone } from "./graphics.js";
import { MathFrames } from "./math-frames.js";
import { loadMathJax } from "./mathjax-loader.js";
import { languageOf, setLanguage, uiLanguage } from "./language.js";

let serial = 0;

function restoreIdentifiers(root, ids) {
  const seen = new Set();
  for (const node of [root, ...root.querySelectorAll("*")]) {
    if (node.closest("mjx-assistive-mml")) {
      node.removeAttribute("id");
      continue;
    }
    if (ids.has(node.id)) {
      const id = ids.get(node.id);
      if (seen.has(id)) node.removeAttribute("id");
      else {
        node.id = id;
        seen.add(id);
      }
    }
    for (const attribute of [...node.attributes]) {
      let value = attribute.value;
      if (attribute.localName === "href" && value.startsWith("#") && ids.has(value.slice(1)))
        value = "#" + ids.get(value.slice(1));
      value = value.replace(/url\(#([^)]*)\)/g, (whole, id) =>
        ids.has(id) ? `url(#${ids.get(id)})` : whole,
      );
      if (value !== attribute.value)
        node.setAttributeNS(attribute.namespaceURI, attribute.name, value);
    }
  }
}

function accessibleLinks(root) {
  // Native assistive MathML carries the expression. Keep visible references
  // keyboard/screen-reader accessible without also exposing presentation glyphs.
  function exposeLinks(node) {
    if (node.matches("a[href]")) return;
    if (!node.querySelector("a[href]")) {
      node.setAttribute("aria-hidden", "true");
      return;
    }
    node.removeAttribute("aria-hidden");
    for (const child of node.children) exposeLinks(child);
  }
  for (const math of root.querySelectorAll("mjx-math")) exposeLinks(math);
  for (const link of root.querySelectorAll("mjx-assistive-mml a[href]")) {
    link.removeAttribute("href");
    link.removeAttribute("tabindex");
  }
}

export class ResponsiveMath {
  constructor(article, { preserve, changed, selectionActive }) {
    Object.assign(this, { article, preserve, changed, selectionActive });
    this.records = new Set();
    this.generation = 0;
    this.resize = new ResizeObserver(() => this.schedule());
    this.intersection = new IntersectionObserver(() => this.schedule(), { rootMargin: "1200px" });
    window.addEventListener("resize", () => this.schedule());
    document.addEventListener("selectionchange", () => this.schedule());
    document.addEventListener("close", () => this.schedule(), true);
    document.fonts.ready.then(() => this.schedule());
    article.addEventListener("copy", (event) => this.copy(event));
  }

  prepare(root) {
    for (const math of [...root.querySelectorAll("math")]) {
      if (
        math.closest("svg,mjx-assistive-mml,.flow-math-view") ||
        math.parentElement.closest("math")
      )
        continue;
      const display = math.getAttribute("display") === "block";
      const view = document.createElement("span");
      view.className = "flow-math-view";
      setLanguage(view, languageOf(math) ?? "");
      view.dataset.mathDisplay = display ? "block" : "inline";
      view.dataset.mathState = "native";
      const model = new MathIdentity(math, `math-${++serial}`);
      const template = math.cloneNode(true);
      math.replaceWith(view);
      view.append(math);
      this.records.add({ view, model, template, display, key: null });
    }
  }

  clear() {
    this.generation++;
    clearTimeout(this.timer);
    this.resize.disconnect();
    this.intersection.disconnect();
    this.records.clear();
  }

  sync() {
    this.resize.disconnect();
    this.resize.observe(this.article);
    for (const record of this.records) {
      if (!record.view.isConnected) {
        this.intersection.unobserve(record.view);
        this.records.delete(record);
      } else {
        this.intersection.observe(record.view);
        this.resize.observe(record.view.parentElement);
      }
    }
    this.schedule();
  }

  schedule(delay = 100) {
    for (const record of this.records) {
      const measurement = this.measure(record);
      if (
        measurement &&
        record.key !== measurement.key &&
        record.view.dataset.mathState !== "error"
      )
        record.view.dataset.mathState = "pending";
    }
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.render(), delay);
  }

  measure(record) {
    if (!record.view.isConnected) return null;
    const rect = record.view.getBoundingClientRect();
    if (rect.bottom < -1200 || rect.top > innerHeight + 1200) {
      // A figure can have long semantic legends. Compose all its labels when
      // any part of their canvas is nearby, including a later legend passage.
      let canvas = record.view.closest("[data-flow-canvas-model]");
      while (canvas) {
        const area = canvas.getBoundingClientRect();
        if (area.bottom >= -1200 && area.top <= innerHeight + 1200) break;
        canvas = canvas.parentElement.closest("[data-flow-canvas-model]");
      }
      if (!canvas) return null;
    }
    let container = record.view.parentElement;
    while (
      container !== this.article &&
      ["inline", "inline-block", "contents"].includes(getComputedStyle(container).display)
    )
      container = container.parentElement;
    const parentStyle = getComputedStyle(container);
    const style = getComputedStyle(record.view);
    let width =
      container.clientWidth -
      parseFloat(parentStyle.paddingLeft) -
      parseFloat(parentStyle.paddingRight);
    const label = record.view.closest(".flow-canvas-label-body");
    const canvas = label?.closest("[data-flow-canvas-model]");
    if (canvas) {
      // Label boxes shrink to their natural content after composition. Their
      // intrinsic width is an output, not the next mathematical line budget:
      // otherwise a short accent alternates between inline and full-width block.
      width = Math.floor(canvas.getBoundingClientRect().width);
      for (let node = container; node && label.contains(node); node = node.parentElement) {
        const style = getComputedStyle(node);
        width -=
          parseFloat(style.paddingLeft) +
          parseFloat(style.paddingRight) +
          parseFloat(style.borderLeftWidth) +
          parseFloat(style.borderRightWidth);
      }
    }
    const fontSize = parseFloat(style.fontSize);
    if (width < 1 || fontSize < 1) return null;
    const key = JSON.stringify([
      Math.round(width * 100) / 100,
      fontSize,
      style.fontFamily,
      style.fontWeight,
      style.fontStyle,
    ]);
    return {
      width,
      fontSize,
      inset: { left: parseFloat(style.paddingLeft), right: parseFloat(style.paddingRight) },
      font: style.font,
      key,
      left:
        container.getBoundingClientRect().left +
        container.clientLeft +
        parseFloat(parentStyle.paddingLeft),
    };
  }

  notice(record, message) {
    if (!message) {
      record.notice?.remove();
      record.notice = null;
      return;
    }
    if (!record.notice) {
      record.notice = document.createElement("span");
      record.notice.className = "flow-math-status";
      setLanguage(record.notice, uiLanguage());
      record.notice.setAttribute("role", "status");
      record.view.after(record.notice);
    }
    record.notice.textContent = message;
  }

  async candidate(record, measurement, mathjax) {
    const stage = document.createElement("span");
    stage.className = "flow-math-stage";
    stage.setAttribute("aria-hidden", "true");
    stage.inert = true;
    stage.style.width = `${measurement.width}px`;
    stage.style.font = measurement.font;
    stage.style.paddingLeft = `${measurement.inset.left}px`;
    stage.style.paddingRight = `${measurement.inset.right}px`;
    const template = record.template.cloneNode(true);
    const prefix = `math-stage-${++serial}-`;
    const ids = new Map(
      [template, ...template.querySelectorAll("[id]")]
        .filter((n) => n.id)
        .map((n) => [prefix + n.id, n.id]),
    );
    namespaceClone(template, prefix);
    stage.append(template);
    for (const svg of stage.querySelectorAll("math mtext > svg")) {
      const span = document.createElement("span");
      svg.replaceWith(span);
      span.append(svg);
    }
    splitDerivations(stage);
    prepareNativeDecorations(stage);
    let frames = new MathFrames(stage);
    const metrics = {
      ...mathjax.getMetricsFor(record.view, record.display),
      containerWidth: Math.max(
        1,
        measurement.width - measurement.inset.left - measurement.inset.right,
      ),
    };
    let blueprint = [...stage.childNodes].map((node) => node.cloneNode(true));
    let promoted = false;
    let corrections = 0;
    let frameWidth = metrics.containerWidth - measurement.fontSize * 1.5;
    let frameAttempts = 0;
    let best;
    try {
      this.article.append(stage);
      for (let attempt = 0; attempt < 8; attempt++) {
        if (attempt) stage.replaceChildren(...blueprint.map((node) => node.cloneNode(true)));
        for (const math of [...stage.querySelectorAll("math")].filter(
          (n) => !n.parentElement.closest("math"),
        )) {
          const converted = await mathjax.mathml2chtmlPromise(
            new XMLSerializer().serializeToString(math),
            { ...metrics, display: math.getAttribute("display") === "block" },
          );
          math.replaceWith(converted);
        }
        mathjax.startup.document.reset();
        mathjax.startup.document.updateDocument();
        restoreNativeDecorations(stage);
        await document.fonts.ready;
        if (stage.querySelector("mjx-merror")) throw new Error("수식 조판 오류가 발생했습니다.");
        // Layout boxes do not include every italic/stretched glyph overhang.
        // Rebreak a small measured overhang at the same font; do not squeeze an
        // indivisible structure or loop trying to fix a fundamentally wide one.
        const overflow = mathOverflow(stage, { width: measurement.width });
        const excess = Math.max(overflow.left, overflow.right);
        if (!best || excess < best.excess)
          best = { excess, nodes: [...stage.childNodes].map((node) => node.cloneNode(true)) };
        if (!record.display && !promoted && excess > 1) {
          const source = document.createElement("span");
          source.append(...blueprint.map((node) => node.cloneNode(true)));
          promoteInlineMath(source);
          splitDerivations(source);
          frames = new MathFrames(source);
          blueprint = [...source.childNodes];
          promoted = true;
          best = null;
          continue;
        }
        if (excess > 1 && frameAttempts < 4) {
          if (!frameAttempts) frames.measure(stage);
          else frameWidth -= Math.max(measurement.fontSize * 0.5, excess + 1);
          const composed = frames.compose(Math.max(measurement.fontSize * 2, frameWidth));
          if (composed) {
            blueprint = [...composed.childNodes];
            frameAttempts++;
            continue;
          }
        }
        const correction = 2 * excess + 1;
        if (
          excess <= 1 ||
          corrections >= 2 ||
          measurement.width - metrics.containerWidth + correction > measurement.fontSize
        )
          break;
        metrics.containerWidth = Math.max(1, metrics.containerWidth - correction);
        corrections++;
      }
      if (best) stage.replaceChildren(...best.nodes);
      return { stage, ids, layout: record.display || promoted ? "block" : "inline" };
    } catch (error) {
      stage.remove();
      throw error;
    }
  }

  async render() {
    if (this.busy) return;
    if (this.selectionActive()) return;
    const outdated = [...this.records].filter((record) => {
      const measurement = this.measure(record);
      return measurement && record.key !== measurement.key;
    });
    const pending = outdated.filter((record) => (record.retryAt ?? 0) <= Date.now()).slice(0, 32);
    if (!pending.length) {
      if (outdated.length)
        this.schedule(
          Math.max(100, Math.min(...outdated.map((record) => record.retryAt)) - Date.now()),
        );
      return;
    }
    this.busy = true;
    const generation = this.generation;
    try {
      const mathjax = await loadMathJax();
      for (const record of pending) {
        if (generation !== this.generation || this.selectionActive()) break;
        const measurement = this.measure(record);
        if (!measurement) continue;
        record.view.dataset.mathState = "pending";
        let result;
        try {
          result = await this.candidate(record, measurement, mathjax);
          if (
            generation !== this.generation ||
            !this.records.has(record) ||
            this.selectionActive() ||
            this.measure(record)?.key !== measurement.key
          )
            continue;
          this.preserve(() => {
            restoreIdentifiers(result.stage, result.ids);
            accessibleLinks(result.stage);
            const errors = record.model.bind(result.stage, { view: record.view });
            if (errors.length) throw new Error("원본 수식과 조판 결과를 연결하지 못했습니다.");
            record.view.replaceChildren(...result.stage.childNodes);
            record.view.dataset.mathLayout = result.layout;
            if (record.view.parentElement.matches(".flow-inline-equation"))
              record.view.parentElement.dataset.mathLayout = result.layout;
            record.key = measurement.key;
            record.retryAt = 0;
            const bounds = mathOverflow(record.view, measurement);
            const overflow = Math.max(bounds.left, bounds.right) > 1;
            record.view.dataset.mathState = overflow ? "overflow" : "ready";
            this.notice(
              record,
              overflow ? "이 수식은 현재 글자 크기에서 추가 배치 조정이 필요합니다." : "",
            );
            this.changed();
          });
        } catch (error) {
          if (generation === this.generation && record.view.isConnected) {
            record.view.dataset.mathState = "error";
            record.retryAt = Date.now() + 5000;
            this.notice(record, `${error.message} 자동으로 다시 시도합니다.`);
          }
        } finally {
          result?.stage.remove();
        }
      }
    } catch (error) {
      if (generation === this.generation)
        for (const record of pending) {
          record.view.dataset.mathState = "error";
          record.retryAt = Date.now() + 5000;
          this.notice(record, `${error.message} 자동으로 다시 시도합니다.`);
        }
    } finally {
      this.busy = false;
      this.schedule(200);
    }
  }

  copy(event) {
    const selection = window.getSelection();
    if (
      !event.clipboardData ||
      !selection?.rangeCount ||
      selection.isCollapsed ||
      !this.article.contains(selection.anchorNode) ||
      !this.article.contains(selection.focusNode)
    )
      return;
    const range = selection.getRangeAt(0);
    if (
      ![...this.records].some(
        (record) =>
          record.view.isConnected && record.model.bound && range.intersectsNode(record.view),
      )
    )
      return;
    const index = logicalTextIndex(this.article, { includeNested: true, includeNotes: true });
    const text = selectedIntervals(index, range)
      .map(([start, end]) => index.text.slice(start, end))
      .join("");
    if (text) {
      event.clipboardData.setData("text/plain", text);
      event.preventDefault();
    }
  }
}
