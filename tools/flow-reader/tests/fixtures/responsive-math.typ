#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, markhl, annot, annot-cetz
#set heading(numbering: "1")
#set math.equation(numbering: "(1)")

= Responsive mathematics

The symbols retain their selected reading size. Long sums break into lines.

$ Gamma_(i j)^k = markhl(a + b + c + d + e + f + g + h + i + j + k + l, color: #yellow, tag: #<sum>) $ <long-sum>
#annot-cetz((<sum>,), cetz, {
  import cetz.draw: *
  line("sum.south-west", "sum.south-east", stroke: red)
  content((rel: (0, -0.5), to: "sum.south"), [Same terms], anchor: "north")
})

Reference to @long-sum, and an inline $Gamma_(i j)^k$ with distinct scripts.

$ a &= b + c + d + e + f + g + h + i + j + k + l \
    &= 2 (b + c + d + e + f + g) $ <derivation>

$ mark(x^2, tag: #<square>) + y^2 = 1 $
#annot(<square>)[The square of $x$ remains visible.]

The matrix $mat(a, b; c, d)$ stays a matrix. Decorations retain vector content:
$cancel(x) + overline(A)$.

An equation reference inside math: $"see" #link(<long-sum>)[Equation 1]$.
