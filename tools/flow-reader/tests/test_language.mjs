import assert from "node:assert/strict";
import test from "node:test";
import { languageOf, setLanguage } from "../web/ui/language.js";

const xml = "http://www.w3.org/XML/1998/namespace";
const html = "http://www.w3.org/1999/xhtml";
function element(parentElement = null, namespaceURI = html) {
  const attributes = new Map();
  return {
    parentElement,
    namespaceURI,
    getAttribute: (name) => attributes.get(name) ?? null,
    getAttributeNS: (namespace, name) => attributes.get(`${namespace}:${name}`) ?? null,
    setAttribute: (name, value) => attributes.set(name, value),
    setAttributeNS: (namespace, name, value) =>
      attributes.set(`${namespace}:${name.split(":").at(-1)}`, value),
    removeAttribute: (name) => attributes.delete(name),
    removeAttributeNS: (namespace, name) => attributes.delete(`${namespace}:${name}`),
  };
}

test("source language follows its nearest ancestor and preserves an explicit unknown language", () => {
  const article = element();
  setLanguage(article, "en");
  const paragraph = element(article);
  const term = element(paragraph);
  assert.equal(languageOf(term), "en");
  setLanguage(paragraph, "fr");
  assert.equal(languageOf(term), "fr");
  setLanguage(paragraph, "");
  assert.equal(languageOf(term), "");
  setLanguage(paragraph, null);
  assert.equal(languageOf(term), "en");
  assert.equal(languageOf(element()), null);
});

test("MathML and SVG language uses XML attributes when moved into Korean UI", () => {
  const ui = element();
  setLanguage(ui, "ko");
  const math = element(ui, "http://www.w3.org/1998/Math/MathML");
  math.setAttribute("lang", "ko");
  setLanguage(math, "en");
  assert.equal(math.getAttribute("lang"), null);
  assert.equal(math.getAttributeNS(xml, "lang"), "en");
  assert.equal(languageOf(element(math)), "en");
  setLanguage(math, null);
  assert.equal(languageOf(math), "ko");
  const svg = element(ui, "http://www.w3.org/2000/svg");
  setLanguage(svg, "ko");
  assert.equal(svg.getAttributeNS(xml, "lang"), "ko");
});
