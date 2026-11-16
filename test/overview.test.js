const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const O = load("overview.js");

const monitor = { x: 0, y: 0, w: 1536, h: 864 };
const area = { x: 70, y: 76, w: 1396, h: 668 };
const opts = { gapX: 40, gapY: 62, maxHeightFraction: 0.62 };

const win = (x, y, w, h) => ({ at: [x, y], size: [w, h], monitor });
const layout = (wins) => O.layoutRows(wins, area, opts);

// Claude (top-left), Spotify (top-right), Firefox (bottom, centred): the
// arrangement from the screenshots that exposed the navigation bug.
const claude = win(4, 30, 760, 411);
const spotify = win(770, 30, 760, 411);
const firefox = win(300, 449, 760, 411);

test("columnsFor follows the 1 / 2 / 2+1 / 2+2 / 3+2 / 3+3 pattern", () => {
    assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 9].map(O.columnsFor), [1, 2, 2, 2, 3, 3, 4, 4]);
});

test("no windows, no rects", () => {
    assert.deepEqual(layout([]), []);
});

test("one window is centred and capped in height", () => {
    const [r] = layout([win(4, 30, 1528, 830)]);
    assert.ok(r.h <= Math.round(area.h * opts.maxHeightFraction));
    assert.equal(r.x + r.w / 2, area.x + area.w / 2);
});

test("two windows sit side by side on one row", () => {
    const [a, b] = layout([claude, spotify]);
    assert.equal(a.y, b.y);
    assert.ok(a.x < b.x);
    assert.equal(b.x - (a.x + a.w), opts.gapX);
});

test("three windows make two on top and one below", () => {
    const [c, s, f] = layout([claude, spotify, firefox]);
    assert.equal(c.y, s.y);
    assert.ok(f.y > c.y + c.h, "Firefox is on its own row below");
});

test("every window in a layout has the same height", () => {
    const rects = layout([claude, spotify, firefox]);
    assert.equal(new Set(rects.map((r) => r.h)).size, 1);
});

test("the last, shorter row is centred", () => {
    const [, , f] = layout([claude, spotify, firefox]);
    assert.ok(Math.abs(f.x + f.w / 2 - (area.x + area.w / 2)) <= 1);
});

test("nothing overlaps and everything stays inside the area", () => {
    const wins = [];
    for (let n = 0; n < 9; n++) wins.push(win(10 + n * 40, 30 + (n % 3) * 200, 500 + n * 30, 300 + (n % 4) * 60));
    for (let count = 1; count <= wins.length; count++) {
        const rects = layout(wins.slice(0, count));
        rects.forEach((r, i) => {
            assert.ok(r.x >= area.x - 1 && r.x + r.w <= area.x + area.w + 1, `x, ${count} windows`);
            assert.ok(r.y >= area.y - 1 && r.y + r.h <= area.y + area.h + 1, `y, ${count} windows`);
            for (let j = i + 1; j < rects.length; j++) {
                const o = rects[j];
                const hit = r.x < o.x + o.w && r.x + r.w > o.x && r.y < o.y + o.h && r.y + r.h > o.y;
                assert.equal(hit, false, `${i} and ${j} overlap with ${count} windows`);
            }
        });
    }
});

test("windows keep the reading order of where they really are", () => {
    // Given right-to-left in the input, they must still come out left-to-right.
    const [s, c] = layout([spotify, claude]);
    assert.ok(c.x < s.x);
});

test("each rect remembers where its window really is", () => {
    const [c] = layout([claude]);
    assert.deepEqual([c.rx, c.ry, c.rw, c.rh], [4, 30, 760, 411]);
});

test("window positions are taken relative to their own monitor", () => {
    const second = { x: 1536, y: 0, w: 1280, h: 720 };
    const [r] = layout([{ at: [1536 + 10, 40], size: [600, 400], monitor: second }]);
    assert.equal(r.rx, 10);
});

test("a zero-sized window does not break the layout", () => {
    const rects = layout([win(0, 0, 0, 0), claude]);
    assert.equal(rects.length, 2);
    rects.forEach((r) => assert.ok(Number.isFinite(r.x) && Number.isFinite(r.w) && r.w > 0));
});

// ---- arrow navigation ----------------------------------------------------------

const arranged = layout([claude, spotify, firefox]);    // 0 Claude, 1 Spotify, 2 Firefox

test("left from the bottom window goes to the window on the left, not the list neighbour", () => {
    // This is the bug: sequential order would have gone to Spotify (index 1).
    assert.equal(O.neighbor(arranged, 2, "left"), 0);
});

test("right from the bottom window goes to the window on the right", () => {
    assert.equal(O.neighbor(arranged, 2, "right"), 1);
});

test("left and right between the top windows", () => {
    assert.equal(O.neighbor(arranged, 0, "right"), 1);
    assert.equal(O.neighbor(arranged, 1, "left"), 0);
});

test("down from either top window reaches the bottom one", () => {
    assert.equal(O.neighbor(arranged, 0, "down"), 2);
    assert.equal(O.neighbor(arranged, 1, "down"), 2);
});

test("up from the bottom window reaches the nearer top window", () => {
    // Firefox is centred, slightly nearer one of them; either way it is a top window.
    assert.ok([0, 1].includes(O.neighbor(arranged, 2, "up")));
});

test("nothing in that direction keeps the selection", () => {
    assert.equal(O.neighbor(arranged, 0, "left"), 0);
    assert.equal(O.neighbor(arranged, 0, "up"), 0);
    assert.equal(O.neighbor(arranged, 2, "down"), 2);
});

test("a window straight below beats one that is closer but off to the side", () => {
    const rects = [
        { x: 100, y: 0, w: 100, h: 100 },       // 0 selected
        { x: 400, y: 120, w: 100, h: 100 },     // 1 close in y, far to the side
        { x: 100, y: 300, w: 100, h: 100 }      // 2 further down, but aligned
    ];
    assert.equal(O.neighbor(rects, 0, "down"), 2);
});

test("unknown index is returned unchanged", () => {
    assert.equal(O.neighbor(arranged, 9, "left"), 9);
});

test("step wraps around in both directions", () => {
    assert.equal(O.step(2, 1, 3), 0);
    assert.equal(O.step(0, -1, 3), 2);
    assert.equal(O.step(1, 1, 3), 2);
    assert.equal(O.step(0, 1, 0), 0);
});

test("the overview's area sits below the bar, inside the margins", () => {
    const m = { w: 1536, h: 864, reserved: [0, 26, 0, 0] };
    const a = O.area(m, false);
    assert.equal(a.x, O.MARGIN.side);
    assert.equal(a.y, 26 + O.MARGIN.top);
    assert.equal(a.w, 1536 - 2 * O.MARGIN.side);
    assert.equal(a.h, 864 - a.y - O.MARGIN.bottom);
});

test("with a workspace strip the area starts lower", () => {
    const m = { w: 1536, h: 864, reserved: [0, 26, 0, 0] };
    const plain = O.area(m, false), withStrip = O.area(m, true);
    assert.equal(withStrip.y - plain.y, O.MARGIN.topWithStrip - O.MARGIN.top);
    assert.ok(withStrip.h < plain.h);
});
