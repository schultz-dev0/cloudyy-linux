# QML / Quickshell Conventions

## Window structure

- Bar-style, layer-shell panels: root is `PanelWindow` (`Bar.qml:19`, `modules/dock/Dock.qml:18`).
- Standalone dialog-style apps (own `qs -p <config>` invocation): root is `FloatingWindow`, `color: "transparent"` (`cloud-center/shell.qml:11`). Chrome is built from a `Rectangle`/`GlassPanel` inside, relying on Hyprland's blur behind the transparent window.
- The main bar's `shell.qml:24` root is `ShellRoot { id: root }` — a container hosting multiple `PanelWindow`/overlay children, not a window itself.

## Theme singleton pattern

Canonical `Theme.qml` (`pragma Singleton`, `QtObject`, loads the active curated theme's JSON (`~/.local/state/cloudyy/current/theme/theme.json`) via `FileView`) lives at `.config/quickshell/Theme.qml`. Every other config root **symlinks** it into its own directory rather than importing via a relative path:

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
This toggle-to-trigger idiom is used throughout (e.g. `AppLibraryService.qml`).

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

## Visual language (minimalism, 2026-09-30)

**A tool with the decoration taken off.** Square, all-mono, technical, and it stays that way. Minimalism here means *subtracting* chrome, repetition and empty-state text, not softening. Rounded panels and a sans face were both tried against the real surfaces and rejected by the user; don't propose them as the "minimal" option.

Full doc with per-surface detail and reasoning: `~/Dev/cloudyy_visual/VISUAL-LANGUAGE.md` (local to the main machine only; this section is self-sufficient). Decision log: `.superpowers/brainstorm/17580-1790797621/decisions.md` (gitignored, main machine only).

**Implementation status:** the rules below are the *target*. Until the minimalism pass lands, the code still carries the September HUD layer (`CornerFrame`, `MarginRules`, rule labels like `SPOTLIGHT`/`GRAIN 0.05`/`640 × AUTO`, `resinGlow` corner discs). That layer is **legacy**: never add it to a surface, and remove it when you touch one. Cloud Center has not migrated yet and gets its own pass, so leave its HUD alone unless doing that pass.

### Rules (numbered; specs and reviews cite them)

1. **No frame.** A panel is defined by its material alone: no corner brackets, rule lines or rule labels.
2. **One-line rows.** A row is its label. The right-hand slot shows only live state (`Performance`, `Running`) or location (a deep hit's parent, `Appearance`). `›` marks a row that opens a submenu. No kind-of-row subtitles (`Menu`, `App library`).
3. **Context lives in the search field.** A submenu path is the empty field's placeholder (`Appearance › Bar Position`); an active category is a muted prefix (`commands ›`) that stays while typing.
4. **Hints show while deciding** (empty field, nothing chosen) and hide once you act, unless the hint is the only way to discover a control (Theme picker key line).
5. **Grain only on panels you stay in:** Control Center, Calendar, System monitor. Not on launchers, toasts, bar, dock or island.
6. **Bracketed readouts are the one instrument voice**, for live values only (below).
7. **No self-description.** No panel titles (`Power`, `Control Center`, `SYSTEM`), theme names, sizes, grain values or meta text (`live · 2s`, `5 mounts`).
8. **Say it once.** Don't repeat what another surface or element shows: the date is in the bar, CPU/RAM live in the System monitor, a slider's readout names it, and mounts that share a device are one row.
9. **Silence is the empty state.** No "No notifications" / "No events". Empty regions collapse.

### Material: `Panel.qml`

Every floating shell panel uses one component, `.config/quickshell/Panel.qml` (added by the minimalism pass), as its background, with content on top:

```qml
Panel { anchors.fill: parent; grain: true }   // grain only per rule 5
```

- Fill `Theme.resin(Theme.resinFillAlpha)` (theme `surface` at 0.72) over Hypr layer blur.
- Gloss `Theme.resinGloss` → transparent over the top 40%.
- **1px rim** `Theme.panelRim` (white 0.14 dark / `border` at 0.38 light). The rim is the edge of the glass, not a frame.
- Grain (`GrainOverlay`) sits **under** content.
- Radius 0; `Panel` has no radius property.
- **No inner glow.** Don't use `Theme.resinGlow`.
- Before `Panel.qml` exists, reproduce exactly this stack inline rather than copying an old `panelShell` block.

### Shape, type, controls

- **Radius:** panels 0; anything inside (tiles, pills, cells, focus boxes) 0-2px. Exceptions: the island's square-top/round-bottom shape (edge-attached, not floating) and existing bar pills. The dock is a flush, square status rail (`modules/dock`: `DockSegment.qml`, sizes and name rules in `DockLayout.js`): icon + lowercase name + one LED per window, selected = inverted accent block, no magnify, no rotation.
- **Font:** `"JetBrainsMono Nerd Font"` for everything. No second family.
- **Nameplate labels:** `font.capitalization: Font.AllUppercase`, `font.letterSpacing: 0.6`.
- **Rows (Spotlight / Command Center):** 38px, 28px icon slot (20px glyph), 13px label, 11px muted right slot, `›` muted at 0.6.
- **Group separation:** 1px `Theme.hairline` `Rectangle` between groups, not a border around every tile.
- **State:** a 7x7 square LED (1px `Theme.accent` border, filled when active). Never recolour the whole element.
- **Sliders:** tick gauge: a `Repeater` of thin ticks, `Theme.accent` up to the value, `Theme.hairline` past it, 2px flat-bar handle.

### Bracketed readouts (`Readout.js`, never hand-format)

`[ KEY · value ]`: square brackets with spaces inside, `·` between fields. `KEY` short and lowercase, except the codes `REC`, `VOL`, `BRT`, `KBD`, `NL`, `MUTE`, `K`. Progress is `mm:ss`, `mm:ss / mm:ss` or `N%`. Used for the bar mpris (`[ spotify · 03:14 / 04:20 ]`), bar recording, OSD (`[ VOL 54% ]`) and Control Center sliders. Never bracket labels, titles or states.

### Tokens

- **Use:** `resin*` (fill, gloss), `panelRim`, `hairline`, `grainOpacity`, `grainTexture`.
- **Shared with Cloud Center:** `Theme.qml` is symlinked there, so add new tokens rather than changing the meaning of existing ones (that's why `panelRim` doesn't reuse `glassPanelBorder`).
- **Legacy, kept only because Cloud Center symlinks them:** `CornerFrame.qml`, `MarginRules.qml`, `frameArmLength`/`frameStroke`/`frameInset`, `resinGlow`. Don't use them in the shell.

## Style

- 4-space indentation, no tabs.
- K&R brace style (opening brace same line).
- No `.editorconfig`/`.qmlformat`/lint config anywhere — style is convention-by-example only.
- Files often open with a `// path/File.qml` comment restating their own path.
