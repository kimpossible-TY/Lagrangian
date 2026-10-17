#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot-cetz

$ mark(x^2, tag: #<left>) + mark(y^2, tag: #<right>) = 1 $
#annot-cetz((<left>, <right>), cetz, {
  import cetz.draw: *
  set-style(mark: (end: ">"))
  bezier-through("left.south", (rel: (0, -0.5)), "right.south", name: "connection", stroke: red)
  get-ctx(ctx => {
    let (_, actual, start) = cetz.coordinate.resolve(ctx, "connection", "left.south")
    assert(cetz.vector.dist(actual, start) < 0.000001,
      message: "A routed Bezier changed its default anchor")
    ()
  })
  content("connection.mid", [Route label], anchor: "north")
})
