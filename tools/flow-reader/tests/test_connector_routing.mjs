import assert from "node:assert/strict";
import test from "node:test";
import {
  pathHits,
  routeConnection,
  routeConnections,
  segmentHits,
} from "../web/connector-routing.js";

const connection = {
  id: "connector-1",
  kind: "cubic",
  start: { tag: "a", anchor: "south" },
  end: { tag: "b", anchor: "south" },
  points: [
    { x: 10, y: 40 },
    { x: 30, y: 40 },
    { x: 70, y: 40 },
    { x: 90, y: 40 },
  ],
};
const obstacle = { left: 40, top: 30, right: 60, bottom: 70 };

test("a colliding connection keeps its endpoints and stays clear at readable scale", () => {
  const result = routeConnection(connection, [obstacle], 100, 100, 18);
  assert.equal(result.changed, true);
  assert.deepEqual(result.points[0], connection.points[0]);
  assert.deepEqual(result.points.at(-1), connection.points.at(-1));
  assert.equal(pathHits(result.points, [{ left: 37, top: 27, right: 63, bottom: 73 }]), false);
  assert.ok(result.points.every((p) => p.x >= 0 && p.x <= 100));
  assert.ok(result.points.some((p) => p.y >= 73));
});

test("an already clear curve retains the author's controls", () => {
  const result = routeConnection(
    connection,
    [{ left: 40, top: 80, right: 60, bottom: 90 }],
    100,
    100,
    30,
  );
  assert.equal(result.changed, false);
  assert.equal(result.points, connection.points);
});

test("a colliding closed loop cannot be collapsed into a zero-length connection", () => {
  const loop = {
    ...connection,
    points: [
      { x: 10, y: 40 },
      { x: 80, y: 40 },
      { x: 80, y: 40 },
      { x: 10, y: 40 },
    ],
  };
  assert.equal(routeConnection(loop, [obstacle], 100, 100, 18), null);
});

test("vertical outsets are available without routing outside the body width", () => {
  const connector = {
    ...connection,
    start: { tag: "a", anchor: "north" },
    end: { tag: "b", anchor: "north" },
    points: connection.points.map((p) => ({ ...p, y: 10 })),
  };
  const result = routeConnection(
    connector,
    [{ left: 40, top: 0, right: 60, bottom: 100 }],
    100,
    100,
    18,
  );
  assert.equal(result.changed, true);
  assert.ok(result.points.some((p) => p.y < 0));
  assert.ok(result.points.every((p) => p.x >= 0 && p.x <= 100));
});

test("blocked endpoint egress remains an explicit unresolved route", () => {
  assert.equal(
    routeConnection(connection, [{ left: 0, top: 41, right: 100, bottom: 70 }], 100, 100, 18),
    null,
  );
});

test("an anchor can turn inside a narrow readable gap before the next row", () => {
  const connector = {
    ...connection,
    kind: "polyline",
    points: [
      { x: 10, y: 40 },
      { x: 90, y: 30 },
    ],
  };
  const result = routeConnection(
    connector,
    [
      { left: 40, top: 24, right: 60, bottom: 36 },
      { left: 0, top: 45, right: 100, bottom: 70 },
    ],
    100,
    100,
    18,
  );
  assert.equal(result.changed, true);
  assert.ok(result.points[1].y > 40 && result.points[1].y < 42);
  assert.equal(
    pathHits(result.points, [
      { left: 37, top: 21, right: 63, bottom: 39 },
      { left: -3, top: 42, right: 103, bottom: 73 },
    ]),
    false,
  );
});

test("only a connection's own endpoint terms are exempt from its obstacles", () => {
  const result = routeConnections(
    [connection],
    [
      { ...obstacle, tag: "a" },
      { left: 42, top: 30, right: 58, bottom: 70, tag: "other" },
    ],
    { width: 100, height: 100, fontSize: 18 },
  );
  assert.deepEqual(result.unresolved, []);
  assert.ok(result.routes["connector-1"].some((p) => p.y > 70));
});

test("diagonal segments and tangential channels use complete segment tests", () => {
  assert.equal(segmentHits({ x: 0, y: 0 }, { x: 100, y: 100 }, obstacle), true);
  assert.equal(segmentHits({ x: 0, y: 30 }, { x: 100, y: 30 }, obstacle), false);
  assert.equal(segmentHits({ x: 0, y: 29 }, { x: 100, y: 29 }, obstacle), false);
});
