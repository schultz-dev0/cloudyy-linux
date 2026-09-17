#!/usr/bin/env bash
# phone-webcam.sh — use the Android phone's camera as a v4l2 webcam via scrcpy.
#
# One-time setup (a v4l2loopback device must exist before this will work —
# separate from the droidcam-audio v4l2loopback_dc module, this uses the
# plain v4l2loopback module on its own device number):
#
#   sudo pacman -S v4l2loopback-dkms   # already installed if droidcam works
#
#   echo 'options v4l2loopback video_nr=10 card_label="Z Fold 7" exclusive_caps=1' \
#     | sudo tee /etc/modprobe.d/v4l2loopback-webcam.conf
#   echo 'v4l2loopback' | sudo tee /etc/modules-load.d/v4l2loopback-webcam.conf
#
#   # load it now, without rebooting:
#   sudo modprobe v4l2loopback video_nr=10 card_label="Z Fold 7" exclusive_caps=1
#
# Then: enable USB debugging on the phone, plug it in, run this script, and
# pick "Z Fold 7" (/dev/video10) as the camera source in OBS/Discord/etc.
#
# Usage: ~/cloudyy_scripts/phone-webcam.sh [extra scrcpy args...]

VIDEO_DEV="/dev/video10"

if [[ ! -e "$VIDEO_DEV" ]]; then
  echo "phone-webcam: $VIDEO_DEV doesn't exist — v4l2loopback isn't loaded." >&2
  echo "  sudo modprobe v4l2loopback video_nr=10 card_label=\"Z Fold 7\" exclusive_caps=1" >&2
  echo "  (see the header of this script for persistent one-time setup)" >&2
  exit 1
fi

exec scrcpy \
  --video-source=camera \
  --camera-facing=back \
  --camera-size=1920x1080 \
  --v4l2-sink="$VIDEO_DEV" \
  --no-video-playback \
  --stay-awake \
  "$@"
