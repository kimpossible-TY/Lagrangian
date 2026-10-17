#include "canvases.typ"
#import "@preview/cetz:0.4.2"

= Dense existing coordinates and a long legend
#cetz.canvas({
  import cetz.draw: *
  rect((0, 0), (14, 8), stroke: 1pt)
  line((0, 0), (14, 8), mark: (end: ">"))
  circle((7, 4), radius: 2, stroke: 1pt)
  content((6.8, 4), text(size: 6pt, $x^2+y^2$))
  content((7.2, 4), text(size: 8pt, $a+b=c$))
  content((7, 7), text(size: 6pt)[This complete explanation remains visible at the
    chosen reading size. Its words wrap automatically without opening another view.])
  content((7, 1), stack(spacing: 3pt,
    [Original stacked label],
    $integral_0^t (a+b+c+d+e+f+g+h+i+j+k+l+m+n+p+q) dif x$,
  ))
})

= Nested drawing in an original label
#cetz.canvas({
  import cetz.draw: *
  rect((0, 0), (8, 5))
  content((4, 2.5), cetz.canvas({
    import cetz.draw: *
    line((0, 0), (6, 2))
    content((3, 1), text(size: 6pt)[Nested readable label])
  }))
})

This paragraph follows every figure and remains in the ordinary reading flow.
