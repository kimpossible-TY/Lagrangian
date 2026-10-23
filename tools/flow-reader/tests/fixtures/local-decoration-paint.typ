#import "@preview/mannot:0.4.0": markhl, markrect, markul, core-mark
#let custom = core-mark
= Local decoration paint
$ markhl(a + b + c + d + e + f + g + h + i + j, color: #yellow) = 0 $
$ markrect(x^2 + y_1, color: #blue, outset: #(left: 1pt + .1em, y: .2em)) = 1 $
$ markul(alpha + beta + gamma, color: #red, stroke: #1pt) = 2 $
$ cancel(p + q + r + s + t + u + v + w + x + y + z) = 3 $
$ cancel(x + y, cross: #true, inverted: #true, angle: #30deg,
  length: #(130% + 2pt + .2em), stroke: #(paint: blue, thickness: 1.5pt)) = 4 $

// Rounded rectangles and callbacks retain the exact Typst path; dashes are local.
$ markrect(a + b, color: #blue, radius: #20%) = 5 $
$ markul(x + y, stroke: #(paint: red, dash: "dashed")) = 6 $
$ cancel(u + v, angle: #(a => a + 10deg)) = 7 $
$ custom(x + z, overlay: #((w, h, c) => line(end: (w, h), stroke: c))) = 8 $
$ markhl(p + q, fill: #gradient.linear(red, blue)) = 9 $

$ markul(a + b + c, stroke: #(paint: blue, thickness: .08em,
  cap: "round", dash: "dotted")) = 10 $
$ cancel(x + y, stroke: #(paint: red, thickness: 1pt + .04em,
  cap: "square", dash: (array: (2pt, .2em, "dot", 3pt), phase: -1pt + .1em))) = 11 $
$ markrect(alpha + beta, stroke: #(paint: blue, thickness: 1pt,
  join: "bevel", miter-limit: 5)) = 12 $
$ markul(x + y, stroke: #(paint: blue, dash: "solid")) = 13 $
$ markrect(x^2 + y^2, stroke: #(paint: blue, thickness: 1pt,
  join: "round", cap: "round", dash: "dash-dotted")) = 14 $
