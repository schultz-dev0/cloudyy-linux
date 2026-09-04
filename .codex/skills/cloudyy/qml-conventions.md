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

- Standard font family: `"JetBrainsMono Nerd Font"` everywhere.
- Every `Text`/`TextInput` sets `renderType: Text.NativeRendering` (or `TextInput.NativeRendering`) — no exceptions found repo-wide.
- Often paired with `font.hintingPreference: Font.PreferVerticalHinting`.

## Style

- 4-space indentation, no tabs.
- K&R brace style (opening brace same line).
- No `.editorconfig`/`.qmlformat`/lint config anywhere — style is convention-by-example only.
- Files often open with a `// path/File.qml` comment restating their own path.
