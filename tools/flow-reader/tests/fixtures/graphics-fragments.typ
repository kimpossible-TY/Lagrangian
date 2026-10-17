#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot-cetz

= Fragmented relationship anchors

$ mark(a + b + c + d + e + f, tag: #<left>) = mark(g, tag: #<right>) $
#annot-cetz((<left>, <right>), cetz, {
  import cetz.draw: *
  get-ctx(ctx => {
    let px = 0.75pt / 1cm
    let point(anchor) = {
      let (_, position) = cetz.coordinate.resolve(ctx, (name: "left", anchor: anchor))
      (80 + position.at(0) / px, 20 - position.at(1) / px)
    }
    let expected = (north: (100, 20), south: (45, 80), east: (120, 30),
      west: (10, 70), center: (45, 70), default: (45, 70),
      start: (80, 20), mid: (20, 80), end: (10, 60))
    for (anchor, position) in expected {
      assert(cetz.vector.dist(point(anchor), position) < 0.001,
        message: repr((anchor, point(anchor), position)))
    }
    assert(cetz.vector.dist(point("50%"), (20, 80)) < 0.001)
    for anchor in range(0, 360, step: 15).map(value => value * 1deg) {
      let (x, y) = point(anchor)
      let on-rectangle(left, top, right, bottom) = {
        let within = (x >= left - 0.001 and x <= right + 0.001 and
          y >= top - 0.001 and y <= bottom + 0.001)
        within and calc.min(calc.abs(x - left), calc.abs(x - right),
          calc.abs(y - top), calc.abs(y - bottom)) < 0.001
      }
      assert(on-rectangle(80, 20, 120, 40) or on-rectangle(10, 60, 80, 80),
        message: repr((anchor, x, y)))
    }
    ()
  })
  line("left.south", "right.north", stroke: red, mark: (end: ">"))
})
