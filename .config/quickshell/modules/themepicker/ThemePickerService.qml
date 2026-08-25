pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../spotlight"
import "../commandcenter/applibrary"
import "../commandcenter/powermenu"
import "../commandcenter/wallpapers"

Singleton {
    id: svc

    readonly property string themeCtl: "cloudyy-theme"

    property bool visible: false
    property bool keyboardGrab: false
    property int selectedIndex: -1
    // Keyboard/visual focus within the active theme's wallpaper strip — the
    // only strip shown (see ThemeRow). Meaningless while selectedIndex isn't
    // on the active theme's row; reset on open() so it never carries over a
    // stale value from a previous session.
    property int selectedWallpaperIndex: 0
    property string currentSlug: ""
    property var themes: []
    property bool loading: false

    signal requestFocus()

    Component {
        id: procProto
        Process {}
    }

    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        const p = procProto.createObject(svc, { command: cmd });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function open() {
        closeOtherPanels();
        showPanel();
        selectedIndex = -1;
        selectedWallpaperIndex = 0;
        loadThemes();
        requestFocus();
    }

    function closeOtherPanels() {
        if (SpotlightService.visible)
            SpotlightService.close();
        if (AppLibraryService.visible)
            AppLibraryService.close();
        if (PowerMenuService.visible)
            PowerMenuService.close();
        if (WallpaperPickerService.visible)
            WallpaperPickerService.close();
    }

    function showPanel() {
        hideTimer.stop();
        visible = true;
        keyboardGrab = true;
    }

    function finishClose() {
        visible = false;
        selectedIndex = -1;
    }

    function close() {
        keyboardGrab = false;
        if (!visible) {
            finishClose();
            return;
        }
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 80
        repeat: false
        onTriggered: svc.finishClose()
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    function loadThemes() {
        loading = themes.length === 0;
        listProc.running = false;
        listProc.running = true;
    }

    function applyTheme(slug) {
        if (!slug)
            return;
        launch(["bash", themeCtl, "use", slug]);
        currentSlug = slug;
        close();
    }

    function activateIndex(idx) {
        if (idx < 0 || idx >= themes.length)
            return;
        applyTheme(themes[idx].slug);
    }

    function applyWallpaper(path) {
        if (!path)
            return;
        launch(["bash", themeCtl, "set-image", path]);
        close();
    }

    // Direct click target from a strip thumbnail — takes both indices
    // explicitly rather than trusting selectedIndex/selectedWallpaperIndex
    // already point here, syncing them for a consistent highlight either way.
    function applyWallpaperAt(themeIndex, wallpaperIndex) {
        if (themeIndex < 0 || themeIndex >= themes.length)
            return;
        const wallpapers = themes[themeIndex].wallpapers || [];
        if (wallpaperIndex < 0 || wallpaperIndex >= wallpapers.length)
            return;
        selectedIndex = themeIndex;
        selectedWallpaperIndex = wallpaperIndex;
        applyWallpaper(wallpapers[wallpaperIndex]);
    }

    // Enter/click on the active theme's row picks whichever wallpaper is
    // focused in its strip; on any other row it switches to that theme.
    function activateSelection() {
        if (selectedIndex < 0 || selectedIndex >= themes.length)
            return;
        const entry = themes[selectedIndex];
        if (entry.slug === currentSlug) {
            const wallpapers = entry.wallpapers || [];
            applyWallpaper(wallpapers[selectedWallpaperIndex]);
        } else {
            applyTheme(entry.slug);
        }
    }

    // Left/Right move the wallpaper-strip focus; only the active theme's row
    // shows one, so this only does anything while that row is selected.
    function moveWallpaperFocus(delta) {
        if (selectedIndex < 0 || selectedIndex >= themes.length)
            return;
        const entry = themes[selectedIndex];
        if (entry.slug !== currentSlug)
            return;
        const count = (entry.wallpapers || []).length;
        if (count === 0)
            return;
        selectedWallpaperIndex = Math.max(0, Math.min(count - 1, selectedWallpaperIndex + delta));
    }

    Process {
        id: listProc
        running: false
        command: ["bash", svc.themeCtl, "list", "--json"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                svc.loading = false;
                const text = listOut.text.trim();
                if (text.length === 0)
                    return;
                try {
                    const payload = JSON.parse(text);
                    svc.currentSlug = payload.current || "";
                    svc.themes = Array.isArray(payload.themes) ? payload.themes : [];
                    if (svc.themes.length > 0)
                        svc.selectedIndex = Math.max(0, svc.themes.findIndex(t => t.slug === svc.currentSlug));
                } catch (e) {
                    console.warn("themepicker: bad catalog json", e);
                }
            }
        }
    }
}
