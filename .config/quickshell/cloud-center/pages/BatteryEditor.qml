import QtQuick
import QtQuick.Controls
import "../components"
import "../components/BatteryState.js" as BatteryState
import "../services" as S
import ".."

Flickable {
    id: batteryPage
    required property var page

    contentWidth: width
    contentHeight: content.implicitHeight + 54
    clip: true

    property var snapshot: BatteryState.emptySnapshot()
    property int nextActionId: 1
    property int nextGeneration: 1
    property string statusMessage: ""
    property bool watchStarted: false
    property bool thresholdPending: false
    property int pendingThreshold: 100
    property bool suppressModeSignal: false

    readonly property bool present: snapshot.present === true
    readonly property var info: snapshot.info || null
    readonly property var display: snapshot.display || ({})

    function applySnapshot(next) {
        if (!next)
            return;
        snapshot = BatteryState.clone(next);
        if (snapshot.stale === true) {
            statusMessage = String(snapshot.error || "Battery could not be refreshed");
            return;
        }
        statusMessage = String(snapshot.error || "");
        if (!thresholdPending && BatteryState.hasCapability(snapshot, "threshold"))
            pendingThreshold = BatteryState.thresholdValue(snapshot);
        if (BatteryState.hasCapability(snapshot, "asus_mode")) {
            suppressModeSignal = true;
            modeSelect.currentIndex = BatteryState.chargeModeIndex(snapshot);
            suppressModeSignal = false;
        }
    }

    function requestSnapshot(startWatchAfter) {
        S.Backend.request("get_battery_snapshot", {}, function(result) {
            batteryPage.applySnapshot(result);
            if (startWatchAfter && !batteryPage.watchStarted) {
                batteryPage.watchStarted = true;
                S.Backend.request("start_battery_watch", {}, function(watchSnapshot) {
                    batteryPage.applySnapshot(watchSnapshot);
                }, function(error) {
                    batteryPage.statusMessage = String(
                        (error && (error.message || error.error))
                        || "Battery live updates could not start"
                    );
                });
            }
        }, function(error) {
            batteryPage.statusMessage = String(
                (error && (error.message || error.error))
                || "Battery could not be refreshed"
            );
        });
    }

    function sendAction(action, value, target) {
        const actionId = String(nextActionId++);
        const generation = nextGeneration++;
        S.Backend.request("run_battery_action", {
            action: action,
            target: target || action,
            value: value,
            action_id: actionId,
            generation: generation,
        }, function(result) {
            if (result && result.queued === true)
                return;
            batteryPage.statusMessage = String(
                (result && (result.message || result.error))
                || "Battery action was rejected"
            );
            if (action === "set_threshold")
                batteryPage.thresholdPending = false;
        }, function(error) {
            batteryPage.statusMessage = String(
                (error && (error.message || error.error))
                || "Battery action failed"
            );
            if (action === "set_threshold")
                batteryPage.thresholdPending = false;
        });
    }

    function commitThreshold() {
        thresholdPending = true;
        sendAction("set_threshold", pendingThreshold, "threshold");
    }

    Component.onCompleted: requestSnapshot(true)
    Component.onDestruction: S.Backend.request("stop_battery_watch", {}, null)

    Connections {
        target: S.Backend
        function onBatterySnapshotEvent(next) {
            batteryPage.applySnapshot(next);
        }
        function onBatteryActionDoneEvent(actionId, target, generation, ok,
                                          staleTarget, message) {
            if (String(target) === "threshold" || String(target) === "set_threshold")
                batteryPage.thresholdPending = false;
            if (message)
                batteryPage.statusMessage = String(message);
        }
    }

    Timer {
        id: thresholdDebounce
        interval: 800
        onTriggered: batteryPage.commitThreshold()
    }

    Column {
        id: content
        width: Math.min(batteryPage.width - 56, 760)
        x: (batteryPage.width - width) / 2
        y: 24
        spacing: 14

        Item {
            width: content.width
            height: 46
            Text {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                text: batteryPage.page.title || "Battery"
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 20
                    weight: Font.Bold
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
            CloudButton {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                text: "Refresh"
                glyph: "󰑐"
                subtle: true
                compact: true
                onClicked: batteryPage.requestSnapshot(false)
            }
        }

        Item {
            visible: !batteryPage.present
            width: content.width
            height: Math.max(220, batteryPage.height - 120)
            Text {
                anchors.centerIn: parent
                text: "No battery"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 16
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
        }

        Column {
            visible: batteryPage.present
            width: content.width
            spacing: 14

            SectionCard {
                width: parent.width
                section: ({ title: "Battery Status" })

                Column {
                    width: parent.width
                    spacing: 0

                    Item {
                        width: parent.width
                        height: 72
                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                top: parent.top
                                topMargin: 14
                            }
                            text: BatteryState.displayValue(
                                batteryPage.snapshot, "hero_title", "Battery"
                            )
                            color: Theme.textPrimary
                            renderType: Text.NativeRendering
                            font {
                                family: "JetBrainsMono Nerd Font"
                                pixelSize: 13
                                weight: Font.Medium
                                hintingPreference: Font.PreferVerticalHinting
                            }
                        }
                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                bottom: parent.bottom
                                bottomMargin: 12
                            }
                            text: BatteryState.displayValue(
                                batteryPage.snapshot, "hero_subtitle", ""
                            )
                            visible: text !== ""
                            color: Theme.textMuted
                            renderType: Text.NativeRendering
                            font {
                                family: "JetBrainsMono Nerd Font"
                                pixelSize: 11
                                hintingPreference: Font.PreferVerticalHinting
                            }
                        }
                        Text {
                            anchors {
                                right: parent.right
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: BatteryState.displayValue(
                                batteryPage.snapshot, "percentage_label", "—%"
                            )
                            color: Theme.accent
                            renderType: Text.NativeRendering
                            font {
                                family: "JetBrainsMono Nerd Font"
                                pixelSize: 28
                                weight: Font.Bold
                                hintingPreference: Font.PreferVerticalHinting
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 24
                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: 10
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            height: 8
                            radius: 4
                            color: Theme.glass(Theme.outline_variant, 0.55)
                            Rectangle {
                                width: parent.width * Math.max(
                                    0, Math.min(1, BatteryState.percentage(batteryPage.snapshot) / 100)
                                )
                                height: parent.height
                                radius: 4
                                color: Theme.primary
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width - 20
                        x: 10
                        height: 1
                        color: Theme.glass(Theme.outline_variant, 0.35)
                    }

                    Repeater {
                        model: [
                            {
                                title: "State",
                                value: batteryPage.info
                                    ? String(batteryPage.info.status || "—") : "—",
                            },
                            {
                                title: "Power Draw",
                                value: BatteryState.displayValue(
                                    batteryPage.snapshot, "power_label", "—"
                                ),
                            },
                            {
                                title: "Time Remaining",
                                value: BatteryState.displayValue(
                                    batteryPage.snapshot, "time_label", "—"
                                ),
                            },
                        ]
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 44
                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.title
                                color: Theme.textPrimary
                                renderType: Text.NativeRendering
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 12
                                    hintingPreference: Font.PreferVerticalHinting
                                }
                            }
                            Text {
                                anchors {
                                    right: parent.right
                                    rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.value
                                color: Theme.textMuted
                                renderType: Text.NativeRendering
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 12
                                    hintingPreference: Font.PreferVerticalHinting
                                }
                            }
                            Rectangle {
                                visible: index < 2
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    right: parent.right
                                    rightMargin: 10
                                    bottom: parent.bottom
                                }
                                height: 1
                                color: Theme.glass(Theme.outline_variant, 0.35)
                            }
                        }
                    }
                }
            }

            SectionCard {
                width: parent.width
                section: ({ title: "Battery Health" })

                Column {
                    width: parent.width
                    Repeater {
                        model: [
                            {
                                title: "Health",
                                value: BatteryState.displayValue(
                                    batteryPage.snapshot, "health_label", "—"
                                ),
                            },
                            {
                                title: "Capacity",
                                value: BatteryState.displayValue(
                                    batteryPage.snapshot, "capacity_label", "—"
                                ),
                            },
                            {
                                title: "Voltage",
                                value: BatteryState.displayValue(
                                    batteryPage.snapshot, "voltage_label", "—"
                                ),
                            },
                            {
                                title: "Charge Cycles",
                                value: BatteryState.displayValue(
                                    batteryPage.snapshot, "cycles_label", "N/A"
                                ),
                            },
                        ]
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 44
                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.title
                                color: Theme.textPrimary
                                renderType: Text.NativeRendering
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 12
                                    hintingPreference: Font.PreferVerticalHinting
                                }
                            }
                            Text {
                                anchors {
                                    right: parent.right
                                    rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.value
                                color: Theme.textMuted
                                renderType: Text.NativeRendering
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 12
                                    hintingPreference: Font.PreferVerticalHinting
                                }
                            }
                            Rectangle {
                                visible: index < 3
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    right: parent.right
                                    rightMargin: 10
                                    bottom: parent.bottom
                                }
                                height: 1
                                color: Theme.glass(Theme.outline_variant, 0.35)
                            }
                        }
                    }
                }
            }

            SectionCard {
                visible: BatteryState.hasCapability(batteryPage.snapshot, "threshold")
                width: parent.width
                section: ({ title: "Charge Limit" })

                Item {
                    width: parent.width
                    height: 64
                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 10
                            top: parent.top
                            topMargin: 12
                        }
                        text: "Stop Charging At"
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                        font {
                            family: "JetBrainsMono Nerd Font"
                            pixelSize: 12
                            hintingPreference: Font.PreferVerticalHinting
                        }
                    }
                    Text {
                        anchors {
                            right: parent.right
                            rightMargin: 10
                            top: parent.top
                            topMargin: 12
                        }
                        text: batteryPage.pendingThreshold + "%"
                        color: Theme.textMuted
                        renderType: Text.NativeRendering
                        font {
                            family: "JetBrainsMono Nerd Font"
                            pixelSize: 12
                            hintingPreference: Font.PreferVerticalHinting
                        }
                    }
                    Slider {
                        id: thresholdSlider
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 10
                            rightMargin: 10
                            bottom: parent.bottom
                            bottomMargin: 10
                        }
                        height: 24
                        from: 40
                        to: 100
                        stepSize: 5
                        value: batteryPage.pendingThreshold
                        onMoved: {
                            batteryPage.pendingThreshold = Math.round(value);
                            thresholdDebounce.restart();
                        }
                        background: Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.outline_variant
                            Rectangle {
                                width: thresholdSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: Theme.primary
                            }
                        }
                        handle: Rectangle {
                            x: thresholdSlider.visualPosition * (thresholdSlider.width - width)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 14
                            radius: 7
                            color: Theme.surface_container_lowest
                            border {
                                width: 1
                                color: Theme.outline
                            }
                        }
                    }
                }
            }

            SectionCard {
                visible: BatteryState.hasCapability(batteryPage.snapshot, "asus_mode")
                width: parent.width
                section: ({ title: "Charge Mode" })

                Item {
                    width: parent.width
                    height: 52
                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        text: "Charging Mode"
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                        font {
                            family: "JetBrainsMono Nerd Font"
                            pixelSize: 12
                            hintingPreference: Font.PreferVerticalHinting
                        }
                    }
                    CloudSelect {
                        id: modeSelect
                        anchors {
                            right: parent.right
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        width: 180
                        compact: true
                        options: batteryPage.snapshot.asus_modes || []
                        currentIndex: BatteryState.chargeModeIndex(batteryPage.snapshot)
                        onActivated: index => {
                            if (batteryPage.suppressModeSignal)
                                return;
                            batteryPage.sendAction("set_charge_mode", index, "charge_mode");
                        }
                    }
                }
            }

            SectionCard {
                width: parent.width
                section: ({ title: "Device Information" })

                Column {
                    width: parent.width
                    Repeater {
                        model: [
                            {
                                title: "Manufacturer",
                                value: batteryPage.info
                                    ? String(batteryPage.info.manufacturer || "N/A") : "N/A",
                            },
                            {
                                title: "Model",
                                value: batteryPage.info
                                    ? String(batteryPage.info.model || "N/A") : "N/A",
                            },
                            {
                                title: "Technology",
                                value: batteryPage.info
                                    ? String(batteryPage.info.technology || "N/A") : "N/A",
                            },
                            {
                                title: "Serial Number",
                                value: batteryPage.info
                                    ? String(batteryPage.info.serial || "N/A") : "N/A",
                            },
                        ]
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 44
                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.title
                                color: Theme.textPrimary
                                renderType: Text.NativeRendering
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 12
                                    hintingPreference: Font.PreferVerticalHinting
                                }
                            }
                            Text {
                                anchors {
                                    right: parent.right
                                    rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.value
                                color: Theme.textMuted
                                renderType: Text.NativeRendering
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 12
                                    hintingPreference: Font.PreferVerticalHinting
                                }
                            }
                            Rectangle {
                                visible: index < 3
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    right: parent.right
                                    rightMargin: 10
                                    bottom: parent.bottom
                                }
                                height: 1
                                color: Theme.glass(Theme.outline_variant, 0.35)
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: batteryPage.statusMessage !== ""
            width: content.width
            text: batteryPage.statusMessage
            wrapMode: Text.WordWrap
            color: batteryPage.snapshot.stale === true ? Theme.error : Theme.textMuted
            renderType: Text.NativeRendering
            font {
                family: "JetBrainsMono Nerd Font"
                pixelSize: 10
                hintingPreference: Font.PreferVerticalHinting
            }
            leftPadding: 4
        }
    }
}
