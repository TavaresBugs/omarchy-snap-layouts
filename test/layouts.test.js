const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const L = load("layouts.js");

// A 1920x1080 panel at scale 1.25 -> 1536x864 logical, with a 26px bar on top.
const monitor = { x: 0, y: 0, w: 1536, h: 864, reserved: [0, 26, 0, 0] };
const gaps = { outer: 2, inner: 0, border: 2 };

test("every picker layout has zones that stay inside the screen", () => {
    for (let i = 0; i < L.LAYOUTS.length; i++) {
        for (const [x, y, w, h] of L.LAYOUTS[i]) {
            assert.ok(x >= 0 && y >= 0 && x + w <= 1.0001 && y + h <= 1.0001, `layout ${i}`);
        }
    }
});

test("named layouts point at the intended layouts", () => {
    assert.equal(L.LAYOUTS[L.INDEX.halves].length, 2);
    assert.equal(L.LAYOUTS[L.INDEX.quarters].length, 4);
    assert.equal(L.LAYOUTS[L.INDEX.full].length, 1);
    assert.ok(L.INDEX.full >= L.PICKER_COUNT, "full is not offered by the picker");
});

test("left half sits under the bar with gap and border", () => {
    const r = L.zoneScreenRect(monitor, gaps, L.INDEX.halves, 0);
    assert.deepEqual(r, { x: 4, y: 30, w: 762, h: 830 });
});

test("neighbouring zones share an exact edge", () => {
    const left = L.zoneScreenRect(monitor, gaps, L.INDEX.halves, 0);
    const right = L.zoneScreenRect(monitor, gaps, L.INDEX.halves, 1);
    // Their borders (2 px each) are what separates them.
    assert.equal(left.x + left.w + 2 * gaps.border, right.x);
    assert.equal(left.y, right.y);
    assert.equal(left.h, right.h);
});

test("quarters tile the usable area without overlapping", () => {
    const q = [0, 1, 2, 3].map((z) => L.zoneScreenRect(monitor, gaps, L.INDEX.quarters, z));
    for (let a = 0; a < 4; a++) {
        for (let b = a + 1; b < 4; b++) {
            const A = q[a], B = q[b];
            const overlap = A.x < B.x + B.w && A.x + A.w > B.x && A.y < B.y + B.h && A.y + A.h > B.y;
            assert.equal(overlap, false, `quarters ${a} and ${b}`);
        }
    }
});

test("full zone fills the usable area", () => {
    const r = L.zoneScreenRect(monitor, gaps, L.INDEX.full, 0);
    assert.deepEqual(r, { x: 4, y: 30, w: 1528, h: 830 });
});

test("zone positions follow a monitor that is not at the origin", () => {
    const second = { x: 1536, y: 0, w: 1280, h: 720, reserved: [0, 26, 0, 0] };
    const r = L.zoneScreenRect(second, gaps, L.INDEX.halves, 0);
    assert.equal(r.x, 1536 + 4);
});

test("inner gap pulls neighbouring zones apart", () => {
    const wide = { outer: 2, inner: 10, border: 2 };
    const a = L.zoneScreenRect(monitor, wide, L.INDEX.halves, 0);
    const b = L.zoneScreenRect(monitor, wide, L.INDEX.halves, 1);
    assert.equal(b.x - (a.x + a.w), 10 + 2 * wide.border);
});

const card = { padding: 16, gap: 12, thumbHeight: 76 };

test("picker card is centred under the bar", () => {
    const c = L.cardRect(monitor, card);
    assert.equal(c.x, Math.round((monitor.w - c.w) / 2));
    assert.equal(c.y, monitor.reserved[1] + 12);
});

test("hit test finds the zone under a point, and nothing elsewhere", () => {
    const t = L.thumbRect(monitor, card, 0);
    const left = L.hitTest(monitor, card, t.x + 8, t.y + t.h / 2);
    assert.deepEqual(left, { layout: 0, zone: 0 });
    const right = L.hitTest(monitor, card, t.x + t.w - 8, t.y + t.h / 2);
    assert.deepEqual(right, { layout: 0, zone: 1 });
    assert.deepEqual(L.hitTest(monitor, card, 5, 5), { layout: -1, zone: -1 });
});

test("hit test resolves every zone of every picker layout", () => {
    for (let i = 0; i < L.PICKER_COUNT; i++) {
        const t = L.thumbRect(monitor, card, i);
        for (let j = 0; j < L.LAYOUTS[i].length; j++) {
            const z = L.zoneThumbRect(i, j, t.w, t.h);
            const hit = L.hitTest(monitor, card, t.x + z.x + z.w / 2, t.y + z.y + z.h / 2);
            assert.deepEqual(hit, { layout: i, zone: j });
        }
    }
});

test("zoneRect places any fraction of the usable area, and a layout zone is the same thing", () => {
    const zone = L.LAYOUTS[L.INDEX.halves][0];
    assert.deepEqual(L.zoneRect(monitor, gaps, zone), L.zoneScreenRect(monitor, gaps, L.INDEX.halves, 0));
    const third = L.zoneRect(monitor, gaps, [0, 0, 1 / 3, 1]);
    assert.equal(third.x, 4);
    assert.ok(third.w > 500 && third.w < 520);
});

test("the mosaic is the plugin's layouts for one to four windows", () => {
    assert.deepEqual(L.mosaicZones(1), [L.LAYOUTS[L.INDEX.full][0]]);
    assert.deepEqual(L.mosaicZones(2), L.LAYOUTS[L.INDEX.halves]);
    assert.deepEqual(L.mosaicZones(3), L.LAYOUTS[4]);
    assert.deepEqual(L.mosaicZones(4), L.LAYOUTS[L.INDEX.quarters]);
});

test("past four windows the mosaic is rows of nearly equal windows that cover the screen", () => {
    for (let n = 5; n <= 24; n++) {
        const zones = L.mosaicZones(n);
        assert.equal(zones.length, n, `${n} windows`);
        const area = zones.reduce((sum, [, , w, h]) => sum + w * h, 0);
        assert.ok(Math.abs(area - 1) < 1e-9, `${n}: zones cover the area`);
        const sizes = zones.map(([, , w, h]) => w * h);
        assert.ok(Math.max(...sizes) / Math.min(...sizes) <= 2.0001, `${n}: biggest at most twice the smallest`);
        for (const [x, y, w, h] of zones)
            assert.ok(x >= 0 && y >= 0 && x + w <= 1.0001 && y + h <= 1.0001, `${n}: inside the screen`);
    }
});

test("five windows are three on top and two below, in reading order", () => {
    const z = L.mosaicZones(5);
    assert.deepEqual(z.map((s) => s[1]), [0, 0, 0, 0.5, 0.5]);
    assert.ok(z[3][2] > z[0][2], "the lower row has wider windows");
    for (let i = 1; i < z.length; i++)
        assert.ok(z[i][1] > z[i - 1][1] || z[i][0] > z[i - 1][0], "reading order");
});

test("a nonsense count still gives one zone", () => {
    assert.equal(L.mosaicZones(0).length, 1);
    assert.equal(L.mosaicZones(NaN).length, 1);
});

test("a zone's frame is the zone plus the window's border all round", () => {
    assert.deepEqual(L.frameRect({ x: 10, y: 20, w: 100, h: 50 }, 2), { x: 8, y: 18, w: 104, h: 54 });
    assert.deepEqual(L.frameRect({ x: 10, y: 20, w: 100, h: 50 }, 0), { x: 10, y: 20, w: 100, h: 50 });
    assert.deepEqual(L.frameRect({ x: 10, y: 20, w: 100, h: 50 }, undefined), { x: 10, y: 20, w: 100, h: 50 });
});

test("neighbouring frames touch or sit apart by the gap, never overlap", () => {
    const monitor = { x: 0, y: 0, w: 1000, h: 600, reserved: [0, 0, 0, 0] };
    const gaps = { outer: 2, inner: 4, border: 2 };
    const a = L.frameRect(L.zoneScreenRect(monitor, gaps, L.INDEX.halves, 0), gaps.border);
    const b = L.frameRect(L.zoneScreenRect(monitor, gaps, L.INDEX.halves, 1), gaps.border);
    assert.ok(a.x + a.w <= b.x);
});
