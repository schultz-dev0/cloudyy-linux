import QtQuick
import "../.."

QtObject {
    property bool darkmode: Theme.background.hslLightness < 0.5

    readonly property color m3primary:              Theme.primary
    readonly property color m3onPrimary:            Theme.on_primary

    readonly property color m3primaryContainer:     Theme.primary_container
    readonly property color m3onPrimaryContainer:   Theme.on_primary_container

    readonly property color m3secondary:            Theme.secondary
    readonly property color m3onSecondary:          Theme.on_secondary

    readonly property color m3secondaryContainer:   Theme.secondary_container
    readonly property color m3onSecondaryContainer: Theme.on_secondary_container

    readonly property color m3background:           Theme.background
    readonly property color m3onBackground:         Theme.on_background

    readonly property color m3surface:              Theme.surface

    readonly property color m3surfaceContainerLow:      Theme.surface_container_low
    readonly property color m3surfaceContainer:         Theme.surface_container
    readonly property color m3surfaceContainerHigh:     Theme.surface_container_high
    readonly property color m3surfaceContainerHighest:  Theme.surface_container_highest

    readonly property color m3onSurface:            Theme.on_surface

    readonly property color m3surfaceVariant:       Theme.surface_variant
    readonly property color m3onSurfaceVariant:     Theme.on_surface_variant

    readonly property color m3inverseSurface:       Theme.inverse_surface
    readonly property color m3inverseOnSurface:     Theme.inverse_on_surface

    readonly property color m3outline:              Theme.outline
    readonly property color m3outlineVariant:       Theme.outline_variant

    readonly property color m3shadow:               Theme.shadow
}
