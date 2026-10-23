/** Durable explicit intents. Each key is independent across tabs; server receipts deduplicate. */
export class HighlightIntents {
  constructor({
    storage,
    prefix,
    transport,
    online = () => true,
    changed = () => {},
    identity = () => crypto.randomUUID(),
  }) {
    Object.assign(this, { storage, prefix, transport, online, changed, identity });
    this.running = new Map();
    this.disposed = false;
  }

  records(documentID) {
    const records = [];
    if (!this.storage) return records;
    for (let index = 0; index < this.storage.length; index++) {
      const key = this.storage.key(index);
      if (!key?.startsWith(this.prefix)) continue;
      try {
        const record = JSON.parse(this.storage.getItem(key));
        if (
          record?.request?.documentID === documentID &&
          key === this.prefix + record.request.requestID &&
          ["pending", "rejected"].includes(record.state)
        )
          records.push(record);
      } catch {
        /* An invalid entry never authorizes source work. */
      }
    }
    return records;
  }

  async submit(payload) {
    const existing = this.records(payload.documentID);
    if (existing.length >= 32) throw new Error("Too many pending highlight requests");
    const request = structuredClone({ ...payload, requestID: this.identity() });
    const record = { request, state: "pending" };
    // Persist before dispatch. Storage failure must not masquerade as queued work.
    this.storage.setItem(this.prefix + request.requestID, JSON.stringify(record));
    this.changed();
    return this.deliver(record);
  }

  deliver(record) {
    const id = record.request.requestID;
    if (this.disposed || !this.online()) return Promise.resolve({ status: "queued" });
    if (this.running.has(id)) return this.running.get(id);
    const work = (async () => {
      let result;
      try {
        result = await this.transport.post("api/highlight", record.request, 120000);
        if (!result || typeof result.status !== "string") throw new Error("Invalid acknowledgment");
      } catch {
        return { status: "queued" };
      }
      try {
        if (result.status === "highlighted") this.storage.removeItem(this.prefix + id);
        else
          this.storage.setItem(
            this.prefix + id,
            JSON.stringify({ ...record, state: "rejected", result }),
          );
      } catch {
        // If acknowledgment cleanup failed, the durable request retries with the
        // same ID. Its server receipt prevents another source edit.
      }
      return result;
    })().finally(() => {
      this.running.delete(id);
      if (!this.disposed) this.changed();
    });
    this.running.set(id, work);
    return work;
  }

  async flush(documentID) {
    if (this.disposed || !this.online()) return;
    for (const record of this.records(documentID)) {
      if (this.disposed || !this.online()) break;
      if (record.state !== "pending") continue;
      const result = await this.deliver(record);
      if (result.status === "queued") break;
    }
  }

  clearRejected(documentID) {
    for (const record of this.records(documentID))
      if (record.state === "rejected")
        this.storage.removeItem(this.prefix + record.request.requestID);
    this.changed();
  }

  dispose() {
    this.disposed = true;
  }
}
