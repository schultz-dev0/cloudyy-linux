pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

// Picks the MPRIS player the bar media pill should reflect.
QtObject {
    id: root

    property int revision: 0
    property var activePlayer: null

    function pick() {
        const players = Mpris.players.values;
        let playing = null;
        let paused = null;
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (p.playbackState === MprisPlaybackState.Playing)
                playing = p;
            else if (!paused && p.playbackState === MprisPlaybackState.Paused)
                paused = p;
        }
        return playing ?? paused ?? (players.length > 0 ? players[0] : null);
    }

    function refresh() {
        root.activePlayer = root.pick();
        root.revision++;
    }
}
