#set page(width: 320pt, height: auto, margin: 16pt)
#set text(size: 14pt)
#set math.equation(numbering: "(1)")
= Native contract <intro>

한글 한글 é 😀 👩‍👩‍👧‍👦 office ffi abc אבג 123.

Plain *bold* _emphasis_ #link("https://example.org/reader")[link] and $x^2 + y$.

Repeated paragraph.

Repeated paragraph.

$ integral_0^1 x^2 dif x = 1/3 $ <eq>

#table(columns: 2,
  table.header([Name], [Value]),
  [Alpha], [10],
  table.cell(colspan: 2)[Merged],
)

#let contract-shape = rect(width: 48pt, height: 24pt, fill: rgb("#2060c0"))
#figure(context { if target() == "html" { html.frame(contract-shape) } else { contract-shape } }, caption: [Blue rectangle]) <fig>

#import "@preview/mannot:0.4.0": mark, annot
#mark(tag: <term>)[Term]
#annot(<term>)[Note]

== Next <next>
See @eq and @fig.
