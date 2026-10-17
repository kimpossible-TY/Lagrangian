#import "@preview/cetz:0.3.4" as cetz
#import "@preview/fletcher:0.5.8": diagram, node, edge

= Existing older CeTZ coordinates
#cetz.canvas({
  import cetz.draw: *
  line((0, 0), (14, 5), mark: (end: ">"))
  circle((7, 2.5), radius: 1.5)
  content((3, 2), text(size: 6pt)[Older readable source label])
  content((10, 4), text(size: 6pt, $x^2+y^2$))
  content((4, 4), $hat(omega)$)
  content((8, 1), $tilde(omega)$)
})

= Fletcher keeps its original CeTZ dependency
#diagram(
  node((0, 0), [Original node $u$], shape: rect),
  node((1, 0), [Target node $v$], shape: rect),
  edge((0, 0), (1, 0), "->", [Original edge $f$]),
  spacing: 4cm,
  node-stroke: 0.8pt,
)

All source content follows the drawings without another reading action.
