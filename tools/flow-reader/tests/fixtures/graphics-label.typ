#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot-cetz
$ mark(x, tag: #<origin>) = 1 $
#annot-cetz(<origin>, cetz, {
  import cetz.draw: *
  content((0, 0), [A readable label], anchor: "north-west")
})
