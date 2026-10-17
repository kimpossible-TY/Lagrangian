#import "@preview/mannot:0.4.0": markhl, markul, markrect, markuw, markub, core-mark, annot
#let custom = core-mark
#set math.equation(numbering: "(1)")
= Semantic decorations
$ markhl(a + b + c + d + e + f + g + h, color: #yellow, tag: #<sum>) = z $
#annot(<sum>)[Each term remains selectable.]
$ markul(x^2 + y^2, color: #red) = markrect(1, color: #blue) $
$ markuw(alpha + beta, color: #green) + markub(gamma + delta, color: #purple) $
$ custom(p + q, color: #orange,
  underlay: #((w, h, c) => rect(width: w, height: h, fill: c.transparentize(80%), stroke: none)),
  overlay: #((w, h, c) => line(start: (0pt, 0pt), end: (w, h), stroke: c))) = 0 $
