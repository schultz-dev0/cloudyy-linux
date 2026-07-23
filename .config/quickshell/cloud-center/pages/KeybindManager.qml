import QtQuick
import QtQuick.Controls
import "../components"
import "../services" as S
import ".."

// Keybind Manager: categorized list of hl.bind() entries (lib/ccd/keybinds.py
// wraps the parsing/writing logic reused from the GTK app's
// lib/keybind_manager_lua.py). v1 simplification vs. the GTK page: the
// dispatcher is typed as raw Lua text instead of guided category/dispatcher
// dropdowns — still fully functional, just less hand-held.
Flickable {
    id: kbPage
    required property var page
    contentHeight: content.implicitHeight + 48
    clip: true

    property var keybinds: []
    property var categories: []
    property string query: ""

    property bool dialogOpen: false
    property string editingKeys: ""       // "" => Add mode
    property string editingDispatcher: ""
    property string editingOpts: ""
    property bool editingOwned: true
    property string formKeys: ""
    property string formDispatcher: ""
    property string formDesc: ""
    property string formError: ""

    function refresh() {
        S.Backend.request("list_keybinds", {}, function (result) {
            if (!result) return;
            kbPage.keybinds = result.keybinds ?? [];
            kbPage.categories = result.categories ?? [];
        });
    }
    Component.onCompleted: refresh()

    function descFor(kb) {
        const m = kb.opts.match(/desc\s*=\s*"([^"]*)"/);
        return m ? m[1] : "";
    }

    function openAdd() {
        editingKeys = ""; editingDispatcher = ""; editingOpts = ""; editingOwned = true;
        formKeys = ""; formDispatcher = ""; formDesc = ""; formError = "";
        keysInput.text = ""; dispatcherInput.text = ""; descInput.text = "";
        dialogOpen = true;
    }
    function openEdit(kb) {
        editingKeys = kb.keys; editingDispatcher = kb.dispatcher; editingOpts = kb.opts;
        editingOwned = kb.owned;
        formKeys = kb.keys; formDispatcher = kb.dispatcher; formDesc = descFor(kb); formError = "";
        keysInput.text = kb.keys; dispatcherInput.text = kb.dispatcher; descInput.text = formDesc;
        dialogOpen = true;
    }
    function save() {
        if (formKeys.trim() === "" || formDispatcher.trim() === "") {
            formError = "Key combo and dispatcher are required.";
            return;
        }
        const params = {
            keys: formKeys,
            dispatcher: formDispatcher,
            opts: formDesc.trim() !== "" ? '{ desc = "' + formDesc.replace(/"/g, "") + '" }' : "",
        };
        if (editingKeys !== "") {
            params.old_keys = editingKeys;
            params.old_dispatcher = editingDispatcher;
            params.old_opts = editingOpts;
            params.was_owned = editingOwned;
        }
        S.Backend.request("save_keybind", params, function (result) {
            if (result && result.ok) { dialogOpen = false; refresh(); }
            else formError = (result && result.message) || "Save failed.";
        });
    }
    function del(kb) {
        S.Backend.request("delete_keybind",
            { keys: kb.keys, dispatcher: kb.dispatcher, opts: kb.opts },
            function (result) { if (result && result.ok) refresh(); });
    }

    Column {
        id: content
        width: Math.min(kbPage.width - 56, 720)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16
        topPadding: 24

        Text { text: kbPage.page.title; color: Theme.textPrimary
               font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; bold: true } }

        Item {
            width: content.width
            height: 34

            Rectangle {
                anchors { left: parent.left; right: addBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                height: 30; radius: 8
                color: Theme.glass(Theme.surface_container_high, 0.7)
                TextInput {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                    onTextChanged: kbPage.query = text
                    Text { visible: !parent.text; text: "⌕ Search keybinds…"
                           anchors.verticalCenter: parent.verticalCenter
                           color: Theme.textMuted; font: parent.font }
                }
            }
            Rectangle {
                id: addBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: addText.implicitWidth + 20; height: 30; radius: 8
                color: addHover.hovered ? Theme.glass(Theme.primary, 0.2) : Theme.glass(Theme.primary, 0.12)
                Text { id: addText; anchors.centerIn: parent; text: "\u{f0415} Add"
                       color: Theme.accent; font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                HoverHandler { id: addHover }
                TapHandler { onTapped: kbPage.openAdd() }
            }
        }

        Repeater {
            model: kbPage.categories
            delegate: Column {
                id: catBlock
                required property var modelData
                width: content.width
                readonly property var rows: kbPage.keybinds.filter(kb => {
                    if (kb.category !== modelData.id) return false;
                    if (kbPage.query === "") return true;
                    const q = kbPage.query.toLowerCase();
                    return kb.keys.toLowerCase().includes(q) || kb.dispatcher.toLowerCase().includes(q);
                })
                visible: rows.length > 0
                spacing: 5

                Text { text: catBlock.modelData.label.toUpperCase(); color: Theme.textMuted
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; letterSpacing: 1 }
                       leftPadding: 4 }
                Rectangle {
                    width: catBlock.width
                    height: rowsCol.implicitHeight
                    radius: 12
                    color: Theme.surface_container_lowest
                    border { width: 1; color: Theme.glass(Theme.outline_variant, 0.55) }
                    Column {
                        id: rowsCol
                        width: parent.width
                        Repeater {
                            model: catBlock.rows
                            delegate: RowBase {
                                required property var modelData
                                width: rowsCol.width
                                item: ({
                                    icon: "\u{f030c}",
                                    title: modelData.keys,
                                    description: kbPage.descFor(modelData) || modelData.dispatcher,
                                })

                                Text {
                                    visible: !modelData.owned
                                    text: "locked"
                                    color: Theme.textMuted
                                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 }
                                }
                                Rectangle {
                                    width: 24; height: 24; radius: 6
                                    color: editHover.hovered ? Theme.glass(Theme.primary, 0.14) : "transparent"
                                    Text { anchors.centerIn: parent; text: "\u{f03eb}"; color: Theme.accent
                                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 } }
                                    HoverHandler { id: editHover }
                                    TapHandler { onTapped: kbPage.openEdit(modelData) }
                                }
                                Rectangle {
                                    visible: modelData.owned
                                    width: 24; height: 24; radius: 6
                                    color: delHover.hovered ? Theme.glass(Theme.error, 0.14) : "transparent"
                                    Text { anchors.centerIn: parent; text: "\u{f0a79}"; color: Theme.error
                                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                                    HoverHandler { id: delHover }
                                    TapHandler { onTapped: kbPage.del(modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: editDialog
        modal: true
        dim: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: 400
        padding: 20
        visible: kbPage.dialogOpen
        onClosed: kbPage.dialogOpen = false
        enter: null; exit: null   // motion budget: no popup fade, matches RowSelect's combo popup

        background: Rectangle { radius: 14; color: Theme.surface_container
                                 border { width: 1; color: Theme.outline_variant } }

        contentItem: Column {
            spacing: 12

            Text { text: kbPage.editingKeys === "" ? "Add Keybind" : "Edit Keybind"
                   color: Theme.textPrimary
                   font { family: "JetBrainsMono Nerd Font"; pixelSize: 15; bold: true } }

            Column {
                spacing: 4; width: 360
                Text { text: "Key combo"; color: Theme.textMuted
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                Rectangle {
                    width: parent.width; height: 30; radius: 8
                    color: Theme.glass(Theme.surface_container_high, 0.7)
                    TextInput {
                        id: keysInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                        onTextChanged: kbPage.formKeys = text
                        Text { visible: !parent.text; text: "e.g. SUPER + Q"
                               anchors.verticalCenter: parent.verticalCenter
                               color: Theme.textMuted; font: parent.font }
                    }
                }
            }
            Column {
                spacing: 4; width: 360
                Text { text: "Dispatcher (raw Lua)"; color: Theme.textMuted
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                Rectangle {
                    width: parent.width; height: 30; radius: 8
                    color: Theme.glass(Theme.surface_container_high, 0.7)
                    TextInput {
                        id: dispatcherInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                        onTextChanged: kbPage.formDispatcher = text
                        Text { visible: !parent.text; text: 'e.g. hl.dsp.exec_cmd("firefox")'
                               anchors.verticalCenter: parent.verticalCenter
                               color: Theme.textMuted; font: parent.font }
                    }
                }
            }
            Column {
                spacing: 4; width: 360
                Text { text: "Description (optional)"; color: Theme.textMuted
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                Rectangle {
                    width: parent.width; height: 30; radius: 8
                    color: Theme.glass(Theme.surface_container_high, 0.7)
                    TextInput {
                        id: descInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                        onTextChanged: kbPage.formDesc = text
                    }
                }
            }
            Text {
                visible: !kbPage.editingOwned && kbPage.editingKeys !== ""
                width: 360; wrapMode: Text.WordWrap
                text: "This is a locked base keybind — saving creates your own override; the original stays untouched."
                color: Theme.textMuted
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
            }
            Text {
                visible: kbPage.formError !== ""
                width: 360; wrapMode: Text.WordWrap
                text: kbPage.formError
                color: Theme.error
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
            }

            Row {
                spacing: 8
                Rectangle {
                    width: cancelText.implicitWidth + 20; height: 28; radius: 8
                    color: Theme.glass(Theme.outline_variant, 0.3)
                    Text { id: cancelText; anchors.centerIn: parent; text: "Cancel"
                           color: Theme.textMuted; font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                    TapHandler { onTapped: kbPage.dialogOpen = false }
                }
                Rectangle {
                    width: saveText.implicitWidth + 20; height: 28; radius: 8
                    color: Theme.glass(Theme.primary, 0.18)
                    Text { id: saveText; anchors.centerIn: parent; text: "Save"
                           color: Theme.accent; font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                    TapHandler { onTapped: kbPage.save() }
                }
            }
        }
    }
}
