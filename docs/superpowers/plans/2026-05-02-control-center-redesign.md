# Control Center Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace NotifPanel's icon-only toggles with a macOS-style labeled tile grid, add a playerctl media card, and establish a modular tile architecture so new tiles can be added with one file + one line.

**Architecture:** Each tile is a self-contained QML component in `modules/controlcenter/tiles/`. `TileGrid.qml` is a `GridLayout` wrapper that accepts tiles as declarative children. `NotifPanel.qml` imports both directories and composes everything. No changes to shell.qml, Sliders.qml, or any other file.

**Tech Stack:** QML / Qt Quick, QuickShell, Qt Quick Controls (Popup, Slider), playerctl, nmcli, bluetoothctl

---

## Import conventions (read before coding)

- Files in `modules/controlcenter/` use `import "../.."` to access `Theme` (same pattern as `modules/dock/DockIcon.qml:3`)
- Files in `modules/controlcenter/tiles/` use `import "../../.."` to access `Theme`
- Files in `modules/controlcenter/tiles/` can use `BaseTile` without extra imports (same directory)
- `NotifPanel.qml` needs two new imports: `import "modules/controlcenter"` and `import "modules/controlcenter/tiles"`

---

## File map

| File | Action |
|---|---|
| `modules/controlcenter/tiles/BaseTile.qml` | create |
| `modules/controlcenter/tiles/WifiTile.qml` | create |
| `modules/controlcenter/tiles/DndTile.qml` | create |
| `modules/controlcenter/tiles/BluetoothTile.qml` | create |
| `modules/controlcenter/tiles/DarkModeTile.qml` | create |
| `modules/controlcenter/tiles/NightLightTile.qml` | create |
| `modules/controlcenter/TileGrid.qml` | create |
| `modules/controlcenter/MediaCard.qml` | create |
| `NotifPanel.qml` | modify |

---

## Task 1: Create directory structure + BaseTile

**Files:**
- Create: `modules/controlcenter/tiles/BaseTile.qml`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p /home/schultz/cloudyy-linux/.config/quickshell/modules/controlcenter/tiles
```

- [ ] **Step 2: Write BaseTile.qml**

`BaseTile` is the shared base for all half-width tiles. It renders icon → label → status in a column, highlights teal when `active`, and emits `clicked()` / `rightClicked()`.

```qml
// modules/controlcenter/tiles/BaseTile.qml
import QtQuick
import QtQuick.Layouts
import "../../.."

Rectangle {
    id: root

    property string icon:       ""
    property string label:      ""
    property string statusText: ""
    property bool   active:     false

    signal clicked()
    signal rightClicked()

    implicitHeight: 68
    radius: 12
    color: active
        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
        : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.6)
    border.color: active
        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
        : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
    border.width: 1

    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 2

        Text {
            text:        root.icon
            color:       root.active ? Theme.primary : Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
        }

        Text {
            text:           root.label
            color:          Theme.on_surface
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.weight:    Font.Bold
            Layout.fillWidth: true
            elide:          Text.ElideRight
        }

        Text {
            text:           root.statusText
            color:          root.active
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                : Theme.on_surface_variant
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            visible:        root.statusText !== ""
        }
    }

    MouseArea {
        anchors.fill:    parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked()
            else
                root.clicked()
        }
    }
}
```

- [ ] **Step 3: Verify file exists**

```bash
ls /home/schultz/cloudyy-linux/.config/quickshell/modules/controlcenter/tiles/
# Expected: BaseTile.qml
```

- [ ] **Step 4: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/tiles/BaseTile.qml
git commit -m "feat(cc): add BaseTile base component"
```

---

## Task 2: TileGrid

**Files:**
- Create: `modules/controlcenter/TileGrid.qml`

- [ ] **Step 1: Write TileGrid.qml**

`TileGrid` wraps a `GridLayout`. Its `default property alias` re-parents declarative children into the inner `GridLayout`, so `Layout.columnSpan` on children works correctly. Tiles decide their own span — `WifiTile` sets `Layout.columnSpan: 2`; all others use the default 1.

```qml
// modules/controlcenter/TileGrid.qml
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    default property alias tiles: grid.data

    implicitHeight: grid.implicitHeight

    GridLayout {
        id: grid
        anchors { left: parent.left; right: parent.right }
        columns:       2
        rowSpacing:    6
        columnSpacing: 6
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/TileGrid.qml
git commit -m "feat(cc): add TileGrid layout container"
```

---

## Task 3: WifiTile

**Files:**
- Create: `modules/controlcenter/tiles/WifiTile.qml`

- [ ] **Step 1: Write WifiTile.qml**

Wide tile (spans both columns). Reads connected SSID via `nmcli`. Clicking opens `nm-connection-editor`. Sets `Layout.columnSpan: 2` and `Layout.fillWidth: true` so the `GridLayout` in `TileGrid` gives it the full row.

```qml
// modules/controlcenter/tiles/WifiTile.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../.."

Rectangle {
    id: root

    Layout.columnSpan: 2
    Layout.fillWidth:  true
    implicitHeight:    52
    radius:            12
    color:  Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.13)
    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
    border.width: 1

    property string networkName: "..."

    function refresh() {
        wifiProc.running = false
        wifiProc.running = true
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
        spacing: 10

        Text {
            text:        "󰖩"
            color:       Theme.primary
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 20
        }

        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true

            Text {
                text:           "Wi-Fi"
                color:          Theme.on_surface
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.weight:    Font.Bold
            }

            Text {
                text:           root.networkName
                color:          Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                elide:          Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked:    launchProc.running = true
    }

    Process {
        id: wifiProc
        command: ["bash", "-c", "nmcli -t -f active,ssid dev wifi | awk -F: '/^yes/{print $2}'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const name = line.trim()
                root.networkName = name !== "" ? name : "Not connected"
            }
        }
    }

    Process {
        id: launchProc
        command: ["uwsm-app", "--", "nm-connection-editor"]
        running: false
    }

    Component.onCompleted: refresh()
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/tiles/WifiTile.qml
git commit -m "feat(cc): add WifiTile (nmcli, wide layout)"
```

---

## Task 4: DndTile

**Files:**
- Create: `modules/controlcenter/tiles/DndTile.qml`

- [ ] **Step 1: Write DndTile.qml**

Pure binding tile — no polling. The `dnd` property is bound to `panel.dnd` from outside; `dndToggle` signal is connected to `panel.dndToggle()`.

```qml
// modules/controlcenter/tiles/DndTile.qml
import QtQuick

BaseTile {
    id: root

    property bool dnd: false
    signal dndToggle()

    icon:       "󰂛"
    label:      "Do Not Disturb"
    statusText: dnd ? "On" : "Off"
    active:     dnd

    onClicked: root.dndToggle()
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/tiles/DndTile.qml
git commit -m "feat(cc): add DndTile"
```

---

## Task 5: BluetoothTile

**Files:**
- Create: `modules/controlcenter/tiles/BluetoothTile.qml`

- [ ] **Step 1: Write BluetoothTile.qml**

Reads `bluetoothctl show | awk '/Powered:/{print $2}'` → `yes`/`no`. Clicking opens the bluetooth manager.

```qml
// modules/controlcenter/tiles/BluetoothTile.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

BaseTile {
    id: root

    icon:       "󰂯"
    label:      "Bluetooth"
    statusText: "Off"
    active:     false

    function refresh() {
        btProc.running = false
        btProc.running = true
    }

    onClicked: launchProc.running = true

    Process {
        id: btProc
        command: ["bash", "-c", "bluetoothctl show | awk '/Powered:/{print $2}'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const on = line.trim() === "yes"
                root.active     = on
                root.statusText = on ? "On" : "Off"
            }
        }
    }

    Process {
        id: launchProc
        command: ["bash", "-c", "cloud-center bluetooth"]
        running: false
    }

    Component.onCompleted: refresh()
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/tiles/BluetoothTile.qml
git commit -m "feat(cc): add BluetoothTile"
```

---

## Task 6: DarkModeTile

**Files:**
- Create: `modules/controlcenter/tiles/DarkModeTile.qml`

- [ ] **Step 1: Write DarkModeTile.qml**

Reads `~/.config/hypr/theme_state/state.conf` for `THEME_MODE`. After the toggle command finishes, refreshes itself.

```qml
// modules/controlcenter/tiles/DarkModeTile.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

BaseTile {
    id: root

    icon:       active ? "󰖔" : "󰖙"
    label:      "Dark Mode"
    statusText: active ? "Dark" : "Light"
    active:     true

    function refresh() {
        readProc.running = false
        readProc.running = true
    }

    onClicked: toggleProc.running = true

    Process {
        id: readProc
        command: ["bash", "-c",
            "grep THEME_MODE ~/.config/hypr/theme_state/state.conf | cut -d= -f2 | tr -d '\"'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { root.active = line.trim() === "dark" }
        }
    }

    Process {
        id: toggleProc
        command: ["bash", "-lc", "~/cloudyy_scripts/theme_controller.sh toggle"]
        running: false
        onRunningChanged: if (!running) root.refresh()
    }

    Component.onCompleted: refresh()
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/tiles/DarkModeTile.qml
git commit -m "feat(cc): add DarkModeTile"
```

---

## Task 7: NightLightTile

**Files:**
- Create: `modules/controlcenter/tiles/NightLightTile.qml`

- [ ] **Step 1: Write NightLightTile.qml**

Extends `BaseTile` directly (adding a `Popup` child — valid since `BaseTile` is a `Rectangle`). Left-click calls `sliderController.toggleNightLight()`. Right-click opens a `Popup` with a gradient temperature slider. The popup anchors to the top-right of the tile.

```qml
// modules/controlcenter/tiles/NightLightTile.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../.."

BaseTile {
    id: root

    property var sliderController: null

    icon:       "󰖙"
    label:      "Night Light"
    statusText: (sliderController && sliderController.nightLightActive)
        ? ("On · " + (sliderController ? sliderController.nightLightTemp : 3500) + "K")
        : "Off"
    active: sliderController ? sliderController.nightLightActive : false

    onClicked:      if (sliderController) sliderController.toggleNightLight()
    onRightClicked: tempPopup.open()

    Popup {
        id: tempPopup
        parent:      root
        x:           root.width - width
        y:           -(implicitHeight + 6)
        width:       188
        padding:     12
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

        background: Rectangle {
            radius:       12
            color:        Qt.rgba(Theme.surface_container_high.r,
                                  Theme.surface_container_high.g,
                                  Theme.surface_container_high.b, 0.97)
            border.color: Qt.rgba(Theme.tertiary.r, Theme.tertiary.g, Theme.tertiary.b, 0.4)
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text:           "󰖙  Night Light"
                    color:          Theme.tertiary
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight:    Font.Bold
                    Layout.fillWidth: true
                }

                Text {
                    text:           (root.sliderController
                        ? root.sliderController.nightLightTemp : 3500) + "K"
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                }
            }

            Slider {
                id:             tempSlider
                Layout.fillWidth: true
                from:           1000
                to:             6500
                stepSize:       100
                value:          root.sliderController
                    ? root.sliderController.nightLightTemp : 3500
                live:           true

                onMoved: if (root.sliderController)
                    root.sliderController.setNightLightTemp(value)

                background: Rectangle {
                    x:      tempSlider.leftPadding
                    y:      tempSlider.topPadding + tempSlider.availableHeight / 2 - height / 2
                    width:  tempSlider.availableWidth
                    height: 6
                    radius: 999
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: "#ff8c42" }
                        GradientStop { position: 0.45; color: "#ffe0b3" }
                        GradientStop { position: 1.0;  color: "#afc9e7" }
                    }
                }

                handle: Rectangle {
                    x:      tempSlider.leftPadding
                            + tempSlider.visualPosition
                            * (tempSlider.availableWidth - width)
                    y:      tempSlider.topPadding
                            + tempSlider.availableHeight / 2 - height / 2
                    width:  14
                    height: 14
                    radius: 7
                    color:  "#ffffff"
                    border.color: Qt.rgba(0, 0, 0, 0.2)
                    border.width: 1
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "warm"; color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 7
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "cool"; color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 7
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/tiles/NightLightTile.qml
git commit -m "feat(cc): add NightLightTile with right-click temp popover"
```

---

## Task 8: MediaCard

**Files:**
- Create: `modules/controlcenter/MediaCard.qml`

- [ ] **Step 1: Write MediaCard.qml**

Polls `playerctl` every 2 s. First checks status; if non-empty, fetches metadata in a second `Process`. Hidden when no player is active. Album art uses `layer.enabled: true` on the container rectangle to clip the `Image` to rounded corners.

```qml
// modules/controlcenter/MediaCard.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."

Rectangle {
    id: root

    property bool   playing:          false
    property string title:            ""
    property string artist:           ""
    property string artUrl:           ""
    property string playerName:       ""
    property real   progressFraction: 0

    visible:        root.title !== ""
    implicitHeight: visible ? cardCol.implicitHeight + 24 : 0
    radius:         12
    color:  Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                    Theme.surface_container.b, 0.5)
    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                          Theme.outline_variant.b, 0.25)
    border.width: 1

    ColumnLayout {
        id: cardCol
        anchors { fill: parent; margins: 12 }
        spacing: 8

        // ── Art + info ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                id:           artContainer
                width:        44
                height:       44
                radius:       8
                layer.enabled: true
                gradient: Gradient {
                    orientation: Gradient.Diagonal
                    GradientStop { position: 0.0; color: Theme.primary_container }
                    GradientStop { position: 1.0; color: Theme.tertiary_container }
                }

                Image {
                    anchors.fill:  parent
                    source:        root.artUrl
                    fillMode:      Image.PreserveAspectCrop
                    visible:       status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    text:        "♪"
                    font.pixelSize: 20
                    color:       Theme.on_primary_container
                    visible:     parent.children[0].status !== Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text:           root.title
                    color:          Theme.on_surface
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight:    Font.Bold
                    elide:          Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text:           root.artist
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide:          Text.ElideRight
                }

                Text {
                    text:           root.playerName
                    color:          Qt.rgba(Theme.primary.r, Theme.primary.g,
                                           Theme.primary.b, 0.6)
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 8
                    visible:        root.playerName !== ""
                }
            }
        }

        // ── Progress bar ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 3
            radius: 999
            color:  Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                            Theme.outline_variant.b, 0.4)

            Rectangle {
                width:  parent.width * root.progressFraction
                height: parent.height
                radius: parent.radius
                color:  Theme.primary
            }
        }

        // ── Controls ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 20

            Text {
                text: "⏮"; color: Theme.on_surface_variant; font.pixelSize: 16
                MouseArea { anchors.fill: parent; onClicked: prevProc.running = true }
            }

            Text {
                text: root.playing ? "⏸" : "⏵"
                color: Theme.primary; font.pixelSize: 22
                MouseArea { anchors.fill: parent; onClicked: playPauseProc.running = true }
            }

            Text {
                text: "⏭"; color: Theme.on_surface_variant; font.pixelSize: 16
                MouseArea { anchors.fill: parent; onClicked: nextProc.running = true }
            }
        }
    }

    // ── Polling ─────────────────────────────────────────────────────────────
    Timer {
        interval:  2000
        repeat:    true
        running:   true
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }

    Process {
        id: statusProc
        command: ["bash", "-c", "playerctl status 2>/dev/null"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const s = line.trim()
                if (s === "") {
                    root.title   = ""
                    root.playing = false
                    return
                }
                root.playing       = (s === "Playing")
                metaProc.running   = false
                metaProc.running   = true
            }
        }
    }

    Process {
        id: metaProc
        command: ["bash", "-c",
            "playerctl metadata --format '{{title}}\t{{artist}}\t{{mpris:artUrl}}\t{{mpris:length}}\t{{position}}\t{{playerName}}' 2>/dev/null"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const p = line.split("\t")
                if (p.length < 4) return
                root.title          = p[0] || ""
                root.artist         = p[1] || ""
                root.artUrl         = p[2] || ""
                const lenUs         = parseFloat(p[3]) || 0
                const posSec        = parseFloat(p[4]) || 0
                root.progressFraction = lenUs > 0
                    ? Math.max(0, Math.min(1, (posSec * 1e6) / lenUs)) : 0
                root.playerName     = p[5] || ""
            }
        }
    }

    Process { id: prevProc;      command: ["playerctl", "previous"];   running: false }
    Process { id: playPauseProc; command: ["playerctl", "play-pause"]; running: false }
    Process { id: nextProc;      command: ["playerctl", "next"];       running: false }
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/MediaCard.qml
git commit -m "feat(cc): add MediaCard with playerctl polling"
```

---

## Task 9: Refactor NotifPanel.qml

**Files:**
- Modify: `NotifPanel.qml`

This task replaces the old inline toggle/slider system with the new components. The Display section, Sound section, and notification list stay byte-for-byte identical.

- [ ] **Step 1: Read current NotifPanel.qml to orient yourself**

```bash
wc -l /home/schultz/cloudyy-linux/.config/quickshell/NotifPanel.qml
# Should be ~423 lines
```

- [ ] **Step 2: Replace the entire file with the refactored version**

```qml
// NotifPanel.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "modules/controlcenter"
import "modules/controlcenter/tiles"

PanelWindow {
    id: panel

    // ── Tunables ─────────────────────────────────────────────────────────────
    readonly property int panelWidth:   380
    readonly property int panelHeight:  900
    readonly property int topGap:        10
    readonly property int rightGap:      20
    readonly property int panelRadius:   24
    readonly property int sectionRadius: 16

    // ── Props ─────────────────────────────────────────────────────────────────
    property bool open:             false
    property bool dnd:              false
    property var  notifServer:      null
    property var  sliderController: null
    signal close()
    signal dndToggle()
    onOpenChanged: {
        if (open && sliderController) sliderController.refreshAll()
        if (open) { wifiTile.refresh(); btTile.refresh(); darkTile.refresh() }
    }

    // ── Clock ─────────────────────────────────────────────────────────────────
    property string clockText: ""
    Timer {
        interval: 60000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: panel.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM · hh:mm")
    }

    // ── One-shot launcher ─────────────────────────────────────────────────────
    Component { id: procProto; Process {} }
    function launch(cmd) {
        procProto.createObject(panel, { command: cmd }).running = true
    }

    // ── Window setup ──────────────────────────────────────────────────────────
    anchors { top: true; right: true }
    margins { top: topGap; right: rightGap }
    implicitWidth:  panelWidth
    implicitHeight: panelHeight
    color:          "transparent"
    visible:        open

    // ── Panel shell ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill:  parent
        radius:        panel.panelRadius
        color:  Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                              Theme.outline_variant.b, 0.3)
        border.width: 1

        ColumnLayout {
            anchors { fill: parent; margins: 18 }
            spacing: 12

            // ── Header ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text:           "Control Center"
                    color:          Theme.on_surface
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.weight:    Font.Bold
                    Layout.fillWidth: true
                }

                Text {
                    text:           panel.clockText
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            // ── Tile grid ─────────────────────────────────────────────────────
            TileGrid {
                Layout.fillWidth: true

                WifiTile { id: wifiTile }

                DndTile {
                    id:        dndTile
                    dnd:       panel.dnd
                    onDndToggle: panel.dndToggle()
                }

                BluetoothTile { id: btTile }

                DarkModeTile { id: darkTile }

                NightLightTile {
                    id:               nlTile
                    sliderController: panel.sliderController
                }
            }

            // ── Display ───────────────────────────────────────────────────────
            Rectangle {
                visible: !!panel.sliderController
                Layout.fillWidth: true
                radius:  panel.sectionRadius
                color:   Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                      Theme.outline_variant.b, 0.25)
                border.width:   1
                implicitHeight: 72

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text:           "Display"
                        color:          Theme.on_surface
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight:    Font.Medium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius:         10
                        color:  Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                                        Theme.surface_container.b, 0.5)
                        implicitHeight: 38

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 10

                            Slider {
                                id:              brightnessSlider
                                Layout.fillWidth: true
                                from:    1; to: 100; live: true
                                value:   panel.sliderController
                                    ? panel.sliderController.brightnessValue : 50
                                palette.highlight: Theme.tertiary
                                onMoved: if (panel.sliderController)
                                    panel.sliderController.setBrightness(value)

                                background: Rectangle {
                                    x: brightnessSlider.leftPadding
                                    y: brightnessSlider.topPadding
                                       + brightnessSlider.availableHeight / 2 - height / 2
                                    width: brightnessSlider.availableWidth; height: 10; radius: 999
                                    color: Qt.rgba(Theme.surface_container_high.r,
                                                   Theme.surface_container_high.g,
                                                   Theme.surface_container_high.b, 0.45)
                                    Rectangle {
                                        width: brightnessSlider.visualPosition * parent.width
                                        height: parent.height; radius: parent.radius
                                        color: brightnessSlider.palette.highlight
                                        opacity: brightnessSlider.enabled ? 1 : 0.35
                                    }
                                }
                                handle: Rectangle {
                                    x: brightnessSlider.leftPadding
                                       + brightnessSlider.visualPosition
                                       * (brightnessSlider.availableWidth - width)
                                    y: brightnessSlider.topPadding
                                       + brightnessSlider.availableHeight / 2 - height / 2
                                    width: 16; height: 16; radius: 8
                                    color: brightnessSlider.pressed ? Theme.primary : Theme.on_surface
                                    border.color: Qt.rgba(Theme.surface.r, Theme.surface.g,
                                                          Theme.surface.b, 0.8)
                                    border.width: 1
                                    opacity: brightnessSlider.enabled ? 1 : 0.4
                                }
                            }

                            Rectangle {
                                width: 30; height: 30; radius: 10
                                color: Qt.rgba(Theme.surface_container_high.r,
                                               Theme.surface_container_high.g,
                                               Theme.surface_container_high.b, 0.55)
                                border.color: Qt.rgba(Theme.outline_variant.r,
                                                      Theme.outline_variant.g,
                                                      Theme.outline_variant.b, 0.3)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent; text: "󰃠"
                                    color: Theme.on_surface
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (panel.sliderController)
                                        panel.sliderController.showBrightness()
                                }
                            }
                        }
                    }
                }
            }

            // ── Sound ─────────────────────────────────────────────────────────
            Rectangle {
                visible: !!panel.sliderController
                Layout.fillWidth: true
                radius:  panel.sectionRadius
                color:   Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                      Theme.outline_variant.b, 0.25)
                border.width:   1
                implicitHeight: 72

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text:           "Sound"
                        color:          Theme.on_surface
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight:    Font.Medium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius:         10
                        color:  Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                                        Theme.surface_container.b, 0.5)
                        implicitHeight: 38

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 10

                            Slider {
                                id:              volumeSlider
                                Layout.fillWidth: true
                                from: 0; to: 100; live: true
                                value: panel.sliderController
                                    ? panel.sliderController.volumeValue : 50
                                palette.highlight: Theme.primary
                                onMoved: if (panel.sliderController)
                                    panel.sliderController.setVolume(value)

                                background: Rectangle {
                                    x: volumeSlider.leftPadding
                                    y: volumeSlider.topPadding
                                       + volumeSlider.availableHeight / 2 - height / 2
                                    width: volumeSlider.availableWidth; height: 10; radius: 999
                                    color: Qt.rgba(Theme.surface_container_high.r,
                                                   Theme.surface_container_high.g,
                                                   Theme.surface_container_high.b, 0.45)
                                    Rectangle {
                                        width: volumeSlider.visualPosition * parent.width
                                        height: parent.height; radius: parent.radius
                                        color: volumeSlider.palette.highlight
                                        opacity: volumeSlider.enabled ? 1 : 0.35
                                    }
                                }
                                handle: Rectangle {
                                    x: volumeSlider.leftPadding
                                       + volumeSlider.visualPosition
                                       * (volumeSlider.availableWidth - width)
                                    y: volumeSlider.topPadding
                                       + volumeSlider.availableHeight / 2 - height / 2
                                    width: 16; height: 16; radius: 8
                                    color: volumeSlider.pressed ? Theme.primary : Theme.on_surface
                                    border.color: Qt.rgba(Theme.surface.r, Theme.surface.g,
                                                          Theme.surface.b, 0.8)
                                    border.width: 1
                                    opacity: volumeSlider.enabled ? 1 : 0.4
                                }
                            }

                            Rectangle {
                                width: 30; height: 30; radius: 10
                                color: Qt.rgba(Theme.surface_container_high.r,
                                               Theme.surface_container_high.g,
                                               Theme.surface_container_high.b, 0.55)
                                border.color: Qt.rgba(Theme.outline_variant.r,
                                                      Theme.outline_variant.g,
                                                      Theme.outline_variant.b, 0.3)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text:  panel.sliderController
                                        ? panel.sliderController.volumeIcon : "󰕾"
                                    color: Theme.on_surface
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (panel.sliderController)
                                        panel.sliderController.toggleMute()
                                }
                            }
                        }
                    }
                }
            }

            // ── Media card ────────────────────────────────────────────────────
            MediaCard { Layout.fillWidth: true }

            // ── Notification list ─────────────────────────────────────────────
            ListView {
                id: notifList
                Layout.fillWidth:  true
                Layout.fillHeight: true
                spacing: 6
                clip:    true
                model:   panel.notifServer ? panel.notifServer.trackedNotifications : null

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width:  notifList.width
                    height: cardContent.implicitHeight + 28
                    radius: 18
                    color: card.modelData.urgency === 2
                        ? Qt.rgba(Theme.error_container.r, Theme.error_container.g,
                                  Theme.error_container.b, 0.2)
                        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
                    border.color: card.modelData.urgency === 2
                        ? Theme.error
                        : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                  Theme.outline_variant.b, 0.4)
                    border.width: 1

                    Column {
                        id: cardContent
                        anchors { left: parent.left; right: parent.right
                                  top: parent.top; margins: 14 }
                        spacing: 4

                        Text {
                            text:           card.modelData.appName
                            color:          Theme.on_surface_variant
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        Text {
                            width:          parent.width
                            text:           card.modelData.summary
                            color:          Theme.on_surface
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.weight:    Font.Bold
                            wrapMode:       Text.WordWrap
                        }
                        Text {
                            visible:  card.modelData.body !== ""
                            width:    parent.width
                            text:     card.modelData.body
                            color:    Qt.rgba(Theme.on_surface.r, Theme.on_surface.g,
                                             Theme.on_surface.b, 0.8)
                            font.family:      "JetBrainsMono Nerd Font"
                            font.pixelSize:   13
                            wrapMode:         Text.WordWrap
                            maximumLineCount: 3
                            elide:            Text.ElideRight
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: card.modelData.dismiss() }
                }

                Text {
                    anchors.centerIn: parent
                    visible:        notifList.count === 0
                    text:           "No notifications"
                    color:  Qt.rgba(Theme.on_surface_variant.r, Theme.on_surface_variant.g,
                                    Theme.on_surface_variant.b, 0.4)
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                }
            }
        }
    }
}
```

- [ ] **Step 3: Verify quickshell can parse the files**

```bash
cd /home/schultz/cloudyy-linux/.config/quickshell
# If qmlls is available:
qmlls NotifPanel.qml 2>&1 | head -20
# If not, check for obvious syntax errors with:
grep -n "import" NotifPanel.qml
# Expected: 8 import lines including the two new modules/controlcenter ones
```

- [ ] **Step 4: Reload quickshell and open the control center**

Trigger the control center (same keybind as before — defined in `bindings.conf`). Verify:
- Header shows "Control Center" + current date/time on the right
- WiFi wide tile shows the connected network name
- DND, Bluetooth, Dark Mode, Night Light tiles are visible in 2-column layout
- Right-clicking Night Light opens the gradient temperature popover
- Display and Sound sliders work as before
- Media card appears if a player (Spotify, mpv, etc.) is running
- Notifications list unchanged

- [ ] **Step 5: Commit**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/NotifPanel.qml
git commit -m "feat(cc): wire TileGrid + MediaCard into NotifPanel"
```

---

## Task 10: Final integration commit

- [ ] **Step 1: Verify all new files are committed**

```bash
cd /home/schultz/cloudyy-linux
git log --oneline -8
# Should show ~6-7 commits from this feature
git status
# Should be clean
```

- [ ] **Step 2: Create summary commit if anything is uncommitted**

```bash
cd /home/schultz/cloudyy-linux
git add .config/quickshell/modules/controlcenter/
git commit -m "feat: macOS-style control center with modular tile system"
```

---

## Adding a new tile later

1. Create `modules/controlcenter/tiles/MyTile.qml` using `BaseTile` as the root element (or a custom `Rectangle` with `Layout.columnSpan: 2` for a wide tile)
2. Add `MyTile { }` inside `TileGrid { }` in `NotifPanel.qml`
3. If the tile needs panel-level state (like DndTile), add a property and binding at the call site
