// Rules are target-aware because html.frame invokes the paged layout engine.
// Keep mathematical text native except for decorations not yet handled by
// Typst's MathML exporter. Never rasterize an entire paragraph or page.
#let apply-reader(body) = {
  // These tables encode mathematical structure, unlike equation alignment.
  // Keep that distinction before the HTML backend turns both into mtable.
  show math.mat: it => context {
    if target() == "html" { html.elem("mrow", attrs: ("data-flow-math-kind": "matrix"), it) } else { it }
  }
  show math.vec: it => context {
    if target() == "html" { html.elem("mrow", attrs: ("data-flow-math-kind": "vector"), it) } else { it }
  }
  show math.cases: it => context {
    if target() == "html" { html.elem("mrow", attrs: ("data-flow-math-kind": "cases"), it) } else { it }
  }
  show math.binom: it => context {
    if target() == "html" { html.elem("mrow", attrs: ("data-flow-math-kind": "binomial"), it) } else { it }
  }
  show align: it => context {
    if target() == "html" {
      html.elem("div", attrs: (class: "flow-aligned"), it.body)
    } else { it }
  }
  show pad: it => context {
    if target() == "html" { html.elem("div", it.body) } else { it }
  }
  show grid: it => context {
    if target() == "html" {
      html.elem("div", attrs: (class: "flow-grid"), it.children.join())
    } else { it }
  }
  show grid.cell: it => context {
    if target() == "html" { html.elem("div", it.body) } else { it }
  }
  let layout-element = layout(_ => []).func()
  show layout-element: it => context {
    if target() == "html" {
      html.elem("span", attrs: (class: "flow-drawing"), html.frame(it))
    } else { it }
  }
  show math.cancel: it => context {
    if target() == "html" { box(html.frame(math.equation(it, numbering: none))) } else { it }
  }
  show math.overline: it => context {
    if target() == "html" { box(html.frame(math.equation(it, numbering: none))) } else { it }
  }
  show math.equation: it => context {
    if target() == "html" and it.block {
      html.elem("div", attrs: (class: "flow-equation"), [
        #it
        #if it.numbering != none {
          html.elem("span", attrs: (class: "flow-equation-number"),
            counter(math.equation).display(it.numbering))
        }
      ])
    } else { it }
  }
  // Page furniture has no position in a continuous reading flow.
  show pagebreak: it => context { if target() != "html" { it } }
  show v: it => context { if target() != "html" { it } }
  show h: it => context {
    if target() == "html" { [ ] } else { it }
  }
  show repeat: it => context {
    if target() == "html" { it.body } else { it }
  }
  body
}
