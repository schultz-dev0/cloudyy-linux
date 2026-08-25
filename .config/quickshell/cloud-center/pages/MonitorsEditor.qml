import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import "../components"
import "../services" as S
import ".."

Flickable {
    id: monPage
    required property var page

    contentHeight: content.implicitHeight + 48
    clip: true

    property var monitors: []
    property var transforms: []
    property string selectedName: ""
    property string baselineJson: "[]"
    property bool sessionOpen: false
    property bool advancedOpen: false
    property string statusMessage: ""
    property bool confirmationOpen: false
    property string confirmationToken: ""
    property real confirmationDeadline: 0
    property int confirmationSeconds: 15

    readonly property var selected: {
        for (const monitor of monPage.monitors)
            if (monitor.name === monPage.selectedName) return monitor;
        return null;
    }
    readonly property bool dirty: JSON.stringify(monPage.monitors) !== monPage.baselineJson
    readonly property int activeCount: monPage.monitors.filter(monitor => monitor.enabled !== false).length
    readonly property bool selectedIsHeadless: monPage.selectedName.toLowerCase().includes("headless")
    readonly property bool selectedIsHdr: monPage.selected
        && (monPage.selected.cm === "hdr" || monPage.selected.cm === "hdredid")

    readonly property var vrrValues: [0, 1, 2, 3]
    readonly property var vrrLabels: ["Off", "Always", "Fullscreen", "Fullscreen game/video"]
    readonly property var colorValues: ["auto", "srgb", "dcip3", "dp3", "adobe", "wide", "edid", "hdr", "hdredid"]
    readonly property var colorLabels: ["Auto", "sRGB", "DCI-P3", "Display P3", "Adobe RGB", "Wide gamut", "EDID", "HDR (experimental)", "HDR EDID (experimental)"]
    readonly property var eotfValues: ["default", "srgb", "gamma22"]
    readonly property var eotfLabels: ["Default", "sRGB", "Gamma 2.2"]

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function replaceDraft(name, changes) {
        const next = monPage.clone(monPage.monitors);
        const index = next.findIndex(monitor => monitor.name === name);
        if (index < 0) return;
        for (const key in changes)
            next[index][key] = changes[key];
        monPage.monitors = next;
    }

    function setSelectedField(field, value) {
        if (!monPage.selected) return;
        const changes = {};
        changes[field] = value;
        monPage.replaceDraft(monPage.selectedName, changes);
        monPage.statusMessage = "";
    }

    function openSession() {
        S.Backend.request("open_monitor_session", {}, function(result) {
            if (!result || !result.ok) {
                monPage.statusMessage = result ? result.message : "Could not open monitor session";
                return;
            }
            monPage.monitors = monPage.clone(result.monitors ?? []);
            monPage.transforms = result.transforms ?? [];
            monPage.baselineJson = JSON.stringify(monPage.monitors);
            monPage.sessionOpen = true;
            if (!monPage.monitors.some(monitor => monitor.name === monPage.selectedName))
                monPage.selectedName = monPage.monitors.length ? monPage.monitors[0].name : "";
            monPage.statusMessage = "";
        });
    }

    function rescan() {
        const reopen = function() { monPage.sessionOpen = false; monPage.openSession(); };
        if (monPage.sessionOpen)
            S.Backend.request("close_monitor_session", {}, reopen);
        else
            reopen();
    }

    function workspaceEnabled(id) {
        return monPage.selected && (monPage.selected.workspaces ?? []).includes(String(id));
    }

    function toggleWorkspace(id) {
        if (!monPage.selected) return;
        const value = String(id);
        const workspaces = (monPage.selected.workspaces ?? []).slice();
        const index = workspaces.indexOf(value);
        if (index >= 0) workspaces.splice(index, 1);
        else workspaces.push(value);
        monPage.setSelectedField("workspaces", workspaces);
    }

    function extraWorkspaces() {
        if (!monPage.selected) return [];
        return (monPage.selected.workspaces ?? []).filter(workspace => {
            const number = Number(workspace);
            return !(String(number) === String(workspace) && number >= 1 && number <= 10);
        });
    }

    function addExtraWorkspace() {
        if (!monPage.selected) return;
        const value = extraWorkspaceInput.text.trim();
        if (value === "") return;
        const workspaces = (monPage.selected.workspaces ?? []).slice();
        if (!workspaces.includes(value)) workspaces.push(value);
        monPage.setSelectedField("workspaces", workspaces);
        extraWorkspaceInput.text = "";
    }

    function removeExtraWorkspace(value) {
        if (!monPage.selected) return;
        monPage.setSelectedField("workspaces",
            (monPage.selected.workspaces ?? []).filter(workspace => workspace !== value));
    }

    function testLayout() {
        if (!monPage.dirty || monPage.confirmationOpen) return;
        S.Backend.request("test_monitor_layout", { monitors: monPage.monitors }, function(result) {
            if (!result || !result.ok) {
                monPage.statusMessage = result ? result.message : "Could not apply display layout";
                return;
            }
            monPage.confirmationToken = result.token;
            monPage.confirmationDeadline = Number(result.deadline);
            monPage.confirmationSeconds = 15;
            monPage.confirmationOpen = true;
            monPage.statusMessage = "Display layout applied temporarily";
        });
    }

    function keepLayout() {
        const token = monPage.confirmationToken;
        S.Backend.request("keep_monitor_layout", { token }, function(result) {
            monPage.confirmationOpen = false;
            monPage.confirmationToken = "";
            if (result && result.ok) {
                monPage.baselineJson = JSON.stringify(monPage.monitors);
                monPage.statusMessage = result.message;
            } else {
                monPage.monitors = monPage.clone(JSON.parse(monPage.baselineJson));
                monPage.statusMessage = result ? result.message : "Could not save display layout";
            }
        });
    }

    function revertLayout() {
        if (monPage.confirmationToken === "") return;
        const token = monPage.confirmationToken;
        S.Backend.request("revert_monitor_layout", { token }, function(result) {
            monPage.confirmationOpen = false;
            monPage.confirmationToken = "";
            monPage.monitors = monPage.clone(JSON.parse(monPage.baselineJson));
            monPage.statusMessage = result ? result.message : "Previous display layout restored";
        });
    }

    Component.onCompleted: openSession()
    Component.onDestruction: {
        if (monPage.sessionOpen)
            S.Backend.request("close_monitor_session", {}, null);
    }

    Connections {
        target: S.Backend
        function onMonitorLayoutEvent(state, message) {
            if (state !== "reverted") return;
            monPage.confirmationOpen = false;
            monPage.confirmationToken = "";
            monPage.monitors = monPage.clone(JSON.parse(monPage.baselineJson));
            monPage.statusMessage = message;
        }
    }

    component StyledCombo: CloudSelect {
        id: styledCombo
        property var values: []
        property var labels: []
        signal valueChosen(var value)
        width: 175
        compact: true
        options: labels
        onActivated: index => styledCombo.valueChosen(styledCombo.values[index])
    }

    component SmallField: Rectangle {
        id: smallField
        property alias text: field.text
        property alias validator: field.validator
        signal committed(string text)
        width: 76
        height: 28
        radius: 2
        color: Theme.surfaceRaised
        border { width: 1; color: Theme.hairline }
        TextInput {
            id: field
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            selectByMouse: true
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
            onEditingFinished: smallField.committed(text)
        }
    }

    Column {
        id: content
        width: Math.min(monPage.width - 56, 760)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14
        topPadding: 24

        Item {
            width: content.width
            height: 42
            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 2
                Row {
                    spacing: 10
                    Text {
                        text: monPage.page.title
                        color: Theme.text
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; bold: true }
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: monPage.activeCount + " / " + monPage.monitors.length + " active"
                        color: Theme.textMuted
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                    }
                }
                Text {
                    visible: monPage.selected !== null
                    text: monPage.selected ? monPage.selected.name + " · " + (monPage.selected.description || monPage.selected.model || "Display") : ""
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    width: 440
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 7
                Rectangle {
                    width: headlessText.implicitWidth + 18; height: 28; radius: 2
                    color: headlessHover.hovered ? Theme.accent : Theme.accentMuted
                    Text { id: headlessText; anchors.centerIn: parent; text: "󰐕 Headless"
                           color: headlessHover.hovered ? Theme.accentText : Theme.accentText
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                    HoverHandler { id: headlessHover }
                    TapHandler {
                        onTapped: S.Backend.request("add_headless_monitor", {}, function(result) {
                            monPage.statusMessage = result ? result.message : "Could not create headless display";
                            if (result && result.ok) monPage.rescan();
                        })
                    }
                }
                Rectangle {
                    width: rescanText.implicitWidth + 18; height: 28; radius: 2
                    color: rescanHover.hovered ? Theme.accent : Theme.accentMuted
                    Text { id: rescanText; anchors.centerIn: parent; text: "󰑓 Rescan"
                           color: rescanHover.hovered ? Theme.accentText : Theme.accentText
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                    HoverHandler { id: rescanHover }
                    TapHandler { onTapped: monPage.rescan() }
                }
            }
        }

        MonitorLayoutCanvas {
            width: content.width
            height: 205
            monitors: monPage.monitors
            selectedName: monPage.selectedName
            backgroundColor: Theme.background
            monitorColor: Theme.surfaceOverlay
            selectedColor: Theme.glass(Theme.accent, 0.24)
            borderColor: Theme.border
            accentColor: Theme.accent
            textColor: Theme.text
            mutedColor: Theme.textMuted
            onSelected: name => monPage.selectedName = name
            onMoved: (name, x, y) => monPage.replaceDraft(name, { x, y })
        }

        Text {
            visible: monPage.monitors.length === 0
            text: "No monitors detected."
            color: Theme.textMuted
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
        }

        SectionCard {
            visible: monPage.selected !== null
            width: content.width
            section: ({ title: "Display Mode" })

            RowBase {
                width: parent.width
                item: ({ icon: "󰐥", title: "Enabled", description: "Include this display in the layout" })
                Rectangle {
                    width: 40; height: 22; radius: 11
                    color: monPage.selected && monPage.selected.enabled ? Theme.accent : Theme.border
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Rectangle {
                        x: monPage.selected && monPage.selected.enabled ? parent.width - width - 3 : 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16; radius: 8
                        color: Theme.background
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }
                    TapHandler { onTapped: monPage.setSelectedField("enabled", !monPage.selected.enabled) }
                }
            }

            RowBase {
                width: parent.width
                item: ({ icon: "󰍹", title: "Resolution & refresh rate", description: "Click anywhere to choose, or type a custom Hyprland mode" })
                EditableCombo {
                    width: 230
                    options: monPage.selected ? monPage.selected.available_modes ?? [] : []
                    value: monPage.selected ? monPage.selected.mode : ""
                    backgroundColor: Theme.surfaceRaised
                    hoverColor: Theme.surfaceOverlay
                    borderColor: Theme.border
                    textColor: Theme.text
                    mutedColor: Theme.textMuted
                    accentColor: Theme.accent
                    onValueChanged: {
                        if (monPage.selected && value !== monPage.selected.mode)
                            monPage.setSelectedField("mode", value);
                    }
                }
            }

            RowBase {
                width: parent.width
                item: ({ icon: "󰇄", title: "Scale", description: "Display scaling factor" })
                Row {
                    spacing: 5
                    Repeater {
                        model: [
                            { label: "−", delta: -0.25 },
                            { label: monPage.selected ? Number(monPage.selected.scale).toFixed(2) : "1.00", delta: 0 },
                            { label: "+", delta: 0.25 },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: modelData.delta === 0 ? 62 : 28
                            height: 28; radius: 2
                            color: modelData.delta === 0 ? Theme.surfaceRaised : scaleHover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised
                            border { width: 1; color: Theme.hairline }
                            Text { anchors.centerIn: parent; text: modelData.label; color: Theme.text
                                   font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                            HoverHandler { id: scaleHover }
                            TapHandler {
                                enabled: modelData.delta !== 0
                                onTapped: monPage.setSelectedField("scale",
                                    Math.max(0.25, Math.min(4, Number(monPage.selected.scale) + modelData.delta)))
                            }
                        }
                    }
                }
            }

            RowBase {
                width: parent.width
                item: ({ icon: "󰑞", title: "Rotation", description: "Rotate or flip the selected display" })
                StyledCombo {
                    values: monPage.transforms.map(transform => transform.id)
                    labels: monPage.transforms.map(transform => transform.label)
                    currentIndex: Math.max(0, values.indexOf(monPage.selected ? monPage.selected.transform : 0))
                    onValueChosen: value => monPage.setSelectedField("transform", value)
                }
            }
        }

        SectionCard {
            visible: monPage.selected !== null
            width: content.width
            section: ({ title: "Placement" })

            RowBase {
                width: parent.width
                item: ({ icon: "󰍽", title: "Position", description: "Top-left logical pixels; dragging the canvas updates these values" })
                SmallField {
                    text: monPage.selected ? String(monPage.selected.x) : "0"
                    validator: IntValidator { bottom: -32768; top: 32768 }
                    onCommitted: value => monPage.setSelectedField("x", parseInt(value, 10) || 0)
                }
                SmallField {
                    text: monPage.selected ? String(monPage.selected.y) : "0"
                    validator: IntValidator { bottom: -32768; top: 32768 }
                    onCommitted: value => monPage.setSelectedField("y", parseInt(value, 10) || 0)
                }
            }

            RowBase {
                width: parent.width
                item: ({ icon: "󰍺", title: "Mirror of", description: "Mirror another output without re-rendering it" })
                StyledCombo {
                    readonly property var mirrorValues: [""].concat(monPage.monitors.map(monitor => monitor.name).filter(name => name !== monPage.selectedName))
                    values: mirrorValues
                    labels: ["None"].concat(mirrorValues.slice(1))
                    currentIndex: Math.max(0, values.indexOf(monPage.selected ? monPage.selected.mirror_of : ""))
                    onValueChosen: value => monPage.setSelectedField("mirror_of", value)
                }
            }
        }

        SectionCard {
            visible: monPage.selected !== null
            width: content.width
            section: ({ title: "Workspaces" })

            Item {
                width: parent.width
                height: workspaceColumn.implicitHeight + 20
                Column {
                    id: workspaceColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    Grid {
                        columns: 5
                        columnSpacing: 10
                        rowSpacing: 8
                        Repeater {
                            model: 10
                            delegate: Rectangle {
                                required property int index
                                readonly property string workspaceId: String(index + 1)
                                width: (workspaceColumn.width - 40) / 5
                                height: 28; radius: 2
                                color: monPage.workspaceEnabled(workspaceId)
                                    ? Theme.accentMuted : Theme.surfaceRaised
                                border { width: 1; color: monPage.workspaceEnabled(workspaceId) ? Theme.accent : Theme.hairline }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Rectangle {
                                        width: 13; height: 13; radius: 4
                                        color: monPage.workspaceEnabled(workspaceId) ? Theme.accent : "transparent"
                                        border { width: 1; color: Theme.hairline }
                                        Text { anchors.centerIn: parent; visible: monPage.workspaceEnabled(workspaceId)
                                               text: "✓"; color: Theme.background; font.pixelSize: 9 }
                                    }
                                    Text { text: workspaceId; color: Theme.text
                                           renderType: Text.NativeRendering
                                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; weight: Font.Medium
                                                  hintingPreference: Font.PreferVerticalHinting } }
                                }
                                TapHandler { onTapped: monPage.toggleWorkspace(workspaceId) }
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: monPage.extraWorkspaces()
                            delegate: Rectangle {
                                required property string modelData
                                width: extraLabel.implicitWidth + 28
                                height: 25; radius: 2
                                color: Theme.surfaceRaised
                                border { width: 1; color: Theme.hairline }
                                Text { id: extraLabel; anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                       text: modelData; color: Theme.text
                                       renderType: Text.NativeRendering
                                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                              hintingPreference: Font.PreferVerticalHinting } }
                                Text { anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                                       text: "×"; color: Theme.error; font.pixelSize: 12 }
                                TapHandler { onTapped: monPage.removeExtraWorkspace(modelData) }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 30; radius: 2
                        color: Theme.surfaceRaised
                        border { width: 1; color: Theme.hairline }
                        TextInput {
                            id: extraWorkspaceInput
                            anchors { left: parent.left; right: addExtra.left; top: parent.top; bottom: parent.bottom
                                      leftMargin: 9; rightMargin: 8 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            selectByMouse: true
                            renderType: TextInput.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                   hintingPreference: Font.PreferVerticalHinting }
                            onAccepted: monPage.addExtraWorkspace()
                            Text { visible: extraWorkspaceInput.text === ""; anchors.verticalCenter: parent.verticalCenter
                                   text: "Add extra workspace name or ID"; color: Theme.textMuted
                                   font: extraWorkspaceInput.font; renderType: Text.NativeRendering }
                        }
                        Text { id: addExtra; anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                               text: "＋"; color: Theme.accent; font.pixelSize: 13 }
                        TapHandler { onTapped: monPage.addExtraWorkspace() }
                    }
                }
            }
        }

        SectionCard {
            visible: monPage.selected !== null
            width: content.width
            section: ({ title: "" })

            RowBase {
                width: parent.width
                item: ({ icon: "󰒓", title: "Advanced display", description: "Synchronization, color management, and output behavior" })
                Text { text: monPage.advancedOpen ? "󰅀" : "󰅂"; color: Theme.textMuted
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                onClicked: monPage.advancedOpen = !monPage.advancedOpen
            }

            RowBase {
                visible: monPage.advancedOpen
                width: parent.width
                item: ({ icon: "󰖺", title: "Adaptive Sync / VRR", description: "Variable refresh behavior for this output" })
                StyledCombo {
                    width: 195
                    values: monPage.vrrValues
                    labels: monPage.vrrLabels
                    currentIndex: Math.max(0, values.indexOf(monPage.selected ? monPage.selected.vrr : 0))
                    onValueChosen: value => monPage.setSelectedField("vrr", value)
                }
            }

            RowBase {
                visible: monPage.advancedOpen
                width: parent.width
                item: ({ icon: "󰻂", title: "Color depth", description: "10-bit output may be incompatible with some capture tools" })
                StyledCombo {
                    values: [8, 10]
                    labels: ["8-bit", "10-bit"]
                    currentIndex: values.indexOf(monPage.selected ? monPage.selected.bitdepth : 8)
                    onValueChosen: value => monPage.setSelectedField("bitdepth", value)
                }
            }

            RowBase {
                visible: monPage.advancedOpen
                width: parent.width
                item: ({ icon: "󰏘", title: "Color preset", description: "HDR presets are experimental in Hyprland" })
                StyledCombo {
                    width: 195
                    values: monPage.colorValues
                    labels: monPage.colorLabels
                    currentIndex: Math.max(0, values.indexOf(monPage.selected ? monPage.selected.cm : "srgb"))
                    onValueChosen: value => monPage.setSelectedField("cm", value)
                }
            }

            RowBase {
                visible: monPage.advancedOpen
                width: parent.width
                item: ({ icon: "󰈙", title: "ICC profile", description: "Overrides the color preset and is incompatible with HDR gaming" })
                Rectangle {
                    width: 245; height: 28; radius: 2
                    color: Theme.surfaceRaised
                    border { width: 1; color: Theme.hairline }
                    Text {
                        anchors { left: parent.left; right: clearIcc.left; leftMargin: 8; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        text: monPage.selected && monPage.selected.icc ? monPage.selected.icc : "No profile selected"
                        color: monPage.selected && monPage.selected.icc ? Theme.text : Theme.textMuted
                        elide: Text.ElideMiddle
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 }
                    }
                    Text { id: clearIcc; anchors { right: browseIcc.left; rightMargin: 7; verticalCenter: parent.verticalCenter }
                           visible: monPage.selected && monPage.selected.icc !== ""; text: "×"; color: Theme.error; font.pixelSize: 12 }
                    Text { id: browseIcc; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                           text: "Browse…"; color: Theme.accent
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 } }
                    TapHandler {
                        onTapped: eventPoint => {
                            if (clearIcc.visible && eventPoint.position.x >= clearIcc.x - 5
                                    && eventPoint.position.x < browseIcc.x) {
                                monPage.setSelectedField("icc", "");
                            } else {
                                iccDialog.open();
                            }
                        }
                    }
                }
            }

            RowBase {
                visible: monPage.advancedOpen
                width: parent.width
                item: ({ icon: "󰖨", title: "SDR transfer function", description: "Default, piecewise sRGB, or Gamma 2.2" })
                StyledCombo {
                    values: monPage.eotfValues
                    labels: monPage.eotfLabels
                    currentIndex: Math.max(0, values.indexOf(monPage.selected ? monPage.selected.sdr_eotf : "default"))
                    onValueChosen: value => monPage.setSelectedField("sdr_eotf", value)
                }
            }

            RowBase {
                visible: monPage.advancedOpen && monPage.selectedIsHdr
                width: parent.width
                item: ({ icon: "󰃠", title: "SDR brightness in HDR", description: monPage.selected ? Number(monPage.selected.sdrbrightness).toFixed(2) : "1.00" })
                Slider {
                    id: brightnessSlider
                    width: 165; height: 24
                    from: 0.5; to: 3.0; stepSize: 0.05
                    value: monPage.selected ? Number(monPage.selected.sdrbrightness) : 1
                    onMoved: monPage.setSelectedField("sdrbrightness", value)
                    background: Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2
                                             color: Theme.hairline
                                             Rectangle { width: brightnessSlider.visualPosition * parent.width; height: parent.height; radius: 2; color: Theme.accent } }
                    handle: Rectangle { x: brightnessSlider.visualPosition * (brightnessSlider.width - width); anchors.verticalCenter: parent.verticalCenter
                                         width: 14; height: 14; radius: 7; color: Theme.background; border { width: 1; color: Theme.border } }
                }
            }

            RowBase {
                visible: monPage.advancedOpen && monPage.selectedIsHdr
                width: parent.width
                item: ({ icon: "󰕸", title: "SDR saturation in HDR", description: monPage.selected ? Number(monPage.selected.sdrsaturation).toFixed(2) : "1.00" })
                Slider {
                    id: saturationSlider
                    width: 165; height: 24
                    from: 0.0; to: 2.0; stepSize: 0.05
                    value: monPage.selected ? Number(monPage.selected.sdrsaturation) : 1
                    onMoved: monPage.setSelectedField("sdrsaturation", value)
                    background: Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2
                                             color: Theme.hairline
                                             Rectangle { width: saturationSlider.visualPosition * parent.width; height: parent.height; radius: 2; color: Theme.accent } }
                    handle: Rectangle { x: saturationSlider.visualPosition * (saturationSlider.width - width); anchors.verticalCenter: parent.verticalCenter
                                         width: 14; height: 14; radius: 7; color: Theme.background; border { width: 1; color: Theme.border } }
                }
            }

            RowBase {
                visible: monPage.advancedOpen
                width: parent.width
                item: ({ icon: "󰐥", title: "Power off now", description: "Temporary DPMS power-off; this does not alter the layout" })
                Rectangle {
                    width: 120; height: 28; radius: 2
                    color: dpmsHover.hovered ? Theme.error : Theme.glass(Theme.error, 0.12)
                    Text { anchors.centerIn: parent; text: "Power off " + monPage.selectedName
                           color: dpmsHover.hovered ? Theme.accentText : Theme.error
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 } }
                    HoverHandler { id: dpmsHover }
                    TapHandler {
                        onTapped: S.Backend.request("set_monitor_dpms", { name: monPage.selectedName, enabled: false }, function(result) {
                            monPage.statusMessage = result ? result.message : "DPMS command failed";
                        })
                    }
                }
            }
        }

        Item {
            visible: monPage.selected !== null
            width: content.width
            height: 38
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width - applyButton.width - 20
                text: monPage.statusMessage !== "" ? monPage.statusMessage
                    : monPage.dirty ? "Changes are staged; Apply tests the complete layout" : "Layout matches the opening snapshot"
                color: monPage.statusMessage !== "" ? Theme.textMuted : monPage.dirty ? Theme.accent : Theme.textMuted
                elide: Text.ElideRight
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Rectangle {
                id: applyButton
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 116; height: 30; radius: 2
                color: monPage.dirty && !monPage.confirmationOpen
                    ? Theme.accent
                    : Theme.surfaceOverlay
                Text { anchors.centerIn: parent; text: "Apply layout"
                       color: monPage.dirty && !monPage.confirmationOpen ? Theme.background : Theme.textMuted
                       renderType: Text.NativeRendering
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; weight: Font.Medium
                              hintingPreference: Font.PreferVerticalHinting } }
                HoverHandler { id: applyHover }
                TapHandler { enabled: monPage.dirty && !monPage.confirmationOpen; onTapped: monPage.testLayout() }
            }
        }

        Rectangle {
            visible: monPage.selectedIsHeadless
            width: content.width
            height: 34; radius: 0
            color: Theme.glass(Theme.error, 0.12)
            Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                   text: "Remove virtual output " + monPage.selectedName; color: Theme.error
                   font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
            TapHandler {
                onTapped: S.Backend.request("remove_headless_monitor", { name: monPage.selectedName }, function(result) {
                    monPage.statusMessage = result ? result.message : "Could not remove headless display";
                    if (result && result.ok) { monPage.selectedName = ""; monPage.rescan(); }
                })
            }
        }
    }

    FileDialog {
        id: iccDialog
        title: "Choose an ICC profile"
        nameFilters: ["ICC profiles (*.icc *.icm)", "All files (*)"]
        onAccepted: {
            const path = selectedFile.toString().replace(/^file:\/\//, "");
            monPage.setSelectedField("icc", decodeURIComponent(path));
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: monPage.confirmationOpen
        onTriggered: {
            monPage.confirmationSeconds = Math.max(0,
                Math.ceil(monPage.confirmationDeadline - Date.now() / 1000));
            if (monPage.confirmationSeconds === 0) {
                monPage.confirmationOpen = false;
                monPage.confirmationToken = "";
                monPage.monitors = monPage.clone(JSON.parse(monPage.baselineJson));
                monPage.statusMessage = "Previous display layout restored";
            }
        }
    }

    Popup {
        id: confirmationDialog
        modal: true
        dim: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: 390
        padding: 22
        visible: monPage.confirmationOpen
        closePolicy: Popup.NoAutoClose
        enter: null
        exit: null

        background: Rectangle {
            radius: 0
            color: Theme.surfaceRaised
            border { width: 1; color: Theme.hairline }
        }

        contentItem: Column {
            width: 346
            spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Keep these display settings?"
                color: Theme.text
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 15; bold: true }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "The complete previous layout will be restored automatically if you do nothing."
                color: Theme.textMuted
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64; height: 64; radius: 32
                color: Theme.surfaceOverlay
                border { width: 4; color: Theme.accent }
                Text { anchors.centerIn: parent; text: monPage.confirmationSeconds; color: Theme.text
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; bold: true } }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "seconds remaining"
                color: Theme.textMuted
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 9
                Rectangle {
                    width: 112; height: 30; radius: 2
                    color: revertHover.hovered ? Theme.surfaceOverlay : Theme.surface
                    border { width: 1; color: Theme.hairline }
                    Text { anchors.centerIn: parent; text: "Revert now"; color: Theme.text
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                    HoverHandler { id: revertHover }
                    TapHandler { onTapped: monPage.revertLayout() }
                }
                Rectangle {
                    width: 112; height: 30; radius: 2
                    color: Theme.accent
                    Text { anchors.centerIn: parent; text: "Keep layout"; color: Theme.background
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; bold: true } }
                    HoverHandler { id: keepHover }
                    TapHandler { onTapped: monPage.keepLayout() }
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: monPage.confirmationOpen
        onActivated: monPage.revertLayout()
    }
}
