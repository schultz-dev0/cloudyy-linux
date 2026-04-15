#!/usr/bin/env python3
# ~/cloudyy_scripts/nvidia-powerd.py

import subprocess
import time
import os

# --- Config ---
POLL_INTERVAL = 4
HIGH_THRESHOLD = 30
LOW_THRESHOLD = 10
HIGH_POWER = 300
LOW_POWER = 80
HYSTERESIS_TIME = 20
VRAM_THRESHOLD = 1800  # Mib - jumpd to 11 ish when a model loads

# Processes that force HIGH power immediately
# Add game executables here too if you want explicit entries
HIGH_POWER_PROCS = [
    "steam",
    "steamwebhelper",
    "reaper",  # Steam game launcher wrapper
    "gameoverlayui",
    "dxvk",
    "wine",
    "wine64",
    "wineserver",
    "proton",
    "pressure-vessel",  # Steam Runtime container
    "lutris",
    "heroic",
    "mangohud",  # strong signal a game is running
    "gamescope",
    "vkBasalt",
]


def get_gpu_util():
    result = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=utilization.gpu,memory.used",
            "--format=csv,noheader,nounits",
        ],
        capture_output=True,
        text=True,
    )
    parts = result.stdout.strip().split(",")
    util = int(parts[0].strip())
    vram_used = int(parts[1].strip())  # MiB
    return util, vram_used


def get_running_procs():
    result = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True)
    return set(result.stdout.lower().split())


def check_steam_game_running():
    """
    Steam games run as children of the 'reaper' process.
    If reaper is alive, a game is actively launched.
    """
    result = subprocess.run(["pgrep", "-x", "reaper"], capture_output=True, text=True)
    return result.returncode == 0


def should_force_high(procs, vram_used):
    # Any known high-power process running
    for proc in HIGH_POWER_PROCS:
        if proc in procs:
            return True, proc

    # Steam game via reaper subprocess
    if check_steam_game_running():
        return True, "steam-game(reaper)"

    # Ollama loaded a model (VRAM spike even if not actively inferring)
    if vram_used > VRAM_THRESHOLD:  # MiB — tune to above your desktop baseline
        return True, f"vram-pressure({vram_used}MiB)"

    return False, None


def set_power_limit(watts):
    subprocess.run(["nvidia-smi", "-pl", str(watts)], capture_output=True)


def log(msg):
    print(f"[nvidia-powerd] {msg}", flush=True)


def main():
    current_limit = HIGH_POWER
    set_power_limit(current_limit)
    low_since = None
    cycle = 0

    log("Started. Monitoring GPU...")

    while True:
        util, vram_used = get_gpu_util()
        procs = get_running_procs()
        forced, reason = should_force_high(procs, vram_used)

        if cycle % 5 == 0:
            log(
                f"poll | util: {util}% | vram: {vram_used}MiB | forced: {forced} ({reason}) | limit: {current_limit}W"
            )
        if forced:
            low_since = None
            if current_limit != HIGH_POWER:
                log(f"→ HIGH ({HIGH_POWER}W) | reason: {reason}")
                set_power_limit(HIGH_POWER)
                current_limit = HIGH_POWER

        elif util >= HIGH_THRESHOLD:
            low_since = None
            if current_limit != HIGH_POWER:
                log(f"→ HIGH ({HIGH_POWER}W) | util spike: {util}%")
                set_power_limit(HIGH_POWER)
                current_limit = HIGH_POWER

        elif util <= LOW_THRESHOLD and not forced:
            if low_since is None:
                low_since = time.time()
            elif time.time() - low_since >= HYSTERESIS_TIME:
                if current_limit != LOW_POWER:
                    log(f"→ LOW ({LOW_POWER}W) | util: {util}%, vram: {vram_used}MiB")
                    set_power_limit(LOW_POWER)
                    current_limit = LOW_POWER
        else:
            # Utilization in the middle band — reset hysteresis
            low_since = None

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
