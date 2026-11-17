#set page(width: 640pt, height: 800pt, margin: 16pt)
#set text(size: 20pt)
#set math.equation(numbering: "(1)")
= Objects <objects>
한글 é 😀 👩‍👩‍👧‍👦 and $x^2 + y$ continue.

$ (a + b)/(c + d) + sqrt(x) + sum_(i=1)^n i = n(n+1)/2 $ <formula>

Inline $a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_10 + a_11 + a_12 + a_13 + a_14 + a_15 + a_16 + a_17 + a_18 + a_19 + a_20$ end.

#table(columns: 3,
  table.header([Name], [Value], [단위😀]),
  table.cell(rowspan: 2)[Mass], [$10$], [kg], [20], [g],
  table.cell(colspan: 3)[Merged],
)
#let shape = rect(width: 48pt, height: 24pt, fill: rgb("#2060c0"))
#figure(context { if target() == "html" { html.frame(shape) } else { shape } }, caption: [Blue rectangle]) <blue>
See @formula and @blue.

#import "@preview/cetz:0.4.2": canvas, draw
#let native-canvas = canvas(length: 1pt, {
  import draw: *
  set-style(stroke: 1pt + rgb("#2060c0"))
  line((0, 0), (40, 20))
  circle((20, 10), radius: 5, fill: rgb("#c02020"))
})
#figure(context { if target() == "html" { html.frame(native-canvas) } else { native-canvas } }, caption: [CeTZ vector]) <cetz>
