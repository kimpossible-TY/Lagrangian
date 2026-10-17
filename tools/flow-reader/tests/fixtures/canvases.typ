#import "@preview/cetz:0.4.2"

= Existing logical coordinates
#cetz.canvas({
  import cetz.draw: *
  rect((0, 0), (14, 4), stroke: 1pt)
  line((0, 0), (14, 4), stroke: 1pt)
  content((7, 2), [Readable label])
})

= Fixed physical geometry
#cetz.canvas({
  import cetz.draw: *
  rect((0pt, 0pt), (500pt, 80pt), stroke: 1pt)
  content((250pt, 40pt), [Fixed geometry])
})
