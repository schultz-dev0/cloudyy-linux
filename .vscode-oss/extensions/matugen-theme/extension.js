// @ts-check
"use strict";

const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const os = require("os");

// ─── JSONC parser (strips // comments so JSON.parse works) ───────────────────

function stripJsonComments(raw) {
  let result = "";
  let i = 0;
  while (i < raw.length) {
    if (raw[i] === '"') {
      result += raw[i++];
      while (i < raw.length) {
        const ch = raw[i];
        result += ch;
        if (ch === "\\" && i + 1 < raw.length) result += raw[++i];
        else if (ch === '"') break;
        i++;
      }
      i++;
      continue;
    }
    if (raw[i] === "/" && raw[i + 1] === "/") {
      while (i < raw.length && raw[i] !== "\n") i++;
      continue;
    }
    if (raw[i] === "/" && raw[i + 1] === "*") {
      i += 2;
      while (i < raw.length && !(raw[i] === "*" && raw[i + 1] === "/")) i++;
      i += 2;
      continue;
    }
    result += raw[i++];
  }
  return result;
}

// ─── Color utilities ──────────────────────────────────────────────────────────

function hexToHsl(hex) {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    else if (max === g) h = ((b - r) / d + 2) / 6;
    else h = ((r - g) / d + 4) / 6;
  }
  return [h * 360, s * 100, l * 100];
}

function hslToHex(h, s, l) {
  h = ((h % 360) + 360) % 360;
  s = Math.max(0, Math.min(100, s)) / 100;
  l = Math.max(0, Math.min(100, l)) / 100;
  const k = (n) => (n + h / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  const hex = (x) => Math.round(x * 255).toString(16).padStart(2, "0");
  return `#${hex(f(0))}${hex(f(8))}${hex(f(4))}`;
}

function deriveColor(base, hueShift, lightnessTarget) {
  if (!base || !base.startsWith("#")) return base;
  const [h, s, l] = hexToHsl(base);
  return hslToHex(h + hueShift, s, lightnessTarget ?? l);
}

// ─── Fill empty syntax color keys ────────────────────────────────────────────

function fillMissingSyntax(colors) {
  const out = { ...colors };
  const primary = out["primary"] || "";

  const derive = (key, hueShift, lTarget) => {
    if (!out[key] && primary) out[key] = deriveColor(primary, hueShift, lTarget);
  };

  if (!out["syntax.comment"] && out["mutedForeground"]) {
    const [h, s, l] = hexToHsl(out["mutedForeground"]);
    out["syntax.comment"] = hslToHex(h, s * 0.6, l * 0.75);
  }

  if (!out["syntax.string"] && out["secondaryForeground"]) {
    out["syntax.string"] = out["secondaryForeground"];
  } else derive("syntax.string", 60);

  if (!out["syntax.keyword"] && primary) {
    const [h, s, l] = hexToHsl(primary);
    out["syntax.keyword"] = hslToHex(h, s, Math.min(l + 10, 90));
  }

  derive("syntax.variable",  120);
  derive("syntax.attribute", 150);
  derive("syntax.property",  180);
  derive("syntax.function",  -60);
  derive("syntax.constant",  -30, 75);

  ["syntax.bracket1", "syntax.bracket2", "syntax.bracket3", "syntax.bracket4"]
    .forEach((key, i) => derive(key, [0, 60, 120, 180][i]));

  return out;
}

// ─── Core: read file + apply to settings ─────────────────────────────────────

function resolvePath(rawPath) {
  return rawPath.startsWith("~")
    ? path.join(os.homedir(), rawPath.slice(1))
    : rawPath;
}

async function applyColors(statusBar) {
  const config = vscode.workspace.getConfiguration("matugen-vscode");
  const resolvedPath = resolvePath(
    config.get("colorsPath", "~/.config/matugen/generated/vscode-colors.json")
  );

  statusBar.text = "$(sync~spin) Matugen: applying…";

  let parsed;
  try {
    const raw = fs.readFileSync(resolvedPath, "utf-8");
    parsed = JSON.parse(stripJsonComments(raw));
  } catch (err) {
    vscode.window.showErrorMessage(`Matugen: failed to read/parse ${resolvedPath} — ${err.message}`);
    statusBar.text = "$(error) Matugen: error";
    return;
  }

  let rawColors = {};

  if (parsed["material-code.colors"]) {
    // Your format: file already has material-code keys with hex values
    rawColors = parsed["material-code.colors"];
  } else if (parsed["colors"]) {
    // Raw matugen palette format
    const p = parsed["colors"];
    const c = (name) => p[name]?.default?.hex ?? "";
    rawColors = {
      primary: c("primary"), primaryForeground: c("on_primary"),
      foreground: c("on_surface"), mutedForeground: c("on_surface_variant"),
      background: c("surface"), card: c("surface_container"),
      popover: c("surface_container_high"), hover: c("surface_container_highest"),
      border: c("outline_variant"), secondary: c("secondary_container"),
      secondaryForeground: c("on_secondary_container"),
      error: c("error"), errorForeground: c("on_error"),
      success: c("tertiary"), warning: c("error_container"),
      "syntax.comment": c("outline"), "syntax.string": c("secondary"),
      "syntax.keyword": c("primary"), "syntax.variable": c("primary_fixed"),
      "syntax.attribute": c("secondary_fixed_dim"), "syntax.property": c("secondary_fixed"),
      "syntax.function": c("tertiary"), "syntax.constant": c("tertiary_fixed"),
      "syntax.bracket1": c("primary"), "syntax.bracket2": c("tertiary"),
      "syntax.bracket3": c("secondary"), "syntax.bracket4": c("primary_fixed"),
    };
  } else {
    vscode.window.showErrorMessage(`Matugen: unrecognised format in ${path.basename(resolvedPath)}`);
    statusBar.text = "$(error) Matugen: unknown format";
    return;
  }

  // Derive any missing syntax colors, then strip empty values
  const withSyntax = fillMissingSyntax(rawColors);
  const final = Object.fromEntries(
    Object.entries(withSyntax).filter(([, v]) => v && v.trim() !== "")
  );

  // Write directly to settings.json — the VSCode API rejects keys that aren't
  // registered by an installed extension (e.g. material-code.colors).
  const settingsPath = path.join(os.homedir(), ".config", "Code - OSS", "User", "settings.json");
  let settings = {};
  try {
    const raw = fs.readFileSync(settingsPath, "utf-8");
    settings = JSON.parse(stripJsonComments(raw));
  } catch {
    // File missing or empty — start fresh
  }

  settings["material-code.colors"] = final;
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2), "utf-8");

  statusBar.text = `$(paintcan) Matugen: synced ${new Date().toLocaleTimeString()}`;
  vscode.window.setStatusBarMessage(`Matugen: applied ${Object.keys(final).length} colors`, 4000);
}

// ─── File watcher ─────────────────────────────────────────────────────────────

function createWatcher(statusBar) {
  const config = vscode.workspace.getConfiguration("matugen-vscode");
  const resolvedPath = resolvePath(
    config.get("colorsPath", "~/.config/matugen/generated/vscode-colors.json")
  );

  if (!fs.existsSync(resolvedPath)) {
    vscode.window.showWarningMessage(
      `Matugen: file not found at ${resolvedPath}. Set "matugen-vscode.colorsPath" in settings.`
    );
    statusBar.text = "$(warning) Matugen: file not found";
    return null;
  }

  statusBar.text = "$(eye) Matugen: watching";
  let debounce = null;

  const watcher = fs.watch(resolvedPath, (event) => {
    if (event === "change" || event === "rename") {
      clearTimeout(debounce);
      debounce = setTimeout(() => applyColors(statusBar), 300);
    }
  });

  watcher.on("error", (err) => {
    vscode.window.showErrorMessage(`Matugen watcher error: ${err.message}`);
    statusBar.text = "$(error) Matugen: watcher error";
  });

  return watcher;
}

// ─── Activate ─────────────────────────────────────────────────────────────────

function activate(context) {
  const statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  statusBar.command = "matugen-vscode.applyNow";
  statusBar.tooltip = "Matugen — click to apply colors now";
  statusBar.show();
  context.subscriptions.push(statusBar);

  let activeWatcher = null;

  const restartWatcher = () => {
    activeWatcher?.close();
    activeWatcher = null;
    const cfg = vscode.workspace.getConfiguration("matugen-vscode");
    if (cfg.get("enableWatcher", true)) {
      activeWatcher = createWatcher(statusBar);
    } else {
      statusBar.text = "$(circle-slash) Matugen: watcher off";
    }
  };

  context.subscriptions.push(
    vscode.commands.registerCommand("matugen-vscode.applyNow", () => applyColors(statusBar))
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("matugen-vscode.toggleWatch", async () => {
      const cfg = vscode.workspace.getConfiguration("matugen-vscode");
      const current = cfg.get("enableWatcher", true);
      await cfg.update("enableWatcher", !current, vscode.ConfigurationTarget.Global);
      restartWatcher();
      vscode.window.showInformationMessage(`Matugen watcher ${!current ? "enabled" : "disabled"}`);
    })
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (
        e.affectsConfiguration("matugen-vscode.colorsPath") ||
        e.affectsConfiguration("matugen-vscode.enableWatcher") ||
        e.affectsConfiguration("matugen-vscode.scheme")
      ) {
        restartWatcher();
        applyColors(statusBar);
      }
    })
  );

  applyColors(statusBar).then(() => restartWatcher());
  context.subscriptions.push({ dispose: () => activeWatcher?.close() });
}

function deactivate() {}

module.exports = { activate, deactivate };
