.pragma library
.import "overview.js" as Overview

// What a key does in the overview. The focus is either on the windows (cards)
// or on the workspace strip at the top; Up from the top row of windows moves
// into the strip, Down moves back. Pure: it returns what to do, the plugin does it.
//
//   state: { strip: bool,        focus is on the strip
//            hasStrip: bool,     there is a strip to move into
//            index, rects,       the selected card and the cards' layout (for the arrows)
//            count }             number of cards
//   input: { key: "up"|"down"|"left"|"right"|"tab"|"backtab"|"pageup"|"pagedown"|"enter",
//            ctrl: bool, shift: bool }
//   result: { action, ... }
//     select            { index }
//     enterStrip / leaveStrip
//     stepWorkspace     { delta }   view the next/previous workspace
//     swapWorkspace     { delta }   move the viewed workspace one place along the strip
//     activate          the selected window is brought forward
//     activateWorkspace go to the viewed workspace
//     none

function overviewKey(state, input) {
    var strip = state.strip || (state.count === 0 && state.hasStrip);
    var key = input.key;

    if (key === "pageup" || key === "pagedown")
        return { action: "stepWorkspace", delta: key === "pagedown" ? 1 : -1 };

    if (strip) {
        if (key === "left" || key === "right") {
            var d = key === "right" ? 1 : -1;
            return { action: input.shift ? "swapWorkspace" : "stepWorkspace", delta: d };
        }
        if (key === "tab" || key === "backtab")
            return { action: "stepWorkspace", delta: key === "tab" ? 1 : -1 };
        if (key === "down" && state.count > 0)
            return { action: "leaveStrip" };
        if (key === "enter")
            return { action: "activateWorkspace" };
        return { action: "none" };
    }

    if (input.ctrl && (key === "left" || key === "right"))
        return { action: "stepWorkspace", delta: key === "right" ? 1 : -1 };
    if (key === "tab" || key === "backtab")
        return { action: "select", index: Overview.step(state.index, key === "tab" ? 1 : -1, state.count) };
    if (key === "enter")
        return state.count > 0 ? { action: "activate" } : { action: "none" };
    if (key === "left" || key === "right" || key === "up" || key === "down") {
        var next = Overview.neighbor(state.rects, state.index, key);
        if (next === state.index && key === "up" && state.hasStrip)
            return { action: "enterStrip" };
        return { action: "select", index: next };
    }
    return { action: "none" };
}
