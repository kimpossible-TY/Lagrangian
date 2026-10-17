#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot-cetz

= Graphical annotation geometry

$ mark(x^2, tag: #<left>) + mark(y^2, tag: #<right>) = 1 $
#annot-cetz((<left>, <right>), cetz, {
  import cetz.draw: *
  set-style(mark: (end: ">"))
  bezier-through("left.south", (rel: (0, -0.5)), "right.south", stroke: red)
  content((rel: (0, -0.4), to: "left.south"), [Same degree], anchor: "north")
})
