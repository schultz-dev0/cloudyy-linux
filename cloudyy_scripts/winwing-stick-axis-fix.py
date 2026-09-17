#!/usr/bin/env python3
# Mirrors the WINWING Orion Joystick Base 2 onto a virtual uinput device with a
# 7th (dummy) axis. Wine's winebus.sys misclassifies any device with exactly
# 6 axes + a hat + >=10 buttons as a "gamepad" instead of a "joystick", which
# breaks axis exposure (notably Y) in DCS. The real device has exactly 6 axes;
# this passthrough breaks that match so Wine treats it as a normal joystick.
import evdev
from evdev import ecodes, UInput, AbsInfo

REAL_NAME = "Winwing WINWING Orion Joystick Base 2 + JGRIP-F16"
VIRT_NAME = "WINWING Orion Joystick Base 2 (axis-fix)"

def find_real_device():
    for path in evdev.list_devices():
        dev = evdev.InputDevice(path)
        if dev.name == REAL_NAME:
            return dev
    raise SystemExit(f"device '{REAL_NAME}' not found")

def main():
    real = find_real_device()
    caps = real.capabilities(absinfo=True)

    abs_caps = list(caps.get(ecodes.EV_ABS, []))
    # dummy 7th axis so analog axis_count != 6 (breaks wine's gamepad heuristic)
    abs_caps.append((ecodes.ABS_RUDDER, AbsInfo(value=2048, min=0, max=4095, fuzz=0, flat=0, resolution=0)))

    virt_caps = {
        ecodes.EV_KEY: caps.get(ecodes.EV_KEY, []),
        ecodes.EV_ABS: abs_caps,
    }

    virt = UInput(virt_caps, name=VIRT_NAME, vendor=0x4098, product=0xbea9, version=0x0111)
    real.grab()  # stop the real device's events from reaching anything else (e.g. wine)

    print(f"mirroring '{REAL_NAME}' -> '{VIRT_NAME}' ({virt.device.path})", flush=True)
    try:
        for event in real.read_loop():
            virt.write_event(event)
    except (KeyboardInterrupt, OSError):
        pass
    finally:
        real.ungrab()
        virt.close()

if __name__ == "__main__":
    main()
