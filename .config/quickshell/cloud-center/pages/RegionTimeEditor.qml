import QtQuick
import QtQuick.Controls
import "../components"
import "../components/RegionTimeState.js" as RegionTimeState
import "../services" as S
import ".."

Flickable {
    id: regionPage
    required property var page

    contentWidth: width
    contentHeight: content.implicitHeight + 54
    clip: true

    property var snapshot: RegionTimeState.emptySnapshot()
    property var timezones: []
    property string tzQuery: ""
    property int nextActionId: 1
    property int nextGeneration: 1
    property string statusMessage: ""
    property bool watchStarted: false
    property bool suppressNtp: false
    property bool suppressManual: false
    property bool actionBusy: false
    property bool timeDirty: false
    property bool coordsDirty: false

    property int draftYear: 1970
    property int draftMonth: 1
    property int draftDay: 1
    property string draftHour: "0"
    property string draftMinute: "0"
    property string draftLat: ""
    property string draftLon: ""
    property string draftAccuracy: "200"
    property var displayClock: ({ year: 1970, month: 1, day: 1, hour: 0, minute: 0, second: 0 })

    readonly property bool ntpEnabled: snapshot.ntp_enabled === true
    readonly property bool manualLocation: snapshot.manual_location === true
    readonly property bool polkitReady: snapshot.polkit_ready === true
    readonly property var filteredTimezones: RegionTimeState.filterTimezones(timezones, tzQuery)

    function applySnapshot(next) {
        if (!next)
            return;
        snapshot = RegionTimeState.clone(next);
        displayClock = RegionTimeState.clone(snapshot.clock || RegionTimeState.emptySnapshot().clock);
        if (snapshot.stale === true) {
            statusMessage = String(snapshot.error || "Region status could not be refreshed");
            return;
        }
        if (!actionBusy)
            statusMessage = String(snapshot.error || "");

        suppressNtp = true;
        ntpSwitch.checked = snapshot.ntp_enabled === true;
        suppressNtp = false;

        suppressManual = true;
        manualSwitch.checked = snapshot.manual_location === true;
        suppressManual = false;

        if (!timeDirty) {
            draftYear = Number(snapshot.clock.year || draftYear);
            draftMonth = Number(snapshot.clock.month || draftMonth);
            draftDay = Number(snapshot.clock.day || draftDay);
            draftHour = String(snapshot.clock.hour ?? draftHour);
            draftMinute = String(snapshot.clock.minute ?? draftMinute);
        }

        if (!coordsDirty) {
            const coords = RegionTimeState.locationCoords(snapshot);
            if (coords.latitude !== "")
                draftLat = coords.latitude;
            else if (snapshot.saved_lat)
                draftLat = String(snapshot.saved_lat);
            if (coords.longitude !== "")
                draftLon = coords.longitude;
            else if (snapshot.saved_lon)
                draftLon = String(snapshot.saved_lon);
            draftAccuracy = coords.accuracy || draftAccuracy;
        }
    }

    function requestSnapshot(startWatchAfter) {
        S.Backend.request("get_region_snapshot", {}, function(result) {
            regionPage.applySnapshot(result);
            if (startWatchAfter && !regionPage.watchStarted) {
                regionPage.watchStarted = true;
                S.Backend.request("start_region_watch", {}, function(watchSnapshot) {
                    regionPage.applySnapshot(watchSnapshot);
                }, function(error) {
                    regionPage.statusMessage = String(
                        (error && (error.message || error.error))
                        || "Region live updates could not start"
                    );
                });
            }
        }, function(error) {
            regionPage.statusMessage = String(
                (error && (error.message || error.error))
                || "Region status could not be refreshed"
            );
        });
    }

    function loadTimezones() {
        S.Backend.request("get_region_timezones", {}, function(result) {
            regionPage.timezones = (result && result.timezones) || [];
        }, function(error) {
            regionPage.statusMessage = String(
                (error && (error.message || error.error))
                || "Timezone list could not be loaded"
            );
        });
    }

    function sendAction(action, value, target) {
        const actionId = String(nextActionId++);
        const generation = nextGeneration++;
        actionBusy = true;
        statusMessage = "Working…";
        S.Backend.request("run_region_action", {
            action: action,
            target: target || action,
            value: value,
            action_id: actionId,
            generation: generation,
        }, function(result) {
            if (result && result.queued === true)
                return;
            actionBusy = false;
            statusMessage = String(
                (result && (result.message || result.error))
                || "Region action was rejected"
            );
        }, function(error) {
            actionBusy = false;
            statusMessage = String(
                (error && (error.message || error.error))
                || "Region action failed"
            );
        });
    }

    function applyManualTime() {
        const hour = Math.max(0, Math.min(23, parseInt(draftHour, 10) || 0));
        const minute = Math.max(0, Math.min(59, parseInt(draftMinute, 10) || 0));
        timeDirty = false;
        sendAction("set_time", {
            year: draftYear,
            month: draftMonth,
            day: draftDay,
            hour: hour,
            minute: minute,
        }, "set_time");
    }

    function applyLocation() {
        const lat = Number(draftLat);
        const lon = Number(draftLon);
        const acc = Number(draftAccuracy);
        if (isNaN(lat) || isNaN(lon)) {
            statusMessage = "Enter valid latitude and longitude";
            return;
        }
        coordsDirty = false;
        sendAction("apply_location", {
            latitude: lat,
            longitude: lon,
            accuracy: isNaN(acc) ? 200 : acc,
        }, "apply_location");
    }

    Component.onCompleted: {
        requestSnapshot(true);
        loadTimezones();
    }
    Component.onDestruction: S.Backend.request("stop_region_watch", {}, null)

    Connections {
        target: S.Backend
        function onRegionSnapshotEvent(next) {
            regionPage.applySnapshot(next);
        }
        function onRegionActionDoneEvent(actionId, target, generation, ok,
                                         staleTarget, message) {
            regionPage.actionBusy = false;
            regionPage.statusMessage = String(message || (ok ? "Done" : "Failed"));
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: regionPage.displayClock = RegionTimeState.tickClock(regionPage.displayClock)
    }

    Column {
        id: content
        width: Math.min(regionPage.width - 56, 760)
        x: (regionPage.width - width) / 2
        y: 24
        spacing: 14

        Item {
            width: content.width
            height: 46
            Column {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2
                Text {
                    text: regionPage.page.title || "Region & Time"
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 20
                        weight: Font.Bold
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
                Text {
                    text: regionPage.statusMessage
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 10
                        hintingPreference: Font.PreferVerticalHinting
                    }
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
                onClicked: regionPage.requestSnapshot(false)
            }
        }

        SectionCard {
            width: parent.width
            section: ({ title: "Date & Time" })

            Column {
                width: parent.width
                spacing: 0

                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰌾",
                        title: "Authentication",
                        description: regionPage.snapshot.polkit_message || "—",
                    })
                }
                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰇧",
                        title: "Offline place names",
                        description: regionPage.snapshot.offline_places_message || "—",
                    })
                }
                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰅐",
                        title: "Local Time",
                        description: RegionTimeState.formatClock(regionPage.displayClock),
                    })
                }
                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰁫",
                        title: "Current Timezone",
                        description: regionPage.snapshot.timezone_label || "—",
                    })
                }
                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰔛",
                        title: "Network Time (NTP)",
                        description: "Synchronize clock automatically",
                    })
                    CloudSwitch {
                        id: ntpSwitch
                        enabled: regionPage.polkitReady && !regionPage.actionBusy
                        onToggled: checked => {
                            if (regionPage.suppressNtp)
                                return;
                            ntpSwitch.checked = Qt.binding(function() {
                                return regionPage.ntpEnabled;
                            });
                            regionPage.sendAction("set_ntp", checked, "set_ntp");
                        }
                    }
                }
                RowBase {
                    showDivider: false
                    item: ({
                        icon: "󰦖",
                        title: "Sync Status",
                        description: regionPage.snapshot.ntp_status_label || "—",
                    })
                }
            }
        }

        SectionCard {
            width: parent.width
            section: ({ title: "Timezone" })

            Column {
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 48
                    CloudTextField {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                            topMargin: 8
                            bottomMargin: 8
                        }
                        placeholderText: "Search timezones…"
                        text: regionPage.tzQuery
                        onTextEdited: value => regionPage.tzQuery = value
                    }
                }

                Rectangle {
                    width: parent.width - 16
                    x: 8
                    height: 1
                    color: Theme.hairline
                }

                ListView {
                    id: tzList
                    width: parent.width
                    height: Math.min(280, Math.max(120, count * 52))
                    clip: true
                    model: regionPage.filteredTimezones
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: SelectableRow {
                        required property var modelData
                        required property int index
                        width: tzList.width
                        selected: modelData.id === regionPage.snapshot.timezone
                        title: modelData.id || ""
                        subtitle: modelData.offset || ""
                        leadingGlyph: selected ? "󰄬" : "󰁫"
                        showDivider: index < tzList.count - 1
                        busy: regionPage.actionBusy
                        onClicked: {
                            if (modelData.id && modelData.id !== regionPage.snapshot.timezone)
                                regionPage.sendAction("set_timezone", modelData.id, "set_timezone");
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: tzList.count === 0
                        text: regionPage.timezones.length === 0
                            ? "Loading timezones…"
                            : "No matching timezones"
                        color: Theme.textMuted
                        renderType: Text.NativeRendering
                        font {
                            family: "JetBrainsMono Nerd Font"
                            pixelSize: 11
                            hintingPreference: Font.PreferVerticalHinting
                        }
                    }
                }
            }
        }

        SectionCard {
            width: parent.width
            visible: !regionPage.ntpEnabled
            section: ({ title: "Manual Date & Time" })

            Column {
                width: parent.width
                spacing: 10
                leftPadding: 10
                rightPadding: 10
                topPadding: 10
                bottomPadding: 12

                Text {
                    width: parent.width - 20
                    text: "Disable NTP above to set the clock manually."
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 10
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }

                Row {
                    spacing: 16
                    width: parent.width - 20

                    Column {
                        spacing: 6
                        width: 220

                        Row {
                            spacing: 8
                            CloudButton {
                                text: "‹"
                                compact: true
                                subtle: true
                                onClicked: {
                                    regionPage.timeDirty = true;
                                    let m = regionPage.draftMonth - 1;
                                    let y = regionPage.draftYear;
                                    if (m < 1) { m = 12; y -= 1; }
                                    regionPage.draftMonth = m;
                                    regionPage.draftYear = y;
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 120
                                horizontalAlignment: Text.AlignHCenter
                                text: RegionTimeState.monthShort(regionPage.draftMonth)
                                      + " " + regionPage.draftYear
                                color: Theme.textPrimary
                                renderType: Text.NativeRendering
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 12
                                    weight: Font.Medium
                                    hintingPreference: Font.PreferVerticalHinting
                                }
                            }
                            CloudButton {
                                text: "›"
                                compact: true
                                subtle: true
                                onClicked: {
                                    regionPage.timeDirty = true;
                                    let m = regionPage.draftMonth + 1;
                                    let y = regionPage.draftYear;
                                    if (m > 12) { m = 1; y += 1; }
                                    regionPage.draftMonth = m;
                                    regionPage.draftYear = y;
                                }
                            }
                        }

                        DayOfWeekRow {
                            locale: Qt.locale()
                            width: parent.width
                            delegate: Text {
                                required property string shortName
                                text: shortName
                                color: Theme.textMuted
                                horizontalAlignment: Text.AlignHCenter
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 9
                                }
                            }
                        }

                        MonthGrid {
                            id: monthGrid
                            locale: Qt.locale()
                            month: regionPage.draftMonth - 1
                            year: regionPage.draftYear
                            width: parent.width
                            height: 160
                            onClicked: date => {
                                regionPage.timeDirty = true;
                                regionPage.draftYear = date.getFullYear();
                                regionPage.draftMonth = date.getMonth() + 1;
                                regionPage.draftDay = date.getDate();
                            }
                            delegate: Text {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                opacity: model.month === monthGrid.month ? 1 : 0.35
                                text: model.day
                                color: (
                                    model.day === regionPage.draftDay
                                    && model.month === monthGrid.month
                                    && model.year === monthGrid.year
                                ) ? Theme.on_primary : Theme.textPrimary
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 11
                                    weight: (
                                        model.day === regionPage.draftDay
                                        && model.month === monthGrid.month
                                    ) ? Font.Bold : Font.Normal
                                }
                                Rectangle {
                                    z: -1
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    radius: 8
                                    visible: model.day === regionPage.draftDay
                                             && model.month === monthGrid.month
                                             && model.year === monthGrid.year
                                    color: Theme.primary
                                }
                            }
                        }
                    }

                    Column {
                        spacing: 10
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                            spacing: 8
                            Text {
                                width: 60
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Hour"
                                color: Theme.textMuted
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 11
                                }
                            }
                            CloudTextField {
                                width: 72
                                compact: true
                                text: regionPage.draftHour
                                onTextEdited: value => {
                                    regionPage.timeDirty = true;
                                    regionPage.draftHour = value;
                                }
                            }
                        }
                        Row {
                            spacing: 8
                            Text {
                                width: 60
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Minute"
                                color: Theme.textMuted
                                font {
                                    family: "JetBrainsMono Nerd Font"
                                    pixelSize: 11
                                }
                            }
                            CloudTextField {
                                width: 72
                                compact: true
                                text: regionPage.draftMinute
                                onTextEdited: value => {
                                    regionPage.timeDirty = true;
                                    regionPage.draftMinute = value;
                                }
                            }
                        }
                        CloudButton {
                            text: "Apply Manual Time"
                            primary: true
                            enabled: regionPage.polkitReady && !regionPage.actionBusy
                            onClicked: regionPage.applyManualTime()
                        }
                    }
                }
            }
        }

        SectionCard {
            width: parent.width
            section: ({ title: "Location" })

            Column {
                width: parent.width
                spacing: 0

                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰍎",
                        title: "GeoClue Service",
                        description: regionPage.snapshot.geo_service_label || "—",
                    })
                }
                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰆡",
                        title: "Current Location",
                        description: regionPage.snapshot.location_label || "—",
                    })
                }
                RowBase {
                    showDivider: true
                    item: ({
                        icon: "󰆧",
                        title: "Manual Static Location",
                        description: "Override automatic IP/WiFi geolocation",
                    })
                    CloudSwitch {
                        id: manualSwitch
                        enabled: regionPage.polkitReady && !regionPage.actionBusy
                        onToggled: checked => {
                            if (regionPage.suppressManual)
                                return;
                            manualSwitch.checked = Qt.binding(function() {
                                return regionPage.manualLocation;
                            });
                            regionPage.sendAction("set_manual_mode", checked, "set_manual_mode");
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: regionPage.manualLocation
                    spacing: 8
                    topPadding: 8
                    bottomPadding: 12
                    leftPadding: 12
                    rightPadding: 12

                    Row {
                        spacing: 8
                        width: parent.width - 24
                        Text {
                            width: 110
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Latitude"
                            color: Theme.textMuted
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                        }
                        CloudTextField {
                            width: parent.width - 118
                            compact: true
                            text: regionPage.draftLat
                            onTextEdited: value => {
                                regionPage.coordsDirty = true;
                                regionPage.draftLat = value;
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        width: parent.width - 24
                        Text {
                            width: 110
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Longitude"
                            color: Theme.textMuted
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                        }
                        CloudTextField {
                            width: parent.width - 118
                            compact: true
                            text: regionPage.draftLon
                            onTextEdited: value => {
                                regionPage.coordsDirty = true;
                                regionPage.draftLon = value;
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        width: parent.width - 24
                        Text {
                            width: 110
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Accuracy (m)"
                            color: Theme.textMuted
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                        }
                        CloudTextField {
                            width: parent.width - 118
                            compact: true
                            text: regionPage.draftAccuracy
                            onTextEdited: value => {
                                regionPage.coordsDirty = true;
                                regionPage.draftAccuracy = value;
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        CloudButton {
                            text: "Apply Location"
                            primary: true
                            enabled: regionPage.polkitReady && !regionPage.actionBusy
                            onClicked: regionPage.applyLocation()
                        }
                        CloudButton {
                            text: "Use Automatic"
                            subtle: true
                            enabled: regionPage.polkitReady && !regionPage.actionBusy
                            onClicked: regionPage.sendAction("clear_location", null, "clear_location")
                        }
                    }
                }
            }
        }
    }
}
