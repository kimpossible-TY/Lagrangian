// maquette — render 3D models (STL, OBJ, PLY) as SVG or PNG images in Typst

#let maquette-plugin = plugin("maquette.wasm")

#let _parse-args(args) = {
  // Extract display args (not part of render config)
  let named = args.named()
  let width = named.at("width", default: auto)
  let height = named.at("height", default: auto)
  let format = named.at("format", default: "png")

  // Build config: named params (minus display args) merged with positional dict if any
  let config = (:)
  if args.pos().len() > 0 {
    let first = args.pos().at(0)
    if type(first) == dictionary {
      config = first
    }
  }
  for (k, v) in named {
    if k not in ("width", "height", "format") {
      config.insert(k, v)
    }
  }
  (
    cfg: bytes(json.encode(config)),
    width: width,
    height: height,
    format: format,
  )
}

#let _u32le(data, i) = data.at(i) + data.at(i + 1) * 256 + data.at(i + 2) * 65536 + data.at(i + 3) * 16777216

#let _raw-image(px, w, h, width, height) = image(
  px, format: (encoding: "rgba8", width: w, height: h), width: width, height: height,
)

// Resolve a requested dimension (auto / length / ratio / relative) to a
// concrete length against `base`. Needed because `place`d children can't carry
// relative sizes — they collapse to zero (see the 0x02 overlay path).
#let _resolve(dim, base) = {
  if dim == auto { auto }
  else if type(dim) == length { dim }
  else if type(dim) == ratio { dim * base }
  else { dim.ratio * base + dim.length } // relative = ratio + length
}

#import "@local/flow-canvas:0.1.0": native-figure

#let _reader-svg(node) = {
  if type(node) == str { node }
  else if type(node) == dictionary and node.tag != "text" {
    html.elem(node.tag, attrs: node.attrs, node.children.map(_reader-svg).join())
  }
}

#let _reader-text-count(node) = {
  if type(node) != dictionary { 0 }
  else { (if node.tag == "text" { 1 } else { 0 }) + node.children.map(_reader-text-count).sum(default: 0) }
}

#let _reader-surface(raster, w, h, overlay) = context {
  let root = xml(overlay).find(node => type(node) == dictionary and node.tag == "svg")
  assert(root != none, message: "Missing Maquette SVG overlay")
  let text-nodes = root.children.filter(node => type(node) == dictionary and node.tag == "text")
  assert(_reader-text-count(root) == text-nodes.len(), message: "Unsupported nested Maquette labels")
  let labels = text-nodes.map(node => {
    assert(node.children.all(value => type(value) == str), message: "Unsupported nested Maquette text")
    assert(node.attrs.keys().all(key => key in ("x", "y", "font-family", "font-size", "fill", "text-anchor")),
      message: "Unsupported transformed Maquette text")
    let size = float(node.attrs.at("font-size", default: "16")) * .75pt
    let body = text(font: "Arial", size: size,
      fill: rgb(node.attrs.at("fill", default: "#000000")), node.children.join())
    (body: html.elem("span", attrs: (style: "font-family:" +
        node.attrs.at("font-family", default: "sans-serif")), body),
      x: float(node.attrs.at("x")), y: float(node.attrs.at("y")),
      align: node.attrs.at("text-anchor", default: "start"))
  })
  let model = (version: 1, width: w, height: h, labels: labels.enumerate().map(((i, item)) => (
    id: str(i), left: item.x, top: item.y, width: 0, height: 0,
    align: item.align, baseline: true,
  )))
  let geometry = html.elem("svg", attrs: (xmlns: "http://www.w3.org/2000/svg",
    viewBox: "0 0 " + str(w) + " " + str(h), width: str(w), height: str(h)), [
    #html.elem("g", attrs: ("data-flow-raster-layer": "true"),
      html.frame(_raw-image(raster, w, h, w * .75pt, h * .75pt)))
    #root.children.map(_reader-svg).join()
  ])
  let number = counter("flow-reader-canvas")
  number.update(value => value + 1)
  context { native-figure("canvas-" + str(number.get().first()), model, geometry, labels,
    package: "maquette:0.1.3") }
}

#let _render(data, png-fn, svg-fn, args) = {
  let a = _parse-args(args)
  if a.format != "png" {
    image(svg-fn(data, a.cfg), format: "svg", width: a.width, height: a.height)
  } else {
    let result = png-fn(data, a.cfg)
    let marker = result.at(0)
    if marker == 0x00 {
      // Raw RGBA: [0x00][w u32 LE][h u32 LE][rgba8…]. Embedding the pixels
      // directly skips PNG encode (plugin) and decode (Typst), and avoids
      // re-compressing for the PDF.
      _raw-image(result.slice(9), _u32le(result, 1), _u32le(result, 5), a.width, a.height)
    } else if marker == 0x02 {
      // Raster + vector overlay: [0x02][w][h][rgba8 w*h*4][svg]. Layer the
      // transparent SVG (labels / grid lines / annotations / debug text) over
      // the raw pixels — no PNG anywhere.
      let w = _u32le(result, 1)
      let h = _u32le(result, 5)
      let n = w * h * 4
      let raster = result.slice(9, 9 + n)
      let overlay = result.slice(9 + n)
      // `place` can NOT resolve a relative size (`100%`, `58%`, …) for its
      // child — it collapses to zero and the overlay silently vanishes — so
      // both layers must receive the *same concrete* lengths. Resolve the
      // requested size against the container (via `layout`), fill the width
      // when nothing is given (like a bare SVG image), and otherwise keep the
      // render's aspect ratio (viewBox w×h) for any auto axis.
      context {
        if target() == "html" and sys.inputs.at("flow-native-labels", default: "false") == "true" {
          _reader-surface(raster, w, h, overlay)
        } else {
          layout(size => {
            let dw = _resolve(a.width, size.width)
            let dh = _resolve(a.height, size.height)
            if dw == auto and dh == auto {
              dw = size.width
              dh = size.width * h / w
            } else if dw == auto {
              dw = dh * w / h
            } else if dh == auto {
              dh = dw * h / w
            }
            box({
              _raw-image(raster, w, h, dw, dh)
              place(top + left, image(overlay, format: "svg", width: dw, height: dh))
            })
          })
        }
      }
    } else {
      // 0x3C — a pure SVG (defensive; raster mode returns 0x00 or 0x02).
      image(result, format: "svg", width: a.width, height: a.height)
    }
  }
}

/// Render an STL model to an image (PNG raster by default, `format: "svg"` for vector).
///
/// 🔗 *Dial in the camera, lighting and materials visually in the live web demo, then
/// copy the generated code:* https://bernsteining.github.io/maquette/
///
/// - stl-data (bytes): STL file contents — read with `encoding: none` (binary STL).
/// - ..args (arguments): render config, as named arguments or a single dictionary
///   (camera, lights, material, shading, post-processing, …).
/// -> content
#let render-stl(stl-data, ..args) = {
  _render(stl-data, maquette-plugin.render_stl_png, maquette-plugin.render_stl, args)
}

/// Render a Wavefront OBJ model to an image (PNG raster by default, `format: "svg"` for vector).
///
/// 🔗 *Dial in the camera, lighting and materials visually in the live web demo, then
/// copy the generated code:* https://bernsteining.github.io/maquette/
///
/// - obj-data (bytes, str): OBJ file contents (reading with `encoding: none` is recommended).
/// - ..args (arguments): render config, as named arguments or a single dictionary
///   (camera, lights, material, shading, post-processing, …).
/// -> content
#let render-obj(obj-data, ..args) = {
  let data = bytes(obj-data)
  _render(data, maquette-plugin.render_obj_png, maquette-plugin.render_obj, args)
}

/// Render a PLY model or point cloud to an image (PNG raster by default, `format: "svg"` for vector).
///
/// 🔗 *Dial in the camera, lighting and materials visually in the live web demo, then
/// copy the generated code:* https://bernsteining.github.io/maquette/
///
/// - ply-data (bytes): PLY file contents — read with `encoding: none`.
/// - ..args (arguments): render config, as named arguments or a single dictionary
///   (camera, lights, material, point-cloud reconstruction, …).
/// -> content
#let render-ply(ply-data, ..args) = {
  _render(ply-data, maquette-plugin.render_ply_png, maquette-plugin.render_ply, args)
}

/// STL model metadata (triangles, vertices, bounding box, resolved camera) as a dictionary.
///
/// 🔗 *Explore models interactively in the live web demo:* https://bernsteining.github.io/maquette/
///
/// - stl-data (bytes): STL file contents — read with `encoding: none`.
/// - ..args (arguments): optional config affecting the resolved camera/projection.
/// -> dictionary
#let get-stl-info(stl-data, ..args) = {
  let a = _parse-args(args)
  json(maquette-plugin.get_stl_info(stl-data, a.cfg))
}

/// OBJ model metadata (triangles, vertices, bounding box, groups, resolved camera) as a dictionary.
///
/// 🔗 *Explore models interactively in the live web demo:* https://bernsteining.github.io/maquette/
///
/// - obj-data (bytes, str): OBJ file contents.
/// - ..args (arguments): optional config affecting the resolved camera/projection.
/// -> dictionary
#let get-obj-info(obj-data, ..args) = {
  let a = _parse-args(args)
  json(maquette-plugin.get_obj_info(bytes(obj-data), a.cfg))
}

/// PLY model metadata (triangles, vertices, bounding box, resolved camera) as a dictionary.
///
/// 🔗 *Explore models interactively in the live web demo:* https://bernsteining.github.io/maquette/
///
/// - ply-data (bytes): PLY file contents — read with `encoding: none`.
/// - ..args (arguments): optional config affecting the resolved camera/projection.
/// -> dictionary
#let get-ply-info(ply-data, ..args) = {
  let a = _parse-args(args)
  json(maquette-plugin.get_ply_info(ply-data, a.cfg))
}
