/** Foreground capacity only. Server leases own tasks and accepted publication. */
export class BrowserCompilerClient {
  constructor({ changed = () => {} } = {}) {
    this.state = "idle";
    this.lastError = null;
    this.changed = (state) => {
      this.state = state;
      changed(state);
    };
    this.enabled = false;
    this.disposed = false;
    this.session = null;
    this.retry = null;
    this.update = () => {
      if (!this.enabled || document.visibilityState !== "visible" || !navigator.onLine)
        this.stop(
          false,
          !this.enabled ? "disabled" : !navigator.onLine ? "offline" : "page-hidden",
        );
      else if (!this.session && !this.disposed) {
        clearTimeout(this.retry);
        void this.start();
      }
    };
    this.hide = () => this.stop(false, "page-exit");
    document.addEventListener("visibilitychange", this.update);
    window.addEventListener("online", this.update);
    window.addEventListener("offline", this.update);
    window.addEventListener("pagehide", this.hide);
    window.addEventListener("pageshow", this.update);
  }

  setEnabled(enabled) {
    this.enabled = enabled;
    if (!enabled) this.lastError = null;
    this.update();
  }

  async post(session, action, body = {}) {
    const response = await fetch(new URL(`../api/compiler/${action}`, import.meta.url), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ worker: session.token, ...body }),
      signal: AbortSignal.any([session.controller.signal, AbortSignal.timeout(15000)]),
      cache: "no-store",
    });
    if (!response.ok) {
      const detail = await response.json().catch(() => null);
      throw new Error(detail?.error || `Compiler connection ${response.status}`);
    }
    return response.json();
  }

  request(session, body, timeout) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        session.pending = null;
        reject(
          Object.assign(new Error("Compiler deadline exceeded"), { termination: "client-timeout" }),
        );
      }, timeout);
      session.pending = {
        resolve(value) {
          clearTimeout(timer);
          resolve(value);
        },
        reject(error) {
          clearTimeout(timer);
          reject(error);
        },
      };
      session.worker.postMessage({ ...body, id: ++session.sequence });
    });
  }

  wait(session, milliseconds) {
    return new Promise((resolve) => {
      const signal = session.controller.signal;
      const done = () => {
        clearTimeout(timer);
        signal.removeEventListener("abort", done);
        resolve();
      };
      const timer = setTimeout(done, milliseconds);
      signal.addEventListener("abort", done, { once: true });
      if (signal.aborted) done();
    });
  }

  async heartbeat(session, seconds) {
    try {
      while (this.session === session) {
        await this.wait(session, seconds * 1000);
        if (this.session !== session) return;
        await this.post(session, "heartbeat");
      }
    } catch (error) {
      this.fail(session, error);
    }
  }

  async start() {
    const session = { controller: new AbortController(), sequence: 0, pending: null };
    this.session = session;
    try {
      this.changed("loading");
      const response = await fetch(new URL("../api/compiler/config", import.meta.url), {
        cache: "no-store",
        signal: AbortSignal.any([session.controller.signal, AbortSignal.timeout(8000)]),
      });
      if (!response.ok) throw new Error("Compiler configuration unavailable");
      const config = await response.json();
      if (!config.enabled) {
        this.stop();
        this.changed("unavailable");
        return;
      }
      if (this.session !== session) return;
      session.worker = new Worker(new URL("worker.js", import.meta.url), { type: "module" });
      session.worker.onmessage = ({ data }) => {
        if (data.id !== session.sequence) return;
        const pending = session.pending;
        session.pending = null;
        if (pending)
          data.error
            ? pending.reject(Object.assign(new Error(data.error), { termination: "compile-error" }))
            : pending.resolve(data);
      };
      session.worker.onerror = (error) => {
        session.pending?.reject(new Error(error.message));
        session.pending = null;
        this.fail(
          session,
          Object.assign(new Error(error.message), { termination: "worker-error" }),
        );
      };
      const base = new URL("../", import.meta.url);
      await this.request(
        session,
        {
          type: "init",
          engine: config.engine,
          moduleURL: new URL(config.moduleURL, base).href,
          wasmURL: config.wasmURL,
        },
        90000,
      );
      if (this.session !== session) return;
      const name = /iPhone/.test(navigator.userAgent)
        ? "iPhone"
        : /iPad/.test(navigator.userAgent) ||
            (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
          ? "iPad"
          : /Android/.test(navigator.userAgent)
            ? "Android"
            : "컴퓨터 브라우저";
      const registration = await this.post(session, "register", { engine: config.engine, name });
      session.token = registration.worker;
      session.device = registration.device;
      this.lastError = null;
      if (this.session !== session) {
        this.release(session);
        return;
      }
      void this.heartbeat(session, registration.heartbeatSeconds);
      while (this.session === session) {
        this.changed("ready");
        const { task } = await this.post(session, "poll");
        if (this.session !== session) return;
        if (!task) {
          await this.wait(session, 1000);
          continue;
        }
        this.changed("working");
        let result;
        try {
          result = await this.request(
            session,
            { type: "compile", snapshot: task.snapshot },
            task.timeoutMs,
          );
        } catch (error) {
          if (this.session === session && error.termination) {
            this.fail(session, error);
            throw error;
          }
          if (this.session === session)
            await this.post(session, "result", {
              job: task.job,
              lease: task.lease,
              result: {
                identity: task.snapshot.identity,
                returncode: 1,
                stderr: String(error),
                artifact: "",
                dependencies: [],
              },
            });
          throw error;
        }
        if (this.session !== session) return;
        // Chunk conversion avoids spreading a large artifact onto the JS stack.
        const chunks = [];
        for (let index = 0; index < result.artifact.length; index += 32768)
          chunks.push(String.fromCharCode(...result.artifact.subarray(index, index + 32768)));
        await this.post(session, "result", {
          job: task.job,
          lease: task.lease,
          result: { ...result, artifact: btoa(chunks.join("")) },
        });
      }
    } catch (error) {
      this.fail(session, error);
    }
  }

  fail(session, error) {
    if (this.session !== session) return;
    this.lastError = String(error.message || error).slice(0, 240);
    this.stop(true, error.termination || "transport-error");
  }

  release(session, reason = "released") {
    if (!session.token) return;
    void fetch(new URL("../api/compiler/release", import.meta.url), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ worker: session.token, reason }),
      keepalive: true,
    }).catch(() => {});
    session.token = null;
  }

  get device() {
    return this.session?.device;
  }

  async diagnose(mode) {
    const session = this.session;
    if (!session?.token) throw new Error("device-not-ready");
    return this.post(session, "diagnose", { mode });
  }

  stop(retry = false, reason = "released") {
    clearTimeout(this.retry);
    const session = this.session;
    this.session = null;
    if (session) {
      session.controller.abort();
      session.pending?.reject(new Error("Compiler session ended"));
      session.pending = null;
      session.worker?.terminate();
      this.release(session, reason);
    }
    this.changed(retry ? "retrying" : "idle");
    if (retry && this.enabled && !this.disposed) this.retry = setTimeout(this.update, 5000);
  }

  dispose() {
    this.disposed = true;
    this.stop(false, "disposed");
    document.removeEventListener("visibilitychange", this.update);
    window.removeEventListener("online", this.update);
    window.removeEventListener("offline", this.update);
    window.removeEventListener("pagehide", this.hide);
    window.removeEventListener("pageshow", this.update);
  }
}
