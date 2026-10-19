#import "@local/flow-canvas:0.1.0": native-canvas as _reader-native-canvas
#import "@local/flow-inputs:0.1.0" as flow-inputs
#import "version.typ"
#import "drawable.typ"
#import "vector.typ"
#import "matrix.typ"
#import "util.typ"
#import "path-util.typ"
#import "aabb.typ"
#import "styles.typ"
#import "process.typ"
#import "coordinate.typ"

#let _canvas-context(length, debug: false, background: none) = (
    version: version.version,
    length: length,
    debug: debug,
    background: background,
    // Previous element position & bbox
    prev: (pt: (0.0, 0.0, 0.0)),
    style: styles.default,
    // Current transformation matrix, a rhs coordinate system
    // where z is sheared by a half x and y.
    //   +x = right, +y = up, +z = 1/2 (left + down)
    transform:
      ((1.0, 0.0,-0.5, 0.),
       (0.0,-1.0,+0.5, 0.),
       (0.0, 0.0, 1.0, 0.),
       (0.0, 0.0, 0.0, 1.)),
    // Nodes, stores anchors and paths
    nodes: (:),
    // Group stack
    groups: (),
    // User defined marks
    marks: (
      mnemonics: (:),
      marks: (:),
    ),
    // coordinate resolver
    resolve-coordinate: (),
    // Shared state that is not scoped by group/scope elements.
    // CeTZ itself does not use this dictionary for data.
    shared-state: (:),
  )

// Reader-only inspection uses the same layout context as the paged renderer.
// Offsets remain relative to the input coordinate origin, including negative bounds.
#let reader-bounds(body, length: 1cm, sources: false, padding: none) = {
  let result = process.many(_canvas-context(length.to-absolute()), body)
  let bounds = result.bounds
  if bounds == none { return (left: 0pt, top: 0pt, width: 0pt, height: 0pt, labels: ()) }
  let padding = util.map-dict(util.as-padding-dict(padding), (_, v) => util.resolve-number(result.ctx, v))
  bounds = aabb.padded(bounds, padding)
  let (width, height, ..) = vector.scale(aabb.size(bounds), length)
  let labels = drawable.filter-tagged(result.drawables, drawable.TAG.hidden)
    .filter(item => item.type == "content")
    .map(item => {
      let label = (
        left: (item.pos.at(0) - item.width / 2) * length,
        top: (item.pos.at(1) - item.height / 2) * length,
        width: item.width * length, height: item.height * length,
      )
      if sources { label.insert("body", item.at("reader-body", default: item.body)) }
      label
    })
  let routing = result.ctx.shared-state.at("flow-reader-routing", default: none)
  let connectors = if routing == none { () } else { routing.connectors }
  if routing != none {
    assert(routing.routes.keys().all(id => id in connectors.map(item => item.id)),
      message: "Unknown Reader connector route")
  }
  (left: bounds.low.at(0) * length, top: bounds.low.at(1) * length,
   width: width, height: height, labels: labels, connectors: connectors)
}

/// Sets up a canvas for drawing on.
///
/// - length (length): Used to specify what 1 coordinate unit is. Note that ratios are no longer supported! You can wrap the canvas into a `layout(ly => canvas(length: ly.width * <ratio>, ...))`.
/// - baseline (none,number,coordinate): Specifies the coordinate to use as the baseline. Setting this the canvas behaves like a `box` element instead of a `block`.
/// - body (none, array, element): A code block in which functions from the `draw` module have been called.
/// - background (none, color): A color to be used for the background of the canvas.
/// - stroke (none, stroke): Stroke style to apply to the canvas top-level element (box or block)
/// - padding (none, number, array, dictionary) = none: How much padding to add to the canvas. `none` applies no padding. A number applies padding to all sides equally. A dictionary applies padding following Typst's `pad` function: https://typst.app/docs/reference/layout/pad/. An array follows CSS like padding: `(y, x)`, `(top, x, bottom)` or `(top, right, bottom, left)`.
/// - debug (bool): Shows the bounding boxes of each element when `true`.
/// -> content
#let _paged-canvas(length: 1cm, baseline: none, debug: false, background: none, stroke: none, padding: none, skip-labels: false, body) = context {
  if body == none {
    return []
  }
  assert(
    type(body) == array,
    message: "Incorrect type for body: " + repr(type(body)),
  )

  // TODO: Remove in later versions
  if type(length) == ratio {
    panic("Canvas relative length support got removed! Wrap your canvas in `layout(ly => canvas(length: <ratio> * ly.width, ...))`")
  }

  assert(type(length) == std.length, message: "Expected `length` to be of type length, got " + repr(length))
  let length = length.to-absolute()
  assert(length / 1cm != 0,
    message: "Canvas length must be != 0!")

  let ctx = _canvas-context(length, debug: debug, background: background)

  let (ctx, bounds, drawables) = process.many(ctx, body)
  if bounds == none {
    return []
  }

  // Filter hidden drawables
  drawables = drawable.filter-tagged(drawables, drawable.TAG.hidden)

  // Order draw commands by z-index
  drawables = drawables.sorted(key: (cmd) => {
    return cmd.at("z-index", default: 0)
  })

  // Apply padding
  let padding = util.map-dict(util.as-padding-dict(padding), (_, v) => {
    util.resolve-number(ctx, v)
  })
  bounds = aabb.padded(bounds, padding)

  let (offset-x, offset-y, ..) = bounds.low

  // Final canvas size
  let (width, height, ..) = vector.scale(aabb.size(bounds), length)

  let relative = (orig, c) => {
    return vector.sub(c, orig)
  }

  // The top-level function the canvas gets wrapped in
  let container-fn = block.with(breakable: false)

  // Compute the baseline offset
  let baseline-offset = 0cm
  if baseline != none {
    if type(baseline) in (int, float, length) {
      baseline = (0, baseline)
    }

    let sub-ctx = ctx
    sub-ctx.transform = matrix.ident(4)

    let (_, (x, y, _)) = coordinate.resolve(sub-ctx, baseline)
    baseline-offset = length * (y - offset-y) - height

    container-fn = box.with(baseline: -baseline-offset)
  }

  (container-fn)(width: width, height: height, stroke: stroke, fill: background, align(top, {
    for drawable in drawables {
      // Typst path elements have strange bounding boxes. We need to
      // offset all paths to start at (0, 0) to make gradients work.
      let (segment-x, segment-y, _) = if drawable.type == "path" {
        vector.sub(
          aabb.aabb(path-util.bounds(drawable.segments)).low,
          bounds.low)
      } else {
        (0, 0, 0)
      }

      place(top + left, float: false, if drawable.type == "path" {
        let vertices = ()

        let transform-point((x, y, _)) = {
          ((x - offset-x - segment-x) * length,
           (y - offset-y - segment-y) * length)
        }

        for ((origin, closed, segments)) in drawable.segments {
          vertices.push(curve.move(transform-point(origin)))

          for ((kind, ..args)) in segments {
            if kind == "l" {
              for pt in args {
                vertices.push(curve.line(transform-point(pt)))
              }
            } else if kind == "c" {
              vertices.push(curve.cubic(..args.map(transform-point)))
            } else {
              panic(kind, args)
            }
          }

          if closed {
            vertices.push(curve.close(mode: "straight"))
          }
        }

        if type(drawable.stroke) == dictionary and "thickness" in drawable.stroke and type(drawable.stroke.thickness) != std.length {
          drawable.stroke.thickness *= length
        }
        std.curve(
          stroke: drawable.stroke,
          fill: drawable.fill,
          fill-rule: drawable.at("fill-rule", default: "non-zero"),
          ..vertices,
        )
      } else if drawable.type == "content" and not skip-labels {
        let (width, height) = std.measure(drawable.body)
        move(
          dx: (drawable.pos.at(0) - offset-x) * length - width / 2,
          dy: (drawable.pos.at(1) - offset-y) * length - height / 2,
          drawable.body,
        )
      }, dx: segment-x * length, dy: segment-y * length)
    }
  }))
}

// Reader geometry is expressed in CSS pixels. The drawing program and its
// coordinates are preserved. A uniform geometry transform also handles authored
// physical lengths; label boxes, glyphs and physical strokes are measured afresh.
#let _reader-canvas-counter = counter("flow-reader-canvas")

#let _reader-canvas(id, render, original-length) = context {
  let request = flow-inputs.geometry("canvases").at(id, default: none)
  let attrs = (class: "flow-drawing flow-canvas", "data-flow-canvas": id)
  if request == none {
    html.elem("span", attrs: attrs, html.frame(render(original-length)))
  } else {
    let px = 0.75pt
    // Content is laid out again at the requested reading size, instead of
    // scaling a completed SVG (which would shrink its glyphs with the paths).
    // Explicit sizes in authored content can override this inherited size;
    // width-fit alone is deliberately not a complete readability verdict.
    set text(size: request.fontSize * px)
    let available = request.width * px
    let unit = original-length
    let size = measure(render(unit))
    let natural-width = size.width
    let attempts = 0
    // Content bounds depend on unit length too, so a single proportional scale
    // is insufficient. Re-measure after every change; bound the work and retain
    // all content when fixed physical lengths prevent a width fit.
    for _ in range(12) {
      if size.width <= available + 0.25pt { break }
      let next-unit = unit * calc.max(0.05, calc.min(0.95, available / size.width * 0.99))
      if next-unit < original-length / 4096 { break }
      let next-size = measure(render(next-unit))
      if next-size.width >= size.width - 0.01pt { break }
      unit = next-unit
      size = next-size
      attempts += 1
    }
    let fitted = size.width <= available + 0.25pt
    let attempted-width = size.width
    if not fitted {
      // An impossible fit must not leave geometry crushed around fixed labels.
      unit = original-length
      size = measure(render(unit))
    }
    let result = (
      status: if fitted { "width-fit" } else { "overflow" },
      width: size.width / px, height: size.height / px,
      available: request.width, fontSize: request.fontSize,
      naturalWidth: natural-width / px, unitScale: unit / original-length,
      attemptedWidth: attempted-width / px,
      attempts: attempts,
    )
    attrs.insert("data-flow-canvas-layout", json.encode(result))
    html.elem("span", attrs: attrs, html.frame(render(unit)))
  }
}

// Individual place elements cannot be exported as independent HTML content.
#let canvas(length: 1cm, baseline: none, debug: false, background: none, stroke: none, padding: none, body) = context {
  let render(unit: length, skip-labels: false) = _paged-canvas(length: unit, baseline: baseline, debug: debug,
    background: background, stroke: stroke, padding: padding, skip-labels: skip-labels, body)
  let inspect(sources: false) = reader-bounds(body, length: length, sources: sources, padding: padding)
  if target() == "html" {
    _reader-canvas-counter.step()
    context {
      let id = "canvas-" + str(_reader-canvas-counter.get().first())
      if sys.inputs.at("flow-native-labels", default: "false") == "true" {
        _reader-native-canvas(id, render, inspect, package: "cetz:0.4.2")
      } else { _reader-canvas(id, unit => render(unit: unit), length) }
    }
  } else { render() }
}
