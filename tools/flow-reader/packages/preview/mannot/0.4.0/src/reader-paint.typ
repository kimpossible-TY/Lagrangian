// Explicit Reader primitives only. Never infer drawing code from callbacks.
#let length-spec(value) = (px: value.abs.pt() / 0.75, em: value.em)

#let edges-spec(value) = {
  if value == none { value = 0pt }
  if type(value) == length {
    return (left: length-spec(value), right: length-spec(value),
      top: length-spec(value), bottom: length-spec(value))
  }
  let rest = value.at("rest", default: 0pt)
  let x = value.at("x", default: rest)
  let y = value.at("y", default: rest)
  (left: length-spec(value.at("left", default: x)),
    right: length-spec(value.at("right", default: x)),
    top: length-spec(value.at("top", default: y)),
    bottom: length-spec(value.at("bottom", default: y)))
}

#let paint-spec(value) = {
  if value == auto { "ink" }
  else if value == none { "none" }
  else if type(value) == color { value.to-hex() }
  else { none }
}

#let stroke-spec(value, color, thickness) = {
  if value == none { return none }
  // Sided strokes, gradients, dash patterns and non-default joins stay Typst.
  if type(value) == dictionary and value.keys().any(k => k in ("top", "right", "bottom", "left", "x", "y", "rest")) {
    return false
  }
  let s = stroke(value)
  let paint = paint-spec(if s.paint == auto { color } else { s.paint })
  if paint == none or s.dash != none and s.dash != auto { return false }
  if s.cap != auto and s.cap != "butt" { return false }
  if s.join != auto and s.join != "miter" { return false }
  if s.miter-limit != auto { return false }
  (paint: paint, thickness: length-spec(if s.thickness == auto { thickness } else { s.thickness }))
}

#let local-paint(spec, color, outset, inset) = {
  if spec == none { return none }
  let result = (version: 1, kind: spec.kind, outset: edges-spec(outset), inset: edges-spec(inset))
  if spec.kind == "cancel" {
    if spec.angle != auto and type(spec.angle) != angle { return none }
    let value = spec.length + 0pt + 0%
    result += (angle: if spec.angle == auto { none } else { spec.angle / 1rad },
      ratio: value.ratio / 100%, length: length-spec(value.length),
      cross: spec.cross, inverted: spec.inverted)
  } else if spec.kind == "rect" {
    if spec.radius != (:) and spec.radius != 0pt and spec.radius != 0% { return none }
    let fill = paint-spec(spec.fill)
    if fill == none { return none }
    result += (fill: fill,)
  }
  let s = stroke-spec(spec.stroke, color, if spec.kind == "cancel" { 0.5pt } else { .048em })
  if s == false { return none }
  result += (stroke: s,)
  result
}
