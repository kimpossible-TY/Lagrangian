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

= Small, inherited, large, and automatically scaled labels <native-floor-samples>
#cetz.canvas({
  import cetz.draw: *
  content((0, 0), text(size: 6pt, [Readable]))
  content((0, -2), [Readable])
  content((0, -4), text(size: 6pt, $x^2+y$))
  content((0, -6), $x^2+y$)
  content((0, -8), text(size: 28pt, fill: rgb("#b5261e"), weight: "bold", [Readable]))
  scope({
    scale(0.25)
    content((0, -40), text(size: 6pt, [Readable]), auto-scale: true)
  })
  content((0, -12), text(size: 28pt, $x^2+y$))
})

= A label wider than the available body
#cetz.canvas({
  import cetz.draw: *
  content((0, 0), box(width: 500pt)[This fixed content box cannot shrink.])
})
