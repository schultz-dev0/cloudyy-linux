pragma Singleton
import QtQuick
import Quickshell

// Shell animation / compositing profile.
// Enabled via Cloud Center → Shell → Lightweight animations (sets CLOUDYY_LIGHTWEIGHT at launch).
QtObject {
    readonly property bool lightweight: {
        const v = (Quickshell.env("CLOUDYY_LIGHTWEIGHT")
            || Quickshell.env("CLOUDYY_REDUCED_MOTION")
            || Quickshell.env("QS_REDUCED_MOTION")
            || "").toLowerCase();
        return v === "1" || v === "true" || v === "yes" || v === "on";
    }

    readonly property bool animationsEnabled: !lightweight

    function ms(normal) {
        return lightweight ? 0 : normal;
    }

    function msHalf(normal) {
        return lightweight ? Math.max(0, Math.round(normal * 0.45)) : normal;
    }

    function geometryMs(normal) {
        return lightweight ? 0 : normal;
    }

    function opacityMs(normal) {
        return lightweight ? 60 : normal;
    }

    readonly property int dockFrameMs: lightweight ? 32 : 16
}
