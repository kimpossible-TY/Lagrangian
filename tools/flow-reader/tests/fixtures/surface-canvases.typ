#import "@preview/maquette:0.1.3": render-obj

#let model = "g z₁\nv -1 -1 0\nv 1 -1 0\nv 0 1 1\nf 1 2 3\ng z₂\nv -1 0 0\nv 1 0 0\nv 0 1 0\nf 4 5 6\n"

= Original surface pixels with native axis labels
#for size in (12, 24) {
  render-obj(model, (width: 720, height: 420, camera: (if size == 12 { 5 } else { -5 }, -7, 6),
    cull_backface: false, background: none,
    annotations: (groups: ("z₁", "z₂"), font_size: size, offset: 18)),
    width: 100%)
}

The complete surface and both axis labels remain in the reading body.
