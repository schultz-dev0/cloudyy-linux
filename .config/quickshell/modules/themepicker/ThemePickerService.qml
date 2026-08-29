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
    // Keyboard/visual focus within the centered theme's wallpaper carousel —
    // only shown when that theme is the active one (see ThemePicker's
    // showWallpaperDeck). Reset on open() so it never carries over stale.
    property int selectedWallpaperIndex: 0
    property string currentSlug: ""
    property var themes: []
    property bool loading: false
    // Set before triggering listProc; onStreamFinished reads it to decide
    // whether this load should snap selection back to the active theme
    // (opening) or leave the user's current navigation alone (background
    // refresh while browsing).
    property bool _resetSelectionOnLoad: true

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
        // selectedIndex is deliberately left as-is (not reset to -1): it
        // already points at the right theme from last time, and resetting
        // it here meant every card rendered as an off-center "side" card
        // for the one tick before loadThemes' async reply arrived and
        // snapped it back — visible as the deck jumping/sliding on open.
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
        _resetSelectionOnLoad = true;
        listProc.running = false;
        listProc.running = true;
    }

    // Picks up wallpapers/theme.json edits made while the picker is open —
    // there's no directory watcher for themes/, so this polls instead.
    // ponytail: polling, not inotify; themes/ is small and list --json is
    // cheap, so a plain Timer is the simplest thing that actually works.
    function refreshThemes() {
        if (!visible)
            return;
        _resetSelectionOnLoad = false;
        listProc.running = false;
        listProc.running = true;
    }

    Timer {
        interval: 2000
        repeat: true
        running: svc.visible
        onTriggered: svc.refreshThemes()
    }

    // wallpaperPath is optional — "use" alone already lands on a theme's
    // wallpaper 1, so it's only passed when the user browsed to a different
    // one before switching (see activateSelection), chaining a second
    // command so it applies after the theme's own colors are live.
    function applyTheme(slug, wallpaperPath) {
        if (!slug)
            return;
        if (wallpaperPath) {
            launch(["bash", "-c",
                'bash "$1" use "$2" && bash "$1" set-image "$3"',
                "--", themeCtl, slug, wallpaperPath]);
        } else {
            launch(["bash", themeCtl, "use", slug]);
        }
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
    // focused in its strip; on any other row it switches to that theme,
    // carrying over the focused wallpaper too if the user browsed away
    // from that theme's default (index 0) before hitting enter.
    function activateSelection() {
        if (selectedIndex < 0 || selectedIndex >= themes.length)
            return;
        const entry = themes[selectedIndex];
        const wallpapers = entry.wallpapers || [];
        if (entry.slug === currentSlug) {
            applyWallpaper(wallpapers[selectedWallpaperIndex]);
        } else {
            const wallpaperPath = selectedWallpaperIndex > 0 ? wallpapers[selectedWallpaperIndex] : undefined;
            applyTheme(entry.slug, wallpaperPath);
        }
    }

    // Left/Right on the main carousel — wraps, unlike the old list's clamp,
    // since cycling past either end of a deck should feel continuous.
    function moveThemeFocus(delta) {
        if (themes.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + themes.length) % themes.length;
        selectedWallpaperIndex = 0;
    }

    // Up/Down move the centered theme's wallpaper-strip focus — browsing
    // works for any centered theme, not just the active one (see
    // ThemePicker.showWallpaperDeck); activateSelection is what actually
    // gates applying a wallpaper to the active theme only.
    function moveWallpaperFocus(delta) {
        if (selectedIndex < 0 || selectedIndex >= themes.length)
            return;
        const entry = themes[selectedIndex];
        const count = (entry.wallpapers || []).length;
        if (count === 0)
            return;
        selectedWallpaperIndex = (selectedWallpaperIndex + delta + count) % count;
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
                    const nextThemes = Array.isArray(payload.themes) ? payload.themes : [];
                    // Every poll parses a fresh array even when nothing on
                    // disk changed. Assigning it unconditionally replaced
                    // svc.themes' reference every 2s, which the carousel's
                    // items binding treats as "the model changed" — tearing
                    // down and rebuilding (redecoding) every card in both
                    // decks on a timer, whether or not anything moved.
                    if (JSON.stringify(nextThemes) !== JSON.stringify(svc.themes))
                        svc.themes = nextThemes;
                    if (svc.themes.length === 0) {
                        svc.selectedIndex = -1;
                    } else if (svc._resetSelectionOnLoad) {
                        svc.selectedIndex = Math.max(0, svc.themes.findIndex(t => t.slug === svc.currentSlug));
                    } else {
                        // Background refresh: keep browsing where the user left
                        // off, just clamp in case the list shrank.
                        svc.selectedIndex = Math.max(0, Math.min(svc.themes.length - 1, svc.selectedIndex));
                    }
                    const wallpaperCount = (svc.themes[svc.selectedIndex]?.wallpapers || []).length;
                    svc.selectedWallpaperIndex = wallpaperCount === 0
                        ? 0 : Math.min(svc.selectedWallpaperIndex, wallpaperCount - 1);
                } catch (e) {
                    console.warn("themepicker: bad catalog json", e);
                }
            }
        }
    }
}
