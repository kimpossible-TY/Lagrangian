// Original-page fixture is separate from HTML semantic reflow fixtures.
#if sys.inputs.at("original-pages-v3", default: "false") == "true" [
  #set page(width: 320pt, height: 360pt, margin: 20pt)
  #set text(size: 14pt)
  = Original One
  Page One office ffi.

  한글 é 😀 👩‍👩‍👧‍👦.

  $ (a+b)/(c+d) + sqrt(x) = y $

  #rect(width: 48pt, height: 24pt, fill: rgb("#2060c0"))
  #pagebreak()
  = Original Two
  Page Two search needle.

  #import "@preview/cetz:0.4.2": canvas, draw
  #canvas(length: 1pt, {
    import draw: *
    rect((0, 0), (80, 30), fill: rgb("#2060c0"))
    content((40, 15), [Label $x^2$], anchor: "center")
  })
  #if sys.inputs.at("original-page-count", default: "2") == "3" [
    #pagebreak()
    = Original Three
    Page Three replacement.
  ]
] else [
#set page(width: 640pt, height: 800pt, margin: 16pt)
#set text(size: 20pt)
#set math.equation(numbering: "(1)")
= Objects <objects>
한글 é 😀 👩‍👩‍👧‍👦 and $x^2 + y$ continue.

$ (a + b)/(c + d) + sqrt(x) + sum_(i=1)^n i = n(n+1)/2 $ <formula>

Inline $a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_10 + a_11 + a_12 + a_13 + a_14 + a_15 + a_16 + a_17 + a_18 + a_19 + a_20$ end.

#table(columns: 3,
  table.header([Name], [Value], [단위😀]),
  table.cell(rowspan: 2)[*Mass*], [$10$], [_kg_], [20], [g],
  table.cell(colspan: 3)[Merged],
)
#let shape = rect(width: 48pt, height: 24pt, fill: rgb("#2060c0"))
#figure(context { if target() == "html" { html.frame(shape) } else { shape } }, caption: [*Blue* _rectangle_ #link("https://example.org/objects")[link]]) <blue>
See @formula and @blue.

#import "@preview/cetz:0.4.2": canvas, draw
#let native-canvas = canvas(length: 1pt, {
  import draw: *
  set-style(stroke: 1pt + rgb("#2060c0"))
  line((0, 0), (40, 20))
  circle((20, 10), radius: 5, fill: rgb("#c02020"))
})
#figure(context { if target() == "html" { html.frame(native-canvas) } else { native-canvas } }, caption: [CeTZ vector]) <cetz>


// Actual compiler fidelity probe. The base snapshot remains independently
// renderable when the frozen importer rejects the new compiler constructs.
#if sys.inputs.at("fidelity-v2", default: "false") == "true" [
  #let labeled = canvas(length: 1pt, {
    import draw: *
    rect((0, 0), (60, 30), fill: rgb("#2060c0"))
    content((30, 15), [*Label* $x^2$], anchor: "center")
  })
  #figure(context { if target() == "html" { html.frame(labeled) } else { labeled } }, caption: [Labeled CeTZ]) <labeled>
  #figure(image("pattern.png"), caption: [Raster PNG]) <raster>
  Inline #box(image("pattern.jpg")) end.
  #figure(image("pattern.png", width: 48pt, height: 18pt, fit: "stretch"), caption: [Authored stretch])
  Width-only #box(image("pattern.jpg", width: 32pt)) tail.
  Height-only #box(image("pattern.png", height: 15pt)) tail.
  #figure(image("symbol-hidden.svg", width: 100pt, height: 40pt, fit: "stretch"), caption: [Hidden symbol clip])
]

]
