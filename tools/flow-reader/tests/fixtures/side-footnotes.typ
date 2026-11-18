#set text(lang: "en")
#set math.equation(numbering: "(1)")

= Connected footnotes

A prose footnote remains beside its reference.#footnote[The original *footnote emphasis* and $alpha^2 + beta^2$ remain readable. See @footnote-equation.] <shared-note>

Two references share a single note in this paragraph: #footnote(<shared-note>) and #footnote(<shared-note>).

#html.elem("figure")[#html.elem("div", attrs: (class: "flow-callout flow-proposition"))[
  Isometric isomorphism#footnote[An isometric isomorphism preserves the norm.],
  Hilbert space#footnote[A Hilbert space is complete.], and
  dense#footnote[Every element is the limit of a sequence.].
  #html.elem("p")[A nested paragraph#footnote[The nested paragraph has its own note.].]
  #html.elem("p")[Other callout text and $alpha + beta$ remain readable.]
]]

$ a &= b #footnote[The first mathematical footnote retains its full explanation.] \
    &= c #footnote[The second mathematical footnote keeps $frac(1, 2)$ and its own number.] $ <footnote-equation>

#for i in range(160) [
  Ordinary paragraph #i keeps the original footnote list in a distant transport section. This text uses the complete reading width without reserving a document-wide gutter.

]
