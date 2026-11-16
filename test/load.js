// Loads a QML JavaScript library (lib/*.js) into node for testing.
//
// The libraries start with `.pragma library`, which only QML understands, and use
// plain top-level `function` / `var` declarations instead of module exports. This
// strips the pragma and evaluates the file in a vm context; whatever the file
// declares at top level is then available as a property of the returned object.

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const BUILTINS = ["Math", "Number", "String", "Array", "Object", "Infinity"];

// Evaluate a library in its own context. `.import "other.js" as Name` lines,
// which QML resolves itself, are loaded the same way and bound to `Name`.
function evaluate(name) {
    const file = path.join(__dirname, "..", "lib", name);
    let source = fs.readFileSync(file, "utf8").replace(/^\.pragma .*$/m, "");
    const globals = { Math, Number, String, Array, Object, Infinity };
    const imported = [];
    source = source.replace(/^\.import "([^"]+)" as (\w+)\s*$/gm, (_, dep, alias) => {
        globals[alias] = evaluate(dep).context;
        imported.push(alias);
        return "";
    });
    const context = vm.createContext(globals);
    vm.runInContext(source, context, { filename: file });
    return { context, imported };
}

function load(name) {
    const { context, imported } = evaluate(name);
    return expose(context, imported);
}

// Arrays and objects created inside a vm context have that context's prototypes,
// which node's strict deep-equality treats as different from the test's own. Hand
// back plain copies so assertions compare content only.
function plain(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function expose(context, imported) {
    const api = {};
    for (const key of Object.keys(context)) {
        const value = context[key];
        if (typeof value === "function") {
            api[key] = (...args) => plain(value(...args));
        } else if (!BUILTINS.includes(key) && !imported.includes(key)) {
            api[key] = plain(value);
        }
    }
    return api;
}

module.exports = { load };
