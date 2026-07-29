pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import "IdleState.js" as IdleState

QtObject {
    id: root

    property string state: "active"

    function show() {
        state = IdleState.show(state);
    }

    function dismiss() {
        state = IdleState.dismiss(state);
    }

}
