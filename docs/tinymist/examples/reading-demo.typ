// A small document for trying Flow's reading and selected-text actions.
#let dark = sys.inputs.at("theme", default: "light") == "dark"
#let foreground = if dark { rgb("e7edf7") } else { rgb("24324a") }
#let background = if dark { rgb("172033") } else { rgb("fbfcff") }
#let highlighted(body) = highlight(
  fill: if dark { rgb("63521f") } else { rgb("fff0a8") },
  body,
)
#set page(width: 108mm, height: 190mm, margin: 10mm, fill: background)
#set text(font: "New Computer Modern", size: 11pt, fill: foreground)
#set par(leading: 0.65em)
#set heading(numbering: none)
#set math.equation(numbering: "(1)")

= Read, select, continue

Keep your Typst document close while you read on a phone or tablet. Saved edits appear in the live preview.

== Mark what matters

#highlighted[Source highlights also appear in your exported document.]

Select this sentence to save it for Codex or add a red strike.

Use Highlight to update the source, Save for Codex to keep the selected text, or Red strike for a mark in this browser.

== Follow a reference

For a familiar example, see @energy. Tap the reference, then use Back to reference to return here.

$ E = m c^2 $ <energy>

== Match your device

Choose System, Light, or Dark in the preview. This example supports both document palettes.
