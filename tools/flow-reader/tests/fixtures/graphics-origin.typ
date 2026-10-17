#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot-cetz

$ mark(x, tag: #<origin>) $
#annot-cetz(<origin>, cetz, {
  import cetz.draw: *
  // Literal coordinates are relative to the first marked term, as in PDF.
  rect((-1, 1), (1, -1), stroke: 1pt)
})
