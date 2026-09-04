import json
from pathlib import Path
import subprocess
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIDGE = REPO_ROOT / "install/assets/zen/cloudyy.cfg"


def evaluate(expression, *, async_body=False):
    if not BRIDGE.exists():
        raise AssertionError(f"missing Zen live theme bridge: {BRIDGE}")
    harness = r"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8");
const context = { CLOUDYY_ZEN_BRIDGE_TEST: true };
vm.createContext(context);
vm.runInContext(source, context);
const code = process.argv[3] === "async"
    ? `(async () => { ${process.argv[2]} })()`
    : process.argv[2];
Promise.resolve(vm.runInContext(code, context)).then(
    result => process.stdout.write(JSON.stringify(result)),
    error => {
        process.stderr.write(String(error && error.stack || error));
        process.exitCode = 1;
    },
);
"""
    result = subprocess.run(
        [
            "node",
            "-e",
            harness,
            str(BRIDGE),
            expression,
            "async" if async_body else "sync",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr.strip())
    return json.loads(result.stdout)


def evaluate_production(expression):
    if not BRIDGE.exists():
        raise AssertionError(f"missing Zen live theme bridge: {BRIDGE}")
    harness = r"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8");
const runtime = {
  events: [],
  observer: null,
  timerCallback: null,
  exists: true,
  sheetExists: true,
  isFile: true,
  isSymlink: false,
  fileSize: 80,
  sheetSize: 200,
  signal: {schema: 1, generation: "stage.Ab12Cd34", mode: "dark"},
  rawSignal: null,
  sheet: "/* Zen Mods - no marker */",
  rawSheet: null,
  currentPath: "",
  boolPrefs: {"zen.mods.updated-value-observer": false},
  stringPrefs: {},
};
const Ci = {
  nsIPrefBranch: {},
  nsIObserverService: {},
  nsIConsoleService: {},
  nsIProperties: {},
  nsIFile: {},
  nsIFileInputStream: {},
  nsIConverterInputStream: {},
  nsITimer: {TYPE_REPEATING_SLACK: 7},
  nsIZenModsBackend: {},
};
const Cc = {
  "@mozilla.org/preferences-service;1": {
    getService: iface => ({
      setIntPref: (key, value) => runtime.events.push(["int-pref", key, value]),
      getBoolPref: (key, fallback) => key in runtime.boolPrefs
        ? runtime.boolPrefs[key]
        : fallback,
      setBoolPref: (key, value) => {
        runtime.boolPrefs[key] = value;
        runtime.events.push(["bool-pref", key, value]);
      },
      getStringPref: (key, fallback) => key in runtime.stringPrefs
        ? runtime.stringPrefs[key]
        : fallback,
      setStringPref: (key, value) => {
        runtime.stringPrefs[key] = value;
        runtime.events.push(["str-pref", key, value]);
      },
    }),
  },
  "@mozilla.org/observer-service;1": {
    getService: iface => ({
      addObserver: (observer, topic) => {
        runtime.events.push(["add-observer", topic]);
        runtime.observer = observer;
      },
      removeObserver: (observer, topic) => {
        runtime.events.push(["remove-observer", topic, observer === runtime.observer]);
      },
    }),
  },
  "@mozilla.org/consoleservice;1": {
    getService: iface => ({
      logStringMessage: message => runtime.events.push(["log", message]),
    }),
  },
  "@mozilla.org/file/directory_service;1": {
    getService: iface => ({
      get: (key, fileInterface) => ({
        appended: [key],
        append(part) { this.appended.push(part); },
        exists() {
          return this.appended.at(-1) === "zen-themes.css"
            ? runtime.sheetExists
            : runtime.exists;
        },
        isFile: () => runtime.isFile,
        isSymlink: () => runtime.isSymlink,
        get fileSize() {
          return this.appended.at(-1) === "zen-themes.css"
            ? runtime.sheetSize
            : runtime.fileSize;
        },
      }),
    }),
  },
  "@mozilla.org/network/file-input-stream;1": {
    createInstance: iface => ({
      init: file => {
        runtime.currentPath = file.appended.join("/");
        runtime.events.push(["read", runtime.currentPath]);
      },
    }),
  },
  "@mozilla.org/intl/converter-input-stream;1": {
    createInstance: iface => {
      let done = false;
      return {
        init: (stream, charset, size, replacement) =>
          runtime.events.push(["converter-init", charset, size, replacement]),
        readString: (length, out) => {
          if (done) return 0;
          done = true;
          if (runtime.currentPath.endsWith("zen-themes.css")) {
            out.value = runtime.rawSheet === null ? runtime.sheet : runtime.rawSheet;
          } else {
            out.value = runtime.rawSignal === null
              ? JSON.stringify(runtime.signal)
              : runtime.rawSignal;
          }
          return out.value.length;
        },
        close: () => {},
      };
    },
  },
  "@mozilla.org/timer;1": {
    createInstance: iface => ({
      initWithCallback: (callback, delay, type) => {
        runtime.events.push(["timer", delay, type, iface === Ci.nsITimer]);
        runtime.timerCallback = callback;
      },
    }),
  },
  "@mozilla.org/zen/mods-backend;1": {
    getService: iface => {
      runtime.events.push(["backend", iface === Ci.nsIZenModsBackend]);
      return {};
    },
  },
};
const context = { runtime, Ci, Cc };
vm.createContext(context);
vm.runInContext(source, context);
const code = `(async () => { ${process.argv[2]} })()`;
Promise.resolve(vm.runInContext(code, context)).then(
  result => process.stdout.write(JSON.stringify(result)),
  error => {
    process.stderr.write(String(error && error.stack || error));
    process.exitCode = 1;
  },
);
"""
    result = subprocess.run(
        ["node", "-e", harness, str(BRIDGE), expression],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr.strip())
    return json.loads(result.stdout)


class ZenLiveThemeBridgeTests(unittest.TestCase):
    def test_signal_schema_is_exact(self):
        self.assertEqual(
            evaluate(
                'cloudyyValidateSignal({schema:1,generation:"stage.Ab12Cd34",mode:"dark"})'
            ),
            {"generation": "stage.Ab12Cd34", "mode": "dark"},
        )
        for expression in (
            'cloudyyValidateSignal({schema:2,generation:"stage.Ab12Cd34",mode:"dark"})',
            'cloudyyValidateSignal({schema:1,generation:"stage.bad",mode:"dark"})',
            'cloudyyValidateSignal({schema:1,generation:"stage.Ab12Cd34",mode:"auto"})',
            'cloudyyValidateSignal({schema:1,generation:"stage.Ab12Cd34",mode:"dark",extra:true})',
        ):
            with self.subTest(expression=expression):
                self.assertIsNone(evaluate(expression))

    def test_mode_mapping_matches_restart_fallback(self):
        self.assertEqual(
            evaluate('cloudyyModePreferences("dark")'),
            {
                "ui.systemUsesDarkTheme": 1,
                "zen.view.window.scheme": 0,
            },
        )
        self.assertEqual(
            evaluate('cloudyyModePreferences("light")'),
            {
                "ui.systemUsesDarkTheme": 0,
                "zen.view.window.scheme": 1,
            },
        )

    def test_changed_generation_applies_mode_and_confirms_via_sheet(self):
        result = evaluate(
            """
const events = [];
let applied = "stage.Ab12Cd34";
const signal = {schema: 1, generation: "stage.Ef56Gh78", mode: "light"};
let sheet = "/* Zen Mods */ cloudyy-generation: stage.Ab12Cd34";
const bridge = cloudyyCreateBridge({
  readSignal: async () => signal,
  readSheetText: async () => sheet,
  getApplied: () => applied,
  setApplied: generation => { applied = generation; events.push(["applied", generation]); },
  backendAvailable: () => true,
  applyMode: prefs => events.push(["mode", prefs]),
  triggerMods: () => events.push(["trigger"]),
  report: key => events.push(["report", key]),
  schedule: callback => ({ callback }),
});
await bridge.poll();
sheet = "/* Zen Mods */ cloudyy-generation: stage.Ef56Gh78";
await bridge.poll();
await bridge.poll();
return {events, applied};
""",
            async_body=True,
        )
        self.assertEqual(
            result,
            {
                "events": [
                    [
                        "mode",
                        {
                            "ui.systemUsesDarkTheme": 0,
                            "zen.view.window.scheme": 1,
                        },
                    ],
                    ["trigger"],
                    ["applied", "stage.Ef56Gh78"],
                ],
                "applied": "stage.Ef56Gh78",
            },
        )

    def test_confirmed_sheet_skips_retrigger(self):
        result = evaluate(
            """
const events = [];
let applied = "";
const signal = {schema: 1, generation: "stage.Ab12Cd34", mode: "dark"};
const sheet = "/* Zen Mods */ cloudyy-generation: stage.Ab12Cd34";
const bridge = cloudyyCreateBridge({
  readSignal: async () => signal,
  readSheetText: async () => sheet,
  getApplied: () => applied,
  setApplied: generation => { applied = generation; events.push(["applied", generation]); },
  backendAvailable: () => true,
  applyMode: () => events.push("mode"),
  triggerMods: () => events.push("trigger"),
  report: key => events.push(["report", key]),
  schedule: () => {},
});
await bridge.poll();
await bridge.poll();
return {events, applied};
""",
            async_body=True,
        )
        self.assertEqual(
            result,
            {"events": [["applied", "stage.Ab12Cd34"]], "applied": "stage.Ab12Cd34"},
        )

    def test_duplicate_generation_has_no_side_effects(self):
        result = evaluate(
            """
const events = [];
let applied = "stage.Ab12Cd34";
const signal = {schema: 1, generation: "stage.Ab12Cd34", mode: "dark"};
const bridge = cloudyyCreateBridge({
  readSignal: async () => signal,
  readSheetText: async () => "",
  getApplied: () => applied,
  setApplied: generation => { applied = generation; events.push(["applied", generation]); },
  backendAvailable: () => true,
  applyMode: () => events.push("mode"),
  triggerMods: () => events.push("trigger"),
  report: key => events.push(["report", key]),
  schedule: () => {},
});
await bridge.poll();
await bridge.poll();
return events;
""",
            async_body=True,
        )
        self.assertEqual(result, [])

    def test_concurrent_poll_does_not_start_second_read(self):
        result = evaluate(
            """
let reads = 0;
let applied = "";
let release;
const pending = new Promise(resolve => { release = resolve; });
const bridge = cloudyyCreateBridge({
  readSignal: () => { reads += 1; return pending; },
  readSheetText: async () => "cloudyy-generation: stage.Ab12Cd34",
  getApplied: () => applied,
  setApplied: generation => { applied = generation; },
  backendAvailable: () => true,
  applyMode: () => {},
  triggerMods: () => {},
  report: () => {},
  schedule: () => {},
});
const first = bridge.poll();
const second = bridge.poll();
release({schema: 1, generation: "stage.Ab12Cd34", mode: "dark"});
await Promise.all([first, second]);
return reads;
""",
            async_body=True,
        )
        self.assertEqual(result, 1)

    def test_failed_trigger_leaves_generation_retryable(self):
        result = evaluate(
            """
const events = [];
let applied = "stage.Ab12Cd34";
const signal = {schema: 1, generation: "stage.Ef56Gh78", mode: "light"};
let sheet = "no marker";
let triggers = 0;
const bridge = cloudyyCreateBridge({
  readSignal: async () => signal,
  readSheetText: async () => sheet,
  getApplied: () => applied,
  setApplied: generation => { applied = generation; events.push(["applied", generation]); },
  backendAvailable: () => true,
  applyMode: () => events.push("mode"),
  triggerMods: () => {
    triggers += 1;
    if (triggers === 1) throw new Error("trigger-failed");
    events.push("trigger");
  },
  report: key => events.push(`report:${key}`),
  schedule: () => {},
});
await bridge.poll();
await bridge.poll();
sheet = "cloudyy-generation: stage.Ef56Gh78";
await bridge.poll();
return {events, triggers};
""",
            async_body=True,
        )
        self.assertEqual(
            result,
            {
                "events": [
                    "mode",
                    "report:trigger-failed",
                    "mode",
                    "trigger",
                    ["applied", "stage.Ef56Gh78"],
                ],
                "triggers": 2,
            },
        )

    def test_rebuild_gives_up_after_bounded_attempts(self):
        result = evaluate(
            """
const events = [];
let applied = "";
const signal = {schema: 1, generation: "stage.Ab12Cd34", mode: "dark"};
const bridge = cloudyyCreateBridge({
  readSignal: async () => signal,
  readSheetText: async () => "no marker",
  getApplied: () => applied,
  setApplied: generation => { applied = generation; events.push(["applied", generation]); },
  backendAvailable: () => true,
  applyMode: () => {},
  triggerMods: () => events.push("trigger"),
  report: key => events.push(`report:${key}`),
  schedule: () => {},
});
for (let index = 0; index < 7; index += 1) await bridge.poll();
return {events, applied};
""",
            async_body=True,
        )
        self.assertEqual(
            result,
            {
                "events": [
                    "trigger", "trigger", "trigger", "trigger", "trigger",
                    "report:rebuild-not-confirmed",
                    ["applied", "stage.Ab12Cd34"],
                ],
                "applied": "stage.Ab12Cd34",
            },
        )

    def test_error_reporting_is_bounded_until_successful_application(self):
        result = evaluate(
            """
const reports = [];
let applied = "";
const signals = [
  {schema: 1, generation: "stage.Ab12Cd34", mode: "dark"},
  {},
  {},
  {schema: 1, generation: "stage.Ef56Gh78", mode: "light"},
  {},
];
const bridge = cloudyyCreateBridge({
  readSignal: async () => signals.shift(),
  readSheetText: async () => "no marker",
  getApplied: () => applied,
  setApplied: generation => { applied = generation; },
  backendAvailable: () => true,
  applyMode: () => {},
  triggerMods: () => {},
  report: key => reports.push(key),
  schedule: () => {},
});
for (let index = 0; index < 5; index += 1) await bridge.poll();
return reports;
""",
            async_body=True,
        )
        self.assertEqual(result, ["invalid-signal", "invalid-signal"])

    def test_production_wrapper_starts_once_and_applies_changed_signal(self):
        result = evaluate_production(
            """
const startupEvents = runtime.events.slice();
runtime.observer.observe();
runtime.observer.observe();
const afterStartup = runtime.events.slice();
await runtime.timerCallback();
runtime.sheet = "/* Zen Mods */ cloudyy-generation: stage.Ab12Cd34";
await runtime.timerCallback();
runtime.boolPrefs["zen.mods.updated-value-observer"] = true;
runtime.sheet = "/* Zen Mods */ cloudyy-generation: stage.Ab12Cd34";
runtime.signal = {schema: 1, generation: "stage.Ef56Gh78", mode: "light"};
await runtime.timerCallback();
return {
  startupEvents,
  afterStartup,
  finalEvents: runtime.events,
  toggledValue: runtime.boolPrefs["zen.mods.updated-value-observer"],
  applied: runtime.stringPrefs["cloudyy.zen.lastAppliedGeneration"],
};
"""
        )
        self.assertEqual(
            result["startupEvents"],
            [["add-observer", "browser-delayed-startup-finished"]],
        )
        self.assertEqual(
            result["afterStartup"],
            [
                ["add-observer", "browser-delayed-startup-finished"],
                ["remove-observer", "browser-delayed-startup-finished", True],
                ["timer", 1000, 7, True],
                ["remove-observer", "browser-delayed-startup-finished", True],
            ],
        )
        self.assertEqual(
            result["finalEvents"][4:],
            [
                ["read", "ProfD/chrome/cloudyy-theme-signal.json"],
                ["converter-init", "UTF-8", 4096, 65533],
                ["read", "ProfD/chrome/zen-themes.css"],
                ["converter-init", "UTF-8", 4096, 65533],
                ["backend", True],
                ["int-pref", "ui.systemUsesDarkTheme", 1],
                ["int-pref", "zen.view.window.scheme", 0],
                ["bool-pref", "zen.mods.updated-value-observer", True],
                ["read", "ProfD/chrome/cloudyy-theme-signal.json"],
                ["converter-init", "UTF-8", 4096, 65533],
                ["read", "ProfD/chrome/zen-themes.css"],
                ["converter-init", "UTF-8", 4096, 65533],
                ["str-pref", "cloudyy.zen.lastAppliedGeneration", "stage.Ab12Cd34"],
                ["read", "ProfD/chrome/cloudyy-theme-signal.json"],
                ["converter-init", "UTF-8", 4096, 65533],
                ["read", "ProfD/chrome/zen-themes.css"],
                ["converter-init", "UTF-8", 4096, 65533],
                ["backend", True],
                ["int-pref", "ui.systemUsesDarkTheme", 0],
                ["int-pref", "zen.view.window.scheme", 1],
                ["bool-pref", "zen.mods.updated-value-observer", False],
            ],
        )
        self.assertFalse(result["toggledValue"])
        self.assertEqual(result["applied"], "stage.Ab12Cd34")

    def test_production_wrapper_rejects_oversized_file_before_read(self):
        result = evaluate_production(
            """
runtime.fileSize = 4097;
runtime.observer.observe();
await runtime.timerCallback();
return runtime.events;
"""
        )
        self.assertEqual(result[-1], ["log", "[CloudyyZenTheme] invalid-signal-file"])
        self.assertFalse(any(event[0] == "read" for event in result))

    def test_production_wrapper_rejects_non_regular_file_before_read(self):
        result = evaluate_production(
            """
runtime.isFile = false;
runtime.observer.observe();
await runtime.timerCallback();
return runtime.events;
"""
        )
        self.assertEqual(result[-1], ["log", "[CloudyyZenTheme] invalid-signal-file"])
        self.assertFalse(any(event[0] == "read" for event in result))

    def test_production_wrapper_rejects_symlink_before_read(self):
        result = evaluate_production(
            """
runtime.isSymlink = true;
runtime.observer.observe();
await runtime.timerCallback();
return runtime.events;
"""
        )
        self.assertEqual(result[-1], ["log", "[CloudyyZenTheme] invalid-signal-file"])
        self.assertFalse(any(event[0] == "read" for event in result))

    def test_production_wrapper_is_quiet_when_signal_is_absent(self):
        result = evaluate_production(
            """
runtime.exists = false;
runtime.observer.observe();
await runtime.timerCallback();
await runtime.timerCallback();
return runtime.events;
"""
        )
        self.assertEqual(
            result,
            [
                ["add-observer", "browser-delayed-startup-finished"],
                ["remove-observer", "browser-delayed-startup-finished", True],
                ["timer", 1000, 7, True],
            ],
        )

    def test_production_wrapper_does_not_log_malformed_signal_contents(self):
        result = evaluate_production(
            """
runtime.rawSignal = "not-json-SENSITIVE-CONTENTS";
runtime.observer.observe();
await runtime.timerCallback();
return runtime.events;
"""
        )
        self.assertEqual(result[-1], ["log", "[CloudyyZenTheme] invalid-signal"])
        self.assertNotIn("SENSITIVE-CONTENTS", json.dumps(result))

    def test_production_source_has_single_fixed_local_bridge(self):
        source = BRIDGE.read_text()
        self.assertEqual(source.count("addObserver("), 1)
        self.assertEqual(
            source.count('"browser-delayed-startup-finished"'),
            2,
        )
        self.assertEqual(source.count("createInstance(Ci.nsITimer)"), 1)
        self.assertIn("Ci.nsITimer.TYPE_REPEATING_SLACK", source)
        self.assertIn('Symbol.for("cloudyy.zenLiveTheme.timer")', source)
        self.assertIn('get("ProfD", Ci.nsIFile)', source)
        self.assertIn("@mozilla.org/network/file-input-stream;1", source)
        self.assertIn("cloudyy.zen.lastAppliedGeneration", source)
        self.assertIn('"zen-themes.css"', source)
        self.assertNotIn("importESModule", source)
        self.assertNotIn("remote-debugging", source)
        self.assertNotIn("socket", source.lower())
        self.assertNotIn("eval(", source)


if __name__ == "__main__":
    unittest.main()
