// node test_disks.js — checks modules/systemmonitor/Disks.js (a QML .pragma library).
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

vm.runInThisContext(fs.readFileSync(__dirname + "/modules/systemmonitor/Disks.js", "utf8").replace(/^\.pragma library$/m, ""));
const D = globalThis;

const root = { mount: "/", percent: 64, used_gb: 1147.1, total_gb: 1792.3 };
const boot = { mount: "/boot", percent: 17, used_gb: 0.2, total_gb: 1.0 };
const home = { mount: "/home", percent: 64, used_gb: 1147.1, total_gb: 1792.3 }; // btrfs @home, same fs
const games = { mount: "/mnt/games2", percent: 79, used_gb: 686.5, total_gb: 869 };

assert.deepStrictEqual(D.unique([root, boot, home, games]).map(d => d.mount), ["/", "/boot", "/mnt/games2"]);
assert.deepStrictEqual(D.unique([]), []);
assert.deepStrictEqual(D.unique([boot]).map(d => d.mount), ["/boot"]);
// same total, different used → different filesystems
assert.strictEqual(D.unique([root, { mount: "/x", percent: 1, used_gb: 5, total_gb: 1792.3 }]).length, 2);
console.log("ok");
