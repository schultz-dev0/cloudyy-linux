# Recording cue sounds (optional)

Quickshell plays a sound when recording **starts** and **stops** (no desktop notification).

## macOS system sounds

On a Mac, Apple’s UI sounds live under:

`/System/Library/Sounds/`

Good pairs for screen recording:

| Role  | macOS file   | Character        |
|-------|--------------|------------------|
| Start | `Tink.aiff`  | Short, subtle    |
| Stop  | `Pop.aiff`     | Soft “done” pop  |
| Alt   | `Ping.aiff`  | Slightly brighter |

Copy (or scp) into this folder:

```text
record-start.aiff   ← e.g. Tink.aiff
record-stop.aiff    ← e.g. Pop.aiff
```

AIFF works as-is if `ffplay` or `mpv` is installed (`ffmpeg` package on Arch).

Convert to WAV if you prefer `paplay` only:

```bash
ffmpeg -i record-start.aiff record-start.wav
ffmpeg -i record-stop.aiff record-stop.wav
```

## Overrides

```bash
export CLOUDYY_SOUNDS_DIR="$HOME/.config/cloudyy/sounds"
export CLOUDYY_RECORD_START_SOUND="/path/to/start.wav"
export CLOUDYY_RECORD_STOP_SOUND="/path/to/stop.wav"
```

If no matching file exists, playback is skipped silently.

## Dependencies

Any one of: `ffmpeg` (ffplay), `mpv`, `pipewire-pulse` (paplay), `libcanberra`.
