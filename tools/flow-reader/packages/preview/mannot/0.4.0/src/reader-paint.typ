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
  // Sided strokes and gradients stay Typst. Resolve dash names through Typst.
  if type(value) == dictionary and value.keys().any(k => k in ("top", "right", "bottom", "left", "x", "y", "rest")) {
    return false
  }
  let s = stroke(value)
  let paint = paint-spec(if s.paint == auto { color } else { s.paint })
  if paint == none { return false }
  let dash = if s.dash == none or s.dash == auto { none } else {
    (array: s.dash.array.map(v => if v == "dot" { "dot" } else { length-spec(v) }),
      phase: length-spec(s.dash.phase))
  }
  (paint: paint, thickness: length-spec(if s.thickness == auto { thickness } else { s.thickness }),
    cap: if s.cap == auto { "butt" } else { s.cap },
    join: if s.join == auto { "miter" } else { s.join },
    miter: if s.miter-limit == auto { 4 } else { s.miter-limit }, dash: dash)
}

#let local-paint(spec, color, outset, inset) = {
  if spec == none { return none }
  let result = (version: 2, kind: spec.kind, outset: edges-spec(outset), inset: edges-spec(inset))
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
