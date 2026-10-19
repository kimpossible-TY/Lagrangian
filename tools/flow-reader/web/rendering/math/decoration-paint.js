// Compiler-carried primitives, expressed in CSS pixels and reading-font ems.
// Return null for the entire decoration when fidelity cannot be guaranteed.
export function localDecorationPaint(record, request) {
  try {
    const descriptions = record.nodes.map((node) => node.dataset?.flowDecorationPaint);
    const source = descriptions[0];
    if (!source || source.length > 16000 || descriptions.some((value) => value !== source))
      return null;
    const spec = JSON.parse(source);
    if (spec.version !== 1 || !["rect", "underline", "cancel"].includes(spec.kind)) return null;
    const finite = (value, limit = 100000) => {
      if (typeof value !== "number" || !Number.isFinite(value) || Math.abs(value) > limit)
        throw new Error("Invalid primitive geometry");
      return value;
    };
    const font = finite(request.fontSize, 60);
    if (font < 8 || !/^#[\da-f]{6}$/i.test(request.ink)) return null;
    const length = (value) => finite(finite(value.px) + finite(value.em, 100) * font);
    const edges = (value) =>
      Object.fromEntries(
        ["left", "right", "top", "bottom"].map((side) => [side, length(value[side])]),
      );
    const paint = (value) => {
      if (value === "ink") return request.ink;
      if (value === "none" || /^#[\da-f]{6}([\da-f]{2})?$/i.test(value)) return value;
      throw new Error("Unsupported primitive paint");
    };
    const outset = edges(spec.outset),
      inset = edges(spec.inset);
    let stroke = 'stroke="none"';
    if (spec.stroke !== null) {
      const thickness = length(spec.stroke.thickness);
      if (thickness < 0) return null;
      stroke = `stroke="${paint(spec.stroke.paint)}" stroke-width="${thickness}"`;
    }
    if (
      !Array.isArray(request.fragments) ||
      !request.fragments.length ||
      request.fragments.length > 128
    )
      return null;
    return request.fragments.map((fragment, index) => {
      const width = finite(fragment.width, 30000) + outset.left + outset.right;
      const height = finite(fragment.height, 30000) + outset.top + outset.bottom;
      if (fragment.width <= 0 || fragment.height <= 0 || width <= 0 || height <= 0)
        throw new Error("Invalid fragment bounds");
      const layout = {
        left: -outset.left,
        top: -outset.top,
        width,
        height,
        anchor: {
          left: -outset.left - inset.left,
          top: -outset.top - inset.top,
          width: width + inset.left + inset.right,
          height: height + inset.top + inset.bottom,
        },
      };
      let shape;
      if (spec.kind === "rect") {
        shape = `<rect width="${width}" height="${height}" fill="${paint(spec.fill)}" ${stroke}/>`;
      } else if (spec.kind === "underline") {
        shape = `<path d="M 0 ${height} H ${width}" fill="none" ${stroke}/>`;
      } else {
        if (typeof spec.cross !== "boolean" || typeof spec.inverted !== "boolean")
          throw new Error("Invalid cancellation");
        const angle = spec.angle === null ? Math.atan2(width, height) : finite(spec.angle);
        const span = finite(spec.ratio, 100) * Math.hypot(width, height) + length(spec.length);
        if (span < 0) throw new Error("Invalid cancellation length");
        const line = (inverted) => {
          const theta = inverted ? -angle : angle;
          const dx = (Math.sin(theta) * span) / 2,
            dy = (Math.cos(theta) * span) / 2;
          return `<path d="M ${width / 2 - dx} ${height / 2 + dy} L ${width / 2 + dx} ${height / 2 - dy}" fill="none" ${stroke}/>`;
        };
        shape = line(!spec.cross && spec.inverted) + (spec.cross ? line(true) : "");
      }
      return {
        fragment: index,
        layer: spec.kind === "rect" ? "under" : "over",
        layout,
        svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" style="width:${width}px;height:${height}px;overflow:visible">${shape}</svg>`,
      };
    });
  } catch {
    return null;
  }
}
