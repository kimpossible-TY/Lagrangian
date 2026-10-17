// Reader-only connector intent. Without a configured annotation context these
// helpers are inert, including all paged rendering and ordinary CeTZ canvases.
#import "util.typ"
#import "vector.typ"

#let marker-reference(value, names) = {
  if type(value) == str {
    let parts = value.split(".")
    if parts.first() in names {
      return (tag: parts.first(), anchor: if parts.len() > 1 { parts.slice(1).join(".") } else { "default" })
    }
  } else if type(value) == dictionary and value.at("name", default: none) in names {
    let anchor = value.at("anchor", default: "default")
    return (tag: value.name, anchor: if type(anchor) == str { anchor } else { repr(anchor) })
  }
  none
}

#let connector(ctx, source-start, source-end, points, kind) = {
  let state = ctx.shared-state.at("flow-reader-routing", default: none)
  if state == none { return (ctx: ctx, points: none) }
  let start = marker-reference(source-start, state.markers)
  let end = marker-reference(source-end, state.markers)
  if start == none or end == none { return (ctx: ctx, points: none) }
  let px = 0.75pt / ctx.length
  let global = points.map(point => util.apply-transform(ctx.transform, point))
  if global.any(point => calc.abs(point.at(2)) > 0.000001) {
    return (ctx: ctx, points: none)
  }
  let id = "connector-" + str(state.connectors.len() + 1)
  let route = state.routes.at(id, default: none)
  state.connectors.push((id: id, start: start, end: end, kind: kind,
    points: global.map(point => (x: point.at(0) / px, y: point.at(1) / px)),
    routed: route != none))
  ctx.shared-state.insert("flow-reader-routing", state)
  if route == none { return (ctx: ctx, points: none) }
  let routed = route.map(point => (point.x * px, point.y * px, 0))
  assert(vector.dist(global.first(), routed.first()) < px * 0.01 and
    vector.dist(global.last(), routed.last()) < px * 0.01,
    message: "Reader connector route changed its original endpoints")
  (ctx: ctx, points: routed.map(point => util.revert-transform(ctx.transform, point)))
}
