import assert from "node:assert/strict";
import test from "node:test";
import {
  chatTokens,
  safeChatLink,
  chatStatus,
  stripMathDelimiters,
} from "../web/features/paragraph-chat/content.js";

const flatten = (tokens) => tokens.flatMap((token) => [token, ...flatten(token.children || [])]);
test("Markdown keeps executable markup literal, disables embedded images and bounds nesting", () => {
  const tokens = flatten(
    chatTokens(
      "**Answer**\n\n<img src=x onerror=alert(1)>\n\n[unsafe](javascript:alert(1))\n\n![image](https://example.invalid/track)",
    ),
  );
  assert.ok(tokens.some((t) => t.type === "strong_open"));
  assert.ok(tokens.some((t) => t.type === "text" && t.content.includes("<img")));
  assert.ok(!tokens.some((t) => t.type.startsWith("html_")));
  assert.ok(
    !tokens.some((t) => t.type === "link_open" && t.attrGet("href").startsWith("javascript:")),
  );
  for (const value of [
    "javascript:alert(1)",
    "data:text/html,x",
    "//example.com",
    "https://user:password@example.com",
    "file:///tmp/source",
  ])
    assert.equal(safeChatLink(value), null);
  assert.equal(safeChatLink("https://example.com/p?q=1"), "https://example.com/p?q=1");
});

test("TeX delimiters become math tokens while fenced and inline code remain literal", () => {
  const tokens = flatten(
    chatTokens(
      "Fixed \\(\\delta q=0\\) and $x^2$.\n\n\\[\\frac{d}{dt}p=0\\]\n\n`$literal$`\n\n```tex\n\\[not math\\]\n```",
    ),
  );
  assert.deepEqual(
    tokens.filter((t) => t.type.startsWith("reader_math")).map((t) => [t.type, t.content]),
    [
      ["reader_math", "\\delta q=0"],
      ["reader_math", "x^2"],
      ["reader_math_block", "\\frac{d}{dt}p=0"],
    ],
  );
  assert.ok(tokens.some((t) => t.type === "code_inline" && t.content === "$literal$"));
  assert.ok(tokens.some((t) => t.type === "fence" && t.content.includes("not math")));
  assert.ok(
    !flatten(chatTokens("$$unfinished\n" + "x".repeat(8001))).some((t) =>
      t.type.startsWith("reader_math"),
    ),
  );
});

test("Conversation labels retain partial, unresolved and unknown truthfulness", () => {
  const record = { attachment: { state: "attached" }, progress: "" };
  assert.match(chatStatus({ ...record, status: "completed" }), /완료/u);
  assert.match(
    chatStatus({ ...record, status: "streaming", progress: "Reading current document…" }),
    /문서를 살펴보는 중/u,
  );
  assert.match(
    chatStatus({ ...record, status: "streaming", progress: "Unknown progress" }),
    /Unknown progress/u,
  );
  assert.match(chatStatus({ ...record, status: "interrupted" }), /부분 답변/u);
  assert.match(chatStatus({ ...record, status: "failed" }), /다시 보내/u);
  assert.match(chatStatus({ ...record, status: "future-state" }), /미확인/u);
  assert.match(
    chatStatus({ ...record, status: "failed", attachment: { state: "unresolved" } }),
    /기록은 보존/u,
  );
});

test("unfinished explicit math delimiters stay literal", () => {
  const tokens = flatten(chatTokens("Unfinished \\(\\frac{1}"));
  assert.ok(tokens.some((t) => t.type === "text" && t.content.includes("\\(")));
});

test("stripMathDelimiters strips LaTeX delimiters to plain text", () => {
  assert.equal(stripMathDelimiters("\\(e_1,e_2\\)"), "e_1,e_2");
  assert.equal(stripMathDelimiters("\\[ X=3e_1+2e_2 \\]"), "X=3e_1+2e_2");
  assert.equal(
    stripMathDelimiters("Here is \\(e_1,e_2\\) and \\[ X=3e_1+2e_2 \\]"),
    "Here is e_1,e_2 and X=3e_1+2e_2",
  );
  assert.equal(stripMathDelimiters("$$A=B$$ and $x$"), "A=B and x");
  assert.equal(stripMathDelimiters("$5 and $10"), "$5 and $10");
  assert.equal(stripMathDelimiters("Cost is \\$5 and \\$10"), "Cost is \\$5 and \\$10");
  assert.equal(stripMathDelimiters("Single dollar \\$"), "Single dollar \\$");
  assert.equal(stripMathDelimiters("$5 and $10 and $x$"), "$5 and $10 and x");
  assert.equal(stripMathDelimiters("Budget is $5-$10"), "Budget is $5-$10");
  assert.equal(stripMathDelimiters("$5–$10"), "$5–$10");
  assert.equal(stripMathDelimiters("US$5–US$10"), "US$5–US$10");
  assert.equal(stripMathDelimiters("$x^2$"), "x^2");
  assert.equal(stripMathDelimiters("$2+3$"), "2+3");
});
