import {
  MathIdentity,
  logicalTextIndex,
  rangesFor,
  selectedIntervals,
  visualFragments,
} from "./math-identity.js";
import { GraphicalAnnotations } from "./graphics.js";

const report = { checks: [], errors: [] };
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
}
try {
  await MathJax.startup.promise;
  const ordinary = document.createElement("p");
  ordinary.dataset.readerKey = "native-paragraph";
  ordinary.innerHTML =
    'Before <em>highlighted</em> after.<svg><text>excluded drawing</text></svg><span data-reader-key="nested">nested block</span>';
  check(
    "Native prose excludes drawings and separately owned blocks",
    logicalTextIndex(ordinary).text === "Before highlighted after.",
  );
  const fixture = document.querySelector("#fixture");
  const view = document.querySelector("#view");
  const math = view.querySelector("math");
  const before = logicalTextIndex(fixture).text;
  const identity = new MathIdentity(math, "selection-fixture");
  await MathJax.typesetPromise([view]);
  await document.fonts.ready;
  check("Every source token has a visual occurrence", identity.bind(view).length === 0);
  const index = logicalTextIndex(fixture);
  check("The complete quotation retains source order", index.text === before);
  check(
    "The renderer actually reordered scripts",
    view.textContent.trim().normalize("NFKD").startsWith("Γkij"),
  );
  const selected = document.createRange();
  selected.setStart(...index.points[3].start);
  selected.setEnd(...index.points[3].end);
  check(
    "Selecting only the superscript returns k",
    JSON.stringify(selectedIntervals(index, selected)) === "[[3,4]]",
  );
  selected.setStart(...index.points[0].start);
  check(
    "A visual selection cannot include unselected subscripts",
    JSON.stringify(selectedIntervals(index, selected)) === "[[0,1],[3,4]]",
  );
  const ranges = rangesFor(index, 0, 3);
  check(
    "Highlighting the base and subscripts excludes the superscript",
    ranges
      .map((r) => r.toString())
      .join("")
      .normalize("NFKD") === "Γij",
  );
  CSS.highlights.set("logical-selection", new Highlight(...ranges));
  report.sourceText = index.text;
  report.presentationText = view.textContent;
  report.logicalMarks = identity.marks.length;
  report.visualMarkFragments = identity.marks.flatMap((mark) => mark.fragments).length;
  check("All line-broken marker fragments remain associated", report.visualMarkFragments > 1);
  const originalMark = identity.marks[0].source;
  const renderer = Object.create(GraphicalAnnotations.prototype);
  renderer.article = fixture;
  renderer.getRevision = () => "fixture";
  const measurement = renderer.measure({
    id: "graphic-1",
    tags: ["sum"],
    nodes: [originalMark],
    scene: { body: view },
  });
  check(
    "A relationship follows all fragments of the detached original mark",
    !originalMark.isConnected &&
      visualFragments(originalMark).length > 1 &&
      measurement.geometry.markers.sum.fragments.length === report.visualMarkFragments,
  );
  report.relationshipFragments = measurement.geometry.markers.sum.fragments;
  check("The expression fits at the selected font", view.scrollWidth <= view.clientWidth + 1);
  document.body.dataset.state = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.state = "error";
}
document.querySelector("#report").textContent = JSON.stringify(report, null, 2);
