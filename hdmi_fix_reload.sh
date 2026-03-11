#!/bin/bash
#
# hdmi_fix_reload.sh - Reload NVIDIA kernel modules to restore HDMI detection
#
# When the NVIDIA GPU loses HDMI hotplug detection (all DFP outputs show
# "disconnected" despite a monitor being plugged in), reloading the kernel
# modules forces a full reinitialization of the GPU's display outputs.
#
# WARNING: This script stops the display manager, which kills the current
# X/Wayland session. ALL UNSAVED WORK WILL BE LOST. Save everything first.
#
# The display manager is restarted automatically after module reload.
# You will be returned to the login screen.
#
# Usage: sudo ./hdmi_fix_reload.sh
#
# What it does:
#   1. Stops the display manager (gdm/sddm/lightdm)
#   2. Unloads nvidia_drm, nvidia_modeset, nvidia_uvm, nvidia modules
#   3. Reloads all NVIDIA modules in correct order
#   4. Restarts the display manager
#
# After logging back in, run:
#   xrandr --output HDMI-1-0 --auto --right-of DP-2

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

echo -e "${GREEN}=== NVIDIA Module Reload ===${NC}"
echo ""
echo -e "${RED}WARNING: This will kill your current desktop session.${NC}"
echo -e "${RED}Save all work before continuing.${NC}"
echo ""
read -p "Continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Detect display manager
DM=""
for candidate in display-manager gdm sddm lightdm; do
    if systemctl is-active --quiet "$candidate" 2>/dev/null; then
        DM="$candidate"
        break
    fi
done

if [ -z "$DM" ]; then
    echo -e "${YELLOW}No display manager detected. Proceeding with module reload only.${NC}"
else
    echo "[1/4] Stopping display manager ($DM)..."
    systemctl stop "$DM"
    echo -e "${GREEN}  Stopped.${NC}"
fi

echo "[2/4] Unloading NVIDIA kernel modules..."
# Unload in dependency order
for mod in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
    if lsmod | grep -q "^$mod "; then
        echo "  Unloading $mod..."
        modprobe -r "$mod" 2>/dev/null || {
            echo -e "${RED}  Failed to unload $mod (may be in use)${NC}"
            echo "  Trying to kill processes using NVIDIA..."
            # Kill any remaining processes using nvidia devices
            fuser -k /dev/nvidia* 2>/dev/null || true
            sleep 2
            modprobe -r "$mod" || {
                echo -e "${RED}  Still cannot unload $mod. A reboot may be required.${NC}"
                # Restart display manager before bailing
                [ -n "$DM" ] && systemctl start "$DM"
                exit 1
            }
        }
    fi
done
echo -e "${GREEN}  All NVIDIA modules unloaded.${NC}"

echo "[3/4] Reloading NVIDIA kernel modules..."
for mod in nvidia nvidia_modeset nvidia_drm nvidia_uvm; do
    echo "  Loading $mod..."
    modprobe "$mod"
done
echo -e "${GREEN}  All NVIDIA modules loaded.${NC}"

# Also force GPU power on to prevent immediate re-suspend
NVIDIA_PCI="0000:01:00.0"
if [ -f "/sys/bus/pci/devices/$NVIDIA_PCI/power/control" ]; then
    echo "on" > "/sys/bus/pci/devices/$NVIDIA_PCI/power/control"
    echo "  GPU power forced to 'on'"
fi

if [ -n "$DM" ]; then
    echo "[4/4] Starting display manager ($DM)..."
    systemctl start "$DM"
    echo -e "${GREEN}  Started. Log in and check HDMI.${NC}"
else
    echo "[4/4] No display manager to restart."
fi

echo ""
echo -e "${GREEN}=== Module reload complete ===${NC}"
echo ""
echo "After logging in, check with:"
echo "  xrandr | grep -E 'HDMI|connected'"
echo ""
echo "If HDMI-1-0 is connected but not active:"
echo "  xrandr --output HDMI-1-0 --auto --right-of DP-2"
echo ""
