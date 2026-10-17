// Test-only report transport. The fixture stores checkpoints even if browser
// observation disconnects; this does not change Reader scheduling or results.
export function attachReport({ kind, id, stateKey }) {
  const run = new URL(location.href).searchParams.get("audit");
  if (!/^[a-zA-Z0-9][a-zA-Z0-9-]{0,63}$/.test(run ?? ""))
    throw new Error("Invalid audit run identifier");
  const output = document.getElementById(id);
  if (!output) throw new Error("The audit report is missing");
  const receipt = document.createElement("pre");
  receipt.id = "audit-receipt";
  receipt.style.cssText =
    "font:12px monospace;white-space:pre-wrap;overflow-wrap:anywhere;margin:16px";
  document.body.append(receipt);
  let sequence = 0,
    timer,
    busy = false,
    pending;
  async function send() {
    clearTimeout(timer);
    if (busy || !pending) return;
    busy = true;
    const current = pending;
    pending = null;
    try {
      const response = await fetch("/api/test-report", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(current),
      });
      if (!response.ok) throw new Error(`Report delivery failed (${response.status})`);
      receipt.textContent = JSON.stringify({ run, state: current.state, saved: current.sequence });
    } catch (error) {
      receipt.textContent = String(error);
      if (!pending || pending.sequence < current.sequence) pending = current;
    } finally {
      busy = false;
      if (pending) timer = setTimeout(send, 500);
    }
  }
  function capture() {
    if (!output.textContent) return;
    const report = JSON.parse(output.textContent);
    if (!report.revision) return;
    const state = document.body.dataset[stateKey] ?? "progress";
    pending = { run, kind, sequence: ++sequence, state, report };
    clearTimeout(timer);
    if (state === "ready" || state === "error") void send();
    else timer = setTimeout(send, 250);
  }
  new MutationObserver(capture).observe(output, {
    childList: true,
    subtree: true,
    characterData: true,
  });
  new MutationObserver(capture).observe(document.body, {
    attributes: true,
    attributeFilter: [`data-${stateKey.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`],
  });
  capture();
}
