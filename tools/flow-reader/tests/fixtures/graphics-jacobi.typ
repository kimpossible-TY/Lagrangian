#import "@preview/cetz:0.4.2"
#import "@preview/mannot:0.4.0": mark, annot-cetz
#set math.equation(numbering: "(1)")

= Jacobi relationship routing

The original relationships follow the differentiated factors after line breaking.

$ lr(frac(d, d t) bar)_(t=t_0) op("det")(A(t)) &= lr(frac(d, d h) bar)_(h=0) op("det")(A+ h K) \
  &= lr(frac(d, d h) bar)_(h=0) op("det") A dot op("det")(I + A^(-1) K) \
  &= mark(lr(frac(d, d h) bar)_(h=0), tag: #<local-scope-annotations-2-d_dh>)
    (mark(det A, tag: #<local-scope-annotations-2-det_A>))
    (mark(I+h op("tr")(A^(-1) K), tag: #<local-scope-annotations-2-bracket>)) \
  \
  &= op("det") A dot op("tr")(A^(-1) K) $ <jacobi-routing>

// Original PDE connector program; browser-supplied geometry is independent of
// this small fixture's text. No authored offsets or control points are changed.
#annot-cetz((<local-scope-annotations-2-d_dh>, <local-scope-annotations-2-det_A>, <local-scope-annotations-2-bracket>), cetz, {
  import cetz.draw: *
  set-style(mark: (end: "straight"))
  bezier-through("local-scope-annotations-2-d_dh.south",
    (rel: (x: 0.15, y: -0.25)), "local-scope-annotations-2-det_A.south", stroke: red)
  bezier-through("local-scope-annotations-2-d_dh.north",
    (rel: (x: 0.8, y: 0.35)), "local-scope-annotations-2-bracket.north", stroke: blue)
})

The full derivation is @jacobi-routing.
