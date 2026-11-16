// Loads a QML JavaScript library (lib/*.js) into node for testing.
//
// The libraries start with `.pragma library`, which only QML understands, and use
// plain top-level `function` / `var` declarations instead of module exports. This
// strips the pragma and evaluates the file in a vm context; whatever the file
// declares at top level is then available as a property of the returned object.

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function load(name) {
    const file = path.join(__dirname, "..", "lib", name);
    const source = fs.readFileSync(file, "utf8").replace(/^\.pragma .*$/m, "");
    const context = vm.createContext({ Math, Number, String, Array, Object, Infinity });
    vm.runInContext(source, context, { filename: file });
    return expose(context);
}

// Arrays and objects created inside a vm context have that context's prototypes,
// which node's strict deep-equality treats as different from the test's own. Hand
// back plain copies so assertions compare content only.
function plain(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function expose(context) {
    const api = {};
    for (const key of Object.keys(context)) {
        const value = context[key];
        if (typeof value === "function") {
            api[key] = (...args) => plain(value(...args));
        } else if (!["Math", "Number", "String", "Array", "Object", "Infinity"].includes(key)) {
            api[key] = plain(value);
        }
    }
    return api;
}

module.exports = { load };
