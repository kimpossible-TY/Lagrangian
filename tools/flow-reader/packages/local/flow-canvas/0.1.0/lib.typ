// Preserve original label bodies before the paged renderer flattens their text.
// Native children participate in the same HTML/MathML export and counter pass
// as the surrounding document; dynamic geometry never recreates these bodies.
#let _native-label-body(body) = context {
  let base-size = text.size
  let math-depth = state("flow-native-label-math-depth", 0)
  let font-style() = {
    let weights = (thin: 100, hairline: 100, extralight: 200, light: 300,
      regular: 400, normal: 400, medium: 500, semibold: 600, bold: 700,
      extrabold: 800, black: 900, heavy: 900)
    let weight = if type(text.weight) in (int, float) { text.weight }
      else { weights.at(str(text.weight).replace("-", ""), default: 400) }
    ("font-size:" + str(calc.max(1, text.size / base-size)) + "em;" +
    "font-weight:" + str(weight) + ";font-style:" + str(text.style) + ";" +
    if type(text.fill) == color { "color:" + text.fill.to-hex() + ";" } else { "" })
  }
  // Typst's experimental HTML exporter does not retain every text set rule.
  // Materialize the supported label typography at its semantic boundary.
  show text: it => context {
    if target() == "html" and math-depth.get() == 0 {
      html.elem("span", attrs: (style: font-style()), it)
    }
    else { it }
  }
  show math.equation: it => context {
    if target() == "html" and math-depth.get() == 0 {
      // An identity text show rule still permits inherited rules to run.
      // Guard mathematical leaves explicitly: HTML wrappers there would turn
      // glyphs into embedded HTML and apply the outer font scale twice.
      html.elem("span", attrs: (style: font-style()), [
        #math-depth.update(value => value + 1)
        #it
        #math-depth.update(value => value - 1)
      ])
    } else { it }
  }
  show stack: it => context {
    if target() == "html" {
      let horizontal = it.dir in (ltr, rtl)
      html.elem("div", attrs: (class: "flow-canvas-stack",
        style: "display:flex;flex-wrap:wrap;gap:.25em;flex-direction:" +
          if horizontal { "row" } else { "column" }),
        it.children.filter(child => type(child) == content).join())
    } else { it }
  }
  show box: it => context {
    if target() == "html" { html.elem("span", it.body) } else { it }
  }
  show scale: it => context {
    if target() == "html" { it.body } else { it }
  }
  body
}

#let native-figure(id, model, geometry, labels, package: none) = context {
  let attrs = (class: "flow-drawing flow-canvas", id: "flow-" + id,
    "data-flow-canvas": id, "data-flow-canvas-model": json.encode(model))
  if package != none { attrs.insert("data-flow-canvas-package", package) }
  html.elem("div", attrs: attrs, [
    #html.elem("div", attrs: (class: "flow-canvas-stage"),
      geometry)
    #html.elem("div", attrs: (class: "flow-canvas-labels"), {
      for (i, item) in labels.enumerate() {
        html.elem("div", attrs: (class: "flow-canvas-label", "data-flow-canvas-label": str(i)), [
          #html.elem("span", attrs: (class: "flow-canvas-label-number", "aria-hidden": "true"), str(i + 1))
          #html.elem("div", attrs: (class: "flow-canvas-label-body"), _native-label-body(item.body))
        ])
      }
    })
  ])
}

#let native-canvas(id, render, inspect, package: none) = context {
  let bounds = inspect(sources: true)
  let size = measure(render())
  let px = 0.75pt
  let labels = bounds.labels.enumerate().map(((i, item)) => (
    id: str(i), left: (item.left - bounds.left) / px,
    top: (item.top - bounds.top) / px,
    width: item.width / px, height: item.height / px,
  ))
  let model = (version: 1, width: size.width / px, height: size.height / px, labels: labels)
  native-figure(id, model, html.frame(render(skip-labels: true)), bounds.labels, package: package)
}
