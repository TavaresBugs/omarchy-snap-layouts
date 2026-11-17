const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const D = load("drag.js");

const left = { name: "eDP-1", x: 0, y: 0, w: 1536, h: 864 };
const right = { name: "DP-3", x: 1536, y: 0, w: 1536, h: 864 };

const ctx = (over) => Object.assign({
    now: 1000, mode: "", current: "", monitors: [left, right], snapOn: true,
    edge: { margin: 12, corner: 60 }, dwellMs: 120, topDistance: 30
}, over);
const look = (x, y, over, state) => D.step(state || D.initial(), { x, y }, ctx(over));

test("the middle of a screen asks for nothing", () => {
    const r = look(700, 400);
    assert.equal(r.act, "none");
    assert.equal(r.state.pending, "");
    assert.equal(r.recheck, undefined);
});

test("a point outside every monitor asks for nothing and keeps what was pending", () => {
    const first = look(3, 400);
    const r = D.step(first.state, { x: 9000, y: 9000 }, ctx());
    assert.equal(r.act, "none");
    assert.deepEqual(r.state, first.state);
});

test("arriving at an edge starts the wait, and says when to look again", () => {
    const r = look(3, 400, { now: 1000 });
    assert.equal(r.act, "none");
    assert.deepEqual(r.state, { pending: "halves:0", since: 1000 });
    assert.equal(r.recheck, 120);
});

test("holding there until the dwell is over opens the edge preview", () => {
    const first = look(3, 400, { now: 1000 });
    const mid = D.step(first.state, { x: 3, y: 400 }, ctx({ now: 1050 }));
    assert.equal(mid.act, "none");
    assert.equal(mid.recheck, 70);
    const done = D.step(mid.state, { x: 3, y: 400 }, ctx({ now: 1120 }));
    assert.equal(done.act, "edge-open");
    assert.equal(done.monitor.name, "eDP-1");
    assert.deepEqual(done.edge, { layout: "halves", zone: 0, key: "halves:0" });
});

test("a dwell of 0 opens the preview at once", () => {
    assert.equal(look(3, 400, { dwellMs: 0 }).act, "edge-open");
});

test("moving to another edge starts the wait again", () => {
    const first = look(3, 400, { now: 1000 });
    const r = D.step(first.state, { x: 1533, y: 400 }, ctx({ now: 1100 }));
    assert.equal(r.act, "none");
    assert.deepEqual(r.state, { pending: "halves:1", since: 1100 });
    assert.equal(r.recheck, 120);
});

test("leaving the edge forgets the wait", () => {
    const first = look(3, 400, { now: 1000 });
    const r = D.step(first.state, { x: 400, y: 400 }, ctx({ now: 1050 }));
    assert.equal(r.state.pending, "");
    assert.equal(r.recheck, undefined);
});

test("with the preview up, the pointer at an edge updates it, and away from every edge closes it", () => {
    const hover = look(1533, 3, { mode: "edge" });
    assert.equal(hover.act, "edge-hover");
    assert.equal(hover.edge.layout, "quarters");
    assert.equal(hover.edge.zone, 1);
    assert.equal(look(700, 400, { mode: "edge" }).act, "edge-close");
});

test("snapping off: no edge asks for anything", () => {
    assert.equal(look(3, 400, { snapOn: false }).act, "none");
    assert.equal(look(3, 400, { snapOn: false, mode: "edge" }).act, "edge-close");
});

test("the right screen's edges are its own", () => {
    const r = look(1536 + 1533, 400, { dwellMs: 0 });
    assert.equal(r.act, "edge-open");
    assert.equal(r.monitor.name, "DP-3");
    assert.equal(r.edge.zone, 1);
});

test("the picker or its assist is not replaced by an edge preview, and nothing is waited for", () => {
    for (const mode of ["picker", "assist"]) {
        const r = look(3, 400, { mode, dwellMs: 0 });
        assert.equal(r.act, "none");
        assert.equal(r.recheck, undefined);
    }
});

test("near the top of a screen asks for the picker", () => {
    // Not at an edge: 200 px along the top, 25 px down is inside the 30 px reach but outside the 12 px margin.
    const r = look(700, 25);
    assert.equal(r.act, "picker-open");
    assert.equal(r.monitor.name, "eDP-1");
    assert.equal(look(700, 60).act, "none");
});

test("the picker follows the pointer to another screen's top, and picks a zone otherwise", () => {
    assert.equal(look(1536 + 700, 25, { mode: "drag", current: "eDP-1" }).act, "picker-monitor");
    assert.equal(look(700, 25, { mode: "drag", current: "eDP-1" }).act, "picker-hover");
    assert.equal(look(700, 300, { mode: "drag", current: "eDP-1" }).act, "picker-hover");
});

test("at the very top the picker opens first, and the edge preview takes over after the dwell", () => {
    const first = look(700, 3, { now: 1000 });
    assert.equal(first.act, "picker-open");
    assert.equal(first.recheck, 120);
    const later = D.step(first.state, { x: 700, y: 3 }, ctx({ now: 1130, mode: "drag", current: "eDP-1" }));
    assert.equal(later.act, "edge-open");
    assert.equal(later.edge.layout, "full");
});

test("the same input always gives the same answer (no hidden state)", () => {
    const state = { pending: "halves:0", since: 900 };
    const a = D.step(state, { x: 3, y: 400 }, ctx({ now: 1100 }));
    const b = D.step(state, { x: 3, y: 400 }, ctx({ now: 1100 }));
    assert.deepEqual(a, b);
    assert.deepEqual(state, { pending: "halves:0", since: 900 });
});
