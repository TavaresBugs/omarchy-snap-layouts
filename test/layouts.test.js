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
