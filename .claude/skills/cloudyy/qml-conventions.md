# QML / Quickshell Conventions

## Window structure

- Bar-style, layer-shell panels: root is `PanelWindow` (`Bar.qml:19`, `modules/dock/Dock.qml:18`).
- Standalone dialog-style apps (own `qs -p <config>` invocation): root is `FloatingWindow`, `color: "transparent"` (`cloud-center/shell.qml:11`). Chrome is built from a `Rectangle`/`GlassPanel` inside, relying on Hyprland's blur behind the transparent window.
- The main bar's `shell.qml:24` root is `ShellRoot { id: root }` — a container hosting multiple `PanelWindow`/overlay children, not a window itself.

## Theme singleton pattern

Canonical `Theme.qml` (`pragma Singleton`, `QtObject`, loads matugen-generated JSON via `FileView`) lives at `.config/quickshell/Theme.qml`. Every other config root **symlinks** it into its own directory rather than importing via a relative path:

```
cloud-center/Theme.qml -> ../Theme.qml
lock/Theme.qml         -> ../Theme.qml
```

Import with `import "."` — same-directory singletons are auto-available, but this repo states the reason explicitly in comments (`cloud-center/shell.qml:5-6`): *"shared Theme.qml singleton (stable loader); symlinked into this dir since Quickshell's per-config import sandbox does not resolve '..' across config roots."* Same-root relative imports (e.g. `import "../.."` within a single `quickshell/` config root) work fine — the limitation is specifically about crossing config-root boundaries.

**When adding a new standalone config root:** symlink `Theme.qml` in at the correct relative depth (get it wrong and every `Theme.*` binding throws a silent `ReferenceError` at runtime).

## File organization

Per config root: `components/` (reusable UI atoms), `pages/` (full views), `services/` (singletons/business logic). Singletons are registered explicitly via `qmldir`:
```
# services/qmldir
singleton Backend Backend.qml
singleton Nav Nav.qml
```
imported as `import "services" as S`, used as `S.Nav.navigate(id)`.

- Files: PascalCase `.qml` (`CloudButton.qml`, `RowToggle.qml`), PascalCase `.js` for plain logic modules (`BezierMath.js`), imported with `as` aliases.
- ids/properties: camelCase (`id: root`, `property bool notifOpen`, `readonly property var barScreens`).
- Modules mirror feature names and get `Quick`-prefixed import aliases at the top of `shell.qml` (`import "modules/dock" as QuickDock`).

## Quickshell.Io patterns

**FileView** — read a file once at load:
```qml
FileView {
    id: contentFile
    path: root.oobeDir + "/content.conf"
    onLoaded: root.parseContent(text())
}
```
(`Theme.qml:83-89` also sets `watchChanges: true` + `onFileChanged: reload()` for files that change at runtime.)

**Process** — shell out via a 3-element command array, toggle `running` to (re-)trigger:
```qml
Process {
    id: proc
    command: ["bash", "-lc", cmd]
    running: false
}
// to run/re-run:
proc.command = ["bash", "-lc", newCmd]
proc.running = false
proc.running = true
```
This toggle-to-trigger idiom is used throughout (`WallpaperPickerService.qml:221-227`, `AppLibraryService.qml:316-317`).

**IpcHandler** — expose callable methods to `qs ipc -p <config> call <target> <fn>`:
```qml
IpcHandler {
    target: "nav"
    function page(id: string): void { S.Nav.navigate(id); }
}
```
(`cloud-center/shell.qml:20-23`, `modules/dock/Dock.qml`'s `target: "dock"` with `toggle()`/`show()`.)

## Font / rendering

- Standard font family: `"JetBrainsMono Nerd Font"` everywhere (500+ occurrences repo-wide, no exceptions found — this one really is universal).
- `renderType: Text.NativeRendering` is common (heaviest in `cloud-center/components`, `modules/island`) but **not universal** — `Bar.qml` and most of `modules/controlcenter`/`modules/calendar` don't use it. Don't assume it's required; match whatever the file you're editing already does.
- Often paired with `font.hintingPreference: Font.PreferVerticalHinting` where it is used.

## Visual language (flat "instrument panel" — rolled out shell-wide)

Off "liquid glass" (blur, translucency, 16-24px radii, soft rim highlights) onto a flatter, lighter language — design doc: `docs/superpowers/specs/2026-08-14-visual-theme-system-design.md` (its "rollout not started" section is stale). Piloted on the Control Center (`NotifPanel.qml` + `modules/controlcenter/**` + `modules/calendar/**`), then rolled out shell-wide in the 2026-08-19 "entire visual redesign" commit — Bar, dock, island, spotlight, command center, toasts/shelf, cloud-center. The one holdout still on plain `Theme.glassShell` is `modules/systemmonitor/SystemOverviewPanel.qml`.

The old `glass*` tokens (`Theme.glassShell`, `Theme.glassSection`, `Theme.glassPanelRadius`, `Theme.glass()`) still exist and are fine for **nested** sections/cards inside a panel; the **panel shell itself** uses the `Theme.resin*` tokens (see next bullet). Don't mix languages within one surface.

Validated rules, for when migrating a new surface:

- **Panel radius:** 0. **Tile/interactive radius:** 0-2px (not a pill unless it already was one for a real reason — see island/dock exception below).
- **Panel fill:** the shared `Theme.resin*` tokens — `color: Theme.resin(Theme.resinFillAlpha)`, `border.color: Theme.resinBorder`, optional `Theme.resinGloss` top-edge gradient + `Theme.resinGlow` corner glow. Flat, no compositor blur. As of 2026-08-27 `resinTint` is `surface` (neutral, matches `glassShell`) — it was briefly an accent-hue tint ("resin keycap"), reverted because saturated accents (Gruvbox orange) washed every panel in that hue. `Bar.qml`'s "frost material" comment describes the same neutral-surface intent.
- **Panel edge:** no full border. Either nothing, or four small corner-bracket marks (`Theme.accent`, ~9px long, 1.5px weight, ~5px inset from the corner) — see `NotifPanel.qml`'s `panelShell` for the pattern (8 `Rectangle`s, no `Shape`/`Canvas` needed).
- **Group separation:** a 1px `Theme.hairline` `Rectangle` between logical groups, not a border around every tile.
- **State indicators** (on/off, active/inactive): a small square LED (7x7, 1px border in `Theme.accent`, filled when active) next to the label — never recolor the whole element. Keeps the label legible in both states.
- **Sliders:** tick-gauge, not pill-and-dot — a `Repeater` of thin ticks across the track, `Theme.accent` up to the value, `Theme.hairline` past it; thin flat-bar handle (2px wide), not a circle.
- **Nameplate-style labels** (section headers, tile labels): `font.capitalization: Font.AllUppercase`, `font.letterSpacing: 0.6`.
- **Exception — don't touch:** the island's shape (square top / round bottom) and the dock's rounded pill tray. Both already fit this language; they were never glass-pill shapes to begin with.
- `Theme.hairline` (`Qt.rgba(outline_variant, 0.4)`) is the shared divider-color token — use it instead of inlining a new `Qt.rgba(Theme.outline_variant...)` per file.

## Style

- 4-space indentation, no tabs.
- K&R brace style (opening brace same line).
- No `.editorconfig`/`.qmlformat`/lint config anywhere — style is convention-by-example only.
- Files often open with a `// path/File.qml` comment restating their own path.
