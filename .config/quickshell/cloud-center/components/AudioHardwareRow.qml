import QtQuick
import ".."
import "AudioState.js" as AudioState

Item {
    id: root

    required property var card
    required property var pending
    property bool busy: false
    signal actionRequested(string action, string target, var value, string fieldKey, int generation)

    implicitHeight: 92
    height: implicitHeight

    readonly property var profiles: profileOptions()

    function profileOptions() {
        const names = root.card && root.card.profiles ? root.card.profiles : [];
        const descriptions = root.card && root.card.profile_descriptions
            ? root.card.profile_descriptions : ({});
        return names.map(name => ({
            name: String(name),
            description: String(descriptions[name] || name),
        }));
    }

    function activeProfile() {
        const key = "card:" + String(root.card.name) + ":active_profile";
        return String(AudioState.displayValue(root.pending, key, root.card.active_profile));
    }

    function profileIndex(name) {
        for (let index = 0; index < root.profiles.length; index++) {
            if (root.profiles[index].name === String(name)) return index;
        }
        return -1;
    }

    Text {
        anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14; top: parent.top; topMargin: 12 }
        text: String(root.card.name || "Audio card")
        elide: Text.ElideRight
        color: Theme.textPrimary
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
               hintingPreference: Font.PreferVerticalHinting }
    }

    Text {
        anchors { left: parent.left; leftMargin: 14; right: profileSelect.left; rightMargin: 12
                  bottom: parent.bottom; bottomMargin: 14 }
        text: String(root.card.driver || "Audio hardware")
        elide: Text.ElideRight
        color: Theme.textMuted
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
               hintingPreference: Font.PreferVerticalHinting }
    }

    CloudSelect {
        id: profileSelect
        anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 10 }
        width: 280
        compact: true
        options: root.profiles
        textRole: "description"
        currentIndex: root.profileIndex(root.activeProfile())
        enabled: !root.busy && root.profiles.length > 0
        onActivated: index => {
            if (index < 0 || index >= root.profiles.length) return;
            root.actionRequested("set_card_profile", root.card.name, root.profiles[index].name,
                "card:" + root.card.name + ":active_profile", 0);
        }
    }
}
