pragma ComponentBehavior: Bound

import QtQuick
import "../../.."
import "../../systemmonitor" as QuickSystemMonitor

BaseTile {
    id: root

    readonly property var svc: QuickSystemMonitor.SystemMonitorService

    icon: "󰘚"
    label: "System"
    statusText: "CPU " + svc.cpuPercent + "% · RAM " + svc.ramPercent + "%"
    active: svc.open

    onClicked: svc.toggleOpen()
}
