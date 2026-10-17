#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot, annot-cetz
#import "@local/math-blocks:0.2.0": flowbox
#set math.equation(numbering: "(1)")

= Visible annotations

All explanations and relationships are part of the reading body.

$ mark(x^2, tag: #<left>) + mark(y^2, tag: #<right>) = 1
  #annot(<left>)[#text(size: 6pt)[The first term is a square.]]
  #annot(<right>)[The second term is also a square.]
$ <first-equation>
#annot-cetz((<left>, <right>), cetz, {
  import cetz.draw: *
  set-style(mark: (end: ">"))
  bezier-through("left.south", (rel: (0, -0.5)), "right.south", stroke: red)
  content((rel: (0, -0.8), to: "left.south"), [Same degree], anchor: "north")
})
#annot-cetz((<right>, <left>), cetz, {
  import cetz.draw: *
  set-style(mark: (end: ">"))
  bezier-through("right.north", (rel: (0, 0.7)), "left.north", stroke: blue)
})

This paragraph must follow the complete relationship drawing without being covered.

= A relationship across blocks

#flowbox[$ mark(u, tag: #<upper>) = 2 $]
Intervening prose stays in its original position and remains selectable.
$ mark(v, tag: #<lower>) = 3 $
#annot-cetz((<upper>, <lower>), cetz, {
  import cetz.draw: *
  line("upper.east", (rel: (0.5, 0)), (horizontal: (), vertical: "lower.east"), "lower.east", stroke: purple)
})

Return to @first-equation. The end of the fixture remains visible.
