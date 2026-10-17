// Keep named term endpoints exact; literal free ends may adapt to reading space.
// Coordinates stay in CSS pixels; CeTZ retains the path's original marks/styles.
const EPS = 0.001;
const round = (n) => Math.round(n * 1000) / 1000;
const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

export function segmentHits(a, b, rect) {
  // Open rectangle interiors allow a channel exactly on the padded boundary.
  let low = 0,
    high = 1;
  for (const [axis, minimum, maximum] of [
    ["x", rect.left + EPS, rect.right - EPS],
    ["y", rect.top + EPS, rect.bottom - EPS],
  ]) {
    const delta = b[axis] - a[axis];
    if (Math.abs(delta) < EPS) {
      if (a[axis] < minimum || a[axis] > maximum) return false;
    } else {
      const enter = (minimum - a[axis]) / delta,
        exit = (maximum - a[axis]) / delta;
      low = Math.max(low, Math.min(enter, exit));
      high = Math.min(high, Math.max(enter, exit));
      if (low > high) return false;
    }
  }
  return true;
}

function padded(rect, amount) {
  return {
    left: rect.left - amount,
    top: rect.top - amount,
    right: rect.right + amount,
    bottom: rect.bottom + amount,
  };
}

export function sampleConnection(connector) {
  if (connector.kind !== "cubic") return connector.points;
  const [a, b, c, d] = connector.points;
  const steps = Math.min(
    2000,
    Math.max(8, Math.ceil(distance(a, b) + distance(b, c) + distance(c, d))),
  );
  return Array.from({ length: steps + 1 }, (_, i) => {
    const t = i / steps,
      s = 1 - t;
    return {
      x: s * s * s * a.x + 3 * s * s * t * b.x + 3 * s * t * t * c.x + t * t * t * d.x,
      y: s * s * s * a.y + 3 * s * s * t * b.y + 3 * s * t * t * c.y + t * t * t * d.y,
    };
  });
}

export function pathHits(points, obstacles) {
  return points.slice(1).some((b, i) => obstacles.some((rect) => segmentHits(points[i], b, rect)));
}

class Heap {
  items = [];
  push(item) {
    const a = this.items;
    a.push(item);
    let i = a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (a[p].score <= item.score) break;
      a[i] = a[p];
      i = p;
    }
    a[i] = item;
  }
  pop() {
    const a = this.items,
      first = a[0],
      last = a.pop();
    if (a.length) {
      let i = 0;
      while (i * 2 + 1 < a.length) {
        let child = i * 2 + 1;
        if (child + 1 < a.length && a[child + 1].score < a[child].score) child++;
        if (a[child].score >= last.score) break;
        a[i] = a[child];
        i = child;
      }
      a[i] = last;
    }
    return first;
  }
}

function direction(endpoint, points, atEnd) {
  const directions = {
    north: [0, -1],
    south: [0, 1],
    east: [1, 0],
    west: [-1, 0],
    "north-east": [1, -1],
    "north-west": [-1, -1],
    "south-east": [1, 1],
    "south-west": [-1, 1],
  };
  if (directions[endpoint.anchor]) return directions[endpoint.anchor];
  const a = atEnd ? points.at(-1) : points[0],
    b = atEnd ? points.at(-2) : points[1];
  const dx = b.x - a.x,
    dy = b.y - a.y;
  return Math.abs(dx) > Math.abs(dy) ? [Math.sign(dx) || 1, 0] : [0, Math.sign(dy) || 1];
}

function simplify(points) {
  const result = [];
  for (const p of points) {
    const point = { x: round(p.x), y: round(p.y) };
    if (result.length && distance(result.at(-1), point) < EPS) continue;
    while (result.length > 1) {
      const a = result.at(-2),
        b = result.at(-1);
      if (Math.abs((b.x - a.x) * (point.y - b.y) - (b.y - a.y) * (point.x - b.x)) > EPS) break;
      // Do not remove a turnaround at an endpoint's required egress.
      if ((b.x - a.x) * (point.x - b.x) + (b.y - a.y) * (point.y - b.y) < 0) break;
      result.pop();
    }
    result.push(point);
  }
  return result;
}

function freeEndpoint(point, blocked, width, height, fontSize) {
  const edge = Math.max(6, fontSize * 0.3);
  const left = Math.min(edge, width / 3),
    right = width - left;
  const x = Math.max(left, Math.min(right, point.x));
  const y = Math.max(-fontSize * 3, Math.min(height + fontSize * 3, point.y));
  const xs = [x, left, right, ...blocked.flatMap((rect) => [rect.left, rect.right])].filter(
    (value) => value >= left && value <= right,
  );
  const ys = [
    y,
    -fontSize * 3,
    height + fontSize * 3,
    ...blocked.flatMap((rect) => [rect.top, rect.bottom]),
  ];
  const candidates = xs
    .flatMap((x) => ys.map((y) => ({ x: round(x), y: round(y) })))
    .filter((candidate) => !blocked.some((rect) => segmentHits(candidate, candidate, rect)))
    .sort((a, b) => distance(a, { x, y }) - distance(b, { x, y }));
  return candidates[0] ?? null;
}

export function routeConnection(connector, obstacles, width, height, fontSize) {
  const padding = Math.max(3, fontSize * 0.16);
  const blocked = obstacles.map((rect) => padded(rect, padding));
  const points = connector.points.map((point) => ({ ...point }));
  let relocated = false;
  for (const [endpoint, index] of [
    [connector.start, 0],
    [connector.end, points.length - 1],
  ]) {
    if (!endpoint.free) continue;
    const replacement = freeEndpoint(points[index], blocked, width, height, fontSize);
    if (!replacement) return null;
    relocated ||= distance(points[index], replacement) > EPS;
    points[index] = replacement;
  }
  const original = sampleConnection({ ...connector, points });
  if (
    !relocated &&
    original.every((point) => point.x >= 1 && point.x <= width - 1) &&
    !pathHits(original, blocked)
  )
    return { changed: false, points: connector.points };
  const start = points[0],
    end = points.at(-1);
  if (distance(start, end) < EPS) return null;
  const lead = Math.max(8, fontSize * 0.35);
  let [sx, sy] = direction(connector.start, points, false),
    [ex, ey] = direction(connector.end, points, true);
  const top = -fontSize * 4,
    bottom = height + fontSize * 4;
  const inside = (p) => p.x >= 1 && p.x <= width - 1 && p.y >= top && p.y <= bottom;
  const port = (point, dx, dy) =>
    [lead, lead * 0.6, lead * 0.3, 1]
      .map((length) => ({ x: round(point.x + dx * length), y: round(point.y + dy * length) }))
      .find((candidate) => inside(candidate) && !pathHits([point, candidate], blocked));
  const choosePort = (point, endpoint, dx, dy) => {
    const directions = endpoint.free
      ? [
          [dx, dy],
          [0, -1],
          [0, 1],
          [-1, 0],
          [1, 0],
        ]
      : [[dx, dy]];
    for (const [x, y] of directions) {
      const result = port(point, x, y);
      if (result) return { point: result, direction: [x, y] };
    }
    return null;
  };
  const startPort = choosePort(start, connector.start, sx, sy),
    endPort = choosePort(end, connector.end, ex, ey);
  const from = startPort?.point,
    to = endPort?.point;
  if (!from || !to) return null;
  [sx, sy] = startPort.direction;
  [ex, ey] = endPort.direction;
  const unique = (values) => [...new Set(values.map(round))].sort((a, b) => a - b);
  const xs = unique([
    1,
    width - 1,
    from.x,
    to.x,
    ...blocked.flatMap((r) => [r.left, r.right]).filter((x) => x >= 1 && x <= width - 1),
  ]);
  const ys = unique([
    top,
    bottom,
    from.y,
    to.y,
    ...blocked.flatMap((r) => [r.top, r.bottom]).filter((y) => y >= top && y <= bottom),
  ]);
  // Bound work on unusually complex scenes. An unresolved route stays visible
  // as a failed layout requirement rather than freezing reading or hiding ink.
  if (xs.length * ys.length > 160000) return null;
  const columns = xs.length;
  const source = ys.indexOf(from.y) * columns + xs.indexOf(from.x),
    target = ys.indexOf(to.y) * columns + xs.indexOf(to.x);
  const count = columns * ys.length * 2;
  const costs = new Float64Array(count).fill(Infinity),
    previous = new Int32Array(count).fill(-1);
  const queue = new Heap();
  const point = (node) => ({ x: xs[node % columns], y: ys[Math.floor(node / columns)] });
  const heuristic = (node) => {
    const p = point(node);
    return Math.abs(p.x - to.x) + Math.abs(p.y - to.y);
  };
  for (let axis = 0; axis < 2; axis++) {
    const state = source * 2 + axis;
    costs[state] = 0;
    queue.push({ state, cost: 0, score: heuristic(source) });
  }
  let final = -1;
  let expanded = 0;
  while (queue.items.length) {
    const item = queue.pop(),
      state = item.state,
      node = state >> 1,
      axis = state % 2;
    if (item.cost !== costs[state]) continue;
    if (++expanded > 20000) return null;
    if (node === target) {
      final = state;
      break;
    }
    const column = node % columns,
      row = Math.floor(node / columns),
      p = point(node);
    const neighbors = [];
    if (column > 0) neighbors.push([node - 1, 0]);
    if (column + 1 < columns) neighbors.push([node + 1, 0]);
    if (row > 0) neighbors.push([node - columns, 1]);
    if (row + 1 < ys.length) neighbors.push([node + columns, 1]);
    for (const [next, nextAxis] of neighbors) {
      const q = point(next);
      // The anchor's outward lead must not turn straight back through itself.
      if (node === source && (q.x - p.x) * sx + (q.y - p.y) * sy < -EPS) continue;
      if (next === target && (q.x - p.x) * ex + (q.y - p.y) * ey > EPS) continue;
      if (blocked.some((rect) => segmentHits(p, q, rect))) continue;
      const cost = item.cost + distance(p, q) + (axis === nextAxis ? 0 : fontSize * 0.35);
      const nextState = next * 2 + nextAxis;
      if (cost >= costs[nextState]) continue;
      costs[nextState] = cost;
      previous[nextState] = state;
      queue.push({ state: nextState, cost, score: cost + heuristic(next) });
    }
  }
  if (final < 0) return null;
  const middle = [];
  for (let state = final; state >= 0; state = previous[state]) middle.push(point(state >> 1));
  const result = simplify([start, ...middle.reverse(), end]);
  if (result.length > 64 || pathHits(result, blocked)) return null;
  return { changed: true, points: result };
}

export function routeConnections(connectors, ink, { width, height, fontSize }, labels = []) {
  const routes = {},
    unresolved = [];
  for (const connector of connectors) {
    const endpoints = new Set([connector.start.tag, connector.end.tag].filter(Boolean));
    const obstacles = ink.filter((item) => !endpoints.has(item.tag)).concat(labels);
    const result = routeConnection(connector, obstacles, width, height, fontSize);
    if (!result) unresolved.push(connector.id);
    else if (result.changed) routes[connector.id] = result.points;
  }
  return { routes, unresolved };
}
