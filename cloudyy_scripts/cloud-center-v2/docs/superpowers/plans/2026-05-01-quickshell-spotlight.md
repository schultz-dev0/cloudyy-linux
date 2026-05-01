# Quickshell Spotlight — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS-style spotlight search overlay (apps, files, web) as a Quickshell QML module, triggered by Super+D and a pinned dock button.

**Architecture:** A new `modules/spotlight/` module registers a `PanelWindow` anchored to the top of the screen that slides in/out via y-animation. A companion `search.sh` shell script handles app search (`.desktop` files via grep) and file search (`fd`). Results are parsed from newline-delimited JSON via `StdioCollector`. The dock gains a pinned search button on the left that toggles the overlay via Hyprland IPC.

**Tech Stack:** QML (Quickshell, WlrLayershell, Hyprland IPC), Bash, `fd`, `jq`, Papirus-Dark icons, matugen Theme tokens.

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `~/.config/quickshell/modules/spotlight/qmldir` | QML module registration |
| Create | `~/.config/quickshell/modules/spotlight/search.sh` | App + file search backend |
| Create | `~/.config/quickshell/modules/spotlight/SpotlightRow.qml` | Single result row component |
| Create | `~/.config/quickshell/modules/spotlight/Spotlight.qml` | Main PanelWindow |
| Modify | `~/.config/quickshell/shell.qml` | Register `QuickSpotlight.Spotlight {}` |
| Modify | `~/.config/quickshell/modules/dock/Dock.qml` | Add pinned search button left of icons |
| Modify | `~/.config/hypr/source/bindings.conf:39` | Replace old hyprdock spotlight bind with `Super+D` → quickshell IPC |

All paths under `~/.config/quickshell/` are symlinked from `~/cloudyy-linux/.config/quickshell/`. Edit the `~/cloudyy-linux/` path — changes will be reflected at `~/.config/`.

---

## Task 1: search.sh + qmldir

**Files:**
- Create: `~/.config/quickshell/modules/spotlight/qmldir`
- Create: `~/.config/quickshell/modules/spotlight/search.sh`

- [ ] **Step 1: Create the qmldir module registration**

```
# ~/cloudyy-linux/.config/quickshell/modules/spotlight/qmldir
module QuickSpotlight
Spotlight 1.0 Spotlight.qml
SpotlightRow 1.0 SpotlightRow.qml
```

- [ ] **Step 2: Create search.sh**

```bash
#!/usr/bin/env bash
# Usage: search.sh <query>
# Outputs newline-delimited JSON to stdout.
# Each line is one of:
#   {"type":"app","name":"Firefox","icon":"firefox","exec":"firefox","wmclass":"firefox"}
#   {"type":"file","name":"notes.md","path":"/home/user/Documents/notes.md"}

query="${1:-}"
[[ -z "$query" ]] && exit 0

APP_DIR="/usr/share/applications"
MAX_FILE="${MAX_FILE_RESULTS:-10}"

# ── App search ─────────────────────────────────────────────────────────────
# Find .desktop files whose Name= field contains query (case-insensitive fixed string).
# Two-pass: first find files with a Name= line, then filter to those containing query.
while IFS= read -r desktop; do
    name=$(grep -m1    "^Name="           "$desktop" 2>/dev/null | cut -d= -f2-)
    icon=$(grep -m1    "^Icon="           "$desktop" 2>/dev/null | cut -d= -f2-)
    exec_raw=$(grep -m1 "^Exec="         "$desktop" 2>/dev/null | cut -d= -f2-)
    exec=$(printf '%s' "$exec_raw" | sed 's/ %[a-zA-Z]//g')
    wmclass=$(grep -m1 "^StartupWMClass=" "$desktop" 2>/dev/null | cut -d= -f2-)
    [[ -z "$wmclass" ]] && wmclass=$(basename "${exec%% *}" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [[ -z "$name" || -z "$exec" ]] && continue
    jq -cn \
      --arg name    "$name" \
      --arg icon    "${icon:-application-x-executable}" \
      --arg exec    "$exec" \
      --arg wmclass "$wmclass" \
      '{type:"app",name:$name,icon:$icon,exec:$exec,wmclass:$wmclass}'
done < <(
    grep -rl "^Name=" "$APP_DIR" 2>/dev/null \
    | xargs grep -lFi "$query"   2>/dev/null \
    | head -8
)

# ── File search ─────────────────────────────────────────────────────────────
# Only runs when query is 4+ chars (matches hyprdock behaviour — avoids noise on short queries).
if [[ ${#query} -ge 4 ]]; then
    fd --max-depth 2 --max-results "$MAX_FILE" -- "$query" "$HOME" 2>/dev/null \
    | while IFS= read -r path; do
        name=$(basename "$path")
        jq -cn --arg name "$name" --arg path "$path" \
          '{type:"file",name:$name,path:$path}'
    done
fi
```

- [ ] **Step 3: Make search.sh executable**

```bash
chmod +x ~/cloudyy-linux/.config/quickshell/modules/spotlight/search.sh
```

- [ ] **Step 4: Test app search manually**

```bash
~/cloudyy-linux/.config/quickshell/modules/spotlight/search.sh firefox
```

Expected: 1–3 JSON lines with `"type":"app"`, `"name"` containing Firefox or similar.

- [ ] **Step 5: Test file search manually (needs a 4-char query)**

```bash
~/cloudyy-linux/.config/quickshell/modules/spotlight/search.sh conf
```

Expected: JSON lines with `"type":"file"` — paths from `$HOME` containing "conf".

- [ ] **Step 6: Test empty query exits cleanly**

```bash
~/cloudyy-linux/.config/quickshell/modules/spotlight/search.sh ""
echo "exit: $?"
```

Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add ~/cloudyy-linux/.config/quickshell/modules/spotlight/
git commit -m "feat: spotlight search.sh and qmldir"
```

---

## Task 2: SpotlightRow.qml

**Files:**
- Create: `~/.config/quickshell/modules/spotlight/SpotlightRow.qml`

This is the single result row. It receives a `resultData` object and an `isSelected` bool, renders the icon + name + subtitle, and emits `activated()` and `hovered()` signals.

- [ ] **Step 1: Create SpotlightRow.qml**

```qml
import QtQuick
import Quickshell
import "../.."

Item {
    id: root

    required property var  resultData   // {type,name,icon?,exec?,wmclass?,isRunning?,path?} or {type:"web",query}
    required property bool isSelected
    required property int  rowWidth

    signal activated()
    signal hovered()

    width:  rowWidth
    height: 46

    // Selection highlight
    Rectangle {
        anchors { fill: parent; margins: 3 }
        radius: 8
        color: root.isSelected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }
    }

    Row {
        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 14; rightMargin: 14
        }
        spacing: 10

        // ── Icon ──────────────────────────────────────────────────────────
        Item {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: iconImg
                anchors.fill: parent
                visible:    root.resultData.type === "app"
                source:     root.resultData.type === "app"
                                ? `file:///usr/share/icons/Papirus-Dark/48x48/apps/${root.resultData.icon}.svg`
                                : ""
                sourceSize: Qt.size(56, 56)
                smooth:     true
                onStatusChanged: {
                    if (status === Image.Error && source.toString().startsWith("file://"))
                        source = Quickshell.iconPath(root.resultData.icon ?? "", "image://icon/application-x-executable")
                }
            }

            Text {
                anchors.centerIn: parent
                visible:     root.resultData.type !== "app"
                text:        root.resultData.type === "file" ? "📄" : "🌐"
                font.pixelSize: 16
            }
        }

        // ── Text ──────────────────────────────────────────────────────────
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: root.rowWidth - 28 - 10 - 14 - 14

            Text {
                width: parent.width
                text:  root.resultData.type === "web"
                    ? `Search DDG for "${root.resultData.query}"`
                    : (root.resultData.name ?? "")
                color: root.resultData.type === "web"
                    ? Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.6)
                    : Theme.textPrimary
                font.pixelSize: 13
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideRight
            }

            Text {
                width:   parent.width
                visible: root.resultData.type === "app" || root.resultData.type === "file"
                text:    root.resultData.type === "app"
                    ? (root.resultData.isRunning ? "Running" : (root.resultData.exec ?? ""))
                    : (root.resultData.path ?? "")
                color:   Theme.textMuted
                font.pixelSize: 11
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideMiddle
            }
        }
    }

    // ── Interaction ───────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered()
        onClicked: root.activated()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ~/cloudyy-linux/.config/quickshell/modules/spotlight/SpotlightRow.qml
git commit -m "feat: SpotlightRow component"
```

---

## Task 3: Spotlight.qml

**Files:**
- Create: `~/.config/quickshell/modules/spotlight/Spotlight.qml`

This is the main PanelWindow. Key behaviours:
- Slides in from above (contentPanel y-animation)
- `WlrKeyboardFocus.Exclusive` when visible so typing works
- `StdioCollector` captures full search.sh output, then parses JSON lines
- Debounce timer prevents a process spawn on every keystroke
- `onSpotlightVisibleChanged` clears state on hide

- [ ] **Step 1: Create Spotlight.qml**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../.."
import "../../overview/services"

PanelWindow {
    id: spotlight

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property string webSearchUrl:   "https://duckduckgo.com/?q="
    readonly property int    overlayWidth:   640
    readonly property int    topMargin:      80
    readonly property int    maxFileResults: 10
    readonly property int    debounceMs:     120

    // ── State ─────────────────────────────────────────────────────────────
    property bool   spotlightVisible: false
    property string query:            ""
    property var    results:          []
    property int    selectedIndex:    0

    // ── Window ────────────────────────────────────────────────────────────
    anchors { top: true; left: true; right: true }
    implicitHeight: contentPanel.implicitHeight + topMargin
    exclusiveZone:  0
    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell:spotlight"
    WlrLayershell.keyboardFocus: spotlightVisible
                                   ? WlrKeyboardFocus.Exclusive
                                   : WlrKeyboardFocus.None
    color: "transparent"

    // ── Launch helper ─────────────────────────────────────────────────────
    Component { id: procProto; Process {} }
    function launch(cmd) {
        const p = procProto.createObject(spotlight, { command: cmd })
        p.runningChanged.connect(() => { if (!p.running) p.destroy() })
        p.running = true
    }

    // ── Search backend ────────────────────────────────────────────────────
    readonly property string searchScript:
        Qt.resolvedUrl("search.sh").toString().replace("file://", "")

    Process {
        id: searchProc
        stdout: StdioCollector {
            id: searchOutput
            onStreamFinished: {
                const runningClasses = new Set(
                    HyprlandData.windowList.map(w => (w.class || "").toLowerCase())
                )
                spotlight.results = searchOutput.text
                    .trim().split("\n")
                    .filter(l => l.length > 0)
                    .flatMap(line => {
                        try {
                            const r = JSON.parse(line)
                            if (r.type === "app")
                                r.isRunning = runningClasses.has((r.wmclass || "").toLowerCase())
                            return [r]
                        } catch (_) { return [] }
                    })
                spotlight.selectedIndex = 0
            }
        }
    }

    Timer {
        id: debounceTimer
        interval: spotlight.debounceMs
        repeat:   false
        onTriggered: {
            if (spotlight.query.length === 0) {
                spotlight.results = []
                return
            }
            spotlight.results = []
            searchProc.command = ["bash", spotlight.searchScript, spotlight.query]
            searchProc.running = true
        }
    }

    onQueryChanged: debounceTimer.restart()

    // ── Activate result at index ──────────────────────────────────────────
    function activateIndex(idx) {
        if (idx < results.length) {
            const r = results[idx]
            if (r.type === "app") {
                if (r.isRunning)
                    Hyprland.dispatch("focuswindow class:" + r.wmclass)
                else
                    launch(["uwsm-app", "--", r.exec])
            } else {
                launch(["xdg-open", r.path])
            }
        } else {
            launch(["xdg-open", webSearchUrl + encodeURIComponent(query)])
        }
        spotlightVisible = false
    }

    // ── Content panel ─────────────────────────────────────────────────────
    Item {
        id: contentPanel
        width:         spotlight.overlayWidth
        implicitHeight: searchBar.height + resultCol.implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: spotlight.spotlightVisible ? spotlight.topMargin : -(implicitHeight + 10)

        Behavior on y {
            NumberAnimation {
                duration: 180
                easing.type: spotlight.spotlightVisible ? Easing.OutCubic : Easing.InCubic
            }
        }

        // Glass pill background
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(Theme.surface_container.r,
                           Theme.surface_container.g,
                           Theme.surface_container.b, 0.92)
            border.color: Qt.rgba(Theme.outline_variant.r,
                                  Theme.outline_variant.g,
                                  Theme.outline_variant.b, 0.25)
            border.width: 1
        }

        // ── Search bar ────────────────────────────────────────────────────
        Item {
            id: searchBar
            width:  parent.width
            height: 52

            Row {
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 16; rightMargin: 16
                }
                spacing: 10

                Text {
                    text: "⌕"
                    color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.55)
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width:  parent.width - 30 - parent.spacing
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter

                    // Placeholder
                    Text {
                        visible: searchInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text:  "Search apps, files, web…"
                        color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.4)
                        font.pixelSize: 16
                        font.family:    "JetBrainsMono Nerd Font"
                    }

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        color:        Theme.textPrimary
                        font.pixelSize: 16
                        font.family:    "JetBrainsMono Nerd Font"
                        selectByMouse:  true
                        text: spotlight.query

                        onTextChanged: spotlight.query = text

                        Keys.onEscapePressed: { spotlight.spotlightVisible = false; event.accepted = true }
                        Keys.onUpPressed: {
                            spotlight.selectedIndex = Math.max(0, spotlight.selectedIndex - 1)
                            event.accepted = true
                        }
                        Keys.onDownPressed: {
                            spotlight.selectedIndex = Math.min(
                                spotlight.results.length,
                                spotlight.selectedIndex + 1
                            )
                            event.accepted = true
                        }
                        Keys.onReturnPressed: {
                            spotlight.activateIndex(spotlight.selectedIndex)
                            event.accepted = true
                        }
                    }
                }
            }

            // Divider shown only when results are present
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height:  1
                visible: spotlight.query.length > 0
                color:   Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                 Theme.outline_variant.b, 0.18)
            }
        }

        // ── Results ───────────────────────────────────────────────────────
        Column {
            id: resultCol
            width: parent.width
            anchors.top: searchBar.bottom

            Repeater {
                model: spotlight.results
                SpotlightRow {
                    required property var  modelData
                    required property int  index
                    resultData:  modelData
                    isSelected:  index === spotlight.selectedIndex
                    rowWidth:    spotlight.overlayWidth
                    onActivated: spotlight.activateIndex(index)
                    onHovered:   spotlight.selectedIndex = index
                }
            }

            // Web row — always last when query is non-empty
            SpotlightRow {
                visible:    spotlight.query.length > 0
                resultData: ({ type: "web", query: spotlight.query })
                isSelected: spotlight.selectedIndex === spotlight.results.length
                rowWidth:   spotlight.overlayWidth
                onActivated: spotlight.activateIndex(spotlight.results.length)
                onHovered:   spotlight.selectedIndex = spotlight.results.length
            }
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────
    IpcHandler {
        target: "spotlight"
        function toggle() { spotlight.spotlightVisible = !spotlight.spotlightVisible }
        function show()   { spotlight.spotlightVisible = true }
        function hide()   { spotlight.spotlightVisible = false }
    }

    onSpotlightVisibleChanged: {
        if (spotlightVisible) {
            searchInput.forceActiveFocus()
        } else {
            query         = ""
            results       = []
            selectedIndex = 0
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ~/cloudyy-linux/.config/quickshell/modules/spotlight/Spotlight.qml
git commit -m "feat: Spotlight PanelWindow"
```

---

## Task 4: Register in shell.qml

**Files:**
- Modify: `~/.config/quickshell/shell.qml`

- [ ] **Step 1: Add the import and component**

Open `~/cloudyy-linux/.config/quickshell/shell.qml`. Add the import after the existing dock import:

```qml
import "modules/spotlight" as QuickSpotlight
```

Add the component inside `ShellRoot` after `QuickDock.Dock {}`:

```qml
QuickSpotlight.Spotlight {}
```

The relevant section of shell.qml after the edit:

```qml
import "overview/modules/overview" as QuickOverview
import "modules/dock" as QuickDock
import "modules/spotlight" as QuickSpotlight

ShellRoot {
    ...
    QuickOverview.Overview {}
    QuickDock.Dock {}
    QuickSpotlight.Spotlight {}
}
```

- [ ] **Step 2: Reload Quickshell and verify no errors**

```bash
quickshell reload
```

Watch the Quickshell log for QML errors:

```bash
journalctl --user -u quickshell -f --no-pager
```

Expected: no errors. If you see `module "QuickSpotlight" not found`, double-check `qmldir` module name matches the import string.

- [ ] **Step 3: Test IPC toggle**

```bash
quickshell ipc call spotlight toggle
```

Expected: the overlay slides in from the top (empty search bar visible, no results yet).

```bash
quickshell ipc call spotlight toggle
```

Expected: overlay slides back up.

- [ ] **Step 4: Commit**

```bash
git add ~/cloudyy-linux/.config/quickshell/shell.qml
git commit -m "feat: register spotlight in shell.qml"
```

---

## Task 5: Dock search button

**Files:**
- Modify: `~/.config/quickshell/modules/dock/Dock.qml`

Two changes:
1. Update `dockWidth` to account for the extra button.
2. Wrap `iconsRow` in a parent Row that prepends the search button.

- [ ] **Step 1: Update dockWidth formula**

Find this line (currently around line 80):

```qml
    readonly property int dockWidth: mergedApps.length * (iconSize + iconSpacing)
                                     - iconSpacing + paddingH * 2
```

Replace with (adds one extra icon slot for the search button):

```qml
    readonly property int dockWidth: mergedApps.length * (iconSize + iconSpacing)
                                     + iconSize + iconSpacing + paddingH * 2
```

- [ ] **Step 2: Replace the iconsRow Row with a wrapper Row**

Find this block inside `dockBody`:

```qml
        // Icon row
        Row {
            id: iconsRow
            anchors {
                verticalCenter: parent.verticalCenter
                horizontalCenter: parent.horizontalCenter
            }
            spacing: dock.iconSpacing

            Repeater {
                model: dock.mergedApps
                DockIcon {
                    required property var  modelData
                    required property int  index
                    appData:      modelData
                    iconSize:     dock.iconSize
                    maxScale:     dock.maxScale
                    spread:       dock.spread
                    frameMs:      dock.frameMs
                    dockMouseX:   dock.dockMouseX
                    iconCenterX:  x + dock.iconSize / 2
                    onClicked: {
                        if (modelData.isRunning)
                            Hyprland.dispatch("focuswindow class:" + modelData.class)
                        else
                            dock.launch(["uwsm-app", "--", modelData.exec])
                    }
                }
            }
        }
```

Replace with:

```qml
        // Icon row (search button pinned left + app icons)
        Row {
            anchors {
                verticalCenter: parent.verticalCenter
                horizontalCenter: parent.horizontalCenter
            }
            spacing: dock.iconSpacing

            // Search button — always leftmost, never displaced by app list
            Item {
                width:  dock.iconSize
                height: dock.iconSize
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    anchors.fill: parent
                    source: "file:///usr/share/icons/Papirus-Dark/48x48/apps/system-search.svg"
                    sourceSize: Qt.size(dock.iconSize * 2, dock.iconSize * 2)
                    smooth: true
                    onStatusChanged: {
                        if (status === Image.Error)
                            source = Quickshell.iconPath("system-search", "image://icon/edit-find")
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch("global quickshell:spotlight:toggle")
                }
            }

            Row {
                id: iconsRow
                spacing: dock.iconSpacing

                Repeater {
                    model: dock.mergedApps
                    DockIcon {
                        required property var  modelData
                        required property int  index
                        appData:      modelData
                        iconSize:     dock.iconSize
                        maxScale:     dock.maxScale
                        spread:       dock.spread
                        frameMs:      dock.frameMs
                        dockMouseX:   dock.dockMouseX
                        iconCenterX:  x + dock.iconSize / 2
                        onClicked: {
                            if (modelData.isRunning)
                                Hyprland.dispatch("focuswindow class:" + modelData.class)
                            else
                                dock.launch(["uwsm-app", "--", modelData.exec])
                        }
                    }
                }
            }
        }
```

- [ ] **Step 3: Reload and verify dock shows search button**

```bash
quickshell reload
```

Expected: dock is wider by one icon slot on the left, with a search/magnifier icon pinned there.

- [ ] **Step 4: Click the search button and verify spotlight opens**

Click the search icon in the dock. Expected: spotlight overlay slides in from top.

- [ ] **Step 5: Commit**

```bash
git add ~/cloudyy-linux/.config/quickshell/modules/dock/Dock.qml
git commit -m "feat: pinned spotlight button on dock left"
```

---

## Task 6: Hyprland keybind

**Files:**
- Modify: `~/.config/hypr/source/bindings.conf:39`

- [ ] **Step 1: Replace the old hyprdock spotlight bind**

Find line 39 in `~/cloudyy-linux/.config/hypr/source/bindings.conf`:

```conf
bindd   = ALT, 6, Open spotlight search, exec, $scripts/cloudyy-other/hyprdock hyprdock -s
```

Replace with:

```conf
bindd   = $mainMod, D, Open spotlight search, exec, quickshell ipc call spotlight toggle
```

- [ ] **Step 2: Reload Hyprland config**

```bash
hyprctl reload
```

- [ ] **Step 3: Test Super+D opens spotlight**

Press `Super+D`. Expected: spotlight overlay slides in from top.

- [ ] **Step 4: Test full search flow**

1. Type `fire` → expected: Firefox app result appears within ~120ms
2. Press `↓` → web row selected
3. Press `↑` → back to Firefox
4. Press `Enter` → Firefox focused (if running) or launched (if not)
5. Open spotlight again with `Super+D`
6. Type `conf` (4 chars) → expected: file results appear below app results
7. Press `Escape` → overlay closes, search cleared

- [ ] **Step 5: Commit**

```bash
git add ~/cloudyy-linux/.config/hypr/source/bindings.conf
git commit -m "feat: bind Super+D to spotlight toggle"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Upper-third position (topMargin: 80, anchored top)
- ✅ No backdrop (transparent PanelWindow, exclusiveZone: 0)
- ✅ Super+D trigger (bindings.conf)
- ✅ Dock search button always pinned left
- ✅ App search from .desktop files (search.sh)
- ✅ File search via fd, depth 2, 4-char minimum (search.sh)
- ✅ Web row always last, opens DDG (Spotlight.qml activateIndex)
- ✅ webSearchUrl tunable at top of Spotlight.qml
- ✅ Arrow navigation, Enter activate, Escape close (Keys handlers)
- ✅ Running app detection (cross-reference HyprlandData.windowList by wmclass)
- ✅ Focus running app via Hyprland.dispatch (activateIndex)
- ✅ Launch non-running app via uwsm-app (activateIndex)
- ✅ File open via xdg-open (activateIndex)
- ✅ IPC toggle/show/hide (IpcHandler)
- ✅ Papirus-Dark icons + fallback (SpotlightRow iconImg)
- ✅ Glass aesthetic (surface_container background, outline_variant border)
- ✅ 640px overlay width (overlayWidth tunable)
- ✅ Slide animation 180ms OutCubic/InCubic (contentPanel Behavior on y)
- ✅ Debounce 120ms (debounceTimer)
- ✅ State cleared on hide (onSpotlightVisibleChanged)
