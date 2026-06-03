// ElevatedEffect.qml — disabled permanently (card drop shadows removed from the shell).
// Call sites are kept as no-ops so layouts stay unchanged; do not re-enable RectangularShadow here.
import QtQuick

Item {
    required property var target
    visible: false
}
