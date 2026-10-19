// Exercise browser-native fragment navigation and history on the actual book.
// A native hash navigation may inherit the previous entry's history.state.
import { logicalTextIndex } from "/rendering/math/identity.js";

const testSearch = new URLSearchParams(location.search);
testSearch.delete("section");
const testKey = "flow-reader-navigation-test:" + testSearch;
const saved = JSON.parse(sessionStorage.getItem(testKey) || "null");
const report = saved?.report ?? { checks: [], errors: [], measurements: [] };
const output = document.createElement("script");
output.type = "application/json";
output.id = "navigation-report";
const progress = document.createElement("pre");
progress.id = "navigation-progress";
progress.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px monospace;margin:16px";
document.body.append(output, progress);
function publish() {
  output.textContent = JSON.stringify(report);
  progress.textContent = JSON.stringify({
    checks: report.checks.length,
    active: report.active,
    errors: report.errors,
  });
}
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  publish();
}
async function until(condition, name, timeout = 20000) {
  const deadline = Date.now() + timeout;
  while (!(await condition())) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
function position(id, phase) {
  const target = document.getElementById(id);
  const result = {
    phase,
    id,
    top: target?.getBoundingClientRect().top ?? null,
    url: location.href,
    savedURL: history.state?.readerAnchor?.url,
    section: target?.closest("[data-reader-section]")?.dataset.readerSection,
  };
  report.measurements.push(result);
  publish();
  return result;
}
async function settled(id, name) {
  await until(() => {
    const target = document.getElementById(id);
    return target && Math.abs(target.getBoundingClientRect().top - 88) <= 3;
  }, name);
  await until(() => history.state?.readerAnchor?.url === location.href, `${name} saved entry`);
}
async function run() {
  await until(() => document.querySelector("#reader-document [data-reader-key]"), "accepted book");
  const manifest = await (await fetch("/api/manifest")).json();
  report.revision = manifest.revision;
  if (saved) {
    await settled(saved.last, "reload reading target");
    check(
      "Reload retains the native fragment's reading entry",
      position(saved.last, "reload").section === saved.section,
    );
    check(
      "Reload retains the selected 13px default",
      getComputedStyle(document.querySelector("#reader-document")).fontSize === "13px",
    );
    sessionStorage.removeItem(testKey);
    document.body.dataset.navigationState = report.errors.length ? "error" : "ready";
    publish();
    return;
  }
  const anchors = await Promise.all(
    [manifest.sections[0], manifest.sections.at(-2)].map(async (section) => {
      const source = new DOMParser().parseFromString(
        await (await fetch(`/api/sections/${section.id}?revision=${manifest.revision}`)).text(),
        "text/html",
      );
      return { id: source.querySelector("[data-reader-key][id]")?.id, section: section.id };
    }),
  );
  check(
    "Both native navigation targets come from distant real book sections",
    anchors.length === 2 && anchors.every((a) => a.id) && anchors[0].section !== anchors[1].section,
  );
  const [first, last] = anchors;
  const link = document.createElement("a");
  link.href = `#${first.id}`;
  document.getElementById("reader-document").append(link);
  link.click();
  link.remove();
  await settled(first.id, "initial reading entry");
  position(first.id, "before-native-fragment");
  report.active = "native fragment";
  publish();
  location.hash = last.id;
  await settled(last.id, "native fragment target");
  check(
    "A new native fragment wins over an inherited reading anchor",
    position(last.id, "native-fragment").section === last.section,
  );
  report.active = "history back";
  publish();
  history.back();
  await settled(first.id, "browser back");
  check(
    "Browser back restores the earlier real section",
    position(first.id, "back").section === first.section,
  );
  report.active = "history forward";
  publish();
  history.forward();
  await settled(last.id, "browser forward");
  check(
    "Browser forward restores the later fragment",
    position(last.id, "forward").section === last.section,
  );
  check(
    "Native navigation stays bounded without horizontal movement",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  sessionStorage.setItem(testKey, JSON.stringify({ last: last.id, section: last.section, report }));
  document.body.dataset.navigationState = "await-reload";
  publish();
}
async function sourceUpdates() {
  await until(() => document.querySelector("#reader-document [data-reader-key]"), "accepted book");
  const readState = async () => (await fetch("/api/state", { cache: "no-store" })).json();
  const initialState = await readState();
  const manifest = await (await fetch("/api/manifest")).json();
  report.revision = manifest.revision;
  const heading = manifest.outline.find((item) =>
    item.title.includes("Translation invariance reduces"),
  );
  if (!heading) throw new Error("No actual PDE translation subsection");
  const source = new DOMParser().parseFromString(
    await (await fetch(`/api/sections/${heading.section}?revision=${manifest.revision}`)).text(),
    "text/html",
  );
  const title = [...source.querySelectorAll(".flow-callout-title")].find((node) =>
    node.textContent.includes("(Translation Invariance)"),
  );
  const targetId = title?.parentElement.querySelector(".flow-equation")?.id;
  if (!targetId) throw new Error("No original Translation Invariance equation");
  const link = document.createElement("a");
  link.href = `#${targetId}`;
  document.getElementById("reader-document").append(link);
  link.click();
  link.remove();
  const equation = () => document.getElementById(targetId);
  const view = () => equation()?.querySelector(".flow-math-view");
  await until(() => view()?.dataset.mathState === "ready", "initial real PDE equation");
  equation().scrollIntoView({ block: "start" });
  await settled(targetId, "selected equation");
  const initial = view();
  const glyphs = initial.firstElementChild;
  const canonical = logicalTextIndex(initial).text;
  const quotation = {
    key: equation().closest("[data-reader-key]").dataset.readerKey,
    exact: canonical,
    prefix: "",
    suffix: "",
  };
  const before = position(targetId, "before-source-error");
  const range = document.createRange();
  range.selectNodeContents(initial);
  getSelection().removeAllRanges();
  getSelection().addRange(range);
  const copiedSelection = () => {
    const clipboardData = new DataTransfer();
    initial.dispatchEvent(
      new ClipboardEvent("copy", { clipboardData, bubbles: true, cancelable: true }),
    );
    return clipboardData.getData("text/plain");
  };
  check(
    "The real PDE equation can be selected and copied canonically",
    !getSelection().isCollapsed && copiedSelection() === canonical,
  );

  report.active = "await invalid save in the owned copy";
  document.body.dataset.navigationState = "await-invalid-save";
  publish();
  let failed;
  await until(
    async () => {
      failed = await readState();
      return !failed.compiling && failed.exitCode !== 0;
    },
    "owned source error",
    90000,
  );
  await until(
    () => document.querySelector("#reader-status").dataset.state === "error",
    "visible source error",
  );
  check(
    "A failed save retains the accepted real book revision",
    failed.revision === initialState.revision,
  );
  check(
    "A failed save retains the selected mathematical DOM and quotation",
    view() === initial &&
      initial.firstElementChild === glyphs &&
      !getSelection().isCollapsed &&
      copiedSelection() === canonical,
  );
  check(
    "The error notice preserves the selected equation's reading position",
    Math.abs(position(targetId, "source-error").top - before.top) <= 3,
  );

  report.active = "await valid insertion before the selected passage";
  document.body.dataset.navigationState = "await-valid-save";
  publish();
  let accepted;
  await until(
    async () => {
      accepted = await readState();
      return (
        !accepted.compiling &&
        accepted.exitCode === 0 &&
        accepted.revision !== initialState.revision
      );
    },
    "valid owned source insertion",
    90000,
  );
  await until(
    () => document.querySelector("#reader-status").dataset.state === "ready",
    "accepted state observed by Reader",
  );
  await new Promise((resolve) => setTimeout(resolve, 300));
  check(
    "An accepted source update waits for the active mathematical selection",
    view() === initial &&
      initial.firstElementChild === glyphs &&
      !getSelection().isCollapsed &&
      copiedSelection() === canonical,
  );
  const response = await fetch("/api/locate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ revision: accepted.revision, fragments: [quotation] }),
  });
  if (!response.ok) throw new Error(`Actual quotation lookup returned ${response.status}`);
  const located = (await response.json()).locations[0];
  report.quotation = { before, located, exact: canonical };
  check(
    "The accepted book uniquely relocates the mathematical quotation across sections",
    located.state === "located" && located.section !== before.section,
  );
  getSelection().removeAllRanges();
  await until(
    () => view() && view() !== initial && view().dataset.mathState === "ready",
    "source publication after selection release",
    90000,
  );
  check(
    "Source publication retains every original mathematical term",
    logicalTextIndex(view()).text === canonical,
  );
  check(
    "The moved passage mounts in its newly located section",
    equation().closest("[data-reader-section]").dataset.readerSection === located.section,
  );
  check(
    "Source publication keeps the same equation at the reading reference",
    Math.abs(position(targetId, "accepted-source").top - before.top) <= 3,
  );
  check(
    "The updated real book stays bounded at the 13px default",
    getComputedStyle(view()).fontSize === "13px" &&
      document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  report.acceptedRevision = accepted.revision;
  document.body.dataset.navigationState = report.errors.length ? "error" : "ready";
  publish();
}

(new URL(location.href).searchParams.has("updates") ? sourceUpdates() : run()).catch((error) => {
  report.errors.push(String(error));
  document.body.dataset.navigationState = "error";
  publish();
});
