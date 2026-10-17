const testKey = "flow-reader-entry-test:" + location.search;
const saved = JSON.parse(sessionStorage.getItem(testKey) || "null");
const report = saved?.report ?? { checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "entry-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  output.textContent = JSON.stringify(report, null, 2);
}
async function until(condition, name) {
  const deadline = Date.now() + 30000;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
try {
  if (!saved) {
    await until(
      () => document.querySelector('#reading-position .flow-math-view[data-math-state="ready"]'),
      "named entry",
    );
    await new Promise((resolve) => setTimeout(resolve, 500));
    const target = document.getElementById("reading-position");
    check(
      "A new named link wins over a conflicting saved position with the same URL",
      document.documentElement.dataset.entrySeedMode === "new" &&
        target.dataset.readerKey !== document.documentElement.dataset.entrySeedKey &&
        Math.abs(target.getBoundingClientRect().top - 88) <= 3,
    );
    const paragraph = [...document.querySelectorAll("#reader-document p[data-reader-key]")].find(
      (n) =>
        n.getBoundingClientRect().top > target.getBoundingClientRect().bottom + 30 &&
        n.textContent.length > 40 &&
        !n.closest(".flow-notes"),
    );
    if (!paragraph) throw new Error("No following reading paragraph");
    paragraph.scrollIntoView({ block: "start" });
    await until(
      () => history.state?.readerAnchor?.key === paragraph.dataset.readerKey,
      "saved reading position",
    );
    const snapshot = {
      key: paragraph.dataset.readerKey,
      top: paragraph.getBoundingClientRect().top,
      url: location.href,
      report,
    };
    report.measurements.push({ phase: "before-reload", key: snapshot.key, top: snapshot.top });
    sessionStorage.setItem(testKey, JSON.stringify(snapshot));
    document.body.dataset.entryState = "await-reload";
  } else {
    await until(
      () => document.querySelector(`[data-reader-key="${saved.key}"]`),
      "resumed paragraph",
    );
    await new Promise((resolve) => setTimeout(resolve, 800));
    const paragraph = document.querySelector(`[data-reader-key="${saved.key}"]`);
    const top = paragraph.getBoundingClientRect().top;
    report.measurements.push({ phase: "after-reload", key: saved.key, top });
    check(
      "A reload resumes the saved paragraph at the same URL",
      document.documentElement.dataset.entrySeedMode === "reload" &&
        location.href === saved.url &&
        Math.abs(top - saved.top) <= 3,
    );
    const target = document.getElementById("reading-position");
    check(
      "Reload does not jump back to the original named target",
      !target || Math.abs(target.getBoundingClientRect().top - 88) > 30,
    );
    check(
      "The resumed reading page remains bounded",
      document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
    );
    document.body.dataset.entryState = report.errors.length ? "error" : "ready";
    sessionStorage.removeItem(testKey);
  }
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.entryState = "error";
}
output.textContent = JSON.stringify(report, null, 2);
