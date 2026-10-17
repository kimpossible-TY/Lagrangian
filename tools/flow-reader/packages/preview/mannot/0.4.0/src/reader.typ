// Reader-only decoration output. The mathematical body stays in MathML.
#import "util.typ": coerce-outset

#let decoration-counter = counter("flow-reader-decoration")

#let decoration(id, underlay, overlay, color, outset, inset) = context {
  let request = json(bytes(sys.inputs.at("flow-decorations", default: "{}"))).at(id, default: none)
  if request != none {
    let px = 0.75pt
    set text(size: request.fontSize * px)
    // Internal stretched brackets are decoration, not numbered document equations.
    set math.equation(numbering: none)
    context {
      let outset = coerce-outset(outset)
      let color = if color == auto { rgb(request.ink) } else { color }
      for (index, fragment) in request.fragments.enumerate() {
        let width = fragment.width * px + outset.left + outset.right
        let height = fragment.height * px + outset.top + outset.bottom
        let inset = inset
        let front = if overlay != none { overlay(width, height, color) }
        if type(front) == array {
          inset = front.at(1)
          front = front.first()
        }
        let inset = coerce-outset(inset)
        let layout = (
          left: -outset.left / px, top: -outset.top / px,
          width: width / px, height: height / px,
          anchor: (left: -(outset.left + inset.left) / px,
            top: -(outset.top + inset.top) / px,
            width: (width + inset.left + inset.right) / px,
            height: (height + inset.top + inset.bottom) / px),
        )
        for (layer, drawing) in (("under", if underlay != none { underlay(width, height, color) }), ("over", front)) {
          if drawing != none {
            html.elem("mtext", html.elem("span", attrs: (
              "data-flow-decoration-rendered": id,
              "data-flow-decoration-fragment": str(index),
              "data-flow-decoration-layer": layer,
              "data-flow-decoration-layout": json.encode(layout),
            ), html.frame(box(width: width, height: height,
              place(top + left, float: false, drawing)))))
          }
        }
      }
    }
  }
}
