import QtQuick
import QtQuick.Controls
import "../components"
import "../components/RuleEditorPolicy.js" as RuleEditorPolicy
import "../services" as S
import ".."

Flickable {
    id: rulesPage
    required property var page
    clip: true
    contentHeight: content.implicitHeight + 56

    property int activeTab: 0
    property var readonlyData: ({ window_rules: [], layer_rules: [], autostart: [], env_vars: [] })
    property var schema: ({ matcher_modes: [], window_matchers: [], window_effects: [], layer_effects: [] })
    property bool sessionOpen: false
    property bool loading: true
    property bool showLocked: false
    property string statusMessage: ""
    property bool conflict: false

    property string editorKind: ""
    property int editingIndex: -1
    property string formName: ""
    property var formMatchers: []
    property string formNamespace: ""
    property string formNamespaceMode: "exact"
    property var formEffects: ({})
    property string formCommand: ""
    property bool formExecOnce: true
    property string formEnvName: ""
    property string formEnvValue: ""
    property bool showAdvanced: false
    property bool showLuaPreview: false
    property string customKey: ""
    property string customValue: ""
    property string previewText: ""
    property string formError: ""

    readonly property var tabDefinitions: [
        { label: "Window Rules", collection: "window_rules", kind: "window",
          intro: "Control where applications open and how their windows behave." },
        { label: "Layer Rules", collection: "layer_rules", kind: "layer",
          intro: "Style panels, launchers, notifications, and other desktop layers." },
        { label: "Autostart", collection: "autostart", kind: "autostart",
          intro: "Start applications and commands with your Hyprland session." },
        { label: "Environment", collection: "env_vars", kind: "env",
          intro: "Set environment variables for applications started next session." },
    ]
    readonly property var currentTab: tabDefinitions[activeTab]
    readonly property var currentItems: drafts.valuesFor(currentTab.collection)
    readonly property var currentLocked: readonlyData[currentTab.collection] ?? []

    RulesDraftModel { id: drafts }

    function clone(value) { return JSON.parse(JSON.stringify(value)); }

    function openSession() {
        loading = true;
        S.Backend.request("open_rules_startup_session", {}, function(result) {
            loading = false;
            if (!result || !result.ok) {
                statusMessage = result ? result.message : "Could not open Rules & Startup";
                return;
            }
            drafts.load(result.data ?? {});
            readonlyData = clone(result.readonly ?? {});
            schema = clone(result.schema ?? {});
            sessionOpen = true;
            conflict = false;
            statusMessage = "";
        });
    }

    function reloadFromDisk() {
        if (sessionOpen)
            S.Backend.request("close_rules_startup_session", {}, function() { openSession(); });
        else
            openSession();
    }

    function describe(item, kind) {
        if (kind === "window") {
            const matches = (item.matchers ?? []).map(m => {
                const field = matcherField(m.property);
                const label = (field.label ?? m.property).toLowerCase();
                if (field.type === "bool") return label + " is " + m.value;
                if (field.type === "number") return label + " is " + m.value;
                return label + " " + (m.mode ?? "exact").replace(/_/g, " ") + " “" + m.value + "”";
            });
            return matches.length ? matches.join(" · ") : "Matches every window";
        }
        if (kind === "layer")
            return "namespace " + (item.namespace_mode ?? "exact").replace(/_/g, " ") + " “" + item.namespace + "”";
        if (kind === "autostart")
            return item.exec_once ? "Runs once at the start of the next session" : "Runs on startup and every reload";
        return "Value · " + item.value;
    }

    function itemTitle(item, kind, index) {
        if (kind === "window" || kind === "layer") return item.name || "Unnamed rule";
        if (kind === "autostart") return item.command || "Empty command";
        return item.name || "Unnamed variable";
    }

    function showEditor(index, existing) {
        editorKind = currentTab.kind;
        editingIndex = index;
        formName = existing ? (existing.name ?? "") : "";
        formMatchers = existing ? clone(existing.matchers ?? []) : [];
        formNamespace = existing ? (existing.namespace ?? "") : "";
        formNamespaceMode = existing ? (existing.namespace_mode ?? "exact") : "exact";
        formEffects = existing ? clone(existing.effects ?? {}) : ({});
        formCommand = existing ? (existing.command ?? "") : "";
        formExecOnce = existing ? existing.exec_once !== false : true;
        formEnvName = existing ? (existing.name ?? "") : "";
        formEnvValue = existing ? (existing.value ?? "") : "";
        showAdvanced = false;
        showLuaPreview = false;
        customKey = ""; customValue = ""; formError = "";
        editorSheet.open();
        updatePreview();
    }

    function openNewEditor() {
        showEditor(-1, null);
    }

    function openEditor(index) {
        if (index < 0 || index >= currentItems.length)
            return;
        showEditor(index, clone(currentItems[index]));
    }

    function editorRule() {
        if (editorKind === "window")
            return { name: formName, matchers: clone(formMatchers), effects: clone(formEffects) };
        if (editorKind === "layer")
            return { name: formName, namespace: formNamespace,
                     namespace_mode: formNamespaceMode, effects: clone(formEffects) };
        if (editorKind === "autostart")
            return { command: formCommand, exec_once: formExecOnce };
        return { name: formEnvName, value: formEnvValue };
    }

    function saveEditor() {
        if ((editorKind === "window" || editorKind === "layer") && formName.trim() === "") {
            formError = "Give this rule a descriptive name."; return;
        }
        if (editorKind === "window" && formMatchers.length === 0) {
            formError = "Add at least one window matcher."; return;
        }
        if (editorKind === "layer" && formNamespace.trim() === "") {
            formError = "Enter a layer namespace."; return;
        }
        if (editorKind === "autostart" && formCommand.trim() === "") {
            formError = "Enter a command to start."; return;
        }
        if (editorKind === "env" && formEnvName.trim() === "") {
            formError = "Enter a variable name."; return;
        }
        const item = editorRule();
        if (editingIndex < 0) drafts.append(currentTab.collection, item);
        else drafts.replace(currentTab.collection, editingIndex, item);
        editorSheet.close();
        statusMessage = "Draft changed — Apply to write it to your configuration";
        conflict = false;
    }

    function setMatcher(index, key, value) {
        const next = clone(formMatchers);
        next[index][key] = value;
        formMatchers = next;
        previewDelay.restart();
    }

    function setMatcherValue(index, value) {
        RuleEditorPolicy.setMatcherValueInPlace(formMatchers, index, value);
        previewDelay.restart();
    }

    function applyPickedWindow(window) {
        const picked = RuleEditorPolicy.applyPickedWindow(
            formName, formMatchers, window, editingIndex < 0);
        formName = picked.name;
        formMatchers = picked.matchers;
        previewDelay.restart();
    }

    function addMatcher(propertyName, value) {
        const next = clone(formMatchers);
        next.push({ property: propertyName || "class", mode: "exact", value: value || "" });
        formMatchers = next;
        previewDelay.restart();
    }

    function removeMatcher(index) {
        const next = clone(formMatchers); next.splice(index, 1); formMatchers = next;
        previewDelay.restart();
    }

    function matcherField(propertyName) {
        return (schema.window_matchers ?? []).find(field => field.key === propertyName)
            ?? { type: "pattern" };
    }

    function effectEnabled(key) { return formEffects[key] !== undefined; }
    function effectValue(key) { return effectEnabled(key) ? String(formEffects[key]) : ""; }
    function setEffect(key, value) {
        const next = clone(formEffects); next[key] = String(value); formEffects = next;
        previewDelay.restart();
    }
    function toggleEffect(field, enabled) {
        const next = clone(formEffects);
        if (!enabled) delete next[field.key];
        else if (field.type === "bool") next[field.key] = "on";
        else if (field.choices && field.choices.length) next[field.key] = field.choices[0];
        else next[field.key] = "";
        formEffects = next;
        previewDelay.restart();
    }
    function visibleEffects() {
        const all = editorKind === "layer" ? (schema.layer_effects ?? []) : (schema.window_effects ?? []);
        return showAdvanced ? all : all.filter(field => field.group === "Common behavior");
    }
    function addCustomEffect() {
        const key = customKey.trim();
        if (key === "") return;
        setEffect(key, customValue);
        customKey = ""; customValue = "";
    }

    function updatePreview() {
        if (editorKind !== "window" && editorKind !== "layer") return;
        S.Backend.request("preview_rule", { kind: editorKind, rule: editorRule() }, function(result) {
            previewText = result ? (result.lua ?? "") : "";
        });
    }
    Timer { id: previewDelay; interval: 120; onTriggered: rulesPage.updatePreview() }

    function pickerWindows() {
        S.Backend.request("list_rule_windows", {}, function(result) {
            pickerMode = "window"; pickerItems = result ? (result.windows ?? []) : []; picker.open();
        });
    }
    function pickerLayers() {
        S.Backend.request("list_rule_layers", {}, function(result) {
            pickerMode = "layer"; pickerItems = result ? (result.layers ?? []) : []; picker.open();
        });
    }
    function pickerApps() {
        S.Backend.request("list_autostart_apps", {}, function(result) {
            pickerMode = "app"; pickerItems = result ? (result.apps ?? []) : []; picker.open();
        });
    }
    property string pickerMode: ""
    property var pickerItems: []

    function applyDrafts() {
        if (!drafts.dirty) return;
        if (drafts.dirtySurfaces.includes("windowrules")
                && drafts.autostart.concat(readonlyData.autostart ?? [])
                    .some(entry => entry.exec_once === false)) {
            reloadWarning.open();
            return;
        }
        performApply();
    }

    function performApply() {
        const data = drafts.currentData();
        data.dirty_surfaces = clone(drafts.dirtySurfaces);
        S.Backend.request("save_rules_startup", data, function(result) {
            if (result && result.ok) {
                drafts.load(result.data ?? data);
                readonlyData = clone(result.readonly ?? readonlyData);
                statusMessage = result.message;
                conflict = false;
            } else {
                statusMessage = result ? result.message : "Could not apply changes";
                conflict = result && result.reason === "external_change";
            }
        });
    }

    Component.onCompleted: openSession()
    Component.onDestruction: {
        if (sessionOpen) S.Backend.request("close_rules_startup_session", {}, null);
    }

    Column {
        id: content
        width: Math.min(rulesPage.width - 56, 820)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14
        topPadding: 24

        Row {
            width: parent.width
            Text {
                width: parent.width - headerActions.width
                anchors.verticalCenter: parent.verticalCenter
                text: rulesPage.page.title
                color: Theme.text
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; weight: Font.Bold
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Row {
                id: headerActions; spacing: 8
                Rectangle {
                    width: discardLabel.implicitWidth + 20; height: 30; radius: 2
                    opacity: drafts.dirty ? 1 : 0.4
                    color: discardHover.hovered && drafts.dirty ? Theme.surfaceOverlay : Theme.surfaceRaised
                    Text { id: discardLabel; anchors.centerIn: parent; text: "Discard"; color: Theme.textMuted
                           renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; hintingPreference: Font.PreferVerticalHinting } }
                    HoverHandler { id: discardHover }
                    TapHandler { enabled: drafts.dirty; onTapped: { drafts.discard(); statusMessage = "Draft changes discarded"; } }
                }
                Rectangle {
                    width: applyLabel.implicitWidth + 22; height: 30; radius: 2
                    opacity: drafts.dirty ? 1 : 0.4
                    color: applyHover.hovered && drafts.dirty ? Theme.accent : Theme.accentMuted
                    Text { id: applyLabel; anchors.centerIn: parent; text: "Apply"; color: Theme.accentText
                           renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; weight: Font.Medium
                                  hintingPreference: Font.PreferVerticalHinting } }
                    HoverHandler { id: applyHover }
                    TapHandler { enabled: drafts.dirty; onTapped: rulesPage.applyDrafts() }
                }
            }
        }

        Rectangle {
            width: parent.width; height: 38; radius: 0
            color: Theme.background
            border { width: 1; color: Theme.hairline }
            Row {
                anchors.fill: parent; anchors.margins: 4; spacing: 4
                Repeater {
                    model: rulesPage.tabDefinitions
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: (content.width - 8 - 12) / 4; height: 30; radius: 2
                        color: rulesPage.activeTab === index ? Theme.accentMuted
                            : tabHover.hovered ? Theme.surfaceOverlay : "transparent"
                        Text { anchors.centerIn: parent; text: modelData.label
                               color: rulesPage.activeTab === index ? Theme.accentText : Theme.textMuted
                               renderType: Text.NativeRendering
                               font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; weight: Font.Medium
                                      hintingPreference: Font.PreferVerticalHinting } }
                        HoverHandler { id: tabHover }
                        TapHandler { onTapped: { rulesPage.activeTab = index; rulesPage.showLocked = false; } }
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: currentTab.intro
            color: Theme.textMuted
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                   hintingPreference: Font.PreferVerticalHinting }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Cloud Center entries" })
            Repeater {
                model: rulesPage.currentItems
                delegate: RulesEntryRow {
                    required property var modelData
                    required property int index
                    width: parent.width
                    title: rulesPage.itemTitle(modelData, rulesPage.currentTab.kind, index)
                    description: rulesPage.describe(modelData, rulesPage.currentTab.kind)
                    canMoveUp: index > 0
                    canMoveDown: index < rulesPage.currentItems.length - 1
                    onEditRequested: rulesPage.openEditor(index)
                    onRemoveRequested: drafts.remove(rulesPage.currentTab.collection, index)
                    onMoveUpRequested: drafts.move(rulesPage.currentTab.collection, index, index - 1)
                    onMoveDownRequested: drafts.move(rulesPage.currentTab.collection, index, index + 1)
                    onReorderByRequested: offset => drafts.move(rulesPage.currentTab.collection, index,
                        Math.max(0, Math.min(rulesPage.currentItems.length - 1, index + offset)))
                }
            }
            CloudButton {
                width: parent.width; height: 42
                subtle: true
                glyph: "+"
                text: rulesPage.currentItems.length ? "Add another" : "Add your first entry"
                onClicked: rulesPage.openNewEditor()
            }
        }

        Column {
            width: parent.width; spacing: 6
            Rectangle {
                width: parent.width; height: 44; radius: 2
                color: lockedHover.hovered ? Theme.surfaceRaised : Theme.background
                border { width: 1; color: Theme.hairline }
                Row {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           width: parent.width - lockedGlyph.width
                           text: "Existing configuration  ·  " + rulesPage.currentLocked.length
                           color: Theme.text; renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                                  hintingPreference: Font.PreferVerticalHinting } }
                    Text { id: lockedGlyph; anchors.verticalCenter: parent.verticalCenter
                           text: rulesPage.showLocked ? "⌃" : "⌄"; color: Theme.textMuted }
                }
                HoverHandler { id: lockedHover }
                TapHandler { onTapped: rulesPage.showLocked = !rulesPage.showLocked }
            }
            Rectangle {
                visible: rulesPage.showLocked
                width: parent.width; height: lockedColumn.implicitHeight; radius: 0
                color: Theme.background
                border { width: 1; color: Theme.hairline }
                Column {
                    id: lockedColumn; width: parent.width
                    Repeater {
                        model: rulesPage.currentLocked
                        delegate: RulesEntryRow {
                            required property var modelData
                            required property int index
                            width: parent.width
                            title: rulesPage.itemTitle(modelData, rulesPage.currentTab.kind, index)
                            description: rulesPage.describe(modelData, rulesPage.currentTab.kind)
                            editable: false
                            origin: modelData.origin ?? ""
                        }
                    }
                    Text {
                        visible: rulesPage.currentLocked.length === 0
                        width: parent.width; height: 42; verticalAlignment: Text.AlignVCenter
                        leftPadding: 14; text: "No distro or handwritten entries found"
                        color: Theme.textMuted; renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                }
            }
        }

        Row {
            width: parent.width; spacing: 10
            Text {
                width: parent.width - (conflictReload.visible ? conflictReload.width + 10 : 0)
                text: rulesPage.loading ? "Loading configuration…"
                    : rulesPage.statusMessage || (drafts.dirty ? "Draft changes have not been applied" : "Configuration is up to date")
                color: rulesPage.conflict ? Theme.error : Theme.textMuted
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Rectangle {
                id: conflictReload; visible: rulesPage.conflict
                width: reloadLabel.implicitWidth + 18; height: 28; radius: 2
                color: Theme.error
                Text { id: reloadLabel; anchors.centerIn: parent; text: "Reload from disk"; color: Theme.accentText
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                TapHandler { onTapped: rulesPage.reloadFromDisk() }
            }
        }
    }

    CloudDialog {
        id: editorSheet
        width: Math.min(rulesPage.width - 42, 780)
        height: Math.min(rulesPage.height - 36, 720)
        heading: (rulesPage.editingIndex < 0 ? "Add " : "Edit ")
            + rulesPage.tabDefinitions[rulesPage.activeTab].label.replace(/s$/, "")
        supportingText: "Changes stay in draft until you apply them from the Rules & Startup page"
        primaryText: "Save draft"
        secondaryText: "Cancel"
        onPrimaryClicked: rulesPage.saveEditor()

        Item {
            anchors.fill: parent

            Flickable {
                id: editorScroll
                anchors.fill: parent
                clip: true
                contentHeight: editorForm.implicitHeight + 36
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Theme.glass(Theme.accent, 0.45) }
                    background: Item {}
                }

                Column {
                    id: editorForm
                    x: 20; width: editorScroll.width - 40
                    topPadding: 18; bottomPadding: 18
                    spacing: 15

                    Text {
                        visible: rulesPage.editorKind === "window" || rulesPage.editorKind === "layer"
                        text: "IDENTITY"
                        color: Theme.textMuted
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                               letterSpacing: 1.2; hintingPreference: Font.PreferVerticalHinting }
                    }
                    CloudTextField {
                        visible: rulesPage.editorKind === "window" || rulesPage.editorKind === "layer"
                        width: parent.width
                        placeholderText: "Descriptive rule name"
                        text: rulesPage.formName
                        leadingGlyph: "\u{f040a}"
                        onTextEdited: value => { rulesPage.formName = value; previewDelay.restart(); }
                    }

                    Column {
                        visible: rulesPage.editorKind === "window"
                        width: parent.width; spacing: 8
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - matchButtons.width
                                anchors.verticalCenter: parent.verticalCenter
                                text: "MATCH WINDOWS WHEN"
                                color: Theme.textMuted
                                renderType: Text.NativeRendering
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                                       letterSpacing: 1.2; hintingPreference: Font.PreferVerticalHinting }
                            }
                            Row {
                                id: matchButtons; spacing: 6
                                CloudButton { text: "Pick window"; glyph: "\u{f05b5}"; compact: true; subtle: true
                                              onClicked: rulesPage.pickerWindows() }
                                CloudButton { text: "Add condition"; glyph: "+"; compact: true; subtle: true
                                              onClicked: rulesPage.addMatcher("class", "") }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: Math.max(48, matcherColumn.implicitHeight)
                            radius: 0
                            color: Theme.background
                            border { width: 1; color: Theme.hairline }
                            Column {
                                id: matcherColumn; width: parent.width
                                Repeater {
                                    model: rulesPage.formMatchers
                                    delegate: Rectangle {
                                        id: matcherRow
                                        required property var modelData
                                        required property int index
                                        readonly property var matcherInfo: rulesPage.matcherField(modelData.property)
                                        width: parent.width; height: 48; color: "transparent"
                                        Row {
                                            anchors { fill: parent; margins: 8 }
                                            spacing: 7
                                            CloudSelect {
                                                width: 154; height: 32; compact: true
                                                options: rulesPage.schema.window_matchers ?? []
                                                textRole: "label"
                                                currentIndex: options.findIndex(value => value.key === matcherRow.modelData.property)
                                                onActivated: selected => {
                                                    rulesPage.setMatcher(matcherRow.index, "property", options[selected].key);
                                                    if (options[selected].type === "bool")
                                                        rulesPage.setMatcher(matcherRow.index, "value", "on");
                                                }
                                            }
                                            CloudSelect {
                                                visible: matcherRow.matcherInfo.type === "pattern"
                                                width: visible ? 145 : 0; height: 32; compact: true
                                                options: rulesPage.schema.matcher_modes ?? []
                                                textRole: "label"
                                                currentIndex: options.findIndex(value => value.id === matcherRow.modelData.mode)
                                                onActivated: selected => rulesPage.setMatcher(matcherRow.index, "mode", options[selected].id)
                                            }
                                            CloudSelect {
                                                visible: matcherRow.matcherInfo.type === "bool"
                                                width: visible ? 145 : 0; height: 32; compact: true
                                                options: ["On", "Off"]
                                                currentIndex: matcherRow.modelData.value === "off" ? 1 : 0
                                                onActivated: selected => rulesPage.setMatcher(matcherRow.index, "value", selected === 0 ? "on" : "off")
                                            }
                                            CloudTextField {
                                                visible: matcherRow.matcherInfo.type !== "bool"
                                                width: parent.width - 350; height: 32; compact: true
                                                text: matcherRow.modelData.value ?? ""
                                                placeholderText: "Match value"
                                                onTextEdited: value => rulesPage.setMatcherValue(matcherRow.index, value)
                                            }
                                            CloudButton {
                                                width: 32; height: 32; compact: true; subtle: true; danger: true; glyph: "×"
                                                onClicked: rulesPage.removeMatcher(matcherRow.index)
                                            }
                                        }
                                        Rectangle {
                                            visible: matcherRow.index < rulesPage.formMatchers.length - 1
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 10; rightMargin: 10 }
                                            height: 1; color: Theme.hairline
                                        }
                                    }
                                }
                                Item {
                                    visible: rulesPage.formMatchers.length === 0
                                    width: parent.width; height: 48
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Add a condition or pick a running window"
                                        color: Theme.textMuted; opacity: 0.74
                                        renderType: Text.NativeRendering
                                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                                               hintingPreference: Font.PreferVerticalHinting }
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        visible: rulesPage.editorKind === "layer"
                        width: parent.width; spacing: 8
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - pickLayer.width
                                anchors.verticalCenter: parent.verticalCenter
                                text: "MATCH LAYER NAMESPACE"
                                color: Theme.textMuted
                                renderType: Text.NativeRendering
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                                       letterSpacing: 1.2; hintingPreference: Font.PreferVerticalHinting }
                            }
                            CloudButton { id: pickLayer; text: "Pick active layer"; glyph: "\u{f05b5}"; compact: true; subtle: true
                                          onClicked: rulesPage.pickerLayers() }
                        }
                        Rectangle {
                            width: parent.width; height: 50; radius: 0
                            color: Theme.background
                            border { width: 1; color: Theme.hairline }
                            Row {
                                anchors { fill: parent; margins: 8 }
                                spacing: 7
                                CloudSelect {
                                    width: 180; height: 34; compact: true
                                    options: rulesPage.schema.matcher_modes ?? []; textRole: "label"
                                    currentIndex: options.findIndex(value => value.id === rulesPage.formNamespaceMode)
                                    onActivated: selected => { rulesPage.formNamespaceMode = options[selected].id; previewDelay.restart(); }
                                }
                                CloudTextField {
                                    width: parent.width - 187; height: 34; compact: true
                                    text: rulesPage.formNamespace; placeholderText: "Namespace"
                                    onTextEdited: value => { rulesPage.formNamespace = value; previewDelay.restart(); }
                                }
                            }
                        }
                    }

                    Column {
                        visible: rulesPage.editorKind === "window" || rulesPage.editorKind === "layer"
                        width: parent.width; spacing: 8
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - advancedButton.width
                                anchors.verticalCenter: parent.verticalCenter
                                text: rulesPage.showAdvanced ? "ALL BEHAVIOR" : "COMMON BEHAVIOR"
                                color: Theme.textMuted
                                renderType: Text.NativeRendering
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                                       letterSpacing: 1.2; hintingPreference: Font.PreferVerticalHinting }
                            }
                            CloudButton {
                                id: advancedButton; compact: true; subtle: true
                                text: rulesPage.showAdvanced ? "Show common" : "Advanced"
                                glyph: rulesPage.showAdvanced ? "\u{f0143}" : "\u{f0140}"
                                onClicked: rulesPage.showAdvanced = !rulesPage.showAdvanced
                            }
                        }
                        Rectangle {
                            width: parent.width; height: effectsColumn.implicitHeight; radius: 0
                            color: Theme.background
                            border { width: 1; color: Theme.hairline }
                            Column {
                                id: effectsColumn; width: parent.width
                                Repeater {
                                    model: rulesPage.visibleEffects()
                                    delegate: RuleEffectRow {
                                        required property var modelData
                                        required property int index
                                        width: parent.width
                                        field: modelData
                                        active: rulesPage.effectEnabled(modelData.key)
                                        value: rulesPage.effectValue(modelData.key)
                                        last: index === rulesPage.visibleEffects().length - 1
                                        onToggled: active => rulesPage.toggleEffect(modelData, active)
                                        onValueEdited: value => rulesPage.setEffect(modelData.key, value)
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: rulesPage.showAdvanced
                            width: parent.width; height: 50; radius: 0
                            color: Theme.background
                            border { width: 1; color: Theme.hairline }
                            Row {
                                anchors { fill: parent; margins: 8 }
                                spacing: 7
                                CloudTextField { width: 200; height: 34; compact: true; placeholderText: "Custom property"
                                                 text: rulesPage.customKey; onTextEdited: value => rulesPage.customKey = value }
                                CloudTextField { width: parent.width - 260; height: 34; compact: true; placeholderText: "Value"
                                                 text: rulesPage.customValue; onTextEdited: value => rulesPage.customValue = value }
                                CloudButton { width: 46; height: 34; compact: true; subtle: true; text: "Add"
                                              onClicked: rulesPage.addCustomEffect() }
                            }
                        }
                    }

                    Column {
                        visible: rulesPage.editorKind === "autostart"
                        width: parent.width; spacing: 9
                        Row {
                            width: parent.width
                            Text { width: parent.width - chooseApp.width; anchors.verticalCenter: parent.verticalCenter
                                   text: "COMMAND"; color: Theme.textMuted; renderType: Text.NativeRendering
                                   font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                                          letterSpacing: 1.2; hintingPreference: Font.PreferVerticalHinting } }
                            CloudButton { id: chooseApp; text: "Choose application"; glyph: "\u{f0415}"; compact: true; subtle: true
                                          onClicked: rulesPage.pickerApps() }
                        }
                        CloudTextField { width: parent.width; placeholderText: "Command and arguments"; leadingGlyph: "\u{f0489}"
                                         text: rulesPage.formCommand; onTextEdited: value => rulesPage.formCommand = value }
                        Rectangle {
                            width: parent.width; height: 58; radius: 0
                            color: Theme.background
                            border { width: 1; color: Theme.hairline }
                            Row {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                spacing: 10
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; radius: 2
                                            color: Theme.glass(Theme.accent, 0.13)
                                    Text { anchors.centerIn: parent; text: "\u{f033e}"; color: Theme.accent
                                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                                }
                                Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - onceSwitch.width - 66; spacing: 2
                                    Text { text: "Run once when the session starts"; color: Theme.text; renderType: Text.NativeRendering
                                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                                                  hintingPreference: Font.PreferVerticalHinting } }
                                    Text { text: rulesPage.formExecOnce ? "Runs once next session" : "Runs again on every Hyprland reload"
                                           color: Theme.textMuted; renderType: Text.NativeRendering
                                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 9
                                                  hintingPreference: Font.PreferVerticalHinting } }
                                }
                                CloudSwitch { id: onceSwitch; anchors.verticalCenter: parent.verticalCenter
                                              checked: rulesPage.formExecOnce
                                              onToggled: checked => rulesPage.formExecOnce = checked }
                            }
                        }
                    }

                    Column {
                        visible: rulesPage.editorKind === "env"
                        width: parent.width; spacing: 9
                        Text { text: "VARIABLE"; color: Theme.textMuted; renderType: Text.NativeRendering
                               font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                                      letterSpacing: 1.2; hintingPreference: Font.PreferVerticalHinting } }
                        CloudTextField { width: parent.width; placeholderText: "Name, for example EDITOR"; leadingGlyph: "\u{f04b9}"
                                         text: rulesPage.formEnvName; onTextEdited: value => rulesPage.formEnvName = value }
                        CloudTextField { width: parent.width; placeholderText: "Value"; leadingGlyph: "\u{f04cb}"
                                         text: rulesPage.formEnvValue; onTextEdited: value => rulesPage.formEnvValue = value }
                        Text { width: parent.width; wrapMode: Text.WordWrap
                               text: "Environment changes apply to applications launched in your next Hyprland session."
                               color: Theme.textMuted; renderType: Text.NativeRendering
                               font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                                      hintingPreference: Font.PreferVerticalHinting } }
                    }

                    Column {
                        visible: rulesPage.editorKind === "window" || rulesPage.editorKind === "layer"
                        width: parent.width; spacing: 7
                        Rectangle {
                            width: parent.width; height: 44; radius: 2
                            color: luaHover.hovered ? Theme.glass(Theme.accent, 0.07)
                                : Theme.background
                            border { width: 1; color: Theme.hairline }
                            Row {
                                anchors { fill: parent; leftMargin: 13; rightMargin: 13 }
                                Text { width: parent.width - luaChevron.width; anchors.verticalCenter: parent.verticalCenter
                                       text: "GENERATED LUA  ·  READ ONLY"; color: Theme.textMuted; renderType: Text.NativeRendering
                                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                                              letterSpacing: 1; hintingPreference: Font.PreferVerticalHinting } }
                                Text { id: luaChevron; anchors.verticalCenter: parent.verticalCenter
                                       text: rulesPage.showLuaPreview ? "\u{f0143}" : "\u{f0140}"; color: Theme.accent
                                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                            }
                            HoverHandler { id: luaHover }
                            TapHandler { onTapped: rulesPage.showLuaPreview = !rulesPage.showLuaPreview }
                        }
                        Rectangle {
                            visible: rulesPage.showLuaPreview
                            width: parent.width; height: Math.max(96, preview.implicitHeight + 24); radius: 0
                            color: Theme.background
                            border { width: 1; color: Theme.hairline }
                            TextEdit { id: preview; anchors { fill: parent; margins: 12 }
                                       text: rulesPage.previewText
                                       readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: Theme.textMuted
                                       renderType: TextEdit.NativeRendering
                                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                                              hintingPreference: Font.PreferVerticalHinting } }
                        }
                    }
                    Text {
                        visible: rulesPage.formError !== ""; width: parent.width; wrapMode: Text.WordWrap
                        text: rulesPage.formError; color: Theme.error; renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; hintingPreference: Font.PreferVerticalHinting }
                    }
                }
            }
        }
    }

    CloudDialog {
        id: picker
        width: Math.min(rulesPage.width - 86, 620); height: Math.min(rulesPage.height - 92, 540)
        heading: rulesPage.pickerMode === "window" ? "Pick a running window"
            : rulesPage.pickerMode === "layer" ? "Pick an active layer" : "Choose an application"
        supportingText: rulesPage.pickerMode === "window" ? "Use its current class as an exact matcher"
            : rulesPage.pickerMode === "layer" ? "Use its namespace as an exact matcher"
            : "Insert the application command into this draft"
        showFooter: false

        Item {
            anchors.fill: parent
            ListView {
                anchors { fill: parent; margins: 10 }
                clip: true; spacing: 3
                model: rulesPage.pickerItems
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width; height: 54; radius: 2
                    color: pickHover.hovered ? Theme.glass(Theme.accent, 0.09) : "transparent"
                    Column { anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                        Text { width: parent.width; elide: Text.ElideRight; color: Theme.text
                               text: rulesPage.pickerMode === "window" ? (modelData.class || "Unknown application")
                                   : rulesPage.pickerMode === "layer" ? modelData.namespace : modelData.name
                               renderType: Text.NativeRendering
                               font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                                      hintingPreference: Font.PreferVerticalHinting } }
                        Text { width: parent.width; elide: Text.ElideRight; color: Theme.textMuted
                               text: rulesPage.pickerMode === "window" ? modelData.title
                                   : rulesPage.pickerMode === "layer" ? modelData.monitor : modelData.command
                               renderType: Text.NativeRendering
                               font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                                      hintingPreference: Font.PreferVerticalHinting } }
                    }
                    HoverHandler { id: pickHover }
                    TapHandler { onTapped: {
                        if (rulesPage.pickerMode === "window") rulesPage.applyPickedWindow(modelData);
                        else if (rulesPage.pickerMode === "layer") {
                            rulesPage.formNamespace = modelData.namespace || "";
                            rulesPage.formNamespaceMode = "exact"; previewDelay.restart();
                        } else rulesPage.formCommand = modelData.command || "";
                        picker.close();
                    } }
                }
            }
        }
    }

    CloudDialog {
        id: reloadWarning
        width: 480; height: 250
        heading: "Reload may run startup commands"
        supportingText: "Review this before applying the rule draft"
        primaryText: "Apply and reload"
        secondaryText: "Cancel"
        onPrimaryClicked: { reloadWarning.close(); rulesPage.performApply(); }

        Item {
            anchors.fill: parent
            Row {
                anchors { fill: parent; margins: 20 }
                spacing: 14
                Rectangle {
                    width: 38; height: 38; radius: 2
                    color: Theme.glass(Theme.info, 0.14)
                    Text { anchors.centerIn: parent; text: "\u{f0026}"; color: Theme.info
                           renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 16
                                  hintingPreference: Font.PreferVerticalHinting } }
                }
                Text {
                    width: parent.width - 52
                    text: "Applying window or layer rules reloads Hyprland. One or more commands are configured to run on every reload and may run now."
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }
        }
    }
}
