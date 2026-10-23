// Pure measured figure placement, shared by browser Worker and fallback.
const gap = 4;

export function overlaps(a, b, padding = gap) {
  return (
    a.left < b.left + b.width + padding &&
    b.left < a.left + a.width + padding &&
    a.top < b.top + b.height + padding &&
    b.top < a.top + a.height + padding
  );
}

function intersects(a, b, box) {
  let low = 0;
  let high = 1;
  for (const [p, q] of [
    [a.x - b.x, a.x - box.left],
    [b.x - a.x, box.left + box.width - a.x],
    [a.y - b.y, a.y - box.top],
    [b.y - a.y, box.top + box.height - a.y],
  ]) {
    if (p === 0 && q < 0) return false;
    if (p < 0) low = Math.max(low, q / p);
    if (p > 0) high = Math.min(high, q / p);
  }
  return low <= high;
}

// Sampled strokes are local obstacles. Query only cells touched by a candidate
// instead of scanning every segment for every alternative label position.
function strokeCollision(segments, cellSize) {
  const cells = new Map();
  const bounds = (box) => [
    Math.floor(box.left / cellSize),
    Math.floor(box.top / cellSize),
    Math.floor((box.left + box.width) / cellSize),
    Math.floor((box.top + box.height) / cellSize),
  ];
  for (const [a, b, clearance = 0] of segments) {
    const edge = {
      a,
      b,
      clearance,
      left: Math.min(a.x, b.x) - clearance,
      top: Math.min(a.y, b.y) - clearance,
      width: Math.abs(a.x - b.x) + 2 * clearance,
      height: Math.abs(a.y - b.y) + 2 * clearance,
    };
    const [left, top, right, bottom] = bounds(edge);
    for (let x = left; x <= right; x++)
      for (let y = top; y <= bottom; y++) {
        const key = `${x},${y}`;
        if (!cells.has(key)) cells.set(key, []);
        cells.get(key).push(edge);
      }
  }
  const cache = new Map();
  return (box) => {
    const key = `${box.left},${box.top},${box.width},${box.height}`;
    if (cache.has(key)) return cache.get(key);
    const [left, top, right, bottom] = bounds(box);
    const seen = new Set();
    for (let x = left; x <= right; x++)
      for (let y = top; y <= bottom; y++) {
        for (const edge of cells.get(`${x},${y}`) || []) {
          if (seen.has(edge)) continue;
          seen.add(edge);
          const { a, b, clearance } = edge;
          if (
            intersects(a, b, {
              left: box.left - clearance,
              top: box.top - clearance,
              width: box.width + 2 * clearance,
              height: box.height + 2 * clearance,
            })
          ) {
            cache.set(key, true);
            return true;
          }
        }
      }
    cache.set(key, false);
    return false;
  };
}

function labelBox(label, anchor) {
  return {
    left:
      anchor.x -
      (label.source.align === "end"
        ? label.width
        : label.source.align === "start"
          ? 0
          : label.width / 2),
    top:
      anchor.y -
      (label.source.baseline && Number.isFinite(label.baseline)
        ? label.baseline
        : label.height / 2),
    width: label.width,
    height: label.height,
  };
}

// Geometry remains in the authored coordinate system. Only its uniform scale
// changes. Text that cannot occupy its anchor safely has an always-visible
// numbered legend; a leader connects a displaced number to its original point.
export function canvasGeometry(model, width, fontSize) {
  const scale = Math.max(1, width - 4) / Math.max(1, model.width);
  const pad = Math.ceil(1.5 * fontSize);
  return { left: 2, top: pad, width: model.width * scale, height: model.height * scale };
}

export function composeCanvas(model, width, labels, fontSize, segments = []) {
  const geometry = canvasGeometry(model, width, fontSize);
  const scale = Math.max(1, width - 4) / Math.max(1, model.width);
  const occupied = [];
  const placed = new Map();
  let height = geometry.height + 2 * geometry.top;
  const point = (label) => ({
    x: geometry.left + (label.source.left + label.source.width / 2) * scale,
    y: geometry.top + (label.source.top + label.source.height / 2) * scale,
  });
  const hits = strokeCollision(segments, Math.max(24, 2 * fontSize));
  const valid = (box, strokes = true) =>
    box.left >= 0 &&
    box.left + box.width <= width &&
    box.top >= 0 &&
    box.top + box.height <= height &&
    !occupied.some((other) => overlaps(box, other)) &&
    (!strokes || !hits(box));
  const sorted = [...labels].sort((a, b) => a.width * a.height - b.width * b.height);
  // Preserve small coordinate symbols before larger nearby descriptions use
  // their limited anchor space. This is priority, never an eligibility cutoff.
  const compact = (label) => label.width <= 3 * fontSize && label.height <= 2 * fontSize;
  for (const group of [sorted.filter(compact), sorted.filter((label) => !compact(label))]) {
    for (const label of group) {
      const anchor = point(label);
      const box = labelBox(label, anchor);
      if (!label.nested && valid(box)) {
        occupied.push(box);
        placed.set(label.id, { ...box, id: label.id, mode: "inline", anchor });
      }
    }
    // Keep safe authored placements, then allocate nearby space to the labels
    // with the fewest available positions. Width alone is not a reason to number
    // a short formula or a two-line name. All candidates use measured text boxes.
    // Keep the largest fitting size for each compact label; legends and larger
    // descriptions retain the reading size. Never trade readability for a fit.
    const minimum = Math.min(1, Math.max(0.8, 11 / fontSize));
    const scales = group.every(compact)
      ? [...new Set([1, 0.95, 0.9, 0.85, minimum].filter((value) => value >= minimum))]
      : [1];
    const pending = group
      .filter(
        (label) =>
          !placed.has(label.id) && !label.nested && label.width <= width && label.height <= height,
      )
      .map((label) => {
        const anchor = point(label);
        const radius = Math.min(
          width / 4,
          Math.max(2 * fontSize, Math.min(4 * fontSize, Math.max(label.width, label.height) / 2)),
        );
        return { label, anchor, radius };
      });
    const leader = (box, anchor) => [
      anchor,
      {
        x: Math.max(box.left, Math.min(box.left + box.width, anchor.x)),
        y: Math.max(box.top, Math.min(box.top + box.height, anchor.y)),
      },
    ];
    const connected = (box, anchor) => {
      const [a, b] = leader(box, anchor);
      return (
        // A moved neighbor must leave other source anchors reachable.
        labels.every((other) => {
          const source = point(other);
          return (
            (source.x === anchor.x && source.y === anchor.y) ||
            source.x < box.left ||
            source.x > box.left + box.width ||
            source.y < box.top ||
            source.y > box.top + box.height
          );
        }) &&
        occupied.every((other) => !intersects(a, b, other)) &&
        [...placed.values()].every((other) => {
          const [start, end] = leader(other, other.anchor);
          return !intersects(start, end, box);
        })
      );
    };
    while (pending.length) {
      const choices = pending
        .map((entry) => {
          const { label, radius, anchor } = entry;
          for (const labelScale of scales) {
            const origin = labelBox(
              {
                ...label,
                width: label.width * labelScale,
                height: label.height * labelScale,
                baseline: label.baseline * labelScale,
              },
              anchor,
            );
            const candidates = [
              {
                ...origin,
                left: Math.max(0, Math.min(width - origin.width, origin.left)),
                top: Math.max(0, Math.min(height - origin.height, origin.top)),
              },
            ];
            for (let distance = fontSize / 4; distance <= radius + 0.01; distance += fontSize / 4) {
              for (let angle = 0; angle < 32; angle++) {
                const theta = (angle * Math.PI) / 16;
                candidates.push({
                  ...origin,
                  left: origin.left + Math.cos(theta) * distance,
                  top: origin.top + Math.sin(theta) * distance,
                });
              }
            }
            // Include the exact clearance around occupied boxes, rather than hoping
            // a coarse angular sample happens to land in a narrow gap.
            for (const other of occupied) {
              for (const left of [
                origin.left,
                other.left - origin.width - gap,
                other.left + other.width + gap,
              ]) {
                for (const top of [
                  origin.top,
                  other.top - origin.height - gap,
                  other.top + other.height + gap,
                ])
                  candidates.push({ ...origin, left, top });
              }
            }
            const distance = (box) => Math.hypot(box.left - origin.left, box.top - origin.top);
            const unique = new Map(
              candidates.map((box) => {
                const bounded = {
                  ...box,
                  left: Math.max(0, Math.min(width - box.width, box.left)),
                  top: Math.max(0, Math.min(height - box.height, box.top)),
                };
                return [`${bounded.left.toFixed(2)},${bounded.top.toFixed(2)}`, bounded];
              }),
            );
            const available = [...unique.values()]
              .filter(
                (box) => distance(box) <= radius + 0.01 && valid(box) && connected(box, anchor),
              )
              .sort((a, b) => distance(a) - distance(b));
            if (available.length) return { entry, available, labelScale };
          }
          return { entry, available: [] };
        })
        .filter(({ available }) => available.length);
      if (!choices.length) break;
      choices.sort((a, b) => a.available.length - b.available.length);
      const {
        entry,
        labelScale,
        available: [box],
      } = choices[0];
      occupied.push(box);
      placed.set(entry.label.id, {
        ...box,
        id: entry.label.id,
        mode: "inline",
        labelScale,
        anchor: entry.anchor,
      });
      pending.splice(pending.indexOf(entry), 1);
    }
  }
  for (const label of labels) {
    if (placed.has(label.id)) continue;
    const anchor = point(label);
    const w = Math.min(width, label.markerWidth);
    const h = label.markerHeight;
    const origin = {
      left: Math.max(0, Math.min(width - w, anchor.x - w / 2)),
      top: Math.max(0, anchor.y - h / 2),
      width: w,
      height: h,
    };
    const candidates = [origin];
    for (let ring = 1; ring <= 8; ring++) {
      for (const [x, y] of [
        [0, -1],
        [0, 1],
        [-1, 0],
        [1, 0],
        [-1, -1],
        [1, -1],
        [-1, 1],
        [1, 1],
      ])
        candidates.push({
          ...origin,
          left: origin.left + (x * ring * (w + gap)) / 2,
          top: origin.top + (y * ring * (h + gap)) / 2,
        });
    }
    let box = candidates.find((candidate) => valid(candidate));
    if (!box) {
      // A new row is preferable to a smaller badge, clipping, or hidden text.
      box = { left: 0, top: height + gap, width: w, height: h };
      height = box.top + h;
    }
    occupied.push(box);
    placed.set(label.id, { ...box, id: label.id, mode: "legend", anchor });
  }
  return { width, height, geometry, labels: labels.map((label) => placed.get(label.id)) };
}
