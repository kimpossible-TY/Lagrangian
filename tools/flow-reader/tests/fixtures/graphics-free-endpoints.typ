#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot-cetz

$ mark(x^2, tag: #<left>) + mark(y^2, tag: #<right>) = 1 $
#annot-cetz((<left>, <right>), cetz, {
  import cetz.draw: *
  set-style(mark: (end: "straight"))
  line("left.south", (10, -1), stroke: purple)
  bezier-through((-10, -1), (rel: (1, 0.5)), "right.south", stroke: blue)
})
