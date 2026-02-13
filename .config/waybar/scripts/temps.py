#!/usr/bin/env python3

import json
import subprocess
import shutil

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
ICON_CPU = "" 
ICON_GPU = ""

def get_cpu_temp(data):
    """
    Universally find the best CPU temperature.
    Priority:
    1. Intel "Package id 0" (Most accurate for Intel)
    2. AMD "Tctl" or "Tdie" (Most accurate for Ryzen)
    3. "CPU" label (Generic motherboard sensors)
    4. "temp1" in a "k10temp" or "coretemp" block (Fallback)
    """
    # 1. Scan for explicit Package/Die temps
    for chip_name, chip_data in data.items():
        # Clean the chip name for easier matching
        chip_lower = chip_name.lower()
        
        # INTEL: Look for "Package id 0"
        if "coretemp" in chip_lower:
            if "Package id 0" in chip_data:
                return float(chip_data["Package id 0"].get("temp1_input", 0))
        
        # AMD: Look for Tctl or Tdie
        if "k10temp" in chip_lower or "zenpower" in chip_lower:
            for label in ["Tctl", "Tdie"]:
                if label in chip_data:
                     # Some drivers return Tctl as a dict, some as raw value
                     val = chip_data[label]
                     if isinstance(val, dict):
                         return float(val.get("temp1_input", 0))
    
    # 2. Fallback: Generic "CPU" label in any sensor (common in nct6687 like yours)
    for chip_name, chip_data in data.items():
        if "CPU" in chip_data:
            val = chip_data["CPU"]
            if isinstance(val, dict):
                return float(val.get("temp1_input", 0))

    return 0

def get_gpu_temp(data):
    """
    Universally find the GPU temperature.
    Priority:
    1. nvidia-smi (Proprietary drivers)
    2. amdgpu/radeon "edge" or "junction"
    3. nouveau (Open source Nvidia)
    """
    # 1. Try NVIDIA-SMI first (most reliable for Nvidia cards)
    if shutil.which("nvidia-smi"):
        try:
            out = subprocess.check_output(
                ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
                stderr=subprocess.DEVNULL
            ).decode("utf-8").strip()
            if out:
                return float(out)
        except:
            pass # Fail silently and try sensors

    # 2. Scan lm_sensors for AMD/Intel/Nouveau
    for chip_name, chip_data in data.items():
        chip_lower = chip_name.lower()
        
        # Filter for known GPU drivers
        if any(x in chip_lower for x in ["amdgpu", "radeon", "nouveau", "iwlwifi"]): # iwlwifi excluded usually, but just in case
            if "iwlwifi" in chip_lower: continue # Skip wifi

            # Preferred labels for GPU
            for label in ["edge", "junction", "temp1", "Composite"]:
                if label in chip_data:
                    val = chip_data[label]
                    if isinstance(val, dict):
                        return float(val.get("temp1_input", 0))
    
    return "N/A"

def main():
    try:
        # Get all sensor data as JSON
        output = subprocess.check_output(["sensors", "-j"]).decode("utf-8")
        data = json.loads(output)
        
        cpu = get_cpu_temp(data)
        gpu = get_gpu_temp(data)

        # Formatting
        # Round to nearest integer for cleaner display
        cpu_str = f"{int(cpu)}°" if isinstance(cpu, (int, float)) and cpu > 0 else "N/A"
        gpu_str = f"{int(gpu)}°" if isinstance(gpu, (int, float)) else "N/A"

        # Determine CSS class based on temps (optional dynamic coloring)
        css_class = "normal"
        if isinstance(cpu, (int, float)) and cpu > 80:
            css_class = "critical"

        # JSON Output for Waybar
        print(json.dumps({
            "text": f"{ICON_CPU} {cpu_str} {ICON_GPU} {gpu_str}",
            "tooltip": f"<b>CPU Package:</b> {cpu_str}C\n<b>GPU Core:</b> {gpu_str}C",
            "class": css_class
        }))

    except Exception as e:
        print(json.dumps({"text": "Err", "tooltip": str(e)}))

if __name__ == "__main__":
    main()
