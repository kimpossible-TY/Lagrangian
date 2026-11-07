/** Tab-local recovery only; the host remains authoritative for saved history. */
export class DraftRecovery {
  constructor(storage = () => globalThis.sessionStorage) {
    this.storage = storage;
    this.cache = new Map();
  }

  key(documentID, id) {
    return `reader_chat_draft_v1_${JSON.stringify([documentID, id])}`;
  }

  get(documentID, id) {
    const key = this.key(documentID, id);
    if (!this.cache.has(key)) {
      let draft = null;
      try {
        const raw = this.storage()?.getItem(key) || "null";
        const value = raw.length <= 65536 ? JSON.parse(raw) : null;
        if (
          value &&
          typeof value.text === "string" &&
          value.text.length <= 8000 &&
          (value.messageID === undefined ||
            (typeof value.messageID === "string" && value.messageID.length <= 80))
        )
          draft = { text: value.text, ...(value.messageID ? { messageID: value.messageID } : {}) };
      } catch {
        // Unavailable or invalid storage does not prevent editing.
      }
      this.cache.set(key, draft);
    }
    return this.cache.get(key);
  }

  set(documentID, id, text, messageID) {
    if (
      typeof text !== "string" ||
      text.length > 8000 ||
      (messageID !== undefined && (typeof messageID !== "string" || messageID.length > 80))
    )
      return false;
    const key = this.key(documentID, id);
    const draft = { text, ...(messageID ? { messageID } : {}) };
    this.cache.set(key, draft);
    try {
      const storage = this.storage();
      if (!storage) return false;
      storage.setItem(key, JSON.stringify(draft));
      return true;
    } catch {
      // The controller's current draft and this in-memory copy remain available.
      return false;
    }
  }

  acknowledge(documentID, record) {
    const draft = this.get(documentID, record.conversation_id);
    if (
      !draft ||
      (draft.messageID
        ? !record.thread.some(
            (message) =>
              message.id === draft.messageID &&
              message.role === "user" &&
              message.text === draft.text,
          )
        : record.draft !== draft.text)
    )
      return null;
    const key = this.key(documentID, record.conversation_id);
    this.cache.set(key, null);
    try {
      this.storage()?.removeItem(key);
    } catch {
      // Acknowledged text must not resurrect if removeItem is denied.
    }
    return draft;
  }
}
