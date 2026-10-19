#import "@preview/mannot:0.4.0": mark, annot
#set text(lang: "en")
#set math.equation(numbering: "(1)")

= Adaptive authored annotations

For the chosen extension, substitute into the split convolution:

$ u(x) = integral_0^infinity underbrace(p_t(x-z) - p_t(x+z), "kernel") f(z) dif z $ <kernel-equation>

The minus sign comes from the odd extension. The boundary contributions cancel.

$ mark(alpha + beta, tag: #<long-term>) = gamma $
#annot(<long-term>)[The two terms describe independent contributions. This longer explanation retains its *original emphasis* and the formula $alpha + beta$.]

$ overbrace(a + b, "sum") + underbracket(c + d, "lower group") + overbracket(e + f, "upper group") = z $

$ mark(x, tag: #<shared>) + y = 1 $
#annot(<shared>)[first]
#annot(<shared>)[Another explanation associated with the same original term.]

$ frac(alpha + beta + gamma, mark(x, tag: #<denominator>)) = 1 $
#annot(<denominator>)[denominator]

$ underbrace(e^i(e_j), delta_j^i) = delta_j^i $

$ mark(lambda, tag: #<stacked>) = 1 #footnote[This longer footnote shares its equation with three short annotation names.] $
#annot(<stacked>)[first identifier]
#annot(<stacked>)[second identifier]
#annot(<stacked>)[third identifier]

$ mark(zeta, tag: #<wide-name>) = 2 $
#annot(<wide-name>)[WWWWWWWWWWWWWWWWWWWWWWWW]

A wrapping prose paragraph keeps its earlier lines visible while $mark(x, tag: #<prose-term>)$ carries an inline annotation and the remaining sentence follows it.
#annot(<prose-term>)[passage]

An unlabeled grouping decoration stays intact: $underbrace(a+b)$.

A prose reference has its own footnote.#footnote[The original *footnote emphasis* and $alpha^2 + beta^2$ remain readable. See @kernel-equation.]

$ a &= b #footnote[The first mathematical footnote retains its full explanation.] \
    &= c #footnote[The second mathematical footnote keeps $frac(1, 2)$ and its own number.] $

#for i in range(10) [
  Ordinary trailing paragraph #i preserves vertical reading and selection.

]
