/** Match the configured editor before allowing terminal-origin source writes. */
export class TerminalEditorConnection {
  constructor(expected, attachment = null) {
    this.expected = expected;
    this.attachment = attachment;
    this.supportsAttachments = false;
    this.connected = null;
  }
  update(server, attachments = 0) {
    this.connected = server ?? null;
    this.supportsAttachments = attachments === 1;
  }
  canHighlight() {
    return this.attachment
      ? this.supportsAttachments
      : !this.expected || this.expected === this.connected;
  }
}

/** Delegate terminal actions to the real HTML selection and navigation owners. */
export function installTerminalBridge(adapter) {
  if (!adapter.enabled) return () => {};
  let followSequence = 0;
  const bridge = Object.freeze({
    state() {
      return {
        revision: adapter.revision(),
        ready: Boolean(adapter.manifest() && adapter.actions()),
      };
    },
    selection() {
      const actions = adapter.actions();
      actions?.capture();
      const fragments = actions?.selection;
      if (!fragments?.length || fragments.some((part) => part.revision !== adapter.revision()))
        return null;
      return { revision: adapter.revision(), fragments: structuredClone(fragments) };
    },
    action(name) {
      const id = {
        highlight: "reader-source-highlight",
        save: "reader-codex-save",
        strike: "reader-strike",
        undo: "reader-strike-undo",
        clear: "reader-strike-clear",
      }[name];
      if (!id) return false;
      adapter.actions()?.capture();
      const button = document.getElementById(id);
      if (!button || button.disabled || button.hidden) return false;
      button.click();
      return true;
    },
    async follow(location) {
      const manifest = adapter.manifest();
      if (
        !manifest ||
        location?.status !== "located" ||
        location.revision !== adapter.revision() ||
        manifest.blocks[location.key] !== location.section ||
        adapter.selectionActive() ||
        adapter.recentGesture()
      )
        return false;
      const sequence = ++followSequence;
      const find = () =>
        adapter.article.querySelector(`[data-reader-key="${CSS.escape(location.key)}"]`);
      if (!find()) await adapter.loadSection(manifest, location.section);
      if (
        sequence !== followSequence ||
        location.revision !== adapter.revision() ||
        adapter.selectionActive() ||
        adapter.recentGesture()
      )
        return false;
      const target = find();
      if (!target || !target.getBoundingClientRect().height) return false;
      if (location.exact && !adapter.textOf(target).includes(location.exact)) return false;
      target.scrollIntoView({ block: "center" });
      return true;
    },
  });
  globalThis.flowReaderTerminal = bridge;
  return () => {
    followSequence++;
    if (globalThis.flowReaderTerminal === bridge) delete globalThis.flowReaderTerminal;
  };
}
