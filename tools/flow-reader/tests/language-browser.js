import { languageOf } from "/language.js";

const report = { checks: [], errors: [] };
const output = document.createElement("script");
output.type = "application/json";
output.id = "language-report";
const progress = document.createElement("pre");
progress.id = "language-progress";
progress.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px monospace;margin:16px";
document.body.append(output, progress);
function publish() {
  output.textContent = JSON.stringify(report);
  progress.textContent = JSON.stringify({ checks: report.checks.length, errors: report.errors });
}
function check(name, passed) {
  report.checks.push(name);
  if (!passed) report.errors.push(name);
  publish();
}
async function until(condition, name) {
  const deadline = Date.now() + 90000;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
try {
  const article = document.querySelector("#reader-document");
  await until(
    () => article.querySelector('.flow-math-view[data-math-state="ready"]'),
    "English mathematics",
  );
  const manifest = await (await fetch("/api/manifest")).json();
  check("The source language travels with section metadata", manifest.language === "en");
  check(
    "Korean Reader controls keep their own language",
    languageOf(document.querySelector("#reader-larger")) === "ko",
  );
  check("The English article overrides the Korean shell", article.lang === "en");
  check(
    "Extracted outline titles retain the source language",
    [...document.querySelectorAll("#reader-outline a")].every((link) => languageOf(link) === "en"),
  );
  const notes = [...article.querySelectorAll(".flow-note")];
  check(
    "Original annotation bodies remain English inside the Korean named region",
    notes.length > 0 &&
      notes.every(
        (note) => languageOf(note) === "en" && languageOf(note.closest(".flow-notes")) === "ko",
      ),
  );
  const target = article.querySelector(".flow-note-targets");
  check(
    "The target region is Korean and its copied original term is English",
    target &&
      languageOf(target) === "ko" &&
      languageOf(target.querySelector(".flow-math-view,math")) === "en",
  );
  check(
    "Rendered and assistive mathematical roots retain English",
    [...article.querySelectorAll(".flow-math-view")].every((view) => languageOf(view) === "en") &&
      [...article.querySelectorAll("mjx-assistive-mml math")].every(
        (math) => languageOf(math) === "en",
      ),
  );
  for (const language of ["fr", "ko"]) {
    const source = [...article.querySelectorAll(`[lang="${language}"]`)].find((node) =>
      node.textContent.includes(language === "fr" ? "Bonjour" : "이 문장은"),
    );
    check(`Original ${language} text keeps its local language`, Boolean(source));
  }
  for (const canvas of article.querySelectorAll("[data-flow-canvas]")) {
    canvas.scrollIntoView({ block: "start" });
    await until(() => canvas.dataset.canvasLayout === "native-labels", "native figure");
  }
  check(
    "Native figure label bodies retain the source language",
    [...article.querySelectorAll(".flow-canvas-label-body")].length > 0 &&
      [...article.querySelectorAll(".flow-canvas-label-body")].every(
        (node) => languageOf(node) === "en",
      ),
  );
  const graphic = article.querySelector(".flow-graphic-scene");
  if (graphic) {
    graphic.scrollIntoView({ block: "start" });
    await until(() => graphic.querySelector("svg"), "relationship paint");
    check(
      "The Korean relationship description has a matching language",
      languageOf(graphic.querySelector("svg")) === "ko",
    );
  } else check("A relationship is available for description checks", false);
  report.articleLanguage = article.lang;
  report.uiLanguage = document.documentElement.lang;
  report.revision = manifest.revision;
  document.body.dataset.languageState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.languageState = "error";
}
publish();
