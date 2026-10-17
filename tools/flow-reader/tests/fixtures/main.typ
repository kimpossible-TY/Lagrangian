#import "@local/math-blocks:0.2.0": flowbox, theorem, apply-math-block-reset
#import "@preview/mannot:0.4.0": mark, markul, annot
#set heading(numbering: "1.1")
#set math.equation(numbering: "(1)")
#show: apply-math-block-reset

= Mobile mathematical reading

This paragraph must remain selectable text and wrap when the reader enlarges
the font. It contains inline mathematics $x^2 + y^2$ and a footnote.#footnote[
  Footnotes remain linked to their text after a resize.
]

#theorem[For $x in RR$, $x^2 >= 0$.] <positive>

#flowbox[
  $ x^2 + y^2 = 1 $ <circle>
  These paragraphs and the equation label remain visible inside a derivation.
]
We refer to @circle and @positive from outside their containers.

$ mark(x^2, tag: #<square>) + markul(y^2, tag: #<other>) = 1
  #annot(<square>)[The square of $x$.]
  #annot(<other>)[The square of $y$.]
$ <marked>

Mathematical decorations must survive: $cancel(x) + overline(A)$.

$ a &= b #footnote[An inline math footnote must not break the next row.] \
    &= c/d $ <math-footnote>

#pad(left: 2em)[#align(center)[$ a + b = c $ <nested>]]
Nested reference: @nested. Annotated reference: @marked.

#grid(columns: (1fr, 1fr), [First panel], [Second panel])
