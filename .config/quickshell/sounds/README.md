# Quickshell UI sounds

| File | When |
|------|------|
| `NotifSOUND.wav` | Every new notification (island) |
| `SCRNCAP_SOUND.wav` | Screenshot preview, recording start, recording stop |

Screenshot preview: island hides after **7s** (5s notification default + 2s); temp PNG stays **5 minutes**.

Screencap sound (`SCRNCAP_SOUND.wav`): screenshot preview, **recording stop only** (no start cue).

Tune in `DynamicIslandService.qml`: `screenshotPreviewExtraMs`, `screenshotTmpRetentionSec`, `screencapRecordStopDelayMs`.

Override directory: `CLOUDYY_SOUNDS_DIR`

Playback: `paplay`, `ffplay`, or `mpv` (any one installed).
