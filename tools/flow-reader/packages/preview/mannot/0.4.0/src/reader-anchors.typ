// A marked mathematical term can occupy several lines. Keep every rectangle
// and resolve anchors on actual fragments, never on the empty union between them.
#let fragment-marker(cetz, name, fragments, origin) = {
  let px = 0.75pt / 1cm
  let rectangles = fragments.map(rect => cetz.draw.rect(
    ((rect.x - origin.x) * px, -(rect.y - origin.y) * px),
    ((rect.x + rect.width - origin.x) * px, -(rect.y + rect.height - origin.y) * px),
    stroke: none, fill: none))
  if fragments.len() == 1 {
    let rect = fragments.first()
    return cetz.draw.rect(
      ((rect.x - origin.x) * px, -(rect.y - origin.y) * px),
      ((rect.x + rect.width - origin.x) * px, -(rect.y + rect.height - origin.y) * px),
      name: name, stroke: none, fill: none)
  }
  (ctx => {
    let result = cetz.process.many(ctx, rectangles.join())
    let elements = result.elements
    let local(point) = cetz.util.revert-transform(ctx.transform, point)
    let areas = fragments.map(rect => rect.width * rect.height)
    let centers = elements.map(element => local((element.anchors)("center")))
    let center = cetz.vector.scale(centers.enumerate().map(((index, point)) =>
      cetz.vector.scale(point, areas.at(index))).fold((0, 0, 0), cetz.vector.add),
      1 / areas.sum())
    let lengths = fragments.map(rect => 2 * (rect.width + rect.height) * px)
    let compass = (east: 0deg, north-east: 45deg, north: 90deg,
      north-west: 135deg, west: 180deg, south-west: 225deg,
      south: 270deg, south-east: 315deg)
    let paths = (start: 0%, mid: 50%, end: 100%)
    let anchors(anchor) = {
      if anchor == () { return (elements.first().anchors)(()) }
      if type(anchor) == array { anchor = anchor.join(".") }
      if anchor in ("default", "center") {
        let index = range(elements.len()).sorted(key: index =>
          cetz.vector.dist(centers.at(index), center)).first()
        return (elements.at(index).anchors)("center")
      }
      if type(anchor) == str {
        if anchor in compass { anchor = compass.at(anchor) }
        else if anchor in paths { anchor = paths.at(anchor) }
        else if cetz.util.str-is-number(anchor) { anchor = cetz.util.str-to-number(anchor) }
      }
      if type(anchor) in (ratio, int, float) {
        // Path anchors traverse the fragment perimeters in logical order.
        // The gaps between lines contribute no invented path segments.
        let distance = if type(anchor) == ratio { anchor / 100% * lengths.sum() } else { anchor }
        assert(distance >= 0 and distance <= lengths.sum(),
          message: "Fragment path anchor is outside its perimeter")
        for (index, length) in lengths.enumerate() {
          if distance <= length or index == lengths.len() - 1 {
            return (elements.at(index).anchors)(calc.min(100%, distance / length * 100%))
          }
          distance -= length
        }
      }
      if type(anchor) == angle {
        // Choose the furthest fragment edge in the requested direction. Equal
        // projections prefer the edge nearest the area's weighted center.
        let candidates = elements.map(element => (element.anchors)(anchor))
        let direction = (calc.cos(anchor), calc.sin(anchor), 0)
        let projections = candidates.map(point => cetz.vector.dot(local(point), direction))
        let furthest = calc.max(..projections)
        let index = range(elements.len()).filter(index =>
          calc.abs(projections.at(index) - furthest) < 0.000001)
          .sorted(key: index => cetz.vector.dist(local(candidates.at(index)), center)).first()
        return candidates.at(index)
      }
      // Let CeTZ retain its normal diagnostic for unsupported anchor names.
      (elements.first().anchors)(anchor)
    }
    (ctx: result.ctx, name: name, anchors: anchors, drawables: result.drawables)
  },)
}
